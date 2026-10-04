#ifndef HALO_FRAME_DIAGNOSTICS_H
#define HALO_FRAME_DIAGNOSTICS_H
#include <stdint.h>
#include <string.h>
#define HALO_SLOW_FRAME_COUNT 8
/* All fields are copied host scalars; no live game/renderer pointers. */
typedef struct { uint64_t cap_wait_ns,drawable_ns; } HaloPresentTiming;
typedef struct {
    uint64_t number,interval_ns,update_ns,render_ns,present_ns;
    HaloPresentTiming display;
    unsigned role,peers,ping,mode;
    char map[64];
} HaloSlowFrame;
typedef struct { uint64_t slow_count,long_gaps;unsigned count;HaloSlowFrame frames[HALO_SLOW_FRAME_COUNT]; } HaloSlowFrames;
/* Retain the eight worst active intervals per reporting window. Loading and
 * background gaps and severe stalls are counted separately; classification requires logs. */
static inline int halo_slow_frame_slot(HaloSlowFrames *frames,uint64_t interval_ns) {
    if(interval_ns>UINT64_C(250000000)){frames->long_gaps++;return -1;}
    if(interval_ns<=UINT64_C(25000000))return -1;
    frames->slow_count++;
    if(frames->count<HALO_SLOW_FRAME_COUNT)return (int)frames->count++;
    unsigned smallest=0;
    for(unsigned i=1;i<frames->count;i++)if(frames->frames[i].interval_ns<frames->frames[smallest].interval_ns)smallest=i;
    return interval_ns>frames->frames[smallest].interval_ns?(int)smallest:-1;
}
static inline void halo_slow_frames_take(HaloSlowFrames *source,HaloSlowFrames *output) {
    *output=*source;memset(source,0,sizeof(*source));
}
#endif
