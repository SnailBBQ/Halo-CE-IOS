"""M2.6.112 Settings and Mods behaviour is wired the way the release notes say (source-level checks; the ObjC files are not
compiled on this machine). Run: python tools/tests/test_ios_m2712_ui.py"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "port/ios/HaloIOS"
problems = []


def read(name):
    return (IOS / name).read_text(encoding="utf-8")


def check(ok, message):
    if not ok:
        problems.append(message)


settings = read("HaloSettingsViewController.m")
library = read("HaloLibrary.m")
app = read("AppDelegate.m")
controls = read("halo_ios_controls.m")
core = read("halo_settings_core.h")
layout = read("halo_controls_layout.h")

# Audio
check('@"Ambient sound"' not in settings and 'HaloUISliderRow(@"Ambient"' in settings, "Ambient must sit in the Sound card, not a card of its own")
check('HaloUISwitchRow(@"Reverb"' in settings and 'HaloUISliderRow(@"Voice volume"' in settings, "Reverb and Voice volume must be in Audio")
check('HaloUISegmentRow(@"Your microphone"' in settings, "the microphone control is missing")
check("s->voice_mode=0" in core.replace(" ", "") or "voice_mode=0" in core.replace(" ", ""), "the microphone must start off")
check("HC_VOICE" in layout and "HC_VOICE" in controls and "halo_ios_ptt_set_held" in controls and "halo_ios_mic_set_muted" in controls, "the Talk / Mute button must be wired")

# Cheats and profiles
check('addCheatSection:@"Vehicle Spawner"' in settings and 'addCheatSection:@"Spawn"' not in settings, "Cheats must show a Vehicle Spawner section")
check("chooseHaloProfile" in settings and "halo_ios_profile_list" in settings and "halo_ios_profile_select" in settings, "Settings must be able to choose a Halo player profile")

# Search
check('@"magnifyingglass"' in settings and "openSearch" in settings and "HaloSettingsSearch" in settings, "the magnifier next to Settings is missing")
check(re.search(r"\[search\.leadingAnchor constraintEqualToAnchor:title\.trailingAnchor", settings), "the magnifier must sit next to the Settings title")
check("hss_suggestions" in settings and "hss_search" in settings and '@"Suggested"' in settings, "search must show suggestions before typing")
check("showSearchResult" in settings and "HaloFindLabel" in settings, "a result must open its category and find the row")

# Icon picker
check("HaloIconPicker" in settings and "UIImagePickerController" in settings and "star.fill" in settings, "the icon picker needs photos and favorite stars")
check("gear_favs" in core and "gear_token" in core and "HaloGearCustomImage" in app, "emoji / photo icons must be stored and drawn")
check('names:@[@"Default gear"' not in settings, "the old four-item icon list must be replaced")

# Mods filters
check("Sort multiplayer maps" not in library and "maps_mp_alpha" not in library, "Sort multiplayer maps A-Z must be gone from Mods")
check(library.count('Multiplayer only (A–Z)') == 2 and library.count('HaloUISwitchRow(@"Campaign only"') == 2, "Installed and Custom Edition maps both need the two filters")
check("hm_visible_mode" in library and "hm_custom_visible" in library and "custom_hide" in library, "filters must drive both lists")
check("0x60" in read("HaloMods.m"), "custom maps need their scenario type read from the header")

# Title screen
check("UNIVERSAL" not in app, "the title screen must not say UNIVERSAL")
check('@"Share logs"' in app and '@"Copy logs"' in app and "logsMenu" in app, "Share logs and Copy logs are one Logs button")

if problems:
    print("\n".join("FAIL: " + p for p in problems))
    sys.exit(1)
print("PASS: M2.6.112 audio, cheats, profiles, search, icon picker, Mods filters and title screen are wired")
