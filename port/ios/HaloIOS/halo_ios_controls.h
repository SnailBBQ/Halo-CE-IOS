#ifndef HALO_IOS_CONTROLS_H
#define HALO_IOS_CONTROLS_H

#import <UIKit/UIKit.h>

/* Full original-Xbox controller drawn over the game: two sticks, LT/RT, A/B/X/Y,
 * White/Black, D-pad, Back/Start and the stick clicks. Feeds the guest's SDL
 * gamepad through halo_ios_menu_button / halo_ios_pad_axis. */
@interface HaloControlsView : UIView
/* Lifts every finger and clears all buttons and axes. */
- (void)releaseAll;
@end

/* Starts listening for MFi / Xbox / PlayStation controllers. `changed` runs on
 * the main queue with YES while at least one controller is connected. */
void halo_ios_controllers_start(void (^changed)(BOOL connected));

#endif
