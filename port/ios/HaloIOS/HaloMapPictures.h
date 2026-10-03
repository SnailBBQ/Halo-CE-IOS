#ifdef HALO_MAP_PICTURE_TEST
#import <Foundation/Foundation.h>
@interface UIImage : NSObject
@property(nonatomic,copy) NSData *rgba;
@property(nonatomic) NSUInteger width,height;
@end
#else
#import <UIKit/UIKit.h>
#endif
/* Background-only parser. Images come from the user's ui.map, never bundled
 * copyrighted assets or live renderer memory. Unsupported caches return nil. */
NSDictionary<NSString *,UIImage *> *HaloReadMapPictures(NSURL *url);
