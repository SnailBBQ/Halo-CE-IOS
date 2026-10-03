"""HaloSettingsStore.m is compiled twice: on the device, and on CI's Foundation-only host with -DHALO_SETTINGS_TEST. A static
function defined only in the device branch but called from code both builds compile is an error on CI (as 'HaloEffectiveCap' was).
This reads the device branch (#else .. #endif of the first HALO_SETTINGS_TEST block) and fails if a static function defined there
is used anywhere outside it."""
import re, sys
from pathlib import Path
text = (Path(__file__).resolve().parents[2] / "port/ios/HaloIOS/HaloSettingsStore.m").read_text(encoding="utf-8")
start = text.index("#ifdef HALO_SETTINGS_TEST")
else_at = text.index("\n#else", start)
end = text.index("\n#endif", else_at)
device_only = text[else_at:end]
outside = text[:else_at] + text[end:]
problems = []
for name in re.findall(r"^\s*static\s+[\w\s\*]+?\b(\w+)\s*\([^)]*\)\s*\{", device_only, re.M):
    if re.search(r"\b" + re.escape(name) + r"\s*\(", outside):
        problems.append(name)
if problems:
    print("defined only in the device branch but used by both builds:", ", ".join(problems)); sys.exit(1)
print("PASS: nothing the CI test build needs is defined only in the device branch of HaloSettingsStore.m")
