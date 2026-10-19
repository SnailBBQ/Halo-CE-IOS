"""Exercise the real iOS cheat gate with mocked engine state, not a copied implementation.
CI uses cc. --emit FILE writes the same harness for a local Windows C compiler.
"""
from pathlib import Path
import argparse, os, shutil, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "source/game/cheats.c").read_text(encoding="utf-8")
start = source.index("extern unsigned int host_cheat_flags(void);")
end = source.index("\n#endif\n\nvoid cheats_update", start)
body = source[start:end]
harness = r"""
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "halo_ios_campaign_options.h"
#include "halo_ios_campaign_assets.h"
typedef int boolean;
typedef float real;
#define TRUE 1
#define FALSE 0
#define NONE (-1)
#define NUMBEROF(a) (sizeof(a)/sizeof((a)[0]))
#define TEST_FLAG(a,b) ((a)&(1u<<(b)))
enum {_object_dead_bit=0,_object_type_biped=0};
static boolean cinematic;static boolean *director_camera_scripted=&cinematic;
struct unit_datum { struct { long player_index; } unit; struct {unsigned damage_flags;int type;long parent_object_index;} object; };
struct player_datum { long unit_index, local_player_index; };
struct { int deathless_player, infinite_ammo, bottomless_clip; } cheat;
static struct unit_datum units[3];
static struct player_datum players[3];
struct tag_iterator{int next;};
static void tag_iterator_new(struct tag_iterator *it,long group){(void)group;it->next=0;}
static long tag_iterator_next(struct tag_iterator *it){return it->next++?NONE:5;}
static const char *tag_get_name(long tag){(void)tag;return "weapons\\pistol\\bullet";}
static unsigned long tag_get_group_tag(long tag){(void)tag;return 'weap';}
static int in_progress, engine, network, actions, toasts;
static HaloCampaignOptions host_wanted;
static unsigned campaign_active;
void host_campaign_state(unsigned active) {
 campaign_active=active;
 if (!active) { memset(&host_wanted,0,sizeof(host_wanted));host_wanted.jump=host_wanted.speed=1.f; }
}
boolean game_in_progress(void) { return in_progress; }
boolean game_engine_running(void) { return engine; }
boolean network_game_is_active(void) { return network; }
struct unit_datum *unit_try_and_get(long i) { return i >= 0 && i < 3 ? &units[i] : NULL; }
struct unit_datum *unit_get(long i) { return unit_try_and_get(i); }
struct player_datum *player_try_and_get(long i) { return i >= 0 && i < 3 ? &players[i] : NULL; }
static long local_player_get_player_index(short i) { return i < 2 ? i : NONE; }
void host_campaign_options(HaloCampaignOptions *out) { *out = host_wanted; host_wanted.action = 0; }
int host_settings_value(unsigned int index, unsigned int address, unsigned int profile)
{ (void)index; (void)address; (void)profile; return 0; }
int host_sdl_show_toast(const char *s, int a, int b, int c, int d)
{ (void)s; (void)a; (void)b; (void)c; (void)d; ++toasts; return 1; }
""" + body + r"""
static void ios_campaign_action(unsigned int action) __attribute__((unused));
static void ios_campaign_action(unsigned int action) { (void)action; }
static void ios_campaign_action_targets(unsigned int action) { actions += (action != 0); }
static short ios_target_players(long *out) __attribute__((unused));
static short ios_target_players(long *out) { (void)out; return 0; }
static long cheat_player_index(void) { return 0; }
static long (*ios_target_ref)(void) __attribute__((unused)) = ios_target_player_index;
static void ios_powerups_tick(void) { /* Power-up behavior is covered by the separate runtime harness. */ }
static void ios_world_cheats_tick(void) { /* covered by the world-cheat harness */ }
static void ios_world_cheats_reset(void) { }
#define CHECK(x) do { if (!(x)) { printf("FAIL line %d: %s\n", __LINE__, #x); return 1; } } while (0)
int main(void)
{
    CHECK(sizeof(HaloCampaignOptions) == 28);
    units[0].unit.player_index = 0; players[0].unit_index = 0; players[0].local_player_index = 0;
    units[1].unit.player_index = NONE;
    units[2].unit.player_index = 2; players[2].unit_index = 2; players[2].local_player_index = NONE;
    in_progress = 1;
    units[0].object.parent_object_index=NONE;
    host_wanted.flags = 15 | IOS_CHEAT_NOCLIP | IOS_CHEAT_FLASHLIGHT;
    host_wanted.jump = 2.5f; host_wanted.speed = 3.f; host_wanted.fov = 80.f; host_wanted.action = 100;
    ios_cheats_apply();
    CHECK(cheat.deathless_player && cheat.infinite_ammo && cheat.bottomless_clip && ios_cheat_infinite_grenades);
    CHECK(ios_cheat_enabled(0, IOS_CHEAT_NOCLIP));
    CHECK(!ios_cheat_enabled(1, IOS_CHEAT_NOCLIP) && !ios_cheat_enabled(2, IOS_CHEAT_NOCLIP));
    CHECK(!ios_cheat_enabled(NONE, IOS_CHEAT_NOCLIP) && !ios_cheat_local_unit(99));
    CHECK(ios_cheat_jump_multiplier(0) == 2.5f && ios_cheat_speed_multiplier(1) == 1.f);
    CHECK(ios_cheat_field_of_view(0) == 80.f && ios_cheat_field_of_view(2) == 0.f);
    CHECK(actions == 1); ios_cheats_apply(); CHECK(actions == 1);
    host_wanted.asset_request = 1; ios_cheats_apply();
    CHECK(ios_campaign_asset_count == 1 && ios_campaign_asset_tags[0].tag == 5);
    CHECK(ios_campaign_asset_tags[0].kind == HALO_CAMPAIGN_ASSET_WEAPON);
    host_wanted.asset_request = 0;
    ios_options.flags|=IOS_CHEAT_DETACH_CAMERA|(1u<<IOS_CHEAT_PROJECTILE_SHIFT);
    CHECK(ios_cheat_camera_detached(0) && ios_cheat_projectile(0,99)==5 && ios_cheat_projectile(1,99)==99);
    cinematic=1;CHECK(!ios_cheat_camera_detached(0));cinematic=0;
    /* Mid-frame networking transition: hooks must immediately reject even cached flags. */
    network = 1; CHECK(!ios_cheat_enabled(0, IOS_CHEAT_NOCLIP));
    CHECK(ios_cheat_speed_multiplier(0) == 1.f);
    host_wanted.action = 200; ios_cheats_apply();
    CHECK(actions == 1 && toasts == 0 && !campaign_active && host_wanted.action == 0);
    CHECK(!cheat.deathless_player && !cheat.infinite_ammo && !cheat.bottomless_clip && !ios_cheat_infinite_grenades);
    network = 0; engine = 1; host_wanted.action = 2; ios_cheats_apply(); CHECK(actions == 1 && toasts == 0 && !campaign_active);
    engine = 0; in_progress = 0; host_wanted.action = 3; ios_cheats_apply(); CHECK(actions == 1 && toasts == 0 && !campaign_active);
    in_progress = 1; ios_cheats_apply(); CHECK(actions == 1 && campaign_active && !cheat.deathless_player); /* no delayed spawns */
    /* Recipe requests wait through player creation, then run once; map and
       multiplayer transitions must discard them before a later mission. */
    players[0].unit_index=NONE;host_wanted.action=100;ios_cheats_apply();CHECK(actions==1 && ios_recipe_count==1);
    ios_cheats_apply();CHECK(actions==1 && ios_recipe_count==1);
    players[0].unit_index=0;ios_cheats_apply();CHECK(actions==2 && ios_recipe_count==0);
    ios_cheats_apply();CHECK(actions==2);
    units[0].object.damage_flags=1;host_wanted.action=100;ios_cheats_apply();CHECK(actions==2 && ios_recipe_count==1);
    ios_cheats_reset();CHECK(!ios_recipe_count);units[0].object.damage_flags=0;ios_cheats_apply();CHECK(actions==2);
    players[0].unit_index=NONE;host_wanted.action=100;ios_cheats_apply();CHECK(ios_recipe_count==1);
    network=1;ios_cheats_apply();CHECK(!ios_recipe_count && actions==2);network=0;players[0].unit_index=0;ios_cheats_apply();CHECK(actions==2);
    players[0].unit_index = 1; CHECK(!ios_cheat_local_unit(0)); /* stale ownership */
    host_wanted.action = 100; ios_cheats_reset();
    CHECK(host_wanted.action == 0 && ios_options.jump == 1.f && ios_options.speed == 1.f);
    CHECK(!cheat.deathless_player && !ios_cheat_infinite_grenades);
    puts("PASS: real campaign gate, local ownership, live multiplayer transitions, packet ABI, one-shot consumption");
    return 0;
}
"""
parser = argparse.ArgumentParser()
parser.add_argument("--emit", type=Path)
args = parser.parse_args()
if args.emit:
    args.emit.write_text(harness, encoding="utf-8")
else:
    compiler = os.environ.get("CC", "cc")
    if not shutil.which(compiler):
        print(f"SKIP: {compiler} is not installed; source checks passed, C runtime harness needs a C compiler")
        raise SystemExit(0)
    with tempfile.TemporaryDirectory(dir=ROOT) as directory:
        path = Path(directory)
        (path / "test.c").write_text(harness, encoding="utf-8")
        exe = path / ("test.exe" if os.name == "nt" else "test")
        subprocess.run([compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I" + str(ROOT / "port/include"), str(path / "test.c"), "-o", str(exe)], check=True)
        subprocess.run([str(exe)], check=True)
