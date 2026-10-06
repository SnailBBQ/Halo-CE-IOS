"""Guard the iOS-only guest source dependencies that upstream rebases can drop.

These headers are intentionally iOS-only so the flags-off source remains byte-for-byte OpenCE.
A missing include compiles through the source-structure checks but fails late in the real arm64_32
Guest build (for example director.c using IOS_CHEAT_THIRD_PERSON without game/cheats.h).

Run: python tools/tests/test_ios_guest_compile_dependencies.py
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]


def view(text: str, ios: bool) -> str:
    out = []
    stack = []

    def live():
        return not any(kind == "ios" and in_else == ios for kind, in_else in stack)

    for line in text.splitlines():
        stripped = line.strip()
        match = re.match(r"#\s*(ifdef|ifndef)\s+HALO_IOS_GUEST\b", stripped)
        if match:
            stack.append(["ios", match.group(1) == "ifndef"])
            continue
        if re.match(r"#\s*(if|ifdef|ifndef)\b", stripped):
            if live():
                out.append(line)
            stack.append(["other", False])
            continue
        if re.match(r"#\s*else\b", stripped):
            if stack and stack[-1][0] == "ios":
                stack[-1][1] = not stack[-1][1]
                continue
            if live():
                out.append(line)
            continue
        if re.match(r"#\s*endif\b", stripped):
            if not stack:
                raise ValueError("#endif without #if")
            top = stack.pop()
            if top[0] == "ios":
                continue
            if live():
                out.append(line)
            continue
        if live():
            out.append(line)
    if stack:
        raise ValueError("unterminated #if")
    return "\n".join(out)


REQUIRED = {
    "source/camera/director.c": ('#include "game/cheats.h"',),
    "source/interface/first_person_weapons.c": ('#include "game/cheats.h"',),
    "source/game/player_control.c": ('#include "game/cheats.h"',),
    "source/ai/ai_debug.c": ('#include "game/game_allegiance.h"',),
    "source/game/cheats.c": (
        '#include "items/equipment_definitions.h"',
        '#include "objects/damage.h"',
        '#include "tag_files/tag_files.h"',
    ),
}


def main():
    failures = []
    for rel, headers in REQUIRED.items():
        text = (ROOT / rel).read_text(encoding="utf-8", errors="surrogateescape")
        ios = view(text, True)
        plain = view(text, False)
        for header in headers:
            if header not in ios:
                failures.append(f"{rel}: iOS view is missing {header}")
            if header in plain:
                failures.append(f"{rel}: {header} leaks into the non-iOS/OpenCE view")

    # Every source file that consumes the iOS cheat API must get its declarations from cheats.h.
    for path in sorted((ROOT / "source").rglob("*.c")):
        rel = path.relative_to(ROOT).as_posix()
        if rel == "source/game/cheats.c":
            continue
        text = path.read_text(encoding="utf-8", errors="surrogateescape")
        ios = view(text, True)
        if ("ios_cheat_" in ios or "IOS_CHEAT_" in ios) and '#include "game/cheats.h"' not in ios:
            failures.append(f"{rel}: consumes the iOS cheat API without #include \"game/cheats.h\"")

    if failures:
        print("\n".join(failures))
        sys.exit(1)
    print("PASS: iOS-only guest compile dependencies are present and remain excluded from the flags-off OpenCE view")


if __name__ == "__main__":
    main()
