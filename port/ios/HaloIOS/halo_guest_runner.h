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
/* Cancels touch ownership without discarding a physical controller snapshot. */
void halo_ios_touch_reset(void);
/* A physical controller's whole state: SDL button bit mask and six axes. */
void halo_ios_physical_pad_state(uint32_t buttons, const int32_t axes[6]);

/* Safe start (after a start that did not finish): 1 turns off sound, internet play, smooth 60 FPS, hi-res
 * HUD/text and the profiler. The notes are lines the log shows at the start of the run. */
void halo_ios_set_safe_level(int level);
int halo_ios_safe_level(void);
void halo_ios_set_launch_notes(const char *note, const char *crash_report);
void halo_ios_leave_safe_mode(void);
/* Back in the foreground: re-marks a running game as running. */
void halo_ios_phase_foreground(void);

/* Cheats from Settings: 1 god mode, 2 infinite ammo, 4 infinite grenades, 8 no reloading. The game applies
 * them only in the campaign (source/game/cheats.c). */
void halo_ios_set_cheat_flags(uint32_t flags);
/* Local first-person meshes: bit 0 weapon, bit 1 hands. */
void halo_ios_set_viewmodel_flags(uint32_t flags);
/* One-shot request; refuses a second action until the game consumes the first. */
int halo_ios_queue_campaign_action(uint32_t action);
void halo_ios_campaign_state(int active);
void halo_ios_quit_app(void);

/* The sampling profiler (log reports "Where the time goes"); costs about 1% of one core. */
void halo_ios_set_profiler_enabled(int enabled);

/* Frames successfully presented so far (for the on-screen frame rate). */
uint64_t halo_ios_presented_frames(void);

/* Touch-look: finger motion in points; delivered to the game as mouse motion. */
void halo_ios_touch_look(float dx, float dy);
/* Touch-only assistance; reset on cancellation, settings, background and controller connection. */
void halo_ios_set_touch_auto_fire(int enabled);
void halo_ios_set_touch_controller_connected(int connected);
/* Makes the game look at the clipboard (an invite link) on its next event poll. */
void halo_ios_post_focus_event(void);

int halo_ios_coop_touch_primary(void);
void halo_ios_physical_pad_state_at(int slot,int connected,uint32_t buttons,const int32_t axes[6]);
void halo_ios_set_channel_gains(float music,float dialogue,float effects);
/* Host-side copies only. Changes are applied on the guest game thread. */
void halo_ios_engine_settings_changed(const void *before, const void *after);
/* Environment sounds (the device and ambient sound classes); 0 ... 1. */
void halo_ios_set_ambient_gain(float gain);
#ifdef __OBJC__
@class NSString;
NSString *HaloNetworkSummary(void);
#endif
#endif
