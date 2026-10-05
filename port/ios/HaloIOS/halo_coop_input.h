#ifndef HALO_COOP_INPUT_H
#define HALO_COOP_INPUT_H
#include <stdint.h>
/* Snapshot hardware ownership when entering local two-player co-op.
 * Do not recompute on disconnect: another controller must not steal a player. */
static inline void halo_coop_route(int first,int second,int *primary,int *secondary) {
    *primary=first&&second?0:-1;
    *secondary=first&&second?1:first?0:second?1:0;
}
/* Match upstream's rest-only ownership changes: a held A/B or stick must not
 * become a fresh press on the other player when joining/leaving a lobby. */
static inline int halo_coop_switch_ready(const uint32_t held[2],const int32_t axes[2][6]) {
    for(int pad=0;pad<2;pad++) {
        if(held[pad])return 0;
        for(int axis=0;axis<6;axis++)if(axes[pad][axis]>8000 || axes[pad][axis]<-8000)return 0;
    }
    return 1;
}
#endif
