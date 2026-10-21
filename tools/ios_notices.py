#!/usr/bin/env python3
"""Writes THIRD_PARTY_NOTICES.txt for the iOS app bundle: the font licenses and the license of every bundled third-party
component, so the notices travel with the IPA. Usage: ios_notices.py OUTPUT [--check]"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    ("Halo CE for iOS / OpenCE (project license, GNU AGPL 3.0)", "LICENSE"),
    ("OpenCE and its decompilation before the change of license (CC0 1.0)", "LICENSES/CC0-1.0.txt"),
    ("Overpass font (SIL Open Font License)", "port/assets/fonts/Overpass-OFL.txt"),
    ("OpenCE font (SIL Open Font License)", "port/assets/fonts/OpenCE-OFL.txt"),
]


def third_party():
    names = ("LICENSE", "LICENSE.TXT", "LICENCE.md", "COPYING")
    for folder in sorted((ROOT / "port/third_party").iterdir()):
        if not folder.is_dir():
            continue
        for name in names:
            path = folder / name
            if path.is_file():
                yield f"{folder.name}", path.relative_to(ROOT).as_posix()
                break


def build():
    parts = ["Third-party notices for Halo CE for iOS.\n"
             "The engine is OpenCE; the components below are included under their own licenses.\n"]
    missing = []
    for title, rel in list(SOURCES) + list(third_party()):
        path = ROOT / rel
        if not path.is_file():
            missing.append(rel)
            continue
        parts.append("=" * 78 + f"\n{title}  [{rel}]\n" + "=" * 78 + "\n" + path.read_text(encoding="utf-8", errors="replace").strip() + "\n")
    return "\n".join(parts), missing


def main():
    text, missing = build()
    if missing:
        print("missing license files:", ", ".join(missing), file=sys.stderr)
        return 1
    if "--check" not in sys.argv[2:]:
        Path(sys.argv[1]).write_text(text, encoding="utf-8")
    print(f"notices: {text.count('=' * 78) // 2} licenses, {len(text)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
