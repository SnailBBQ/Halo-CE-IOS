"""M2.6.113: Settings > Mods and the game's Mods menu share one list (the mods folder and mods/load_order.toml). Source-level checks."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "port/ios/HaloIOS"
problems = []


def check(ok, message):
    if not ok:
        problems.append(message)


mods = (IOS / "HaloMods.m").read_text(encoding="utf-8")
header = (IOS / "HaloMods.h").read_text(encoding="utf-8")
library = (IOS / "HaloLibrary.m").read_text(encoding="utf-8")
runner = (IOS / "halo_guest_runner.m").read_text(encoding="utf-8")
runner_h = (IOS / "halo_guest_runner.h").read_text(encoding="utf-8")
menu = (ROOT / "port/linux/game/menu_functions.c").read_text(encoding="utf-8")

for name in ("HaloModPackList", "HaloModPackSave", "HaloModPackRemove", "HaloModPackImport", "HaloModPackFingerprint"):
    check(name in header and name in mods, name + " must be declared and defined")
check('@"mods"' in mods and "load_order.toml" in mods, "the mods folder and load_order.toml are the game's")
check("hms_order" in mods and "hms_serialize" in mods and "hms_strings" in mods, "the shared reader and writer must be used")
check("#ifndef HALO_BACKUP_TEST\n    halo_ios_mods_changed();" in mods, "the engine signal must stay out of the Foundation-only test build")
check("halo_ios_mods_changed" in runner_h and "UINT32_MAX-6" in runner and "g_mods_changed" in runner, "the host must signal the engine through index -7")
check("host_settings_value((unsigned)-7,text,0))mods_apply()" in menu, "the engine must apply the mods when the host says so")
check("HALO_IOS_GUEST" in menu[: menu.index("host_settings_value((unsigned)-7")], "the -7 poll must live in the iOS block")
check("renderModPacks" in library and "HaloModPackSave" in library and "Add a mod folder" in library and "Remove mod" in library, "Settings > Mods needs the list")
check("kind==9" in library and "HaloModPackImport(urls)" in library, "adding a mod folder must be handled")
check("HaloModPackFingerprint" in library and "scheduledTimerWithTimeInterval:2" in library, "changes made in the game must show in Settings")
check("host_sdl_show_message_box" in runner, "the new host import must be mapped")
if problems:
    print("\n".join("FAIL: " + p for p in problems))
    sys.exit(1)
print("PASS: Settings > Mods and the game's Mods menu share the mods folder and load_order.toml, and changes reach the running game")
