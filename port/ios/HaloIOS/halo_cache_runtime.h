#ifndef HALO_CACHE_RUNTIME_H
#define HALO_CACHE_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

typedef struct halo_ios_cache_boot_result
{
    uint32_t discovered_maps;
    uint32_t valid_maps;
    uint32_t selected_tag_count;
    uint32_t selected_scenario_tag_index;
    uint32_t selected_tag_instances_va;
    uint32_t selected_tag_data_size;
    uint32_t selected_scenario_base_va;
    uint32_t selected_file_length;
    int selected_map_found;
    int header_valid;
    int tag_data_loaded;
    int tag_header_valid;
    int scenario_instance_resolved;
} halo_ios_cache_boot_result;

int halo_ios_cache_bootstrap(void (^line)(const char *text),
                             halo_ios_cache_boot_result *result);

/* State retained after a successful bootstrap so the engine stage can keep
 * consuming the same expanded ui.map rather than reopening/reinflating it. */
int halo_ios_cache_copy_selected_range(uint32_t file_offset,
                                       uint32_t size,
                                       void *destination);
int halo_ios_cache_copy_selected_range_to_guest(uint32_t file_offset,
                                                uint32_t size,
                                                uint32_t guest_va);
int halo_ios_cache_find_tag(uint32_t group_tag,
                            const char *name,
                            uint32_t *tag_index,
                            uint32_t *base_va);
uint32_t halo_ios_cache_tag_instances_va(void);
uint32_t halo_ios_cache_tag_count(void);
uint32_t halo_ios_cache_scenario_tag_index(void);
uint32_t halo_ios_cache_scenario_base_va(void);
uint32_t halo_ios_cache_selected_file_length(void);

#endif
