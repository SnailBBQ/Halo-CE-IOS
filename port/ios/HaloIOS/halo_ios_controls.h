#ifndef HALO_IOS_CONTROLS_H
#define HALO_IOS_CONTROLS_H

#import <UIKit/UIKit.h>

/* Full original-Xbox controller drawn over the game: two sticks, LT/RT, A/B/X/Y,
 * White/Black, D-pad, Back/Start and the stick clicks, laid out by the active control
 * scheme (HaloSettingsStore). Also floating sticks and touch-look. Feeds the guest's SDL
 * gamepad through halo_ios_menu_button / halo_ios_pad_axis / halo_ios_touch_look. */
@interface HaloControlsView : UIView
@property(nonatomic, readonly) BOOL editing;
/* Called after the player taps Done in the layout editor. */
@property(nonatomic, copy) void (^onEditFinished)(void);
/* Lifts every finger and clears all buttons and axes. */
- (void)releaseAll;
/* Layout editor: drag controls, resize, hide, reset; saved into the active scheme. */
- (void)beginEditing;
@end

/* Starts listening for MFi / Xbox / PlayStation controllers. `changed` runs on
 * the main queue with YES while at least one controller is connected. */
/* Rising-edge shortcut inputs; always delivered on the main queue. */
void halo_ios_shortcut_button(int button);
/* Main-queue editor capture. nil ends capture; gameplay input is withheld while active. */
void halo_ios_shortcut_capture(void (^record)(int button));
void halo_ios_controller_rumble_at(int slot,unsigned low,unsigned high,unsigned milliseconds);
void halo_ios_controller_rumble(unsigned low, unsigned high, unsigned milliseconds);
void halo_ios_controllers_start(void (^changed)(BOOL connected));

#endif
