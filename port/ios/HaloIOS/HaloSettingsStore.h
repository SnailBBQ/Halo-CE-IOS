#import <Foundation/Foundation.h>
#import "halo_settings_core.h"

extern NSString *const HaloSettingsChangedNotification;

/* The saved control schemes and options. Thread-safe; changes are saved at once. */
@interface HaloSettingsStore : NSObject
+ (instancetype)shared;
- (HsSettings)snapshot;
/* Runs `block` on a copy, sanitizes and saves the result, applies audio, and posts
 * HaloSettingsChangedNotification on the main queue. */
- (void)update:(void (^)(HsSettings *settings))block;
@end
