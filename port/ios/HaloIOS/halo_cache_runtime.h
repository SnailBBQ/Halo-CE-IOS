#ifndef HALO_CACHE_RUNTIME_H
#define HALO_CACHE_RUNTIME_H

#include <stdint.h>

typedef struct halo_ios_cache_boot_result
{
    uint32_t discovered_maps;
    uint32_t valid_maps;
    uint32_t selected_tag_count;
    uint32_t selected_scenario_tag_index;
    uint32_t selected_tag_instances_va;
    uint32_t selected_tag_data_size;
    int selected_map_found;
    int header_valid;
    int tag_data_loaded;
    int tag_header_valid;
    int scenario_instance_resolved;
} halo_ios_cache_boot_result;

int halo_ios_cache_bootstrap(void (^line)(const char *text),
                             halo_ios_cache_boot_result *result);

#endif
