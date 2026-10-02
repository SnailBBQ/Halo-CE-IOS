/* Checks the event numbers and field offsets port/ios/HaloIOS/halo_sdl_events.h writes against the
 * real SDL3 headers the guest is built with. A mismatch fails the build instead of silently feeding
 * the game the wrong event.
 * cc -Ibuild/android/third_party/SDL3/include -Iport/ios/HaloIOS tools/tests/test_ios_sdl_event_numbers.c */
#include <SDL3/SDL_events.h>
#include <stddef.h>
#include <stdio.h>
#include "halo_sdl_events.h"

_Static_assert(SDL_EVENT_WINDOW_FOCUS_GAINED == HALO_SDL_EVENT_WINDOW_FOCUS_GAINED, "focus gained event number");
_Static_assert(SDL_EVENT_MOUSE_MOTION == HALO_SDL_EVENT_MOUSE_MOTION, "mouse motion event number");
_Static_assert(sizeof(SDL_Event) == HALO_SDL_EVENT_SIZE, "SDL_Event size");
_Static_assert(offsetof(SDL_MouseMotionEvent, type) == 0, "type");
_Static_assert(offsetof(SDL_MouseMotionEvent, timestamp) == 8, "timestamp");
_Static_assert(offsetof(SDL_MouseMotionEvent, windowID) == 16, "windowID");
_Static_assert(offsetof(SDL_MouseMotionEvent, which) == 20, "which");
_Static_assert(offsetof(SDL_MouseMotionEvent, state) == 24, "state");
_Static_assert(offsetof(SDL_MouseMotionEvent, x) == 28, "x");
_Static_assert(offsetof(SDL_MouseMotionEvent, y) == 32, "y");
_Static_assert(offsetof(SDL_MouseMotionEvent, xrel) == 36, "xrel");
_Static_assert(offsetof(SDL_MouseMotionEvent, yrel) == 40, "yrel");
_Static_assert(offsetof(SDL_WindowEvent, windowID) == 16, "window event windowID");

int main(void)
{
    SDL_Event event;

    halo_sdl_event_mouse_motion((uint8_t *)&event, 5.0f, -2.0f, 99);
    if (event.type != SDL_EVENT_MOUSE_MOTION || event.motion.xrel != 5.0f || event.motion.yrel != -2.0f ||
        event.motion.windowID != 1 || event.motion.timestamp != 99)
    {
        printf("FAIL: mouse motion does not read back through SDL's own struct\n");
        return 1;
    }
    halo_sdl_event_focus_gained((uint8_t *)&event, 7);
    if (event.type != SDL_EVENT_WINDOW_FOCUS_GAINED || event.window.windowID != 1)
    {
        printf("FAIL: focus event does not read back through SDL's own struct\n");
        return 1;
    }
    printf("PASS: event numbers and offsets match the SDL3 headers\n");
    return 0;
}
