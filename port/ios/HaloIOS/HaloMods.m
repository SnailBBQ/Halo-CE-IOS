#import "HaloMods.h"
#import "HaloBackupArchive.h"

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
NSArray<NSDictionary *> *HaloModsList(void) {
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
void HaloModsImport(NSArray<NSURL *> *files) {
    NSMutableArray *list=[HaloModsList() mutableCopy];HaloBackupRequire(files.count && list.count+files.count<=256,@"Choose up to 256 mods.");
    NSMutableArray *copied=[NSMutableArray array];
    @try {
        for(NSURL *url in files){
            NSString *name=url.lastPathComponent.lowercaseString;HaloBackupRequire(ValidName(name),@"Use a .map filename containing letters, numbers, dots, dashes or underscores.");ValidateMap(url);
            NSString *identifier=NSUUID.UUID.UUIDString;NSURL *folder=ModFile(identifier);HaloBackupRequire([NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot create mod folder.");[copied addObject:folder];
            NSURL *dest=[folder URLByAppendingPathComponent:name];HaloBackupRequire([NSFileManager.defaultManager copyItemAtURL:url toURL:dest error:nil],@"Cannot import mod; check available storage.");
            [list addObject:@{@"id":identifier,@"file":name,@"enabled":@NO,@"hash":HaloBackupHashFile(dest)}];
        }Save(list);
    } @catch(NSException *e){for(NSURL *url in copied)[NSFileManager.defaultManager removeItemAtURL:url error:nil];@throw e;}
}
void HaloModsSetEnabled(NSUInteger index,BOOL enabled) { NSMutableArray *list=[HaloModsList() mutableCopy];HaloBackupRequire(index<list.count,@"Mod no longer exists.");NSMutableDictionary *m=[list[index] mutableCopy];m[@"enabled"]=@(enabled);list[index]=m;Save(list); }
void HaloModsMove(NSUInteger index,NSInteger delta) { NSMutableArray *list=[HaloModsList() mutableCopy];NSInteger to=(NSInteger)index+delta;HaloBackupRequire(index<list.count && to>=0 && to<(NSInteger)list.count,@"Invalid mod order.");id item=list[index];[list removeObjectAtIndex:index];[list insertObject:item atIndex:(NSUInteger)to];Save(list); }
NSURL *HaloModsExport(NSUInteger index) { NSArray *list=HaloModsList();HaloBackupRequire(index<list.count,@"Mod no longer exists.");NSDictionary *m=list[index];return [ModFile(m[@"id"]) URLByAppendingPathComponent:m[@"file"]]; }
BOOL HaloModsPending(void) { return [NSFileManager.defaultManager fileExistsAtPath:ModFile(@"pending.plist").path] || [NSFileManager.defaultManager fileExistsAtPath:ModFile(@"journal.plist").path]; }
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
BOOL HaloModsApply(NSError **error) {
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
