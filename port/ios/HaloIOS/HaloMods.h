#import <Foundation/Foundation.h>
/* Compiled Xbox map mods contain their weapon/character tags. Loose editor tags
   and executable plugins are not runtime-loadable by this engine. */
NSArray<NSDictionary *> *HaloModsList(void);
void HaloModsImport(NSArray<NSURL *> *files);
void HaloModsSetEnabled(NSUInteger index, BOOL enabled);
void HaloModsMove(NSUInteger index, NSInteger delta);
NSURL *HaloModsExport(NSUInteger index);
BOOL HaloModsPending(void);
BOOL HaloModsApply(NSError **error);
/* Disc imports replace an enabled mod's saved ORIGINAL, not its live overlay.
 * Returns transaction records; staged metadata is committed with the maps. */
NSArray<NSDictionary *> *HaloModsPlanBaseImport(NSArray<NSURL *> *files, NSURL *stage);
