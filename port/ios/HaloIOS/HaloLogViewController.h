#import <UIKit/UIKit.h>

/* The log, made readable: a plain-language summary, problems only, the full log with
 * colours and a filter, and the game's own debug.txt. */
@interface HaloLogViewController : UIViewController
@property(nonatomic, copy) NSString *(^bootLogProvider)(void);
@property(nonatomic, copy) NSString *(^gameLogProvider)(void);
@property(nonatomic, copy) void (^onShare)(UIView *source);
@end
