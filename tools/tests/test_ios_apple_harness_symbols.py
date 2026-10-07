"""M2.6.90 guards Objective-C iOS tests against Apple SDK symbol collisions."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
objc = sorted(ROOT.glob("test_ios_*.m")) + sorted(ROOT.glob("test_ios_*.mm"))
assert objc, "no Objective-C iOS harnesses found"

for path in objc:
    text = path.read_text(errors="replace")
    assert not re.search(r"\b(?:static\s+)?(?:unsigned\s+char|char|int|long|BOOL|void|[A-Za-z_][A-Za-z0-9_]*\s*\*)\s+Marker\s*\(", text), f"Apple SDK collision-prone Marker helper in {path.name}"

mods = (ROOT / "test_ios_mods.m").read_text()
disc = (ROOT / "test_ios_disc_install.m").read_text()
assert "#define CHECK(...)" in mods
assert "#define CHECK(...)" in disc
assert "ReadMarker" in mods and "ReadDiscMarker" in disc
print(f"PASS: {len(objc)} Objective-C iOS harnesses avoid Marker symbol collisions; comma-safe CHECK macros retained")
