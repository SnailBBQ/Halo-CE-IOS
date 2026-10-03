/*
CHEATS.C

symbols in this file:
00094C50 0020:
	_cheats_initialize (0000)
00094C70 0010:
	_cheats_dispose (0000)
00094C80 0010:
	_cheats_dispose_from_old_map (0000)
00094C90 00b0:
	_cheats_update (0000)
00094D40 0090:
	_cheats_load (0000)
00094DD0 0060:
	_cheat_active_camouflage_local_player (0000)
00094E30 0060:
	_cheat_player_index (0000)
00094E90 0010:
	_cheats_initialize_for_new_map (0000)
00094EA0 00b0:
	_cheat_teleport_to_camera (0000)
00094F50 0050:
	_cheat_active_camouflage (0000)
00094FA0 0150:
	_cheat_objects (0000)
000950F0 00d0:
	_cheat_all_weapons (0000)
000951C0 0050:
	_cheat_all_powerups (0000)
00095210 0050:
	_cheat_all_vehicles (0000)
0025AC64 003b:
	??_C@_0DL@LCJIJOPI@Cannot?5execute?5cheats?5attached?5t@ (0000)
0025ACA0 0005:
	??_C@_04JNJDPIIA@?$AN?6?7?$DL?$AA@ (0000)
0025ACA8 000e:
	??_C@_0O@KAFNGCBO@d?3?2cheats?4txt?$AA@ (0000)
0025ACB8 003a:
	??_C@_0DK@OACLODJP@Camera?5is?5outside?5BSP?4?4?4?5cannot?5@ (0000)
0025ACF4 001d:
	??_C@_0BN@DPPGFJCA@c?3?2halo?2SOURCE?2game?2cheats?4c?$AA@ (0000)
0025AD14 0004:
	__real@3ec90fdb (0000)
0043D808 0c81:
	_cheat_strings (0000)
*/

/* ---------- headers */

#include "cseries.h"
#include "cseries/errors.h"
#include "cheats.h"
#include "cache/cache_files.h"
#include "camera/director.h"
#include "camera/observer.h"
#include "game/game_globals.h"
#include "game/players.h"
#include "hs/hs.h"
#include "input/input.h"
#include "interface/terminal.h"
#include "items/weapon_definitions.h"
#include "items/equipment_definitions.h"
#include "main/console.h"
#include "math/real_math.h"
#include "objects/objects.h"
#include "objects/damage.h"
#include "rasterizer/rasterizer_console_vars.h"
#include "scenario/scenario.h"
#include "tag_files/tag_groups.h"
#include "tag_files/tag_files.h"
#include "units/units.h"

/* ---------- constants */

enum
{
	MAXIMUM_CHEATS = NUMBER_OF_GAMEPAD_BUTTONS,
	MAXIMUM_CHEAT_LENGTH = 200
};

#define CHEATS_FILENAME "d:\\cheats.txt"

/* ---------- macros */

#define TAG_BLOCK_TRY_AND_GET_ELEMENT(block_address, index, type) \
	((block_address)->count ? TAG_BLOCK_GET_ELEMENT((block_address), (index), type) : NULL)

/* ---------- structures */

/* ---------- prototypes */

/* ---------- globals */

static char cheat_strings[MAXIMUM_CHEATS][MAXIMUM_CHEAT_LENGTH] = {0};
/* January emits this otherwise unreferenced byte after cheat_strings.
 * Its original name and purpose are unknown; the name is descriptive only. */
static boolean cheats_unused_flag = FALSE;

/* ---------- code */

#ifdef HALO_IOS_GUEST
static void ios_cheats_reset(void);
#endif

void cheats_initialize(
	void)
{
	csmemset(cheat_strings, 0, sizeof(cheat_strings));

	return;
}

void cheats_dispose(
	void)
{
	return;
}

void cheats_dispose_from_old_map(
	void)
{
#ifdef HALO_IOS_GUEST
	ios_cheats_reset();
#endif
	return;
}

/* network_game_globals.c's */
boolean network_game_distributed_client(void);
/* bipeds.c's, player_control.c's */
extern boolean rider_ejection;
extern boolean player_autoaim_flag;
extern boolean player_magnetism_flag;
/* game_time.c's */
boolean game_time_reset_speed(void);

/* port: what the machine draws of the world put back as it draws it for
everyone: nothing seen through walls (wireframe, a drawing mode, the
environment or its parts left out), past fog, or under grass and water;
whether any was other */
static boolean cheats_network_client_rasterizer_enforce(
	void)
{
	boolean changed = FALSE;
	boolean *environment_part;

	if (rasterizer_debug_options.wireframe_enabled || rasterizer_debug_options.drawing_mode != 0 ||
		!rasterizer_debug_options.draw_water || !rasterizer_debug_options.draw_detail_objects ||
		!rasterizer_debug_options.draw_lens_flares || !rasterizer_debug_options.fog_atmospheric_enabled ||
		!rasterizer_debug_options.fog_planar_enabled)
	{
		changed = TRUE;
	}
	rasterizer_debug_options.wireframe_enabled = FALSE;
	rasterizer_debug_options.drawing_mode = 0;
	rasterizer_debug_options.draw_water = TRUE;
	rasterizer_debug_options.draw_detail_objects = TRUE;
	rasterizer_debug_options.draw_lens_flares = TRUE;
	rasterizer_debug_options.fog_atmospheric_enabled = TRUE;
	rasterizer_debug_options.fog_planar_enabled = TRUE;
	/* (the environment and its parts, lightmaps to screen fog, all drawn,
	as rasterizer_frame_begin leaves them from its switch: 2, given) */
	for (environment_part = &rasterizer_debug_options.draw_environment_lightmaps;
		environment_part <= &rasterizer_debug_options.draw_environment_fog_screen;
		environment_part++)
	{
		if (!*environment_part)
			changed = TRUE;
		*environment_part = TRUE;
	}
	if (rasterizer_debug_options.draw_environment != 2)
		changed = TRUE;
	rasterizer_debug_options.draw_environment = 2;

	return changed;
}

/* port: a client in another's game plays by the host's rules: none of its
own cheats, its own game speed or its own changes to how players play, nor
what its drawing shows it that others' does not, set before it joined too
(after, hs_compile_and_evaluate refuses them); each frame and each tick */
void cheats_network_client_enforce(
	void)
{
	static struct cheat_globals const none = { 0 };
	boolean changed;

	if (!network_game_distributed_client())
		return;
	changed = csmemcmp(&cheat, &none, sizeof(cheat)) != 0 || !rider_ejection || !player_autoaim_flag ||
		!player_magnetism_flag;
	csmemset(&cheat, 0, sizeof(cheat));
	rider_ejection = TRUE;
	player_autoaim_flag = TRUE;
	player_magnetism_flag = TRUE;
	changed |= game_time_reset_speed();
	changed |= cheats_network_client_rasterizer_enforce();
	if (changed)
	{
		console_warning("playing in another's game: its host's rules (cheats, game speed and drawing put back)");
		error(_error_log, "playing in another's game: cheats, game speed and drawing put back to the host's");
	}

	return;
}

#ifdef HALO_IOS_GUEST
/* iOS Settings > Cheats. The host passes a bit mask: 1 god mode, 2 infinite ammo, 4 infinite grenades,
8 no reloading. They drive the game's own cheat flags (cheats.h), and only in the campaign: never in a
multiplayer game of the game engine and never in a network game, so nobody cheats where others play.
What this turned on is turned off again when the setting goes off or the game is not the campaign. */
extern unsigned int host_cheat_flags(void);
extern void host_campaign_state(unsigned int active);
extern boolean game_in_progress(void);
extern boolean game_engine_running(void);
extern boolean network_game_is_active(void);
boolean ios_cheat_infinite_grenades;
static unsigned int ios_cheats_set;
static HaloCampaignOptions ios_options = { 0, 0, 1.f, 1.f, 0.f };
extern void host_campaign_options(HaloCampaignOptions *options);
extern int host_sdl_show_toast(const char *, int, int, int, int);
static void host_toast(const char *message) { host_sdl_show_toast(message, 2500, 0, 0, 0); }
static void ios_campaign_action(unsigned int action);
static long cheat_player_index(void);
static unsigned int ios_recipe_actions[16],ios_recipe_head,ios_recipe_count;
static void ios_powerups_tick(void);
static boolean ios_campaign_active(void)
{ return game_in_progress() && !game_engine_running() && !network_game_is_active(); }
boolean ios_cheat_local_unit(long index)
{
    struct unit_datum *unit;
    struct player_datum *player;
    if (!ios_campaign_active() || index == NONE) return FALSE;
    unit = unit_try_and_get(index);
    if (!unit || unit->unit.player_index == NONE) return FALSE;
    player = player_try_and_get(unit->unit.player_index);
    return player && player->local_player_index != NONE && player->unit_index == index;
}
boolean ios_cheat_enabled(long index, unsigned int flag)
{ return (ios_options.flags & flag) && ios_cheat_local_unit(index); }
real ios_cheat_jump_multiplier(long index)
{ return ios_cheat_local_unit(index) ? ios_options.jump : 1.f; }
real ios_cheat_speed_multiplier(long index)
{ return ios_cheat_local_unit(index) ? ios_options.speed : 1.f; }
real ios_cheat_field_of_view(long index)
{ return ios_cheat_local_unit(index) ? ios_options.fov : 0.f; }

static void ios_cheats_apply(void)
{
	unsigned int wanted = 0, released;

	/* Consume requests even outside campaign: they must never execute in a later mission. */
	host_campaign_state(ios_campaign_active());
	host_campaign_options(&ios_options);
	if (ios_campaign_active()) {
		wanted = ios_options.flags & 15u;
		/* A recipe can activate before the intro has created a player. Keep
		   only request IDs, in order, until a living local unit is available. */
		if (ios_options.action && ios_recipe_count < NUMBEROF(ios_recipe_actions)) {
			ios_recipe_actions[(ios_recipe_head + ios_recipe_count) % NUMBEROF(ios_recipe_actions)] = ios_options.action;
			ios_recipe_count++;
		}
		if (ios_recipe_count) {
			long index = cheat_player_index();
			struct player_datum *player = index == NONE ? NULL : player_try_and_get(index);
			if (player && ios_cheat_local_unit(player->unit_index) &&
				!TEST_FLAG(unit_get(player->unit_index)->object.damage_flags, _object_dead_bit)) {
				unsigned int action = ios_recipe_actions[ios_recipe_head];
				ios_recipe_head = (ios_recipe_head + 1) % NUMBEROF(ios_recipe_actions);
				ios_recipe_count--;
				ios_campaign_action(action);
			}
		}
	} else {
		ios_recipe_head = ios_recipe_count = 0;
		if (ios_options.action) host_toast("Campaign actions are unavailable here");
		ios_options.flags = 0;
		ios_options.jump = ios_options.speed = 1.f;
		ios_options.fov = 0.f;
	}
	released = ios_cheats_set & ~wanted;
	/* set again every tick while wanted (nothing else may put them back), cleared once when let go */
	if (wanted & 1u)
		cheat.deathless_player = TRUE;
	if (wanted & 2u)
		cheat.infinite_ammo = TRUE;
	if (wanted & 8u)
		cheat.bottomless_clip = TRUE;
	if (released & 1u)
		cheat.deathless_player = FALSE;
	if (released & 2u)
		cheat.infinite_ammo = FALSE;
	if (released & 8u)
		cheat.bottomless_clip = FALSE;
	ios_cheat_infinite_grenades = (wanted & 4u) != 0;
	ios_cheats_set = wanted;
    ios_powerups_tick();
}
/* Map boundaries discard pending UI requests and release only flags this UI set.
 * Preferences are sampled again on the next tick; no spawn crosses a map load. */
static void ios_cheats_reset(void)
{
    HaloCampaignOptions discarded;
    ios_recipe_head = ios_recipe_count = 0;
    host_campaign_state(0);
    host_campaign_options(&discarded);
    if (ios_cheats_set & 1u) cheat.deathless_player = FALSE;
    if (ios_cheats_set & 2u) cheat.infinite_ammo = FALSE;
    if (ios_cheats_set & 8u) cheat.bottomless_clip = FALSE;
    ios_cheats_set = 0;
    ios_cheat_infinite_grenades = FALSE;
    memset(&ios_options, 0, sizeof(ios_options));
    ios_options.jump = ios_options.speed = 1.f;
}

#endif

void cheats_update(
	void)
{
#ifdef HALO_IOS_GUEST
	ios_cheats_apply();
#endif
	cheats_network_client_enforce();
	if (cheat.controller_enabled)
	{
		short local_player_index;

		for (local_player_index = local_player_get_next(NONE);
			local_player_index!=NONE;
			local_player_index = local_player_get_next(local_player_index))
		{
			struct gamepad_state const *gamepad = input_get_gamepad_state(local_player_index);

			if (gamepad && gamepad->buttons[_gamepad_binary_button_back]>0)
			{
				short button_index;

				for (button_index = 0; button_index<MAXIMUM_CHEATS; button_index++)
				{
					if (cheat_strings[button_index][0] && gamepad->buttons[button_index]>0)
					{
						director_inhibit_input(local_player_index);

						if (gamepad->buttons[button_index]==1)
						{
							console_printf(FALSE, cheat_strings[button_index]);
							if (!hs_compile_and_evaluate(cheat_strings[button_index]))
								cheat_strings[button_index][0] = 0;
						}
					}
				}
			}
		}
	}

	return;
}

void cheats_load(
	void)
{
	FILE *file = fopen(CHEATS_FILENAME, "r");

	if (file)
	{
		short cheat_index;

		for (cheat_index = 0; cheat_index<MAXIMUM_CHEATS; cheat_index++)
		{
			if (!fgets(cheat_strings[cheat_index], MAXIMUM_CHEAT_LENGTH-1, file))
				break;

			csstrtok(cheat_strings[cheat_index], "\r\n\t;");

			if ((cheat_index==_gamepad_binary_button_back || cheat_index==_gamepad_binary_button_start)
				&& cheat_strings[cheat_index][0])
			{
				cheat_strings[cheat_index][0] = 0;
				error(2, "Cannot execute cheats attached to the back or start button");
			}
		}

		fclose(file);
	}

	return;
}

void cheat_active_camouflage_local_player(
	short local_player_index)
{
	if (local_player_index>=0 && local_player_index<MAXIMUM_LOCAL_PLAYERS)
	{
		long player_index = local_player_get_player_index(local_player_index);

		if (player_index!=NONE)
		{
			struct player_datum *player = player_get(player_index);
			struct unit_datum *unit = unit_get(player->unit_index);

			unit->unit.active_camouflage = 1.0f;
			if (TEST_FLAG(unit->unit.flags, _unit_active_camouflaged_bit))
				unit->unit.flags |= FLAG(_unit_super_camouflaged_bit);
			unit->unit.flags |= FLAG(_unit_active_camouflaged_bit);
		}
	}

	return;
}

static long cheat_player_index(
	void)
{
	struct data_iterator iterator;
	struct player_datum *player;
	long player_index = NONE;

	data_iterator_new(&iterator, player_data);
	while ((player = (struct player_datum *)data_iterator_next(&iterator))!=NULL)
	{
		if (player->unit_index!=NONE)
		{
			player_index = iterator.datum_index;
			break;
		}
	}

	return player_index;
}

void cheats_initialize_for_new_map(
	void)
{
#ifdef HALO_IOS_GUEST
	ios_cheats_reset();
#endif
	cheats_load();

	return;
}

void cheat_teleport_to_camera(
	void)
{
	long player_index = cheat_player_index();

	if (player_index!=NONE)
	{
		struct player_datum *player = player_get(player_index);

		if (player->local_player_index!=NONE)
		{
			struct observer_result const *result = observer_get_camera(player->local_player_index);

			match_assert("c:\\halo\\SOURCE\\game\\cheats.c", 256, result);

			if (result->location.cluster_index!=NONE)
			{
				long object_index = unit_get(player->unit_index)->object.parent_object_index;

				if (object_index==NONE)
					object_index = player->unit_index;

				object_set_position(object_index, &result->position, NULL, NULL);
			}
			else
			{
				terminal_printf(global_real_argb_orange, "Camera is outside BSP... cannot initiate teleportation...");
			}
		}
	}

	return;
}

void cheat_active_camouflage(
	void)
{
	long player_index = cheat_player_index();

	if (player_index!=NONE)
	{
		struct player_datum *player = player_get(player_index);
		struct unit_datum *unit = unit_get(player->unit_index);

		unit->unit.active_camouflage = 1.0f;
		if (TEST_FLAG(unit->unit.flags, _unit_active_camouflaged_bit))
			unit->unit.flags |= FLAG(_unit_super_camouflaged_bit);
		unit->unit.flags |= FLAG(_unit_active_camouflaged_bit);
	}

	return;
}

static void cheat_objects(
	struct tag_reference *references,
	short reference_count)
{
	long player_index = cheat_player_index();

	if (player_index!=NONE)
	{
		struct player_datum *player = player_get(player_index);
		struct unit_datum *unit = unit_get(player->unit_index);
		real_point3d origin;
		real_vector3d forward, up;
		short reference_index;

		object_get_origin(player->unit_index, &origin);
		object_get_orientation(player->unit_index, &forward, &up);

		for (reference_index = 0; reference_index<reference_count; reference_index++)
		{
			if (references[reference_index].index!=NONE)
			{
				struct object_placement_data data;
				real angle_separation = CEILING(2*_pi/reference_count, _pi/8);
				real angle = arctangent(forward.i, forward.j)+
					(reference_index-reference_count/2)*angle_separation;

				object_placement_data_new(&data, references[reference_index].index, NONE);

				data.position.x = cosine(angle)*1.5f+origin.x;
				data.position.y = sine(angle)*1.5f+origin.y;
				data.position.z = origin.z+0.8f;
				data.forward = forward;
				data.up = up;

				object_new(&data);
			}
		}
	}

	return;
}

void cheat_all_weapons(
	void)
{
	struct game_globals *globals = scenario_get_game_globals();

	if (TAG_BLOCK_TRY_AND_GET_ELEMENT(&globals->weapon_list, 0, struct tag_reference))
	{
		cheat_objects(
			TAG_BLOCK_TRY_AND_GET_ELEMENT(&globals->weapon_list, 0, struct tag_reference),
			(short)globals->weapon_list.count);
	}
	else
	{
		struct tag_reference references[MAXIMUM_CHEATS];
		struct tag_iterator iterator;
		long tag_index;
		short reference_count = 0;

		tag_iterator_new(&iterator, WEAPON_DEFINITION_TAG);
		for (tag_index = tag_iterator_next(&iterator);
			tag_index!=NONE && reference_count<NUMBEROF(references);
			tag_index = tag_iterator_next(&iterator))
		{
			references[reference_count].index = tag_index;
			reference_count++;
		}

		cheat_objects(references, reference_count);
	}

	return;
}

void cheat_all_powerups(
	void)
{
	struct game_globals *globals = scenario_get_game_globals();

	cheat_objects(
		TAG_BLOCK_TRY_AND_GET_ELEMENT(&globals->cheat_powerups, 0, struct tag_reference),
		(short)globals->cheat_powerups.count);

	return;
}

void cheat_all_vehicles(
	void)
{
	struct game_globals *globals = scenario_get_game_globals();

	if (globals->multiplayer_information.count)
	{
		cheat_objects(
			TAG_BLOCK_GET_ELEMENT(&globals->multiplayer_information, 0,
				struct game_globals_multiplayer_information)->vehicles.address,
			(short)TAG_BLOCK_GET_ELEMENT(&globals->multiplayer_information, 0,
				struct game_globals_multiplayer_information)->vehicles.count);
	}

	return;
}

#ifdef HALO_IOS_GUEST
/* Infinite effects only refresh the living, local solo player. Releasing camo
 * stops refreshing its timer; an existing normal pickup can still run its course.
 * Overshield remains a normal damage-consumable reserve after disabling. */
static void ios_powerups_tick(void) {
    long index=cheat_player_index();
    struct player_datum *p=index==NONE?NULL:player_try_and_get(index);
    struct unit_datum *u;
    if(!p || !ios_cheat_local_unit(p->unit_index))return;
    u=unit_get(p->unit_index);if(TEST_FLAG(u->object.damage_flags,_object_dead_bit))return;
    if(ios_options.flags&IOS_CHEAT_CAMO)player_handle_powerup_minor(index,_player_powerup_active_camouflage,2);
    if(ios_options.flags&IOS_CHEAT_OVERSHIELD) {
        if(u->object.shield_vitality<=1.f)object_double_charge_shield(p->unit_index);
        else if(!TEST_FLAG(u->object.damage_flags,_object_shield_over_charging_bit))u->object.shield_vitality=3.f;
    }
}
/* UI request IDs are fixed; matching only loaded assets keeps map ownership intact. */
static void ios_campaign_action(unsigned int action)
{
    static const char *const weapons[] = { "pistol", "assault rifle", "shotgun", "sniper rifle", "rocket launcher", "plasma pistol", "plasma rifle", "needler", "flamethrower", "gravity rifle" };
    static const char *const vehicles[] = { "warthog", "ghost", "banshee", "scorpion" };
    struct tag_iterator iterator;
    struct tag_reference reference;
    const char *wanted = NULL;
    long group = 'weap', tag;
    {
        long index = cheat_player_index();
        struct player_datum *player = index == NONE ? NULL : player_try_and_get(index);
        if (!player || !ios_cheat_local_unit(player->unit_index) ||
            TEST_FLAG(unit_get(player->unit_index)->object.damage_flags, _object_dead_bit)) {
            host_toast("A living campaign player is required"); return;
        }
    }
    if (action == 4) {
        long player_index=cheat_player_index();
        struct player_datum *player=player_get(player_index);
        host_toast(object_double_charge_shield(player->unit_index) ? "Overshield applied" : "Could not apply overshield"); return;
    }
    if (action == 1) {
        long index=cheat_player_index(); short ticks=30*30;
        tag_iterator_new(&iterator,'eqip');
        while ((tag=tag_iterator_next(&iterator))!=NONE) {
            const char *name=tag_get_name(tag),*leaf;
            if(!name)continue;leaf=strrchr(name,'\\');leaf=leaf?leaf+1:name;
            if(!strcmp(leaf,"active camouflage")) {
                struct equipment_definition *definition=tag_get('eqip',tag);
                real seconds=definition->equipment.powerup_time;
                if(seconds>0 && seconds<=1092.f)ticks=(short)(seconds*30.f);
                break;
            }
        }
        player_handle_powerup_minor(index,_player_powerup_active_camouflage,ticks);
        host_toast("Active Camo applied for the normal pickup duration");return;
    }
    if (action >= 100 && action < 100 + NUMBEROF(weapons)) wanted = weapons[action - 100];
    else if (action >= 200 && action < 200 + NUMBEROF(vehicles)) { wanted = vehicles[action - 200]; group = 'vehi'; }
    else if (action == 2 || action == 3) { wanted = action == 2 ? "over shield" : "active camouflage"; group = 'eqip'; }
    if (!wanted) return;
    tag_iterator_new(&iterator, group);
    while ((tag = tag_iterator_next(&iterator)) != NONE) {
        const char *name = tag_get_name(tag), *leaf;
        if (!name) continue;
        leaf = strrchr(name, '\\');
        leaf = leaf ? leaf + 1 : name;
        if (!strcmp(leaf, wanted)) {
            memset(&reference, 0, sizeof(reference));
            reference.index = tag;
            {
                long player_index = cheat_player_index();
                struct player_datum *player = player_get(player_index);
                struct object_placement_data placement;
                real_point3d origin;
                real_vector3d forward, up;
                object_get_origin(player->unit_index, &origin);
                object_get_orientation(player->unit_index, &forward, &up);
                object_placement_data_new(&placement, reference.index, NONE);
                placement.position.x = origin.x + forward.i * (group == 'vehi' ? 4.f : 1.5f);
                placement.position.y = origin.y + forward.j * (group == 'vehi' ? 4.f : 1.5f);
                placement.position.z = origin.z + 0.8f;
                placement.forward = forward; placement.up = up;
                host_toast(object_new(&placement) == NONE ? "Could not spawn this asset here" : "Spawned in front of the player");
            }
            return;
        }
    }
    host_toast("This asset is not available in the current map");
}
#endif
