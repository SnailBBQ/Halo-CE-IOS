"""Every host function the game can call must be implemented by the iOS host, or the game stops at the moment it calls one it lacks.
port/android/host_imports.list is the list of what the game imports from its host (it grows when the game does: the key-name imports
came with the PC menus); the runner provides them with MAP("name", function). Fails on a name in the list that the runner does not map.
Run: python tools/tests/test_ios_import_coverage.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
listed = [line.strip() for line in (ROOT / "port/android/host_imports.list").read_text(encoding="utf-8").splitlines()
          if line.strip() and not line.lstrip().startswith("#")]
runner = (ROOT / "port/ios/HaloIOS/halo_guest_runner.m").read_text(encoding="utf-8", errors="replace")
mapped = set(re.findall(r'MAP\("(\w+)"', runner))
missing = [name for name in listed if name not in mapped]
if missing:
    print("the game imports these from its host, but the iOS runner does not map them:")
    for name in missing:
        print("   ", name)
    sys.exit(1)
print(f"PASS: all {len(listed)} host imports the game can call are implemented by the iOS runner")
