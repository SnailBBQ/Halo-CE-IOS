"""Runs the real jetpack / AI ignore / slow motion tick and the one-shot actions from source/game/cheats.c against mocked engine
state (the same approach as test_ios_powerups.py): held cheats are set while wanted and put back once when let go, nothing
survives leaving the campaign, a speed this code did not set is never touched, and every action ID does what the screen says."""
from pathlib import Path
import subprocess, tempfile, sys
ROOT = Path(__file__).resolve().parents[2]
s = (ROOT / "source/game/cheats.c").read_text(encoding="utf-8")
start = s.index("/* ---- Settings > Cheats: jetpack, AI ignore")
end = s.index("/* Infinite effects only refresh", start)
body = s[start:end]
harness = r'''
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "halo_ios_campaign_options.h"
typedef int boolean; typedef float real;
#define TRUE 1
#define FALSE 0
#define NONE (-1)
struct player_datum { long unit_index; };
static struct { int jetpack; } cheat;
static HaloCampaignOptions ios_options;
static int campaign, player_exists = 1, failures;
static char last_toast[128]; static int toasts;
static boolean ios_campaign_active(void) { return campaign; }
static long cheat_player_index(void) { return player_exists ? 0 : NONE; }
static struct player_datum the_player = { 7 };
static struct player_datum *player_try_and_get(long i) { return i == 0 ? &the_player : NULL; }
static void host_toast(const char *m) { strncpy(last_toast, m, sizeof(last_toast) - 1); last_toast[sizeof(last_toast) - 1] = 0; toasts++; }
BODY
static int ignore_state, teleports, teleport_ok = 1, restores, resets, safe_saves, forced_saves, reverts, saved_slot = -1, enemies_result = 3;
static real speed = 1.f;
void ios_ai_ignore_player(boolean v) { ignore_state = v; }
boolean ios_teleport_to_crosshair(long u) { (void)u; teleports++; return teleport_ok; }
short ios_teleport_enemies_to_crosshair(long u) { (void)u; return (short)enemies_result; }
boolean ios_save_position(long u, short slot) { (void)u; saved_slot = slot; return 1; }
boolean ios_return_position(long u, short slot) { (void)u; return slot == 0; }
boolean ios_restore_health_shield(long u) { (void)u; restores++; return 1; }
void ios_world_reset(void) { resets++; }
void main_save_map_safe(void) { safe_saves++; }
void main_save_map_nonsafe(void) { forced_saves++; }
void main_revert_map(void) { reverts++; }
void game_time_set_speed(real v) { speed = v; }
boolean game_time_reset_speed(void) { boolean c = speed != 1.f; speed = 1.f; return c; }
#define CHECK(x) do { if (!(x)) { printf("FAIL line %d: %s\n", __LINE__, #x); failures++; } } while (0)
static int near(real a, real b) { return a > b - 1e-4f && a < b + 1e-4f; }
int main(void)
{
    unsigned level;
    static const real expected[5] = { 1.f, .75f, .5f, .25f, .1f };
    campaign = 1;

    /* each slow-motion level sets its speed; the held cheats are on together */
    for (level = 1; level <= 4; level++) {
        ios_options.flags = IOS_CHEAT_JETPACK | IOS_CHEAT_AI_IGNORE | (level << IOS_CHEAT_SLOW_SHIFT);
        ios_world_cheats_tick();
        CHECK(cheat.jetpack == 1 && ignore_state == 1 && near(speed, expected[level]));
    }
    /* letting go puts everything back, once */
    ios_options.flags = 0; ios_world_cheats_tick();
    CHECK(cheat.jetpack == 0 && ignore_state == 0 && near(speed, 1.f));

    /* one at a time */
    ios_options.flags = IOS_CHEAT_JETPACK; ios_world_cheats_tick();
    CHECK(cheat.jetpack == 1 && ignore_state == 0 && near(speed, 1.f));
    ios_options.flags = IOS_CHEAT_AI_IGNORE; ios_world_cheats_tick();
    CHECK(cheat.jetpack == 0 && ignore_state == 1);
    ios_options.flags = 2u << IOS_CHEAT_SLOW_SHIFT; ios_world_cheats_tick();
    CHECK(ignore_state == 0 && near(speed, .5f));

    /* a level number outside 1..4 is no slow motion at all */
    ios_options.flags = 7u << IOS_CHEAT_SLOW_SHIFT; speed = 1.f; ios_world_cheats_tick();
    CHECK(near(speed, 1.f));
    ios_options.flags = 5u << IOS_CHEAT_SLOW_SHIFT; ios_world_cheats_tick();
    CHECK(near(speed, 1.f));

    /* a speed this code did not set is left alone, even while the cheats are off */
    ios_options.flags = 0; ios_world_cheats_tick(); speed = .6f; ios_world_cheats_tick(); ios_world_cheats_tick();
    CHECK(near(speed, .6f));
    speed = 1.f;

    /* leaving the campaign releases everything at once, even if the flags are still set */
    ios_options.flags = IOS_CHEAT_JETPACK | IOS_CHEAT_AI_IGNORE | (3u << IOS_CHEAT_SLOW_SHIFT); ios_world_cheats_tick();
    CHECK(cheat.jetpack == 1 && ignore_state == 1 && near(speed, .25f));
    campaign = 0; ios_world_cheats_tick();
    CHECK(cheat.jetpack == 0 && ignore_state == 0 && near(speed, 1.f));
    campaign = 1;

    /* a map change releases and forgets saved positions */
    ios_options.flags = IOS_CHEAT_JETPACK | IOS_CHEAT_AI_IGNORE | (1u << IOS_CHEAT_SLOW_SHIFT); ios_world_cheats_tick();
    resets = 0; ios_world_cheats_reset();
    CHECK(cheat.jetpack == 0 && ignore_state == 0 && near(speed, 1.f) && resets == 1);
    ios_world_cheats_tick();    /* flags still set: the next tick wants them again, and gets them */
    CHECK(cheat.jetpack == 1);
    ios_options.flags = 0; ios_world_cheats_tick();

    /* actions */
    CHECK(ios_world_action(5) && safe_saves == 1 && forced_saves == 0 && strstr(last_toast, "as soon as it is safe"));
    CHECK(ios_world_action(6) && forced_saves == 1 && strstr(last_toast, "Checkpoint saved"));
    CHECK(ios_world_action(7) && reverts == 1 && strstr(last_toast, "last checkpoint"));
    CHECK(ios_world_action(8) && teleports == 1 && strstr(last_toast, "Teleported to your crosshair"));
    teleport_ok = 0; CHECK(ios_world_action(8) && strstr(last_toast, "Nothing in range")); teleport_ok = 1;
    enemies_result = -1; CHECK(ios_world_action(9) && strstr(last_toast, "Nothing in range"));
    enemies_result = 0;  CHECK(ios_world_action(9) && strstr(last_toast, "No hostile units"));
    enemies_result = 1;  CHECK(ios_world_action(9) && !strcmp(last_toast, "Moved 1 hostile unit to your crosshair"));
    enemies_result = 12; CHECK(ios_world_action(9) && !strcmp(last_toast, "Moved 12 hostile units to your crosshair"));
    enemies_result = 24; CHECK(ios_world_action(9) && !strcmp(last_toast, "Moved 24 hostile units to your crosshair"));
    enemies_result = 7;  CHECK(ios_world_action(9) && !strcmp(last_toast, "Moved 7 hostile units to your crosshair"));
    CHECK(ios_world_action(10) && restores == 1 && strstr(last_toast, "restored"));
    CHECK(ios_world_action(300) && saved_slot == 0 && ios_world_action(301) && saved_slot == 1 && ios_world_action(302) && saved_slot == 2 && strstr(last_toast, "Position saved"));
    CHECK(ios_world_action(310) && strstr(last_toast, "Returned"));
    CHECK(ios_world_action(311) && strstr(last_toast, "No saved position"));
    /* IDs that belong to the other code (powerups, weapons, vehicles) and unknown ones are not taken */
    { unsigned others[] = { 0, 1, 2, 3, 4, 11, 99, 100, 109, 200, 203, 299, 303, 309, 313, 400, 65535 };
      int taken = 0, before = toasts; for (unsigned i = 0; i < sizeof(others) / sizeof(others[0]); i++) taken += ios_world_action(others[i]);
      CHECK(taken == 0 && toasts == before); }
    /* no player, no action */
    player_exists = 0; { int before = toasts; CHECK(!ios_world_action(5) && !ios_world_action(8) && toasts == before && safe_saves == 1); } player_exists = 1;

    if (!failures) printf("PASS: jetpack, AI ignore and four slow-motion levels (held, released once, released on leaving the campaign, foreign speeds untouched), all one-shot action IDs and messages\n");
    return failures ? 1 : 0;
}
'''.replace("BODY", body)
with tempfile.TemporaryDirectory() as tmp:
    src = Path(tmp) / "test.c"; src.write_text(harness)
    subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", f"-I{ROOT / 'port/include'}", str(src), "-o", str(Path(tmp) / "test")], check=True)
    run = subprocess.run([str(Path(tmp) / "test")], capture_output=True, text=True)
    print(run.stdout.strip())
    sys.exit(run.returncode)
