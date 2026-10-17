"""Map sharing is off by default on iOS (network.map_share, network.map_seed) and stays on elsewhere; downloading stays on; the Settings switch
and the one-time migration of an old config.toml are wired. Run: python tools/tests/test_ios_map_sharing_default.py"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
config = (ROOT / "port/linux/src/port_config.c").read_text(encoding="utf-8")

def preprocessed(define):
    text = re.sub(r'#include\s*[<"][^>"]+[>"]', "", config)
    out = subprocess.run(["cc", "-E", "-P", define, "-"], input=text, capture_output=True, text=True)
    return out.stdout

def default_of(text, key):
    m = re.search(r'\{\s*"%s",\s*_config_boolean,\s*"(true|false)"' % re.escape(key), text)
    return m.group(1) if m else None

problems = []
ios, other = preprocessed("-DHALO_IOS_GUEST=1"), preprocessed("-UHALO_IOS_GUEST")
for key in ("network.map_share", "network.map_seed"):
    if default_of(ios, key) != "false":
        problems.append(f"{key} must default to false on iOS")
    if default_of(other, key) != "true":
        problems.append(f"{key} must keep upstream's true default elsewhere")
if default_of(ios, "network.map_download") != "true":
    problems.append("network.map_download must stay true on iOS")
settings = (ROOT / "port/ios/HaloIOS/HaloSettingsViewController.m").read_text(encoding="utf-8")
if "HaloMapSharingSet(on)" not in settings or "HaloMapSharingEnabled()" not in settings:
    problems.append("Settings has no map sharing switch")
delegate = (ROOT / "port/ios/HaloIOS/AppDelegate.m").read_text(encoding="utf-8")
if not re.search(r"finishLaunch:[^{]*\{\s*HaloMapSharingMigrateDefaultOff\(\);", delegate):
    problems.append("the one-time migration does not run at the start of finishLaunch")
mods = (ROOT / "port/ios/HaloIOS/HaloMods.m").read_text(encoding="utf-8")
if "HaloMapSharingDefaultOffV1" not in mods or "HaloMapSharingWrite(NO, 0)" not in mods:
    problems.append("migration missing")
if "settings->voice_mode" not in settings or '@"Push to talk"' not in settings:
    problems.append("Settings has no voice chat control")
if '"enhanced_animations"' not in settings:
    problems.append("Settings has no original animations switch")
if problems:
    print("\n".join(problems))
    sys.exit(1)
print("PASS: map sharing defaults off on iOS only (download stays on), Settings switch and one-time migration wired")
