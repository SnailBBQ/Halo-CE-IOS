#import "HaloMods.h"
#import "HaloBackupArchive.h"
#include "halo_toml_flags.h"
#ifndef HALO_BACKUP_TEST
#import "HaloSettingsStore.h"
#import "halo_ios_audio.h"
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
    uint32_t version = 0; BOOL valid = NO;
    if (header.length == 2048) {
        const unsigned char *bytes = header.bytes;
        version = Little32(bytes + 4);
        valid = Little32(bytes) == UINT32_C(0x68656164) && version == 609 && Little32(bytes + 2044) == UINT32_C(0x666f6f74);
    }
    NSString *stem = url.lastPathComponent.stringByDeletingPathExtension;
    NSURL *folder = url.URLByDeletingLastPathComponent;
    return @{ @"file": url.lastPathComponent,
              @"enabled": @(enabled), @"valid": @(valid), @"version": @(version),
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
    HaloBackupRequire([info[@"valid"] boolValue], @"Custom Edition map header is invalid or unsupported. OpenCE build 211 supports standard version 609 CE maps; OpenSauce maps are not supported.");
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

/* ---------- voice chat mode (config.toml) ---------- */

static const char *const kVoiceChatNames[3] = { "off", "open_mic", "push_to_talk" };

NSInteger HaloVoiceChatMode(void)
{
    NSString *text = [NSString stringWithContentsOfFile:HaloConfigTomlPath() encoding:NSUTF8StringEncoding error:nil];
    char word[32];
    if (!text || !halo_toml_get_string(text.UTF8String, "audio", "voice_chat", word, sizeof word)) return 2; /* the engine's default */
    for (NSInteger i = 0; i < 3; i++) if (!strcmp(word, kVoiceChatNames[i])) return i;
    return 2;
}

BOOL HaloVoiceChatSetMode(NSInteger mode)
{
    if (mode < 0 || mode > 2) return NO;
    NSString *path = HaloConfigTomlPath();
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    int changed = 0;
    char *updated = halo_toml_set_string(text.UTF8String, "audio", "voice_chat", kVoiceChatNames[mode], 1, &changed);
    if (!updated) return NO;
    BOOL ok = YES;
    if (changed) ok = [[NSString stringWithUTF8String:updated] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    free(updated);
    return ok;
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
