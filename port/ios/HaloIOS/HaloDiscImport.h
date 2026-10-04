#import <Foundation/Foundation.h>
typedef BOOL (^HaloDiscCancel)(void);
/* All work runs on a serial background job before engine launch. */
BOOL HaloDiscImportPending(void);
BOOL HaloDiscImportRecover(NSError **error);
BOOL HaloDiscInstall(NSURL *stage,BOOL replace,HaloDiscCancel cancel,
    NSUInteger *installed,NSUInteger *kept,NSError **error);
