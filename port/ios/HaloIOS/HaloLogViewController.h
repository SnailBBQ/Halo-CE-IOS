#import <UIKit/UIKit.h>

/* Diagnostics: two tabs. Summary says how the game is doing; Problems lists what went wrong, in plain words.
 * Closing returns to the game. */
@interface HaloLogViewController : UIViewController
@property(nonatomic, copy) NSString *(^bootLogProvider)(void);
@property(nonatomic, copy) NSString *(^gameLogProvider)(void);
@property(nonatomic, copy) void (^onShare)(UIView *source);
@end
