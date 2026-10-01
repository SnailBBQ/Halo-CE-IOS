#ifndef HALO_IOS_SCENE_SCAN_H
#define HALO_IOS_SCENE_SCAN_H
#include <stdint.h>
enum halo_scene_scan_kind { HALO_SCENE_TRIANGLES=1,HALO_SCENE_BIT_TRIANGLES,
    HALO_SCENE_MATERIAL_RUN,HALO_SCENE_MARK_SURFACES,HALO_SCENE_LEAF_REFERENCES,
    HALO_SCENE_FILTER_OBJECTS };
/* Fixed-width packet; interpretation is documented at each guest call site.
   Helpers own no cache, call no engine callbacks and retain no guest pointer. */
struct halo_scene_scan_packet { uint32_t kind,a[13]; };
#ifdef HALO_IOS_GUEST
extern const unsigned int ios_datum_layout[13];
void host_scene_scan(unsigned int packet);
int host_scene_datum(unsigned int kind,unsigned int data,unsigned int index,unsigned int result,unsigned int layout);
/* M2.6.26: compact rendered-object index list.
 * header_data = object_header_data data_array*
 * indices_va  = array of long object indices (in/out)
 * count       = number of indices
 * filter_mask = bit0 invisible, bit1 shadowless
 * layout      = same 13-word datum layout table
 * Returns 1 and writes the kept count into *result_va on success. */
int host_scene_filter_objects(unsigned int header_data, unsigned int indices_va,
    unsigned int count, unsigned int filter_mask, unsigned int result_va,
    unsigned int layout);
#endif
#endif
