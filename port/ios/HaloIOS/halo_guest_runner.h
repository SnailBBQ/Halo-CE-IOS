#ifndef HALO_GUEST_RUNNER_H
#define HALO_GUEST_RUNNER_H

int halo_ios_run_full_guest(void (^line)(const char *text));

#include <stdint.h>

/* SDL gamepad button index; called by the on-screen controls. */
void halo_ios_menu_button(int button, int pressed);
/* SDL gamepad axis index (0..3 sticks, 4/5 triggers); value -32768..32767
 * (triggers 0..32767). On-screen controls. */
void halo_ios_pad_axis(int axis, int value);
/* Clears every on-screen button and axis (physical controller untouched). */
void halo_ios_menu_reset(void);
/* A physical controller's whole state: SDL button bit mask and six axes. */
void halo_ios_physical_pad_state(uint32_t buttons, const int32_t axes[6]);

/* The sampling profiler (log reports "Where the time goes"); costs about 1% of one core. */
void halo_ios_set_profiler_enabled(int enabled);

/* Frames successfully presented so far (for the on-screen frame rate). */
uint64_t halo_ios_presented_frames(void);

/* Touch-look: finger motion in points; delivered to the game as mouse motion. */
void halo_ios_touch_look(float dx, float dy);
/* Makes the game look at the clipboard (an invite link) on its next event poll. */
void halo_ios_post_focus_event(void);

#endif
