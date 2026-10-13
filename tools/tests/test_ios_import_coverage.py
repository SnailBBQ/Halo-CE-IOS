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


# Guest ABI contract: the runner must agree with the header the guest is built against, or the game never starts
# ("FULL GUEST: image header mismatch."). Broke M2.6.104/105 when upstream moved to ABI 2.
abi = (ROOT / "port/android/include/halo_android_abi.h").read_text(encoding="utf-8", errors="replace")
def define(text, name):
    m = re.search(r"#define\s+" + name + r"\s+(?:UINT32_C\()?(0x[0-9A-Fa-f]+|\d+)u?\)?", text)
    return int(m.group(1), 0) if m else None
def fields(text):
    m = re.search(r"struct\s+halo_guest_header\s*\{(.*?)\}", text, re.S)
    body = re.sub(r"/\*.*?\*/", "", m.group(1), flags=re.S) if m else ""
    return re.findall(r"uint32_t\s+(\w+)\s*;", body)
problems = []
for name in ("HALO_GUEST_MAGIC", "HALO_GUEST_ABI_VERSION"):
    if define(abi, name) is None or define(abi, name) != define(runner, name):
        problems.append(f"{name}: upstream header {define(abi, name)} vs runner {define(runner, name)}")
if fields(abi) != fields(runner):
    problems.append(f"halo_guest_header fields differ:\n  upstream {fields(abi)}\n  runner   {fields(runner)}")
if problems:
    print("the iOS runner disagrees with the guest ABI header:")
    for p in problems:
        print("   ", p)
    sys.exit(1)
print("PASS: guest ABI version and header layout match the runner")
