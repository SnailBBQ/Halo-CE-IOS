#import <UIKit/UIKit.h>

/* Settings with a category list on the left (Multiplayer first, Logs last) and the chosen category's cards on the right. */
@interface HaloSettingsViewController : UIViewController
/* "Edit button layout": the owner closes this screen and starts the layout editor. */
@property(nonatomic, copy) void (^onEditLayout)(void);
/* "Logs" at the bottom of the list: the owner closes this screen and shows the log, like the old Log button. */
@property(nonatomic, copy) void (^onShowLog)(void);
@property(nonatomic, copy) void (^onShareLogs)(UIView *source);
/* "Copy logs as text": the owner puts HaloProblemReportText(YES) on the clipboard. */
@property(nonatomic, copy) void (^onCopyLogs)(UIView *source);
@end

/* The text that Share logs, Copy logs and Report a problem send: the app version, device, thermal state and memory, the settings (never
 * running cheats), and the end of each log with the history of runs that ended badly first. `compact` keeps it short enough to paste
 * into a message. */
NSString *HaloProblemReportText(BOOL compact);

/* The custom Settings button picture (an emoji or a photo) for gear_icon 4 and 5; nil when it cannot be made. */
UIImage *HaloGearCustomImage(const void *settings);   /* settings is a const HsSettings * */
