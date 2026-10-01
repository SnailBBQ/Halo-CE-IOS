#ifndef HALO_IOS_SCENE_SCAN_H
#define HALO_IOS_SCENE_SCAN_H
#include <stdint.h>
enum halo_scene_scan_kind { HALO_SCENE_TRIANGLES=1,HALO_SCENE_BIT_TRIANGLES,
    HALO_SCENE_MATERIAL_RUN,HALO_SCENE_MARK_SURFACES,HALO_SCENE_LEAF_REFERENCES };
/* Fixed-width packet; interpretation is documented at each guest call site.
   Helpers own no cache, call no engine callbacks and retain no guest pointer. */
struct halo_scene_scan_packet { uint32_t kind,a[13]; };
#ifdef HALO_IOS_GUEST
void host_scene_scan(unsigned int packet);
int host_scene_datum(unsigned int kind,unsigned int data,unsigned int index,unsigned int result,unsigned int layout);
#endif
#endif
