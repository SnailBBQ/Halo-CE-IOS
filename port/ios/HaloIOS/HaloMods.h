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
/* "Import maps" accepts more than Xbox maps in one pick: bitmaps.map, sounds.map and loc.map (the Custom Edition shared files) go to
 * custom_maps, and MP4 fallback movies go to the videos folder. Both are optional; the game boots without them. The return value is
 * the rest of the pick (the Xbox .map files); `summary` says what was installed and `errors` collects what was refused. */
NSArray<NSURL *> *HaloImportSharedAndMovies(NSArray<NSURL *> *urls, NSString **summary, NSMutableArray<NSString *> *errors);
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
/* Any true/false key of config.toml: the file's value, or fallback when the key is absent; the setter adds the key when needed. */
BOOL HaloConfigBool(const char *section, const char *key, BOOL fallback);
BOOL HaloConfigSetBool(const char *section, const char *key, BOOL value);

/* OpenCE's Mods (build 220): folders of Halo PC tag files in Documents/Halo/mods, each with a mod.toml. The game's own Mods menu
 * and Settings > Mods read and write the same things, mods/load_order.toml and the folders, so a change made in one shows in
 * the other: Settings reads the files each time it shows the list, and after a change tells the running game to read them
 * again. Entries come in load order (the first loads first; the game's menu and Settings show the last on top). Keys: folder,
 * name, version, authors, description, maps, on (BOOL), note (what is wrong with it, or ""). */
NSArray<NSDictionary *> *HaloModPackList(void);
/* Keeps the load order (folder names, first loads first) and the folders turned off; the running game applies it at once. */
void HaloModPackSave(NSArray<NSString *> *order, NSSet<NSString *> *off);
/* Toggle against the latest on-disk order so an in-game change cannot be
overwritten by a Settings row that was rendered before it. */
void HaloModPackSetEnabled(NSString *folder, BOOL enabled);
void HaloModPackRemove(NSString *folder);
/* Copies mod folders (each with a mod.toml) into the mods folder; throws with a message the person can read. */
void HaloModPackImport(NSArray<NSURL *> *folders);
/* Changes whenever a mod or load_order.toml changes, so a shown list can tell it is out of date. */
NSString *HaloModPackFingerprint(void);
