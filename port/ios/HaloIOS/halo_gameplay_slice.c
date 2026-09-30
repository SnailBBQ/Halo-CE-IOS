/*
 * M1.3 source-derived gameplay cluster from source/game/game_allegiance.c.
 *
 * The team/allegiance state machine and structure layout are preserved using
 * fixed-width Xbox/Win32-sized fields. The original AI notification callback
 * performed by game_allegiance_broken() is intentionally excluded from this
 * isolated slice; that host/subsystem boundary belongs to the later boot/runtime
 * integration stage.
 */
#include "halo_gameplay_slice.h"

#include <stddef.h>
#include <string.h>

_Static_assert(sizeof(halo_game_allegiance_record) == 0x12,
               "allegiance record must preserve recovered 0x12 layout");
_Static_assert(sizeof(halo_game_allegiance_globals) == 0xB4,
               "allegiance globals must preserve recovered 0xB4 layout");

static int valid_team(int16_t team)
{
    return team >= 0 && team < HALO_GAME_TEAM_COUNT;
}

static int bit_index(int16_t a, int16_t b)
{
    return HALO_GAME_TEAM_COUNT * a + b;
}

static uint8_t bit_test(const uint32_t *v, int index)
{
    return (uint8_t)((v[index >> 5] >> (index & 31)) & 1u);
}

static void bit_set(uint32_t *v, int index, uint8_t value)
{
    uint32_t mask = UINT32_C(1) << (index & 31);
    if (value)
        v[index >> 5] |= mask;
    else
        v[index >> 5] &= ~mask;
}

static halo_game_allegiance_record *find_record(
    halo_game_allegiance_globals *globals, int16_t a, int16_t b)
{
    for (int16_t i = 0; i < globals->allegiance_count; ++i)
    {
        halo_game_allegiance_record *r = &globals->allegiances[i];
        if ((r->team1_index == a && r->team2_index == b) ||
            (r->team2_index == a && r->team1_index == b))
            return r;
    }
    return NULL;
}

static const halo_game_allegiance_record *find_record_const(
    const halo_game_allegiance_globals *globals, int16_t a, int16_t b)
{
    for (int16_t i = 0; i < globals->allegiance_count; ++i)
    {
        const halo_game_allegiance_record *r = &globals->allegiances[i];
        if ((r->team1_index == a && r->team2_index == b) ||
            (r->team2_index == a && r->team1_index == b))
            return r;
    }
    return NULL;
}

static void local_allegiance_broken(halo_game_allegiance_globals *globals,
                                    halo_game_allegiance_record *r,
                                    uint8_t currently_broken,
                                    uint8_t permanently_broken)
{
    if (!permanently_broken && r->currently_broken == currently_broken)
        return;

    r->currently_broken = currently_broken;
    if (valid_team(r->team1_index) && valid_team(r->team2_index))
    {
        bit_set(globals->ally_bitvector,
                bit_index(r->team1_index, r->team2_index),
                (uint8_t)!permanently_broken);
        bit_set(globals->ally_bitvector,
                bit_index(r->team2_index, r->team1_index),
                (uint8_t)!permanently_broken);
        bit_set(globals->friendly_bitvector,
                bit_index(r->team1_index, r->team2_index),
                (uint8_t)!currently_broken);
        bit_set(globals->friendly_bitvector,
                bit_index(r->team2_index, r->team1_index),
                (uint8_t)!currently_broken);
    }
    r->status_changed = 1;
}

void halo_gameplay_initialize_fixture(halo_game_allegiance_globals *globals)
{
    memset(globals, 0, sizeof(*globals));

    for (int16_t team = 0; team < HALO_GAME_TEAM_COUNT; ++team)
        bit_set(globals->friendly_bitvector, bit_index(team, team), 1);

    globals->allegiance_count = 1;
    halo_game_allegiance_record *r = &globals->allegiances[0];
    r->team1_index = 1;              /* player */
    r->team2_index = 3;              /* covenant */
    r->incident_threshold = 3;
    r->incident_decay_time = 10;
    r->team1_suspicious = 1;
    r->team2_suspicious = 1;
    r->requires_communication = 0;
    r->currently_broken = 0;

    bit_set(globals->ally_bitvector, bit_index(1, 3), 1);
    bit_set(globals->ally_bitvector, bit_index(3, 1), 1);
    bit_set(globals->friendly_bitvector, bit_index(1, 3), 1);
    bit_set(globals->friendly_bitvector, bit_index(3, 1), 1);
}

uint8_t halo_game_team_is_enemy(const halo_game_allegiance_globals *globals,
                                int16_t our_team_index, int16_t other_team_index)
{
    uint8_t result = 1;
    if (valid_team(our_team_index) && valid_team(other_team_index))
        result = (uint8_t)!bit_test(globals->friendly_bitvector,
                                    bit_index(our_team_index, other_team_index));
    return result;
}

uint8_t halo_game_team_is_ally(const halo_game_allegiance_globals *globals,
                               int16_t our_team_index, int16_t other_team_index)
{
    uint8_t result = 0;
    if (valid_team(our_team_index) && valid_team(other_team_index))
        result = bit_test(globals->ally_bitvector,
                          bit_index(our_team_index, other_team_index));
    return result;
}

uint8_t halo_game_team_ally_status_changed(const halo_game_allegiance_globals *globals,
                                           int16_t our_team_index, int16_t other_team_index)
{
    const halo_game_allegiance_record *r =
        find_record_const(globals, our_team_index, other_team_index);
    return r ? r->status_changed : 0;
}

int16_t halo_game_allegiance_get_incidents(const halo_game_allegiance_globals *globals,
                                           int16_t our_team_index, int16_t other_team_index,
                                           int16_t *incident_threshold)
{
    const halo_game_allegiance_record *r =
        find_record_const(globals, our_team_index, other_team_index);
    int16_t incidents = 0;
    int16_t threshold = -1;
    if (r)
    {
        incidents = r->current_incidents;
        threshold = r->incident_threshold;
    }
    if (incident_threshold)
        *incident_threshold = threshold;
    return incidents;
}

void halo_game_allegiance_provoke(halo_game_allegiance_globals *globals,
                                  int16_t aggressor_team_index, int16_t victim_team_index)
{
    halo_game_allegiance_record *r =
        find_record(globals, aggressor_team_index, victim_team_index);
    if (!r)
        return;

    uint8_t suspicious =
        (r->team1_index == aggressor_team_index) ?
        r->team2_suspicious : r->team1_suspicious;

    if (suspicious && r->current_incidents > 0 &&
        r->incident_decay_time != -1)
        r->current_incident_decay_time = r->incident_decay_time;
}

void halo_game_allegiance_notify_change(halo_game_allegiance_globals *globals,
                                        int16_t team1_index, int16_t team2_index)
{
    halo_game_allegiance_record *r = find_record(globals, team1_index, team2_index);
    if (r)
        r->status_changed = 0;
}

uint8_t halo_game_allegiance_incident(halo_game_allegiance_globals *globals,
                                      int16_t aggressor_team_index, int16_t victim_team_index,
                                      int16_t incident_type, uint8_t *notify_immediately)
{
    halo_game_allegiance_record *r =
        find_record(globals, aggressor_team_index, victim_team_index);
    if (!r)
        return 0;

    uint8_t suspicious =
        (r->team1_index == aggressor_team_index) ?
        r->team2_suspicious : r->team1_suspicious;
    if (!suspicious)
        return 0;

    int16_t increment = 0;
    switch (incident_type)
    {
        case HALO_INCIDENT_ACCIDENT:  increment = 1; break;
        case HALO_INCIDENT_BETRAYAL: increment = 3; break;
        case HALO_INCIDENT_FORGIVE:  increment = -1; break;
        default: break;
    }

    r->current_incidents += increment;
    if (r->incident_decay_time != -1)
        r->current_incident_decay_time = r->incident_decay_time;

    if (r->incident_threshold != -1 &&
        r->current_incidents >= r->incident_threshold)
    {
        local_allegiance_broken(globals, r, 1, 0);
        if (notify_immediately)
            *notify_immediately = (uint8_t)!r->requires_communication;
        return 1;
    }

    return 0;
}
