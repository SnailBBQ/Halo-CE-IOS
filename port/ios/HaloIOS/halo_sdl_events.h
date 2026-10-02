#ifndef HALO_SDL_EVENTS_H
#define HALO_SDL_EVENTS_H

/*
 * The few SDL3 events the host feeds the guest through host_sdl_poll_event.
 * The guest's SDL_Event is a 128-byte union; only the fields the game reads are
 * written. Numbers and offsets are SDL3's (SDL_events.h): window events start at
 * 0x202 with FOCUS_GAINED as the 13th, mouse motion is 0x400.
 */

#include <stdint.h>
#include <string.h>

#define HALO_SDL_EVENT_SIZE 128
#define HALO_SDL_EVENT_WINDOW_FOCUS_GAINED 0x20E
#define HALO_SDL_EVENT_MOUSE_MOTION 0x400

static inline void halo_sdl_event_header(uint8_t *event, uint32_t type, uint64_t timestamp_ns)
{
    uint32_t window = 1;

    memset(event, 0, HALO_SDL_EVENT_SIZE);
    memcpy(event + 0, &type, 4);
    memcpy(event + 8, &timestamp_ns, 8);
    memcpy(event + 16, &window, 4); /* windowID, the same position in every window/mouse event */
}

static inline void halo_sdl_event_focus_gained(uint8_t *event, uint64_t timestamp_ns)
{
    halo_sdl_event_header(event, HALO_SDL_EVENT_WINDOW_FOCUS_GAINED, timestamp_ns);
}

/* SDL_MouseMotionEvent: windowID 16, which 20, state 24, x 28, y 32, xrel 36, yrel 40 */
static inline void halo_sdl_event_mouse_motion(uint8_t *event, float xrel, float yrel, uint64_t timestamp_ns)
{
    float zero = 0.0f;

    halo_sdl_event_header(event, HALO_SDL_EVENT_MOUSE_MOTION, timestamp_ns);
    memcpy(event + 28, &zero, 4);
    memcpy(event + 32, &zero, 4);
    memcpy(event + 36, &xrel, 4);
    memcpy(event + 40, &yrel, 4);
}

/*
 * Touch-look accumulator: finger motion collected between polls, handed over as
 * at most one motion event per poll. Keeps the game's mouse-look fed without a
 * flood of tiny events, and never loses a swipe if the game polls slowly.
 */
typedef struct { float dx, dy; } HaloLookAccumulator;

static inline void halo_look_add(HaloLookAccumulator *a, float dx, float dy) { a->dx += dx; a->dy += dy; }

/* returns 1 and the motion if any is pending (clearing it) */
static inline int halo_look_take(HaloLookAccumulator *a, float *dx, float *dy)
{
    if (a->dx == 0.0f && a->dy == 0.0f)
        return 0;
    *dx = a->dx; *dy = a->dy;
    a->dx = 0.0f; a->dy = 0.0f;
    return 1;
}

#endif
