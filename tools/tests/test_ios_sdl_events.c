#include "halo_sdl_events.h"
#include <stdio.h>
#include <math.h>

int main(void)
{
    uint8_t e[HALO_SDL_EVENT_SIZE];
    memset(e, 0xAA, sizeof(e));
    halo_sdl_event_mouse_motion(e, 12.5f, -3.25f, 123456789ull);
    uint32_t type; memcpy(&type, e, 4);
    uint64_t ts; memcpy(&ts, e + 8, 8);
    float x, y, xr, yr; memcpy(&x, e + 28, 4); memcpy(&y, e + 32, 4); memcpy(&xr, e + 36, 4); memcpy(&yr, e + 40, 4);
    uint32_t window, which, state; memcpy(&window, e + 16, 4); memcpy(&which, e + 20, 4); memcpy(&state, e + 24, 4);
    if (type != 0x400 || ts != 123456789ull || xr != 12.5f || yr != -3.25f || x != 0 || y != 0 || window != 1 || which != 0 || state != 0 || e[127] != 0) {
        printf("FAIL: mouse motion layout\n"); return 1;
    }
    halo_sdl_event_focus_gained(e, 7);
    memcpy(&type, e, 4);
    if (type != 0x20E || e[100] != 0) { printf("FAIL: focus event\n"); return 1; }
    /* SDL3 window events count up from 0x202; FOCUS_GAINED is the 13th (SHOWN is the first) */
    if (HALO_SDL_EVENT_WINDOW_FOCUS_GAINED != 0x202 + 12) { printf("FAIL: numbering\n"); return 1; }

    HaloLookAccumulator a = {0, 0};
    float dx, dy;
    if (halo_look_take(&a, &dx, &dy)) { printf("FAIL: empty accumulator\n"); return 1; }
    halo_look_add(&a, 3, 1); halo_look_add(&a, -1, 2);
    if (!halo_look_take(&a, &dx, &dy) || dx != 2 || dy != 3) { printf("FAIL: accumulate\n"); return 1; }
    if (halo_look_take(&a, &dx, &dy)) { printf("FAIL: cleared\n"); return 1; }
    printf("PASS: SDL event layout and touch-look accumulator\n");
    return 0;
}
