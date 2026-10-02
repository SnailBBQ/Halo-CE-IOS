#ifndef HALO_FRAME_PACER_H
#define HALO_FRAME_PACER_H

/*
 * Holds the presented frame rate at a chosen cap (Settings > Display > Smooth 60). Pure arithmetic on
 * nanosecond times so tools/tests/test_ios_frame_pacer.c can check it without a clock or a screen.
 * Cap 0 means uncapped: the display's own refresh limits the rate.
 */

#include <stdint.h>

typedef struct
{
    uint64_t next_ns;   /* when the next frame may be presented; 0 before the first */
} HaloFramePacer;

/* Called just before presenting at `now_ns`. Returns how many nanoseconds to wait first (0 for none), and
 * moves the schedule on as if the frame were presented after that wait. */
static inline uint64_t halo_pacer_wait(HaloFramePacer *pacer, uint64_t now_ns, int cap_fps)
{
    uint64_t interval, wait = 0, at;

    if (cap_fps <= 0)
    {
        pacer->next_ns = 0;     /* a later cap starts fresh */
        return 0;
    }
    interval = 1000000000ull / (uint64_t)cap_fps;
    if (pacer->next_ns == 0)
    {
        pacer->next_ns = now_ns + interval;
        return 0;
    }
    at = now_ns;
    if (pacer->next_ns > now_ns)
    {
        wait = pacer->next_ns - now_ns;
        at = pacer->next_ns;
    }
    /* a frame more than two intervals late (a load, a pause) starts the count again rather than racing to catch up */
    pacer->next_ns = (at - pacer->next_ns > 2 * interval) ? at + interval : pacer->next_ns + interval;
    return wait;
}

#endif
