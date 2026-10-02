#import <UIKit/UIKit.h>

/* Settings with a category list on the left (Multiplayer first, Logs last) and the chosen category's cards on the right. */
@interface HaloSettingsViewController : UIViewController
/* "Edit button layout": the owner closes this screen and starts the layout editor. */
@property(nonatomic, copy) void (^onEditLayout)(void);
/* "Logs" at the bottom of the list: the owner closes this screen and shows the log, like the old Log button. */
@property(nonatomic, copy) void (^onShowLog)(void);
@property(nonatomic, copy) void (^onShareLogs)(UIView *source);
@end
