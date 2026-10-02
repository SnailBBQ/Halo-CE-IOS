#import <UIKit/UIKit.h>

/* Control schemes (5 named presets), aim, audio, multiplayer and diagnostics. */
@interface HaloSettingsViewController : UIViewController
/* Tapped "Edit layout": the owner closes this screen and starts the layout editor. */
@property(nonatomic, copy) void (^onEditLayout)(void);
@property(nonatomic, copy) void (^onShowLog)(void);
@property(nonatomic, copy) void (^onShareLogs)(UIView *source);
@end
