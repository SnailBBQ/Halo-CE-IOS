#import <UIKit/UIKit.h>
/* Restore runs before the guest or settings singleton is started. */
BOOL HaloApplyPendingRestore(NSError **error);
UIViewController *HaloBackupsController(void);
UIViewController *HaloBackupsControllerForSections(unsigned sections);
UIViewController *HaloMapsController(void);
/* The same Mods page without its own navigation bar, for Settings to show in its detail area. */
UIViewController *HaloModsPageController(void);
