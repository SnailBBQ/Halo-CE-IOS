#ifndef HALO_ENGINE_BOOT_H
#define HALO_ENGINE_BOOT_H

#include <stdint.h>

typedef struct halo_ios_engine_boot_result
{
    uint32_t scenario_base_va;
    uint32_t scenario_type;
    uint32_t bsp_reference_count;
    uint32_t bsp_reference_array_va;
    uint32_t bsp_file_offset;
    uint32_t bsp_file_size;
    uint32_t bsp_load_va;
    uint32_t bsp_definition_va;
    uint32_t bsp_tag_index;
    uint32_t game_globals_tag_index;
    uint32_t game_globals_base_va;
    int scenario_state_bound;
    int bsp_loaded;
    int bsp_header_valid;
    int bsp_tag_instance_bound;
    int game_globals_resolved;
    int source_scenario_load_complete;
} halo_ios_engine_boot_result;

int halo_ios_engine_boot_main_menu(void (^line)(const char *text),
                                   halo_ios_engine_boot_result *result);

#endif
