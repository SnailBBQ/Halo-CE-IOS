#pragma once
#include <stdint.h>
/* Preserve per-output-frame additions and packet completion order exactly. */
static void halo_silent_native(double *cursor, double step, uint32_t frames,
    uint32_t count, uint32_t (*packets)[2])
{
    double position=*cursor;
    for (uint32_t frame=0; frame<frames; frame++) {
        uint32_t packet;
        for (;;) {
            for (packet=0; packet<count && packets[packet][1]; packet++) {}
            if (packet==count || position<(double)packets[packet][0]) break;
            position-=(double)packets[packet][0];
            packets[packet][1]=1;
        }
        if (packet==count) break;
        position+=step;
    }
    *cursor=position;
}
