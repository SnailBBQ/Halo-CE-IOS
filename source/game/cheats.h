/*
CHEATS.H

header included in hcex build.
*/

#ifndef __CHEATS_H
#define __CHEATS_H
#pragma once

/* ---------- constants */

/* ---------- macros */

/* ---------- structures */

struct cheat_globals
{
	boolean deathless_player;
	boolean jetpack;
	boolean infinite_ammo;
	boolean bump_possession;
	boolean super_jump;
	boolean reflexive_damage_effects;
	boolean medusa;
	boolean omnipotent;
	boolean controller_enabled;
	boolean bottomless_clip;
};

/* ---------- prototypes/CHEATS.C */

void cheats_initialize(
	void);
void cheats_initialize_for_new_map(
	void);
void cheat_teleport_to_camera(
	void);
void cheat_active_camouflage(
	void);
void cheat_all_weapons(
	void);
void cheat_all_powerups(
	void);
void cheat_all_vehicles(
	void);
void cheats_dispose(
	void);
void cheats_dispose_from_old_map(
	void);
void cheats_update(
	void);
void cheats_network_client_enforce(
	void);
void cheats_load(
	void);
void cheat_active_camouflage_local_player(
	short player_index);

#ifdef HALO_IOS_GUEST
#include "../../port/include/halo_ios_campaign_options.h"
boolean ios_cheat_local_unit(long unit_index);
boolean ios_cheat_enabled(long unit_index, unsigned int flag);
real ios_cheat_jump_multiplier(long unit_index);
real ios_cheat_speed_multiplier(long unit_index);
real ios_cheat_field_of_view(long unit_index);
#endif

/* ---------- globals */

extern struct cheat_globals cheat;

/* ---------- public code */

#endif // __CHEATS_H
