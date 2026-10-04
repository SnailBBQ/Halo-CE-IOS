#ifndef HALO_COOP_INPUT_H
#define HALO_COOP_INPUT_H
/* Snapshot hardware ownership when entering local two-player co-op.
 * Do not recompute on disconnect: another controller must not steal a player. */
static inline void halo_coop_route(int first,int second,int *primary,int *secondary) {
    *primary=first&&second?0:-1;
    *secondary=first&&second?1:first?0:second?1:0;
}
#endif
