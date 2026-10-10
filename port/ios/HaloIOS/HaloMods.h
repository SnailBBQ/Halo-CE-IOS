#import <Foundation/Foundation.h>

/* M2.6.88 retires the old Xbox-map replacement mod system. This one-time
 * migration restores originals from its durable journal/base store, then
 * removes the legacy catalog. */
BOOL HaloModsLegacyExists(void);
BOOL HaloModsRetireLegacy(NSError **error);

/* Halo Custom Edition content. Active files live in Documents/Halo/custom_maps
 * exactly where OpenCE build 182 scans them. Disabled maps are moved to the
 * sibling custom_maps_disabled directory; resource maps stay active. */
NSArray<NSDictionary *> *HaloCustomMapsList(void);
NSDictionary<NSString *, NSNumber *> *HaloCustomResourcesStatus(void);
void HaloCustomContentImport(NSArray<NSURL *> *files);
void HaloCustomMapSetEnabled(NSString *file, BOOL enabled);
void HaloCustomMapRemove(NSString *file);

/* User-supplied MP4 replacements for Halo's Bink movie requests. A matching
 * stem is used (intro.bik -> videos/intro.mp4, credits.bik -> credits.mp4).
 * Localized _de/_fr/_es/_it names fall back to the unsuffixed MP4. */
NSArray<NSDictionary *> *HaloMoviesList(void);
void HaloMoviesImport(NSArray<NSURL *> *files);
void HaloMovieRemove(NSString *file);
BOOL HaloMovieAvailablePath(const char *binkPath);
BOOL HaloMovieStartPath(const char *binkPath, unsigned long flags);
BOOL HaloMovieIsActive(void);
void HaloMovieStop(void);
