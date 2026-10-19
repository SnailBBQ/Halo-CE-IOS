"""Run the actual campaign-targeting helpers from cheats.c with mock players."""
from pathlib import Path
import os
import re
import shutil
import sys
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "source/game/cheats.c").read_text(encoding="utf-8")
SETTINGS_UI = (ROOT / "port/ios/HaloIOS/HaloSettingsViewController.m").read_text(encoding="utf-8")
LIBRARY_UI = (ROOT / "port/ios/HaloIOS/HaloLibrary.m").read_text(encoding="utf-8")
SETTINGS_DOC = (ROOT / "docs/ios/SETTINGS.md").read_text(encoding="utf-8")

assert "Player 1 when Both is selected" not in SETTINGS_UI
assert "Both players applies them to each active local player" in SETTINGS_UI
assert "A tap will" not in SETTINGS_UI
assert '@[@"Drop in front",@"Replace in hand",@"Add to backpack"]' in SETTINGS_UI
assert "Add to backpack fills an empty weapon slot" in SETTINGS_UI
assert "give=asset->kind==HALO_CAMPAIGN_ASSET_WEAPON && mode!=0" in SOURCE
assert "replace=give && mode==1" in SOURCE
assert "HALO_CAMPAIGN_ASSET_ACTION(token,mode)" in SETTINGS_UI
assert "tag_iterator_new(&iterator,group)" in SOURCE
assert LIBRARY_UI.index('HaloUIButton(@"Import Custom Edition maps') < LIBRARY_UI.index('HaloUIButton(@"Add a mod folder')
assert "Player 1 when Both is selected" not in SETTINGS_DOC


def extract_function(name: str) -> str:
    match = re.search(r"static\s+\w+\s+" + re.escape(name) + r"\s*\([^;]*?\)\s*\{", SOURCE, re.S)
    if not match:
        raise AssertionError(f"could not find {name} in cheats.c")
    start = match.end() - 1
    depth = 0
    for index in range(start, len(SOURCE)):
        if SOURCE[index] == "{":
            depth += 1
        elif SOURCE[index] == "}":
            depth -= 1
            if depth == 0:
                return SOURCE[match.start():index + 1]
    raise AssertionError(f"unterminated function {name}")


functions = "\n\n".join(extract_function(name) for name in (
    "ios_target_player_index",
    "ios_action_is_per_player",
    "ios_target_players",
    "ios_campaign_action_targets",
))
assert "ios_options.target >= 2 && ios_action_is_per_player(action)" in functions
assert "ios_action_override = players[i]" in functions
assert "ios_options.target >= 2" in functions

harness = r"""
#include <stdio.h>
#include <stddef.h>
#include "halo_ios_campaign_assets.h"
#define NONE (-1)
#define MAXIMUM_LOCAL_PLAYERS 2
typedef int boolean;
struct player_datum { long unit_index, local_player_index; };
static struct { int target; } ios_options;
static struct player_datum players[2];
static long ios_action_override = NONE;
static unsigned calls, recorded_actions[8];
static long recorded_players[8];
static long local_player_get_player_index(short i) { return i < 2 ? i : NONE; }
static struct player_datum *player_try_and_get(long i) {
    return i >= 0 && i < 2 ? &players[i] : NULL;
}
static long cheat_player_index(void) {
    if (ios_action_override != NONE) return ios_action_override;
    if (ios_options.target < 2 && players[ios_options.target].unit_index != NONE)
        return ios_options.target;
    return players[0].unit_index != NONE ? 0 : players[1].unit_index != NONE ? 1 : NONE;
}
static void ios_campaign_action(unsigned int action) {
    recorded_actions[calls] = action;
    recorded_players[calls++] = cheat_player_index();
}
""" + functions + r"""
#define CHECK(condition) do { if (!(condition)) { printf("FAIL line %d: %s\n", __LINE__, #condition); return 1; } } while (0)
static void clear_calls(void) { calls = 0; }
int main(void) {
    players[0].unit_index = 10; players[0].local_player_index = 0;
    players[1].unit_index = 11; players[1].local_player_index = 1;
    ios_options.target = 0;
    ios_campaign_action_targets(10);
    CHECK(calls == 1 && recorded_actions[0] == 10 && recorded_players[0] == 0);
    clear_calls(); ios_options.target = 1;
    ios_campaign_action_targets(10);
    CHECK(calls == 1 && recorded_actions[0] == 10 && recorded_players[0] == 1);
    clear_calls(); ios_options.target = 2;
    ios_campaign_action_targets(10);
    CHECK(calls == 2 && recorded_players[0] == 0 && recorded_players[1] == 1);
    CHECK(recorded_actions[0] == 10 && recorded_actions[1] == 10);
    clear_calls(); players[1].unit_index = NONE;
    ios_campaign_action_targets(402);
    CHECK(calls == 1 && recorded_players[0] == 0);
    clear_calls();
    /* 13 is a world action (teleport to camera), and must execute once even with Both selected. */
    ios_campaign_action_targets(13);
    CHECK(calls == 1 && recorded_actions[0] == 13);
    clear_calls(); ios_options.target = 0;
    uint32_t custom_weapon = HALO_CAMPAIGN_ASSET_ACTION(42, 2);
    ios_campaign_action_targets(custom_weapon);
    CHECK(calls == 1 && recorded_actions[0] == custom_weapon && recorded_players[0] == 0);
    clear_calls(); ios_options.target = 2;
    ios_campaign_action_targets(custom_weapon);
    CHECK(calls == 2 && recorded_actions[0] == custom_weapon && recorded_actions[1] == custom_weapon);
    CHECK(recorded_players[0] == 0 && recorded_players[1] == 1);
    puts("PASS: Player 1, Player 2 and Both routing; map asset action repeats per player; world action runs once");
    return 0;
}
"""

with tempfile.TemporaryDirectory(dir=ROOT) as directory:
    source_path = Path(directory) / "test.c"
    exe_path = Path(directory) / ("test.exe" if os.name == "nt" else "test")
    source_path.write_text(harness, encoding="utf-8")
    compiler = os.environ.get("CC", "cc")
    if not shutil.which(compiler):
        print(f"SKIP: {compiler} is not installed; source checks passed, C runtime harness needs a C compiler")
        sys.exit(0)
    subprocess.run([compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I" + str(ROOT / "port/include"), str(source_path), "-o", str(exe_path)], check=True)
    subprocess.run([str(exe_path)], check=True)
