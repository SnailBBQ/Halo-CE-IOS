#ifndef HALO_GAMEPLAY_SLICE_H
#define HALO_GAMEPLAY_SLICE_H

#include <stdint.h>

enum {
    HALO_GAME_TEAM_COUNT = 10,
    HALO_ALLEGIANCE_MAX = 8,
    HALO_INCIDENT_ACCIDENT = 0,
    HALO_INCIDENT_BETRAYAL = 1,
    HALO_INCIDENT_FORGIVE = 2
};

typedef struct halo_game_allegiance_record {
    int16_t team1_index;
    int16_t team2_index;
    int16_t incident_threshold;
    int16_t incident_decay_time;
    uint8_t team1_suspicious;
    uint8_t team2_suspicious;
    uint8_t currently_broken;
    uint8_t status_changed;
    uint8_t requires_communication;
    uint8_t reserved0D;
    int16_t current_incidents;
    int16_t current_incident_decay_time;
} halo_game_allegiance_record;

typedef struct halo_game_allegiance_globals {
    int16_t allegiance_count;
    halo_game_allegiance_record allegiances[HALO_ALLEGIANCE_MAX];
    uint8_t reserved92[2];
    uint32_t ally_bitvector[4];
    uint32_t friendly_bitvector[4];
} halo_game_allegiance_globals;

void halo_gameplay_initialize_fixture(halo_game_allegiance_globals *globals);
uint8_t halo_game_team_is_enemy(const halo_game_allegiance_globals *globals,
                                int16_t our_team_index, int16_t other_team_index);
uint8_t halo_game_team_is_ally(const halo_game_allegiance_globals *globals,
                               int16_t our_team_index, int16_t other_team_index);
uint8_t halo_game_team_ally_status_changed(const halo_game_allegiance_globals *globals,
                                           int16_t our_team_index, int16_t other_team_index);
int16_t halo_game_allegiance_get_incidents(const halo_game_allegiance_globals *globals,
                                           int16_t our_team_index, int16_t other_team_index,
                                           int16_t *incident_threshold);
void halo_game_allegiance_provoke(halo_game_allegiance_globals *globals,
                                  int16_t aggressor_team_index, int16_t victim_team_index);
void halo_game_allegiance_notify_change(halo_game_allegiance_globals *globals,
                                        int16_t team1_index, int16_t team2_index);
uint8_t halo_game_allegiance_incident(halo_game_allegiance_globals *globals,
                                      int16_t aggressor_team_index, int16_t victim_team_index,
                                      int16_t incident_type, uint8_t *notify_immediately);

#endif
