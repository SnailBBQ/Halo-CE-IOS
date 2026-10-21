#import "HaloMods.h"
#import "HaloBackupArchive.h"
#include "halo_toml_flags.h"
#include "halo_mods_state.h"
#ifndef HALO_BACKUP_TEST
#import "HaloSettingsStore.h"
#import "halo_ios_audio.h"
#import "halo_guest_runner.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#include <stdatomic.h>
#endif

/* All mutations run on the library's serial UI/job path. File replacements run
   only before guest startup. The durable journal precedes the first replacement;
   interrupted installs restore originals before retrying. No live engine state
   or guest addresses are stored here. Last enabled mod wins filename conflicts. */
static NSURL *ModRoot(void) { return [HaloBackupWork() URLByAppendingPathComponent:@"mods" isDirectory:YES]; }
static NSURL *ModFile(NSString *name) { return [ModRoot() URLByAppendingPathComponent:name]; }
static BOOL ValidName(NSString *name) {
    if(![name isKindOfClass:NSString.class] || name.length>128 || !name.length)return NO;
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."];
    return [name.pathExtension.lowercaseString isEqual:@"map"] && [name rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound && ![name hasPrefix:@"."];
}
static void ValidateMap(NSURL *url) {
    HaloBackupRequire(HaloBackupRegular(url),@"Choose a regular map file.");
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    HaloBackupRequire([attrs[NSFileSize] unsignedLongLongValue]>=2048 && [attrs[NSFileSize] unsignedLongLongValue]<=1024ull*1024*1024,@"Map size must be between 2 KB and 1 GB.");
    NSFileHandle *in=[NSFileHandle fileHandleForReadingFromURL:url error:nil];NSData *data=nil;
    @try { data=[in readDataOfLength:2048]; } @finally { [in closeFile]; }
    uint32_t magic=0,version=0,foot=0;HaloBackupRequire(data.length==2048,@"Map header is truncated.");
    memcpy(&magic,data.bytes,4);memcpy(&version,(char *)data.bytes+4,4);memcpy(&foot,(char *)data.bytes+2044,4);
    HaloBackupRequire(CFSwapInt32LittleToHost(magic)==0x68656164 && CFSwapInt32LittleToHost(version)==5 && CFSwapInt32LittleToHost(foot)==0x666f6f74,@"Mods must be compiled Xbox version 5 .map files. Compile loose weapon, character or other tags into a compatible map first.");
}
static NSArray<NSDictionary *> *HaloModsList(void) {
    NSArray *list=[NSArray arrayWithContentsOfURL:ModFile(@"list.plist")];
    if(!list)return @[];HaloBackupRequire(list.count<=256,@"Mod list is too large.");
    for(NSDictionary *m in list){
        HaloBackupRequire([m isKindOfClass:NSDictionary.class] && ValidName(m[@"file"]) && [m[@"id"] isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:m[@"id"]] && [m[@"hash"] isKindOfClass:NSString.class] && [m[@"hash"] length]==64,@"Invalid mod catalog.");
    }return list;
}
static void Save(NSArray *list) {
    HaloBackupRequire([NSFileManager.defaultManager createDirectoryAtURL:ModRoot() withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot create mod storage.");
    /* Pending first: even termination between these writes leaves a retryable request. */
    HaloBackupRequire([@{@"pending":@YES} writeToURL:ModFile(@"pending.plist") atomically:YES],@"Cannot queue mod changes.");
    HaloBackupRequire([list writeToURL:ModFile(@"list.plist") atomically:YES],@"Cannot save mod list.");
}
static BOOL HaloModsPending(void) { return [NSFileManager.defaultManager fileExistsAtPath:ModFile(@"pending.plist").path] || [NSFileManager.defaultManager fileExistsAtPath:ModFile(@"journal.plist").path]; }
/* Preserve existing filename casing and reject ambiguous duplicates. */
static NSURL *MapTarget(NSURL *maps,NSString *name) {
    NSString *match=nil;for(NSString *entry in [NSFileManager.defaultManager contentsOfDirectoryAtPath:maps.path error:nil])if([entry.lowercaseString isEqual:name.lowercaseString]){HaloBackupRequire(!match,@"Remove duplicate map filenames differing only by case before applying mods.");match=entry;}
    return [maps URLByAppendingPathComponent:match?:name];
}
static void Replace(NSURL *source,NSURL *dest) {
    NSFileManager *fm=NSFileManager.defaultManager;
    HaloBackupRequire(![fm fileExistsAtPath:dest.path] || HaloBackupRegular(dest),@"Destination is not a regular map file.");
    NSURL *tmp=[dest.URLByDeletingLastPathComponent URLByAppendingPathComponent:[@".mod-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    HaloBackupRequire([fm copyItemAtURL:source toURL:tmp error:nil],@"Cannot copy mod; check available storage.");
    BOOL ok=[fm fileExistsAtPath:dest.path]?[fm replaceItemAtURL:dest withItemAtURL:tmp backupItemName:nil options:0 resultingItemURL:nil error:nil]:[fm moveItemAtURL:tmp toURL:dest error:nil];
    if(!ok)[fm removeItemAtURL:tmp error:nil];HaloBackupRequire(ok,@"Cannot replace map.");
}
static BOOL HaloModsApply(NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *maps=[NSURL fileURLWithPath:[HaloBackupRoot() stringByAppendingPathComponent:@"maps"] isDirectory:YES];
    @try {
        NSDictionary *journal=[NSDictionary dictionaryWithContentsOfURL:ModFile(@"journal.plist")];
        if(journal){
            HaloBackupRequire([@{@"pending":@YES} writeToURL:ModFile(@"pending.plist") atomically:YES],@"Cannot queue recovered mod changes.");
            HaloBackupRequire([journal[@"files"] isKindOfClass:NSDictionary.class],@"Invalid mod recovery journal.");
            for(NSString *name in journal[@"files"]){HaloBackupRequire(ValidName(name),@"Invalid recovery map name.");NSURL *dest=MapTarget(maps,name);if([journal[@"files"][name] boolValue])Replace([ModFile(@"rollback") URLByAppendingPathComponent:name],dest);else HaloBackupRequire(![fm fileExistsAtPath:dest.path] || (HaloBackupRegular(dest)&&[fm removeItemAtURL:dest error:nil]),@"Cannot restore original maps.");}
            HaloBackupRequire([fm removeItemAtURL:ModFile(@"journal.plist") error:nil],@"Cannot finish mod recovery.");
        }
        if(!HaloModsPending())return YES;
        NSArray *list=HaloModsList();NSMutableDictionary *winners=[NSMutableDictionary dictionary];
        for(NSDictionary *m in list)if([m[@"enabled"] boolValue]){NSURL *source=[ModFile(m[@"id"]) URLByAppendingPathComponent:m[@"file"]];ValidateMap(source);HaloBackupRequire([HaloBackupHashFile(source) isEqual:m[@"hash"]],@"Imported mod has changed; reimport the file.");winners[m[@"file"]]=source;}
        NSMutableDictionary *base=[[NSDictionary dictionaryWithContentsOfURL:ModFile(@"base.plist")] mutableCopy]?:[NSMutableDictionary dictionary];
        HaloBackupRequire([fm createDirectoryAtURL:maps withIntermediateDirectories:YES attributes:nil error:nil] && [fm createDirectoryAtURL:ModFile(@"base") withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot prepare map folders.");
        for(NSString *name in winners)if(!base[name]){NSURL *dest=MapTarget(maps,name);BOOL exists=[fm fileExistsAtPath:dest.path];if(exists){HaloBackupRequire(HaloBackupRegular(dest),@"Original map is not a regular file.");NSURL *saved=[ModFile(@"base") URLByAppendingPathComponent:name];[fm removeItemAtURL:saved error:nil];HaloBackupRequire([fm copyItemAtURL:dest toURL:saved error:nil],@"Cannot preserve original map.");}base[name]=@(exists);}
        HaloBackupRequire([base writeToURL:ModFile(@"base.plist") atomically:YES],@"Cannot save original map catalog.");
        [fm removeItemAtURL:ModFile(@"rollback") error:nil];HaloBackupRequire([fm createDirectoryAtURL:ModFile(@"rollback") withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot create mod recovery folder.");
        NSMutableDictionary *had=[NSMutableDictionary dictionary];
        for(NSString *name in base){HaloBackupRequire(ValidName(name),@"Invalid original map name.");NSURL *dest=MapTarget(maps,name);BOOL exists=[fm fileExistsAtPath:dest.path];had[name]=@(exists);if(exists)HaloBackupRequire(HaloBackupRegular(dest)&&[fm copyItemAtURL:dest toURL:[ModFile(@"rollback") URLByAppendingPathComponent:name] error:nil],@"Cannot create recovery copy.");}
        HaloBackupRequire([@{@"files":had} writeToURL:ModFile(@"journal.plist") atomically:YES],@"Cannot create mod journal; maps unchanged.");
        for(NSString *name in base){NSURL *dest=MapTarget(maps,name),*source=winners[name];if(!source && [base[name] boolValue])source=[ModFile(@"base") URLByAppendingPathComponent:name];if(source)Replace(source,dest);else HaloBackupRequire(![fm fileExistsAtPath:dest.path] || (HaloBackupRegular(dest)&&[fm removeItemAtURL:dest error:nil]),@"Cannot unload mod map.");}
        /* Retire unloaded originals: future imports/restores can become the new
           base instead of a later mod change overwriting them with an old copy. */
        NSMutableDictionary *activeBase=[NSMutableDictionary dictionary];for(NSString *name in winners)activeBase[name]=base[name];
        HaloBackupRequire([activeBase writeToURL:ModFile(@"base.plist") atomically:YES],@"Cannot commit original map catalog.");
        /* Keep journal until pending is removed; any interrupted commit rolls back. */
        HaloBackupRequire([fm removeItemAtURL:ModFile(@"pending.plist") error:nil],@"Cannot commit mod changes.");
        HaloBackupRequire([fm removeItemAtURL:ModFile(@"journal.plist") error:nil],@"Cannot commit mod recovery journal.");return YES;
    } @catch(NSException *exception){if(error)*error=HaloBackupFailure([exception.reason stringByAppendingString:@" Halo has not started. Recovery will be retried next launch."]);return NO;}
}

/* ---------- M2.6.88: retire replacement mods; Custom Edition + MP4 library ---------- */

BOOL HaloModsLegacyExists(void)
{
    return [NSFileManager.defaultManager fileExistsAtPath:ModRoot().path];
}

BOOL HaloModsRetireLegacy(NSError **error)
{
    @try {
        if (!HaloModsLegacyExists()) return YES;
        NSArray *old = HaloModsList();
        if (old.count) {
            NSMutableArray *disabled = [NSMutableArray arrayWithCapacity:old.count];
            for (NSDictionary *entry in old) {
                NSMutableDictionary *copy = [entry mutableCopy];
                copy[@"enabled"] = @NO;
                [disabled addObject:copy];
            }
            Save(disabled);
        } else if (![NSFileManager.defaultManager fileExistsAtPath:ModFile(@"pending.plist").path] &&
                   ![NSFileManager.defaultManager fileExistsAtPath:ModFile(@"journal.plist").path]) {
            /* An empty legacy folder has no live overlay to unwind. */
            [NSFileManager.defaultManager removeItemAtURL:ModRoot() error:nil];
            return YES;
        }
        if (!HaloModsApply(error)) return NO;
        HaloBackupRequire(![NSFileManager.defaultManager fileExistsAtPath:ModRoot().path] ||
                          [NSFileManager.defaultManager removeItemAtURL:ModRoot() error:nil],
                          @"Original maps were restored, but the retired mod catalog could not be removed.");
        return YES;
    } @catch (NSException *exception) {
        if (error) *error = HaloBackupFailure([exception.reason stringByAppendingString:@" Halo has not started. Legacy map-mod cleanup will retry next launch."]);
        return NO;
    }
}

static NSURL *CustomRoot(void) { return [NSURL fileURLWithPath:[HaloBackupRoot() stringByAppendingPathComponent:@"custom_maps"] isDirectory:YES]; }
static NSURL *CustomDisabledRoot(void) { return [NSURL fileURLWithPath:[HaloBackupRoot() stringByAppendingPathComponent:@"custom_maps_disabled"] isDirectory:YES]; }
static NSURL *VideoRoot(void) { return [NSURL fileURLWithPath:[HaloBackupRoot() stringByAppendingPathComponent:@"videos"] isDirectory:YES]; }

static BOOL SafeLeaf(NSString *name, NSArray<NSString *> *extensions)
{
    if (![name isKindOfClass:NSString.class] || !name.length || name.length > 255 || [name hasPrefix:@"."]) return NO;
    if (![extensions containsObject:name.pathExtension.lowercaseString]) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_- ."];
    return [name rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static uint32_t Little32(const unsigned char *p)
{
    uint32_t value = 0;
    memcpy(&value, p, sizeof(value));
    return CFSwapInt32LittleToHost(value);
}

static NSDictionary *CustomMapInfo(NSURL *url, BOOL enabled)
{
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil] ?: @{};
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    NSData *header = nil;
    @try { header = [handle readDataOfLength:2048]; } @finally { [handle closeFile]; }
    uint32_t version = 0, type = 1; BOOL valid = NO;
    if (header.length == 2048) {
        const unsigned char *bytes = header.bytes;
        version = Little32(bytes + 4);
        type = (uint32_t)bytes[0x60] | ((uint32_t)bytes[0x61] << 8);   /* scenario type: 0 campaign, 1 multiplayer, 2 ui */
        valid = Little32(bytes) == UINT32_C(0x68656164) && version == 609 && Little32(bytes + 2044) == UINT32_C(0x666f6f74);
    }
    NSString *stem = url.lastPathComponent.stringByDeletingPathExtension;
    NSURL *folder = url.URLByDeletingLastPathComponent;
    return @{ @"file": url.lastPathComponent,
              @"enabled": @(enabled), @"valid": @(valid), @"version": @(version), @"type": @(type),
              @"size": attrs[NSFileSize] ?: @0,
              @"picture": @([NSFileManager.defaultManager fileExistsAtPath:[[folder URLByAppendingPathComponent:[stem stringByAppendingPathExtension:@"bmp"]] path]]),
              @"description": @([NSFileManager.defaultManager fileExistsAtPath:[[folder URLByAppendingPathComponent:[stem stringByAppendingPathExtension:@"txt"]] path]]) };
}

static BOOL IsCEResource(NSString *name)
{
    NSString *lower = name.lowercaseString;
    return [lower isEqual:@"bitmaps.map"] || [lower isEqual:@"sounds.map"] || [lower isEqual:@"loc.map"];
}

static void EnsureCustomFolders(void)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    HaloBackupRequire([fm createDirectoryAtURL:CustomRoot() withIntermediateDirectories:YES attributes:nil error:nil], @"Cannot create Custom Edition maps folder.");
    HaloBackupRequire([fm createDirectoryAtURL:CustomDisabledRoot() withIntermediateDirectories:YES attributes:nil error:nil], @"Cannot create disabled Custom Edition maps folder.");
}

static void AtomicInstall(NSURL *source, NSURL *destination)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    HaloBackupRequire(HaloBackupRegular(source), @"Choose regular files, not folders or links.");
    HaloBackupRequire([fm createDirectoryAtURL:destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil], @"Cannot prepare destination folder.");
    NSURL *temp = [destination.URLByDeletingLastPathComponent URLByAppendingPathComponent:[@".import-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    HaloBackupRequire([fm copyItemAtURL:source toURL:temp error:nil], @"Cannot copy content; check free storage.");
    BOOL ok = [fm fileExistsAtPath:destination.path]
        ? [fm replaceItemAtURL:destination withItemAtURL:temp backupItemName:nil options:0 resultingItemURL:nil error:nil]
        : [fm moveItemAtURL:temp toURL:destination error:nil];
    if (!ok) [fm removeItemAtURL:temp error:nil];
    HaloBackupRequire(ok, @"Cannot finish importing content.");
}

NSArray<NSDictionary *> *HaloCustomMapsList(void)
{
    EnsureCustomFolders();
    NSMutableArray *result = [NSMutableArray array];
    for (NSArray *pair in @[@[CustomRoot(), @YES], @[CustomDisabledRoot(), @NO]]) {
        NSURL *root = pair[0]; BOOL enabled = [pair[1] boolValue];
        NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:root.path error:nil] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *name in names) {
            if (!SafeLeaf(name, @[@"map"]) || IsCEResource(name)) continue;
            NSURL *file = [root URLByAppendingPathComponent:name];
            if (HaloBackupRegular(file)) [result addObject:CustomMapInfo(file, enabled)];
        }
    }
    return result;
}

NSDictionary<NSString *, NSNumber *> *HaloCustomResourcesStatus(void)
{
    EnsureCustomFolders();
    NSMutableDictionary *status = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"bitmaps.map", @"sounds.map", @"loc.map"])
        status[name] = @(HaloBackupRegular([CustomRoot() URLByAppendingPathComponent:name]));
    return status;
}

static void ValidateCEMap(NSURL *url)
{
    NSDictionary *info = CustomMapInfo(url, YES);
    uint32_t version = [info[@"version"] unsignedIntValue];
    if (version == 5) HaloBackupRequire(NO, @"That is an Xbox version 5 map. Use Import maps for original/Xbox maps; Custom Edition Maps requires version 609.");
    HaloBackupRequire([info[@"valid"] boolValue], @"Custom Edition map header is invalid or unsupported. OpenCE build 246 supports standard version 609 CE maps; OpenSauce maps are not supported.");
}

NSArray<NSURL *> *HaloImportSharedAndMovies(NSArray<NSURL *> *urls, NSString **summary, NSMutableArray<NSString *> *errors)
{
    NSMutableArray<NSURL *> *rest = [NSMutableArray array];
    NSMutableArray<NSString *> *done = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSString *name = url.lastPathComponent, *ext = name.pathExtension.lowercaseString;
        BOOL shared = [ext isEqual:@"map"] && IsCEResource(name), movie = [ext isEqual:@"mp4"];
        if (!shared && !movie) { [rest addObject:url]; continue; }
        @try {
            if (shared) {
                /* the first word of a resource map is its kind: 1 bitmaps, 2 sounds, 3 loc */
                NSFileHandle *in = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
                NSData *head = in ? [in readDataOfLength:4] : nil;
                [in closeFile];
                uint32_t kind = 0;
                if (head.length == 4) memcpy(&kind, head.bytes, 4);
                kind = CFSwapInt32LittleToHost(kind);
                HaloBackupRequire(kind >= 1 && kind <= 3, @"does not look like a Custom Edition shared resource file");
                HaloCustomContentImport(@[url]);
            } else {
                HaloMoviesImport(@[url]);
            }
            [done addObject:name.lowercaseString];
        } @catch (NSException *e) {
            [errors addObject:[NSString stringWithFormat:@"%@: %@", name, e.reason ?: @"could not be imported"]];
        }
    }
    if (summary) *summary = done.count ? [NSString stringWithFormat:@"Installed now: %@ (optional extras for Custom Edition maps and movies).", [done componentsJoinedByString:@", "]] : nil;
    return rest;
}

void HaloCustomContentImport(NSArray<NSURL *> *files)
{
    HaloBackupRequire(files.count > 0 && files.count <= 256, @"Choose up to 256 Custom Edition files at once.");
    EnsureCustomFolders();
    NSMutableSet *seen = [NSMutableSet set];
    for (NSURL *url in files) {
        NSString *name = url.lastPathComponent;
        HaloBackupRequire(SafeLeaf(name, @[@"map", @"bmp", @"txt"]), @"Custom Edition content may be .map, .bmp or .txt and must use a simple filename.");
        HaloBackupRequire(![seen containsObject:name.lowercaseString], @"Choose distinct filenames.");
        [seen addObject:name.lowercaseString];
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
        unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
        HaloBackupRequire(size > 0, @"Custom Edition file is empty.");
        NSString *ext = name.pathExtension.lowercaseString;
        if ([ext isEqual:@"map"]) {
            HaloBackupRequire(size <= 2ull * 1024 * 1024 * 1024, @"Map is larger than 2 GB.");
            if (!IsCEResource(name)) ValidateCEMap(url);
        } else if ([ext isEqual:@"bmp"]) {
            HaloBackupRequire(size <= 64ull * 1024 * 1024, @"Custom map picture must be 64 MB or smaller.");
        } else {
            HaloBackupRequire(size <= 1024, @"Custom map description must be 1 KB or smaller, matching OpenCE's limit.");
        }
        AtomicInstall(url, [CustomRoot() URLByAppendingPathComponent:name]);
        /* Importing an active copy retires a disabled copy of the same item. */
        [NSFileManager.defaultManager removeItemAtURL:[CustomDisabledRoot() URLByAppendingPathComponent:name] error:nil];
    }
}

static NSURL *FindCustomMap(NSString *file, BOOL enabled)
{
    HaloBackupRequire(SafeLeaf(file, @[@"map"]) && !IsCEResource(file), @"Invalid Custom Edition map name.");
    return [(enabled ? CustomRoot() : CustomDisabledRoot()) URLByAppendingPathComponent:file];
}

static void MoveSidecar(NSString *stem, NSString *ext, NSURL *from, NSURL *to)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *name = [stem stringByAppendingPathExtension:ext];
    NSURL *source = [from URLByAppendingPathComponent:name], *dest = [to URLByAppendingPathComponent:name];
    if (![fm fileExistsAtPath:source.path]) return;
    [fm removeItemAtURL:dest error:nil];
    HaloBackupRequire([fm moveItemAtURL:source toURL:dest error:nil], @"Cannot move Custom Edition sidecar file.");
}

void HaloCustomMapSetEnabled(NSString *file, BOOL enabled)
{
    EnsureCustomFolders();
    NSURL *source = FindCustomMap(file, !enabled), *dest = FindCustomMap(file, enabled);
    HaloBackupRequire(HaloBackupRegular(source), @"Custom Edition map no longer exists.");
    [NSFileManager.defaultManager removeItemAtURL:dest error:nil];
    HaloBackupRequire([NSFileManager.defaultManager moveItemAtURL:source toURL:dest error:nil], @"Cannot change Custom Edition map state.");
    NSString *stem = file.stringByDeletingPathExtension;
    MoveSidecar(stem, @"bmp", source.URLByDeletingLastPathComponent, dest.URLByDeletingLastPathComponent);
    MoveSidecar(stem, @"txt", source.URLByDeletingLastPathComponent, dest.URLByDeletingLastPathComponent);
}

void HaloCustomMapRemove(NSString *file)
{
    EnsureCustomFolders();
    NSString *stem = file.stringByDeletingPathExtension;
    for (NSURL *root in @[CustomRoot(), CustomDisabledRoot()]) {
        for (NSString *name in @[file, [stem stringByAppendingPathExtension:@"bmp"], [stem stringByAppendingPathExtension:@"txt"]]) {
            NSURL *url = [root URLByAppendingPathComponent:name];
            if ([NSFileManager.defaultManager fileExistsAtPath:url.path]) HaloBackupRequire([NSFileManager.defaultManager removeItemAtURL:url error:nil], @"Cannot remove Custom Edition map content.");
        }
    }
}

static BOOL SafeMovieName(NSString *name)
{
    return SafeLeaf(name, @[@"mp4"]);
}

static BOOL RecognizedMovieStem(NSString *stem)
{
    NSString *s = stem.lowercaseString;
    for (NSString *suffix in @[@"_de", @"_fr", @"_es", @"_it"])
        if ([s hasSuffix:suffix]) { s = [s substringToIndex:s.length - suffix.length]; break; }
    return [@[@"intro", @"credits", @"attract1", @"attract2", @"attract3"] containsObject:s];
}

NSArray<NSDictionary *> *HaloMoviesList(void)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtURL:VideoRoot() withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray *result = [NSMutableArray array];
    NSArray *names = [[fm contentsOfDirectoryAtPath:VideoRoot().path error:nil] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *name in names) {
        if (!SafeMovieName(name)) continue;
        NSURL *url = [VideoRoot() URLByAppendingPathComponent:name]; if (!HaloBackupRegular(url)) continue;
        NSDictionary *attrs = [fm attributesOfItemAtPath:url.path error:nil] ?: @{};
        [result addObject:@{ @"file": name, @"recognized": @(RecognizedMovieStem(name.stringByDeletingPathExtension)), @"size": attrs[NSFileSize] ?: @0 }];
    }
    return result;
}

void HaloMoviesImport(NSArray<NSURL *> *files)
{
    HaloBackupRequire(files.count > 0 && files.count <= 32, @"Choose up to 32 MP4 movies at once.");
    [NSFileManager.defaultManager createDirectoryAtURL:VideoRoot() withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSURL *url in files) {
        NSString *name = url.lastPathComponent.lowercaseString;
        HaloBackupRequire(SafeMovieName(name), @"Movies must be .mp4 files with simple filenames.");
        HaloBackupRequire(RecognizedMovieStem(name.stringByDeletingPathExtension), @"Use Halo movie names: intro.mp4, credits.mp4, attract1.mp4, attract2.mp4 or attract3.mp4. Localized _de/_fr/_es/_it variants are also accepted.");
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
        HaloBackupRequire([attrs[NSFileSize] unsignedLongLongValue] > 0 && [attrs[NSFileSize] unsignedLongLongValue] <= 8ull * 1024 * 1024 * 1024, @"Movie is empty or larger than 8 GB.");
        AtomicInstall(url, [VideoRoot() URLByAppendingPathComponent:name]);
    }
}

void HaloMovieRemove(NSString *file)
{
    HaloBackupRequire(SafeMovieName(file), @"Invalid movie filename.");
    NSURL *url = [VideoRoot() URLByAppendingPathComponent:file];
    HaloBackupRequire(![NSFileManager.defaultManager fileExistsAtPath:url.path] || [NSFileManager.defaultManager removeItemAtURL:url error:nil], @"Cannot remove movie.");
}

static NSURL *MovieURLForBinkPath(const char *binkPath)
{
    if (!binkPath || !*binkPath) return nil;
    NSString *raw = [[NSString stringWithUTF8String:binkPath] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    NSString *stem = raw.lastPathComponent.stringByDeletingPathExtension.lowercaseString;
    if (!stem.length) return nil;
    NSMutableArray *stems = [NSMutableArray arrayWithObject:stem];
    for (NSString *suffix in @[@"_de", @"_fr", @"_es", @"_it"])
        if ([stem hasSuffix:suffix]) { [stems addObject:[stem substringToIndex:stem.length - suffix.length]]; break; }
    for (NSString *candidate in stems) {
        NSURL *url = [VideoRoot() URLByAppendingPathComponent:[candidate stringByAppendingPathExtension:@"mp4"]];
        if (HaloBackupRegular(url)) return url;
    }
    return nil;
}

BOOL HaloMovieAvailablePath(const char *binkPath)
{
    return MovieURLForBinkPath(binkPath) != nil;
}

#ifndef HALO_BACKUP_TEST
@interface HaloMovieSurface : UIView
@property(nonatomic,strong) AVPlayerLayer *movieLayer;
@end
@implementation HaloMovieSurface
- (void)layoutSubviews { [super layoutSubviews];self.movieLayer.frame=self.bounds; }
@end

static AVPlayer *gMoviePlayer;
static HaloMovieSurface *gMovieSurface;
static id gMovieEndObserver, gMovieFailObserver;
static _Atomic int gMovieActive;
static unsigned long gMovieFlags;
static float gMovieRestoreVolume = 1.0f;
@class HaloMovieTapTarget;
static HaloMovieTapTarget *gMovieTapTarget;

static UIWindow *MovieWindow(void)
{
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState == UISceneActivationStateUnattached) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) return window;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static void MovieFinishMain(void)
{
    BOOL hadMovie = gMoviePlayer != nil || gMovieSurface != nil || atomic_load_explicit(&gMovieActive, memory_order_acquire) != 0;
    if (gMovieEndObserver) { [NSNotificationCenter.defaultCenter removeObserver:gMovieEndObserver]; gMovieEndObserver=nil; }
    if (gMovieFailObserver) { [NSNotificationCenter.defaultCenter removeObserver:gMovieFailObserver]; gMovieFailObserver=nil; }
    [gMoviePlayer pause]; gMoviePlayer=nil;
    [gMovieSurface removeFromSuperview]; gMovieSurface=nil;gMovieTapTarget=nil;
    atomic_store_explicit(&gMovieActive, 0, memory_order_release);
    if (hadMovie) { halo_ios_audio_set_volume(gMovieRestoreVolume);halo_ios_audio_resume(); }
}

@interface HaloMovieTapTarget : NSObject
@end
@implementation HaloMovieTapTarget
- (void)skip:(id)sender { (void)sender;MovieFinishMain(); }
@end

BOOL HaloMovieStartPath(const char *binkPath, unsigned long flags)
{
    NSURL *url = MovieURLForBinkPath(binkPath);
    if (!url) return NO;
    __block BOOL started = NO;
    void (^start)(void) = ^{
        MovieFinishMain();
        UIWindow *window = MovieWindow(); if (!window) return;
        gMovieFlags = flags;
        HsSettings settings = [HaloSettingsStore.shared snapshot];
        gMovieRestoreVolume = settings.volume;
        halo_ios_audio_set_volume(0.0f);
        gMoviePlayer = [AVPlayer playerWithURL:url];
        gMovieSurface = [[HaloMovieSurface alloc] initWithFrame:window.bounds];
        gMovieSurface.backgroundColor = UIColor.blackColor;
        gMovieSurface.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        gMovieSurface.movieLayer = [AVPlayerLayer playerLayerWithPlayer:gMoviePlayer];
        gMovieSurface.movieLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [gMovieSurface.layer addSublayer:gMovieSurface.movieLayer];
        UIButton *skip = [UIButton buttonWithType:UIButtonTypeCustom];skip.frame=gMovieSurface.bounds;skip.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;skip.userInteractionEnabled=(flags&(1ul<<1))!=0;
        gMovieTapTarget=[HaloMovieTapTarget new];[skip addTarget:gMovieTapTarget action:@selector(skip:) forControlEvents:UIControlEventTouchUpInside];[gMovieSurface addSubview:skip];
        [window addSubview:gMovieSurface];
        atomic_store_explicit(&gMovieActive, 1, memory_order_release);
        __weak AVPlayer *weakPlayer = gMoviePlayer;
        gMovieEndObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:gMoviePlayer.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){(void)note;if((gMovieFlags&1ul)&&weakPlayer){[weakPlayer seekToTime:kCMTimeZero];[weakPlayer play];}else MovieFinishMain();}];
        gMovieFailObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification object:gMoviePlayer.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){(void)note;MovieFinishMain();}];
        [gMoviePlayer play];started=YES;
    };
    if (NSThread.isMainThread) start(); else dispatch_sync(dispatch_get_main_queue(), start);
    return started;
}

BOOL HaloMovieIsActive(void)
{
    return atomic_load_explicit(&gMovieActive, memory_order_acquire) != 0;
}

void HaloMovieStop(void)
{
    if (NSThread.isMainThread) MovieFinishMain(); else dispatch_sync(dispatch_get_main_queue(), ^{MovieFinishMain();});
}

#else
BOOL HaloMovieStartPath(const char *binkPath, unsigned long flags) { (void)binkPath; (void)flags; return NO; }
BOOL HaloMovieIsActive(void) { return NO; }
void HaloMovieStop(void) {}
#endif


/* ---------- map sharing (config.toml) ---------- */

static NSString *HaloConfigTomlPath(void) { return [HaloBackupRoot() stringByAppendingPathComponent:@"config.toml"]; }

BOOL HaloMapSharingEnabled(void)
{
    NSString *text = [NSString stringWithContentsOfFile:HaloConfigTomlPath() encoding:NSUTF8StringEncoding error:nil];
    if (!text) return NO; /* no file yet: the iOS default is off */
    const char *utf8 = text.UTF8String;
    return halo_toml_get_bool(utf8, "network", "map_share") == 1 || halo_toml_get_bool(utf8, "network", "map_seed") == 1;
}

/* add_missing: a switch the person flips adds the keys; the one-time migration only turns existing "true" lines off. */
static BOOL HaloMapSharingWrite(BOOL on, int add_missing)
{
    NSString *path = HaloConfigTomlPath();
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text) {
        if (!add_missing) return YES;
        text = @""; /* the engine reads a file with only these keys and fills in the rest */
    }
    int changed_share = 0, changed_seed = 0;
    char *first = halo_toml_set_bool(text.UTF8String, "network", "map_share", on, add_missing, &changed_share);
    if (!first) return NO;
    char *second = halo_toml_set_bool(first, "network", "map_seed", on, add_missing, &changed_seed);
    free(first);
    if (!second) return NO;
    BOOL ok = YES;
    if (changed_share || changed_seed) {
        NSString *updated = [NSString stringWithUTF8String:second];
        NSError *error = nil;
        ok = updated && [updated writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    }
    free(second);
    return ok;
}

BOOL HaloMapSharingSet(BOOL on) { return HaloMapSharingWrite(on, 1); }

void HaloMapSharingMigrateDefaultOff(void)
{
    NSString *key = @"HaloMapSharingDefaultOffV1";
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:key]) return;
    /* builds before M2.6.110 wrote map_share/map_seed = true into config.toml; this turns those two lines off once, so a
       later choice in Settings is never undone */
    if (HaloMapSharingWrite(NO, 0)) [defaults setBool:YES forKey:key];
}

BOOL HaloConfigBool(const char *section, const char *key, BOOL fallback)
{
    NSString *text = [NSString stringWithContentsOfFile:HaloConfigTomlPath() encoding:NSUTF8StringEncoding error:nil];
    int value = text ? halo_toml_get_bool(text.UTF8String, section, key) : -1;
    return value < 0 ? fallback : value == 1;
}

BOOL HaloConfigSetBool(const char *section, const char *key, BOOL value)
{
    NSString *path = HaloConfigTomlPath();
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    int changed = 0;
    char *updated = halo_toml_set_bool(text.UTF8String, section, key, value ? 1 : 0, 1, &changed);
    if (!updated) return NO;
    BOOL ok = YES;
    if (changed) ok = [[NSString stringWithUTF8String:updated] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    free(updated);
    return ok;
}


#pragma mark - OpenCE mods (build 220)

static NSString *ModPackRoot(void) { return [HaloBackupRoot() stringByAppendingPathComponent:@"mods"]; }
static NSString *ModPackOrderPath(void) { return [ModPackRoot() stringByAppendingPathComponent:@"load_order.toml"]; }

static NSString *ModPackText(NSString *path, NSUInteger limit)
{
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;
    NSData *data = nil;
    @try { data = [handle readDataOfLength:limit]; } @catch (NSException *e) { (void)e; } @finally { [handle closeFile]; }
    return data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static NSArray<NSString *> *ModPackStrings(NSString *text, const char *key)
{
    if (!text) return @[];
    static char list[64][HMS_TEXT];
    int n = hms_strings(text.UTF8String, key, list, 64);
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < n; i++) {
        NSString *s = [NSString stringWithUTF8String:list[i]];
        if (s) [result addObject:s];
    }
    return result;
}

static NSString *ModPackOne(NSString *text, const char *key)
{
    return ModPackStrings(text, key).firstObject ?: @"";
}

static BOOL ModPackNamed(NSString *name, NSDictionary *info)
{
    return [name caseInsensitiveCompare:info[@"folder"]] == NSOrderedSame || [name caseInsensitiveCompare:info[@"id"]] == NSOrderedSame;
}

NSArray<NSDictionary *> *HaloModPackList(void)
{
    @synchronized (NSFileManager.defaultManager) {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
        for (NSString *name in [fm contentsOfDirectoryAtPath:ModPackRoot() error:nil]) {
            if (!hms_folder_ok(name.UTF8String) || [name hasPrefix:@"."] || found.count >= HMS_MAX_MODS) continue;
            NSString *folder = [ModPackRoot() stringByAppendingPathComponent:name];
            BOOL directory = NO;
            if (![fm fileExistsAtPath:folder isDirectory:&directory] || !directory) continue;
            if (!HaloBackupRegular([NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"mod.toml"]])) continue;   /* no mod.toml: not a mod */
            NSString *toml = ModPackText([folder stringByAppendingPathComponent:@"mod.toml"], 65536) ?: @"";
            NSString *modName = ModPackOne(toml, "name");
            NSString *identifier = ModPackOne(toml, "id");
            [found addObject:@{ @"folder": name, @"id": identifier.length ? identifier : name, @"name": modName.length ? modName : name,
                                @"version": ModPackOne(toml, "version"),
                                @"authors": [ModPackStrings(toml, "authors") componentsJoinedByString:@", "],
                                @"description": ModPackOne(toml, "description"),
                                @"maps": [ModPackStrings(toml, "maps") componentsJoinedByString:@", "],
                                @"incompatible": ModPackStrings(toml, "incompatible"),
                                @"format": @([ModPackOne(toml, "format") integerValue]) }];
        }
        static char folders[HMS_MAX_MODS][HMS_NAME];
        static char kept[HMS_MAX_MODS][HMS_TEXT];
        int order[HMS_MAX_MODS];
        for (NSUInteger i = 0; i < found.count; i++) snprintf(folders[i], HMS_NAME, "%s", [found[i][@"folder"] UTF8String]);
        NSString *orderText = ModPackText(ModPackOrderPath(), 262144);
        int keptCount = orderText ? hms_strings(orderText.UTF8String, "order", kept, HMS_MAX_MODS) : 0;
        NSArray<NSString *> *disabledNames = ModPackStrings(orderText, "disabled");
        int n = hms_order(folders, (int)found.count, kept, keptCount, order);
        NSMutableArray<NSMutableDictionary *> *result = [NSMutableArray array];
        for (int i = 0; i < n; i++) {
            NSMutableDictionary *mod = [found[(NSUInteger)order[i]] mutableCopy];
            BOOL off = NO;
            for (NSString *d in disabledNames) if ([d caseInsensitiveCompare:mod[@"folder"]] == NSOrderedSame) off = YES;
            mod[@"on"] = @(!off);
            [result addObject:mod];
        }
        /* what is wrong with each: made for a later format than this build's (1), or a mod that is on names it as incompatible */
        for (NSMutableDictionary *mod in result) {
            NSMutableArray *notes = [NSMutableArray array];
            if ([mod[@"format"] integerValue] > 1) [notes addObject:@"Made for a later version of the game's mods. It stays off."];
            for (NSDictionary *other in result) {
                if (other == mod || ![other[@"on"] boolValue]) continue;
                for (NSString *name in other[@"incompatible"])
                    if (ModPackNamed(name, mod)) [notes addObject:[NSString stringWithFormat:@"%@ says it cannot be played with this mod.", other[@"name"]]];
                if ([mod[@"on"] boolValue])
                    for (NSString *name in mod[@"incompatible"])
                        if (ModPackNamed(name, other)) [notes addObject:[NSString stringWithFormat:@"This mod says it cannot be played with %@.", other[@"name"]]];
            }
            mod[@"note"] = [notes componentsJoinedByString:@" "];
            [mod removeObjectForKey:@"incompatible"];
            [mod removeObjectForKey:@"format"];
        }
        return result;
    }
}

static void ModPackSignal(void)
{
#ifndef HALO_BACKUP_TEST
    halo_ios_mods_changed();
#endif
}

void HaloModPackSave(NSArray<NSString *> *order, NSSet<NSString *> *off)
{
    HaloBackupRequire(order.count <= HMS_MAX_MODS, @"Too many mods.");
    static char names[HMS_MAX_MODS][HMS_NAME];
    int flags[HMS_MAX_MODS];
    for (NSUInteger i = 0; i < order.count; i++) {
        HaloBackupRequire(hms_folder_ok(order[i].UTF8String), @"A mod folder has a name the game cannot use.");
        snprintf(names[i], HMS_NAME, "%s", order[i].UTF8String);
        flags[i] = [off containsObject:order[i]] ? 1 : 0;
    }
    size_t size = 512 + order.count * 2 * (HMS_NAME * 6 + 8);
    char *text = malloc(size);
    HaloBackupRequire(text != NULL, @"Out of memory.");
    size_t length = hms_serialize(text, size, names, flags, (int)order.count);
    NSData *data = length ? [NSData dataWithBytes:text length:length] : nil;
    free(text);
    HaloBackupRequire(data != nil, @"Cannot write the load order.");
    HaloBackupRequire([NSFileManager.defaultManager createDirectoryAtPath:ModPackRoot() withIntermediateDirectories:YES attributes:nil error:nil], @"Cannot create the mods folder.");
    HaloBackupRequire([data writeToFile:ModPackOrderPath() atomically:YES], @"Cannot write mods/load_order.toml.");
    ModPackSignal();
}

void HaloModPackRemove(NSString *folder)
{
    HaloBackupRequire(hms_folder_ok(folder.UTF8String) && ![folder hasPrefix:@"."], @"That is not a mod folder.");
    NSString *path = [ModPackRoot() stringByAppendingPathComponent:folder];
    HaloBackupRequire([NSFileManager.defaultManager removeItemAtPath:path error:nil], @"Cannot remove that mod.");
    /* load_order.toml may still name it: the game leaves out a mod that is gone, so nothing else needs changing */
    ModPackSignal();
}

void HaloModPackImport(NSArray<NSURL *> *folders)
{
    HaloBackupRequire(folders.count > 0 && folders.count <= 32, @"Choose up to 32 mod folders at once.");
    NSFileManager *fm = NSFileManager.defaultManager;
    HaloBackupRequire([fm createDirectoryAtPath:ModPackRoot() withIntermediateDirectories:YES attributes:nil error:nil], @"Cannot create the mods folder.");
    for (NSURL *source in folders) {
        BOOL access = [source startAccessingSecurityScopedResource];
        @try {
            NSString *name = source.lastPathComponent;
            HaloBackupRequire(hms_folder_ok(name.UTF8String) && ![name hasPrefix:@"."], ([NSString stringWithFormat:@"“%@” cannot be a mod folder name (up to 63 bytes, no slash).", name]));
            BOOL directory = NO;
            HaloBackupRequire([fm fileExistsAtPath:source.path isDirectory:&directory] && directory, ([NSString stringWithFormat:@"“%@” is not a folder. Choose the mod's folder, the one with mod.toml in it.", name]));
            HaloBackupRequire(HaloBackupRegular([source URLByAppendingPathComponent:@"mod.toml"]), ([NSString stringWithFormat:@"“%@” has no mod.toml, so it is not a mod. Choose the folder that has mod.toml and a tags folder.", name]));
            NSString *target = [ModPackRoot() stringByAppendingPathComponent:name];
            HaloBackupRequire(![fm fileExistsAtPath:target], ([NSString stringWithFormat:@"A mod named “%@” is already installed. Remove it first to replace it.", name]));
            /* count first: the game reads 262144 files at most, and links would point outside the mod */
            NSUInteger count = 0;
            NSDirectoryEnumerator *walk = [fm enumeratorAtURL:source includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey, NSURLIsRegularFileKey] options:0 errorHandler:nil];
            for (NSURL *item in walk) {
                NSNumber *link = nil;
                [item getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];
                HaloBackupRequire(!link.boolValue, @"A mod cannot contain links.");
                HaloBackupRequire(++count <= 262144, @"That mod has too many files (262144 at most).");
            }
            NSString *temp = [ModPackRoot() stringByAppendingPathComponent:[@".import-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            NSError *error = nil;
            if (![fm copyItemAtURL:source toURL:[NSURL fileURLWithPath:temp] error:&error] || ![fm moveItemAtPath:temp toPath:target error:&error]) {
                [fm removeItemAtPath:temp error:nil];
                HaloBackupRequire(NO, ([NSString stringWithFormat:@"Cannot copy “%@”: %@", name, error.localizedDescription ?: @"check free space."]));
            }
        } @finally {
            if (access) [source stopAccessingSecurityScopedResource];
        }
    }
    ModPackSignal();
}

NSString *HaloModPackFingerprint(void)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableString *text = [NSMutableString string];
    NSDate *order = [fm attributesOfItemAtPath:ModPackOrderPath() error:nil][NSFileModificationDate];
    [text appendFormat:@"%.3f", order.timeIntervalSince1970];
    for (NSString *name in [[fm contentsOfDirectoryAtPath:ModPackRoot() error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
        NSDate *date = [fm attributesOfItemAtPath:[[ModPackRoot() stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"mod.toml"] error:nil][NSFileModificationDate];
        [text appendFormat:@"|%@:%.3f", name, date.timeIntervalSince1970];
    }
    return text;
}
