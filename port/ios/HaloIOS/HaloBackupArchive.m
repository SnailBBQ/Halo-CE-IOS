#import "HaloBackupArchive.h"
#include "halo_settings_core.h"
#import <CommonCrypto/CommonDigest.h>

/* Versioned streaming archive: 8-byte magic, LE manifest size, JSON manifest,
 * then exact file bytes. No compression or all-map allocation. Paths are never
 * accepted from an archive without whitelist, duplicate and traversal checks. */
NSString *HaloBackupRoot(void) {
#ifdef HALO_BACKUP_TEST
return [NSString stringWithUTF8String:getenv("HALO_BACKUP_TEST_ROOT")];
#else
return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Halo"];
#endif
}
NSURL *HaloBackupWork(void) {
#ifdef HALO_BACKUP_TEST
return [NSURL fileURLWithPath:[HaloBackupRoot() stringByAppendingPathComponent:@"work"] isDirectory:YES];
#else
return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"HaloBackups" isDirectory:YES];
#endif
}
NSError *HaloBackupFailure(NSString *message) { return [NSError errorWithDomain:@"HaloBackup" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
void HaloBackupRequire(BOOL ok,NSString *message) { if(!ok) @throw [NSException exceptionWithName:@"HaloBackup" reason:message userInfo:nil]; }
BOOL HaloBackupAllowed(NSString *path) {
    if(![path isKindOfClass:NSString.class] || path.length>1024 || [path hasPrefix:@"/"] || [path containsString:@"\\"])return NO;
    for(NSString *part in path.pathComponents)if([part isEqual:@".."] || [part isEqual:@"."] || !part.length)return NO;
    return [path hasPrefix:@"save/"] || ([path hasPrefix:@"maps/"] && [path.pathExtension.lowercaseString isEqual:@"map"]) ||
        ([path hasPrefix:@"map_thumbnails/"] && [@[@"png",@"jpg",@"jpeg"] containsObject:path.pathExtension.lowercaseString]) ||
        [path isEqual:@"settings.txt"] || [path isEqual:@"config.toml"];
}
/* Bit 1 remains the legacy combined saves/profiles selection. New bits 16 and
 * 32 select each independently. Cache maps and volatile checkpoints under z:
 * are rebuildable session data, never user progress. Older archives remain
 * readable, but their temporary files are deliberately not restored. */
static unsigned Section(NSString *path) {
    NSString *p=path.lowercaseString;
    if([p hasPrefix:@"save/u/udata/"]) {
        NSString *leaf=p.lastPathComponent;
        if([leaf isEqual:@"blam.sav"] || [leaf isEqual:@"blam.lst"])return 1|32;
        if([leaf isEqual:@"savemeta.xbx"] || [leaf isEqual:@"saveimage.xbx"])return 1|16|32;
        return [leaf isEqual:@"savegame.bin"]?1|16:0;
    }
    if([p hasPrefix:@"save/c/profiles/"] || [p hasPrefix:@"save/z/saved/player_profiles/"] || [p hasPrefix:@"save/z/saved/playlists/"] ||
       [@[@"save/z/lastprof.txt",@"save/z/last_solo.txt",@"save/z/lastmpmp.txt",@"save/z/lastmpvr.txt"] containsObject:p])return 1|32;
    if([p hasPrefix:@"save/"])return 0;
    return [p hasPrefix:@"maps/"]||[p hasPrefix:@"map_thumbnails/"]?8:[p isEqual:@"config.toml"]?2:6;
}
static NSString *Relative(NSURL *file,NSURL *root) {
    /* /var and /private/var may name the same app directory. Enumeration and
     * file URLs must agree before calculating a relative filename. */
    NSString *base=root.URLByResolvingSymlinksInPath.path.stringByStandardizingPath;
    NSString *path=file.URLByResolvingSymlinksInPath.path.stringByStandardizingPath;
    NSString *prefix=[base stringByAppendingString:@"/"];
    HaloBackupRequire([path hasPrefix:prefix],@"File escaped the snapshot directory.");
    return [path substringFromIndex:prefix.length];
}
BOOL HaloBackupRegular(NSURL *url) {
    NSNumber *regular=nil,*link=nil;[url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];[url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];return regular.boolValue&&!link.boolValue;
}
NSString *HaloBackupHashFile(NSURL *url) {
    NSFileHandle *file=[NSFileHandle fileHandleForReadingFromURL:url error:nil];HaloBackupRequire(file!=nil,@"Cannot read a backup file.");
    CC_SHA256_CTX hash;CC_SHA256_Init(&hash);
    @try { for(;;) { @autoreleasepool { NSData *chunk=[file readDataOfLength:1024*1024];if(!chunk.length)break;CC_SHA256_Update(&hash,chunk.bytes,(CC_LONG)chunk.length); } } }
    @finally { [file closeFile]; }
    unsigned char digest[32];CC_SHA256_Final(digest,&hash);NSMutableString *text=[NSMutableString string];for(int i=0;i<32;i++)[text appendFormat:@"%02x",digest[i]];return text;
}
static void SafeParents(NSURL *root,NSString *path) {
    NSURL *cursor=root;NSNumber *link=nil;[cursor getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];HaloBackupRequire(!link.boolValue,@"Destination is a symbolic link.");
    for(NSString *part in path.stringByDeletingLastPathComponent.pathComponents) {
        cursor=[cursor URLByAppendingPathComponent:part];link=nil;[cursor getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];HaloBackupRequire(!link.boolValue,@"Destination contains a symbolic link.");
    }
    NSURL *leaf=[root URLByAppendingPathComponent:path];link=nil;[leaf getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];HaloBackupRequire(!link.boolValue,@"Destination is a symbolic link.");
}
NSURL *HaloBackupExport(unsigned mask) {
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *work=HaloBackupWork();HaloBackupRequire([fm createDirectoryAtURL:work withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot create backup workspace.");
    NSURL *snapshot=[work URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];HaloBackupRequire([fm createDirectoryAtURL:snapshot withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot create snapshot.");
    @try {
        NSURL *root=[NSURL fileURLWithPath:HaloBackupRoot() isDirectory:YES];
        NSDirectoryEnumerator *walk=[fm enumeratorAtURL:root includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey] options:0 errorHandler:^BOOL(NSURL *u,NSError *e) { (void)u;@throw [NSException exceptionWithName:@"HaloBackup" reason:e.localizedDescription userInfo:nil]; }];
        for(NSURL *url in walk) {
            NSNumber *link=nil;[url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];if(link.boolValue){[walk skipDescendants];continue;}
            NSString *path=Relative(url,root);
            if(!HaloBackupRegular(url)||!HaloBackupAllowed(path)||!(Section(path)&mask))continue;
            NSURL *target=[snapshot URLByAppendingPathComponent:path];HaloBackupRequire([fm createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot create snapshot directory.");HaloBackupRequire([fm copyItemAtURL:url toURL:target error:nil],@"Cannot copy save or map into snapshot. Try again after saving.");
        }
        if(mask&6) { HsSettings s;hs_parse(&s,[NSUserDefaults.standardUserDefaults stringForKey:@"HaloSettingsV1"].UTF8String);char text[32768];HaloBackupRequire(hs_serialize(&s,text,sizeof(text))>0,@"Cannot serialize settings.");HaloBackupRequire([[NSString stringWithUTF8String:text] writeToURL:[snapshot URLByAppendingPathComponent:@"settings.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil],@"Cannot save settings snapshot."); }
        NSMutableArray *records=[NSMutableArray array];
        NSDirectoryEnumerator *files=[fm enumeratorAtURL:snapshot includingPropertiesForKeys:@[NSURLIsRegularFileKey] options:0 errorHandler:nil];
        for(NSURL *url in files)if(HaloBackupRegular(url)) {
            NSString *path=Relative(url,snapshot);NSDictionary *a=[fm attributesOfItemAtPath:url.path error:nil];
            [records addObject:@{@"path":path,@"size":a[NSFileSize],@"sha256":HaloBackupHashFile(url)}];
        }
        [records sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"path"] compare:b[@"path"]];}];
        NSData *manifest=[NSJSONSerialization dataWithJSONObject:@{@"format":@1,@"sections":@(mask),@"files":records} options:0 error:nil];HaloBackupRequire(manifest.length<=1024*1024,@"Backup has too many files.");
        NSString *name=[NSString stringWithFormat:@"Halo-%@.halobackup",NSUUID.UUID.UUIDString];NSURL *output=[work URLByAppendingPathComponent:name];HaloBackupRequire([fm createFileAtPath:output.path contents:nil attributes:nil],@"Cannot create backup archive.");
        NSFileHandle *out=[NSFileHandle fileHandleForWritingToURL:output error:nil];HaloBackupRequire(out!=nil,@"Cannot open backup archive.");
        @try {
            [out writeData:[NSData dataWithBytes:"HALOBK01" length:8]];uint32_t length=CFSwapInt32HostToLittle((uint32_t)manifest.length);[out writeData:[NSData dataWithBytes:&length length:4]];[out writeData:manifest];
            for(NSDictionary *record in records) {
                NSFileHandle *in=[NSFileHandle fileHandleForReadingFromURL:[snapshot URLByAppendingPathComponent:record[@"path"]] error:nil];HaloBackupRequire(in!=nil,[@"Snapshot disappeared: " stringByAppendingString:record[@"path"]]);
                @try { for(;;) { @autoreleasepool { NSData *chunk=[in readDataOfLength:1024*1024];if(!chunk.length)break;[out writeData:chunk]; } } } @finally {[in closeFile];}
            }[out synchronizeFile];
        } @finally { [out closeFile]; }
        return output;
    } @finally { [fm removeItemAtURL:snapshot error:nil]; }
}
NSDictionary *HaloBackupStage(NSURL *archive,NSURL *stage) {
    NSFileManager *fm=NSFileManager.defaultManager;HaloBackupRequire([fm createDirectoryAtURL:stage withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot stage restore.");
    NSFileHandle *in=[NSFileHandle fileHandleForReadingFromURL:archive error:nil];HaloBackupRequire(in!=nil,@"Cannot open backup.");
    @try {
        NSData *magic=[in readDataOfLength:8],*n=[in readDataOfLength:4];uint32_t length=0;HaloBackupRequire(magic.length==8&&!memcmp(magic.bytes,"HALOBK01",8)&&n.length==4,@"Not a supported Halo backup.");memcpy(&length,n.bytes,4);length=CFSwapInt32LittleToHost(length);HaloBackupRequire(length>0&&length<=1024*1024,@"Invalid manifest size.");
        NSData *json=[in readDataOfLength:length];HaloBackupRequire(json.length==length,@"Truncated manifest.");NSDictionary *manifest=[NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
        HaloBackupRequire([manifest isKindOfClass:NSDictionary.class]&&[manifest[@"format"] isKindOfClass:NSNumber.class]&&[manifest[@"format"] intValue]==1,@"Unsupported backup format.");
        NSArray *records=manifest[@"files"];HaloBackupRequire([records isKindOfClass:NSArray.class]&&records.count<=10000,@"Invalid file list.");NSMutableSet *seen=[NSMutableSet set];uint64_t total=0;
        for(NSDictionary *record in records) {
            HaloBackupRequire([record isKindOfClass:NSDictionary.class],@"Invalid file record.");NSString *path=record[@"path"],*digest=record[@"sha256"];HaloBackupRequire(HaloBackupAllowed(path)&&![seen containsObject:path.lowercaseString]&&[record[@"size"] isKindOfClass:NSNumber.class]&&[digest isKindOfClass:NSString.class]&&digest.length==64,@"Invalid or duplicate backup path.");[seen addObject:path.lowercaseString];
            uint64_t size=[record[@"size"] unsignedLongLongValue];HaloBackupRequire(size<=32ull*1024*1024*1024&&total<=32ull*1024*1024*1024-size,@"Backup exceeds supported 32 GiB size.");total+=size;
            NSURL *target=[stage URLByAppendingPathComponent:path];HaloBackupRequire([fm createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]&&[fm createFileAtPath:target.path contents:nil attributes:nil],@"Cannot stage file; check free space.");NSFileHandle *out=[NSFileHandle fileHandleForWritingToURL:target error:nil];HaloBackupRequire(out!=nil,@"Cannot write restore file.");
            @try { uint64_t left=size;while(left) { @autoreleasepool { NSUInteger count=(NSUInteger)MIN(left,1024*1024);NSData *chunk=[in readDataOfLength:count];HaloBackupRequire(chunk.length==count,@"Truncated backup file.");[out writeData:chunk];left-=count; } }[out synchronizeFile]; } @finally {[out closeFile];}
            HaloBackupRequire([HaloBackupHashFile(target) isEqual:digest],@"Backup checksum failed.");
        }
        HaloBackupRequire(![in readDataOfLength:1].length,@"Unexpected data after backup.");return manifest;
    } @finally {[in closeFile];}
}
BOOL HaloApplyPendingRestore(NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *work=HaloBackupWork(),*request=[work URLByAppendingPathComponent:@"pending.plist"];
    NSDictionary *pending=[NSDictionary dictionaryWithContentsOfURL:request];if(!pending)return YES;
    NSMutableArray *changed=[NSMutableArray array];NSMutableSet *had=[NSMutableSet set];NSURL *root=[NSURL fileURLWithPath:HaloBackupRoot() isDirectory:YES],*rollback=[work URLByAppendingPathComponent:@"recovery-files" isDirectory:YES];
    NSString *oldSettings=[NSUserDefaults.standardUserDefaults stringForKey:@"HaloSettingsV1"];
    /* A killed app must not resume halfway through a previous transaction.
     * The write-ahead request retains the original files/settings until rollback. */
    if([pending[@"prepared"] boolValue]) {
        BOOL recovered=YES;
        for(NSString *path in pending[@"targets"]) {
            if(!HaloBackupAllowed(path)){recovered=NO;continue;}
            @try { SafeParents(root,path);NSURL *dest=[root URLByAppendingPathComponent:path];
                if([fm fileExistsAtPath:dest.path]&&![fm removeItemAtURL:dest error:nil]){recovered=NO;continue;}
                if([pending[@"had"] containsObject:path]&&![fm copyItemAtURL:[rollback URLByAppendingPathComponent:path] toURL:dest error:nil])recovered=NO;
            } @catch(NSException *e){(void)e;recovered=NO;}
        }
        NSString *saved=pending[@"settings"];if(saved)[NSUserDefaults.standardUserDefaults setObject:saved forKey:@"HaloSettingsV1"];else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloSettingsV1"];
        if(recovered)[fm removeItemAtURL:request error:nil];
        if(error)*error=HaloBackupFailure(recovered?@"An interrupted restore was rolled back. Close and reopen Halo to continue. Your recovery backup is retained.":@"An interrupted restore could not be fully recovered. Keep the recovery backup; do not start the game until recovery succeeds.");return NO;
    }
    @try {
        NSURL *stage=[work URLByAppendingPathComponent:@"staged" isDirectory:YES];NSDictionary *manifest=[NSDictionary dictionaryWithContentsOfURL:[stage URLByAppendingPathComponent:@"manifest.plist"]];HaloBackupRequire(manifest!=nil,@"Staged restore is missing.");unsigned mask=[pending[@"mask"] unsignedIntValue]&63u;
        [fm removeItemAtURL:rollback error:nil];HaloBackupRequire([fm createDirectoryAtURL:rollback withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot create recovery folder.");
        /* Validate staged bytes again, then preserve every overwritten destination. */
        for(NSDictionary *record in manifest[@"files"]) {
            NSString *path=record[@"path"];HaloBackupRequire(HaloBackupAllowed(path),@"Invalid staged path.");if(!(Section(path)&mask))continue;
            SafeParents(root,path);NSURL *source=[stage URLByAppendingPathComponent:path],*dest=[root URLByAppendingPathComponent:path];HaloBackupRequire(HaloBackupRegular(source)&&[HaloBackupHashFile(source) isEqual:record[@"sha256"]],@"Staged file changed.");
            if([path isEqual:@"settings.txt"])continue;
            if([fm fileExistsAtPath:dest.path]) { NSURL *old=[rollback URLByAppendingPathComponent:path];HaloBackupRequire([fm createDirectoryAtURL:old.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]&&[fm copyItemAtURL:dest toURL:old error:nil],@"Cannot create recovery backup; restore cancelled.");[had addObject:path]; }
        }
        /* Recovery archive remains user-exportable after successful restore. */
        NSURL *recovery=HaloBackupExport(mask);[NSUserDefaults.standardUserDefaults setObject:recovery.path forKey:@"HaloLastRecoveryBackup"];
        NSMutableArray *targets=[NSMutableArray array];for(NSDictionary *record in manifest[@"files"]) { NSString *path=record[@"path"];if((Section(path)&mask)&&![path isEqual:@"settings.txt"])[targets addObject:path]; }
        NSMutableDictionary *journal=[pending mutableCopy];journal[@"prepared"]=@YES;journal[@"targets"]=targets;journal[@"had"]=had.allObjects;if(oldSettings)journal[@"settings"]=oldSettings;
        HaloBackupRequire([journal writeToURL:request atomically:YES],@"Cannot create restore journal; no files changed.");
        for(NSDictionary *record in manifest[@"files"]) {
            NSString *path=record[@"path"];if(!(Section(path)&mask)||[path isEqual:@"settings.txt"])continue;
            NSURL *dest=[root URLByAppendingPathComponent:path],*source=[stage URLByAppendingPathComponent:path];HaloBackupRequire([fm createDirectoryAtURL:dest.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot create destination.");
            NSURL *temporary=[dest.URLByDeletingLastPathComponent URLByAppendingPathComponent:[@".restore-" stringByAppendingString:NSUUID.UUID.UUIDString]];HaloBackupRequire([fm copyItemAtURL:source toURL:temporary error:nil],@"Cannot prepare restored file.");[changed addObject:path];
            if([fm fileExistsAtPath:dest.path])HaloBackupRequire([fm replaceItemAtURL:dest withItemAtURL:temporary backupItemName:nil options:0 resultingItemURL:nil error:nil],@"Cannot replace restored file.");
            else HaloBackupRequire([fm moveItemAtURL:temporary toURL:dest error:nil],@"Cannot install restored file.");
        }
        if(mask&6) {
            NSString *text=[NSString stringWithContentsOfURL:[stage URLByAppendingPathComponent:@"settings.txt"] encoding:NSUTF8StringEncoding error:nil];if(text) {
                HsSettings next,current;HaloBackupRequire(hs_parse(&next,text.UTF8String),@"Invalid settings in backup.");hs_parse(&current,oldSettings.UTF8String);
                if(!(mask&4)) { memcpy(next.presets,current.presets,sizeof(next.presets));next.active=current.active;memcpy(next.hud,current.hud,sizeof(next.hud));memcpy(next.hud_presets,current.hud_presets,sizeof(next.hud_presets)); }
                if(!(mask&2)) { HsPreset controls[HS_PRESET_COUNT];HsHud hud[HS_HUD_COUNT];HsHudPreset presets[3];int active=next.active;memcpy(controls,next.presets,sizeof(controls));memcpy(hud,next.hud,sizeof(hud));memcpy(presets,next.hud_presets,sizeof(presets));next=current;next.active=active;memcpy(next.presets,controls,sizeof(controls));memcpy(next.hud,hud,sizeof(hud));memcpy(next.hud_presets,presets,sizeof(presets)); }
                hs_clear_cheats(&next);char buffer[32768];HaloBackupRequire(hs_serialize(&next,buffer,sizeof(buffer))>0,@"Cannot restore settings.");[NSUserDefaults.standardUserDefaults setObject:[NSString stringWithUTF8String:buffer] forKey:@"HaloSettingsV1"];
            }
        }
        [fm removeItemAtURL:request error:nil];[fm removeItemAtURL:stage error:nil];return YES;
    } @catch(NSException *e) {
        BOOL recovered=YES;
        for(NSString *path in changed.reverseObjectEnumerator) { NSURL *dest=[root URLByAppendingPathComponent:path];if([fm fileExistsAtPath:dest.path]&&![fm removeItemAtURL:dest error:nil])recovered=NO;if([had containsObject:path]&&![fm copyItemAtURL:[rollback URLByAppendingPathComponent:path] toURL:dest error:nil])recovered=NO; }
        if(oldSettings)[NSUserDefaults.standardUserDefaults setObject:oldSettings forKey:@"HaloSettingsV1"];else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloSettingsV1"];
        if(recovered)[fm removeItemAtURL:request error:nil];if(error)*error=HaloBackupFailure([e.reason stringByAppendingString:recovered?@" Changes were rolled back. Recovery files remain in app storage.":@" Recovery needs another attempt; recovery files remain in app storage."]);return NO;
    }
}
