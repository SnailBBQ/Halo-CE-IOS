#import <Foundation/Foundation.h>

/* M2.6.88 retires the old Xbox-map replacement mod system. This one-time
 * migration restores originals from its durable journal/base store, then
 * removes the legacy catalog. */
BOOL HaloModsLegacyExists(void);
BOOL HaloModsRetireLegacy(NSError **error);

/* Halo Custom Edition content. Active files live in Documents/Halo/custom_maps
 * exactly where OpenCE build 211 scans them. Disabled maps are moved to the
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

/* Map sharing (OpenCE's network.map_share: this phone sends maps to players who lack them; network.map_seed: it helps
 * other players send them). Off by default on iOS. The Settings switch edits the two keys in Documents/Halo/config.toml and
 * leaves the rest of the file alone; it takes effect the next time the game starts. Downloading a map a game needs
 * (network.map_download) is not changed. */
BOOL HaloMapSharingEnabled(void);
BOOL HaloMapSharingSet(BOOL on);
/* Once per install: turns off sharing in a config.toml written by an earlier version, which wrote "true". */
void HaloMapSharingMigrateDefaultOff(void);
/* Voice chat mode in config.toml (audio.voice_chat): 0 off, 1 open mic, 2 push to talk (the default; needs a keyboard or controller button). */
NSInteger HaloVoiceChatMode(void);
BOOL HaloVoiceChatSetMode(NSInteger mode);
/* Any true/false key of config.toml: the file's value, or fallback when the key is absent; the setter adds the key when needed. */
BOOL HaloConfigBool(const char *section, const char *key, BOOL fallback);
BOOL HaloConfigSetBool(const char *section, const char *key, BOOL value);
