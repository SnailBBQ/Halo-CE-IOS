"""A function must be declared before it is called: Xcode 26's compiler makes the opposite an error ("call to
undeclared function"), and a compile of the iOS host only happens in the macOS job, minutes into a build.

This reads every .m and .c file in port/ios/HaloIOS and fails when a function defined in that file is called on an earlier
line than its first definition or prototype (names declared in the directory's headers count as declared from the start).
It is a text check, not a compile, but it catches exactly this mistake. Run: python tools/tests/test_ios_declaration_order.py
"""
import re
import sys
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parents[2] / "port" / "ios" / "HaloIOS"
SKIP = {"if", "for", "while", "switch", "return", "sizeof", "defined", "__attribute__", "typeof", "offsetof", "alignof"}


def clean(source):
    def blank(match):
        return re.sub(r"[^\n]", " ", match.group(0))

    text = re.sub(r"/\*.*?\*/", blank, source, flags=re.S)
    text = re.sub(r"//[^\n]*", blank, text)
    return re.sub(r'@?"(?:\\.|[^"\\\n])*"', blank, text)


def check(path, header_names):
    text = clean(path.read_text(encoding="utf-8", errors="replace"))
    definitions = {}
    for match in re.finditer(r"^(?:static\s+)?(?:inline\s+)?(?:[A-Za-z_][\w\s\*]*?)\b([A-Za-z_]\w*)\s*\(([^;{}]*)\)\s*([;{])", text, re.M):
        if match.group(1) not in SKIP:
            definitions.setdefault(match.group(1), []).append(match.start())
    problems = []
    for name, positions in definitions.items():
        if name in header_names:
            continue
        first = min(positions)
        for call in re.finditer(r"(?<![\.\w>:\-])" + re.escape(name) + r"\s*\(", text):
            if call.start() < first and call.start() not in positions:
                line_start = text.rfind("\n", 0, call.start()) + 1
                if text[line_start:call.start()].strip() == "" and text[line_start:line_start + 1] not in (" ", "\t"):
                    continue    # the start of another definition, not a call
                problems.append((name, text.count("\n", 0, call.start()) + 1, text.count("\n", 0, first) + 1))
                break
    return problems


def main():
    header_names = set()
    for header in DIRECTORY.glob("*.h"):
        header_names |= set(re.findall(r"\b([A-Za-z_]\w*)\s*\(", clean(header.read_text(encoding="utf-8", errors="replace"))))
    failures = []
    files = sorted(list(DIRECTORY.glob("*.m")) + list(DIRECTORY.glob("*.c")))
    for path in files:
        for name, use, definition in check(path, header_names):
            failures.append(f"{path.name}: {name}() is called on line {use} but not defined or declared until line {definition}")
    if failures:
        print("\n".join(failures))
        sys.exit(1)
    print(f"PASS: no function is called before it is declared in {len(files)} iOS host files")


if __name__ == "__main__":
    main()
