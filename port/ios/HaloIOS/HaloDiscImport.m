#import "HaloDiscImport.h"
#import "HaloBackupArchive.h"
#import "HaloMods.h"

static NSURL *Work(void){return [HaloBackupWork() URLByAppendingPathComponent:@"disc-install" isDirectory:YES];}
static NSURL *Journal(void){return [Work() URLByAppendingPathComponent:@"journal.plist"];}
static BOOL MapName(NSString *name){
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."];
    return name.length>4 && name.length<=255 && [name.pathExtension.lowercaseString isEqual:@"map"] && ![name hasPrefix:@"."] && [name rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound;
}
/* A journal stores root-relative paths, never arbitrary archive paths. */
static NSURL *Target(NSDictionary *record){
    NSString *path=record[@"path"];BOOL maps=[record[@"maps"] boolValue];
    HaloBackupRequire([path isKindOfClass:NSString.class],@"Invalid disc recovery path.");
    BOOL valid=maps?([path hasPrefix:@"maps/"] && path.pathComponents.count==2 && MapName(path.lastPathComponent)):
        ([path isEqual:@"mods/base.plist"] || [path isEqual:@"mods/pending.plist"] ||
         ([path hasPrefix:@"mods/base/"] && path.pathComponents.count==3 && MapName(path.lastPathComponent)));
    HaloBackupRequire(valid,@"Invalid disc recovery destination.");
    NSURL *root=maps?[NSURL fileURLWithPath:HaloBackupRoot() isDirectory:YES]:HaloBackupWork();
    NSURL *target=[root URLByAppendingPathComponent:path];
    NSString *prefix=[root.URLByResolvingSymlinksInPath.path stringByAppendingString:@"/"];
    HaloBackupRequire([target.URLByResolvingSymlinksInPath.path hasPrefix:prefix],@"Disc destination escapes the library.");
    return target;
}
BOOL HaloDiscImportPending(void){return [NSFileManager.defaultManager fileExistsAtPath:Journal().path];}
BOOL HaloDiscImportRecover(NSError **error){
    @try{
        NSFileManager *fm=NSFileManager.defaultManager;NSDictionary *journal=[NSDictionary dictionaryWithContentsOfURL:Journal()];
        if(!journal){HaloBackupRequire(!HaloDiscImportPending(),@"Unreadable disc recovery journal.");return YES;}
        NSArray *records=journal[@"files"];HaloBackupRequire([records isKindOfClass:NSArray.class] && records.count<=258,@"Invalid disc recovery journal.");
        if(![journal[@"committed"] boolValue])for(NSUInteger n=0;n<records.count;n++){
            NSDictionary *r=records[n];HaloBackupRequire([r isKindOfClass:NSDictionary.class],@"Invalid disc recovery record.");
            NSURL *dest=Target(r),*old=[Work() URLByAppendingPathComponent:[NSString stringWithFormat:@"old-%lu",(unsigned long)n]];
            /* Originals are renamed before installation. Missing old-N means
             * an existing destination was never touched, or already recovered. */
            if([fm fileExistsAtPath:old.path]){
                HaloBackupRequire(HaloBackupRegular(old),@"Invalid disc recovery original.");
                HaloBackupRequire(![fm fileExistsAtPath:dest.path] || (HaloBackupRegular(dest)&&[fm removeItemAtURL:dest error:nil]),@"Cannot roll back disc map.");
                HaloBackupRequire([fm moveItemAtURL:old toURL:dest error:nil],@"Cannot restore disc original.");
            }else if(![r[@"had"] boolValue])HaloBackupRequire(![fm fileExistsAtPath:dest.path] || (HaloBackupRegular(dest)&&[fm removeItemAtURL:dest error:nil]),@"Cannot remove interrupted disc map.");
        }
        /* Remove the journal first. Cleanup interruption never replays rollback. */
        HaloBackupRequire([fm removeItemAtURL:Journal() error:nil],@"Cannot finish disc recovery.");
        [fm removeItemAtURL:Work() error:nil];return YES;
    }@catch(NSException *e){if(error)*error=HaloBackupFailure(e.reason);return NO;}
}
BOOL HaloDiscInstall(NSURL *stage,BOOL replace,HaloDiscCancel cancel,NSUInteger *installed,NSUInteger *kept,NSError **error){
    if(installed)*installed=0;if(kept)*kept=0;
    @try{
        NSFileManager *fm=NSFileManager.defaultManager;HaloBackupRequire(!HaloDiscImportPending(),@"Restart Halo to recover the previous disc import.");
        NSMutableArray *files=[NSMutableArray array];NSUInteger skip=0;
        NSURL *maps=[NSURL fileURLWithPath:[HaloBackupRoot() stringByAppendingPathComponent:@"maps"] isDirectory:YES];
        NSArray *existing=[fm contentsOfDirectoryAtPath:maps.path error:nil]?:@[];
        NSArray *names=[[fm contentsOfDirectoryAtPath:stage.path error:nil] sortedArrayUsingSelector:@selector(compare:)];
        HaloBackupRequire(names.count>0 && names.count<=256,@"No validated disc maps found.");
        for(NSString *name in names){HaloBackupRequire(MapName(name),@"Invalid staged disc filename.");
            NSURL *file=[stage URLByAppendingPathComponent:name];HaloBackupRequire(HaloBackupRegular(file),@"Invalid staged disc file.");BOOL exists=NO;
            NSFileHandle *in=[NSFileHandle fileHandleForReadingFromURL:file error:nil];NSData *header=nil;
            @try{header=[in readDataOfLength:2048];}@finally{[in closeFile];}
            uint32_t head=0,version=0,foot=0;if(header.length==2048){memcpy(&head,header.bytes,4);memcpy(&version,(const char *)header.bytes+4,4);memcpy(&foot,(const char *)header.bytes+2044,4);}
            HaloBackupRequire(header.length==2048 && CFSwapInt32LittleToHost(head)==0x68656164 && CFSwapInt32LittleToHost(version)==5 && CFSwapInt32LittleToHost(foot)==0x666f6f74,@"Staged disc map failed the Xbox v5 header check.");
            const char *build=(const char *)header.bytes+64;
            HaloBackupRequire(memchr(build,0,32) && (!strcmp(build,"01.10.12.2276") || !strcmp(build,"01.01.14.2342")),@"Staged disc map has an unsupported build.");
            for(NSString *entry in existing)if([entry.lowercaseString isEqual:name.lowercaseString])exists=YES;
            if(exists&&!replace)skip++;else [files addObject:file];
        }
        if(kept)*kept=skip;if(!files.count)return YES;
        NSArray *plan=HaloModsPlanBaseImport(files,stage);NSMutableArray *records=[NSMutableArray array];
        /* A prior committed install may have been terminated during cleanup,
         * after retiring its journal. Never reuse its numbered originals. */
        HaloBackupRequire(![fm fileExistsAtPath:Work().path] || [fm removeItemAtURL:Work() error:nil],@"Cannot clean completed disc recovery files.");
        HaloBackupRequire([fm createDirectoryAtURL:Work() withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot prepare disc recovery folder.");
        for(NSDictionary *entry in plan){NSURL *dest=entry[@"target"];NSString *mapPrefix=[[maps URLByDeletingLastPathComponent].URLByResolvingSymlinksInPath.path stringByAppendingString:@"/"];
            NSString *destPath=dest.URLByResolvingSymlinksInPath.path;BOOL isMap=[dest.URLByDeletingLastPathComponent.URLByResolvingSymlinksInPath.path isEqual:maps.URLByResolvingSymlinksInPath.path];
            NSString *prefix=isMap?mapPrefix:[HaloBackupWork().URLByResolvingSymlinksInPath.path stringByAppendingString:@"/"];
            HaloBackupRequire([destPath hasPrefix:prefix],@"Invalid disc destination.");
            NSDictionary *r=@{@"maps":@(isMap),@"path":[destPath substringFromIndex:prefix.length],@"had":@([fm fileExistsAtPath:dest.path])};
            (void)Target(r);HaloBackupRequire(![r[@"had"] boolValue]||HaloBackupRegular(dest),@"Disc destination is not a regular file.");[records addObject:r];
        }
        HaloBackupRequire([@{@"files":records} writeToURL:Journal() atomically:YES],@"Cannot create disc recovery journal; maps unchanged.");
        for(NSUInteger n=0;n<plan.count;n++){
            HaloBackupRequire(!cancel || !cancel(),@"Disc import cancelled. Original maps restored.");
            NSURL *dest=Target(records[n]);
            HaloBackupRequire([fm createDirectoryAtURL:dest.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot prepare disc destination.");
            if([records[n][@"had"] boolValue])HaloBackupRequire([fm moveItemAtURL:dest toURL:[Work() URLByAppendingPathComponent:[NSString stringWithFormat:@"old-%lu",(unsigned long)n]] error:nil],@"Cannot preserve existing disc map.");
            HaloBackupRequire([fm moveItemAtURL:plan[n][@"source"] toURL:dest error:nil],@"Cannot install disc map.");
        }
        HaloBackupRequire(!cancel || !cancel(),@"Disc import cancelled. Original maps restored.");
        HaloBackupRequire([@{@"files":records,@"committed":@YES} writeToURL:Journal() atomically:YES],@"Cannot commit disc import.");
        /* Once committed, recovery only cleans the journal and originals. */
        NSError *cleanup=nil;(void)HaloDiscImportRecover(&cleanup);
        if(installed)*installed=files.count;return YES;
    }@catch(NSException *e){NSError *rollback=nil;BOOL recovered=HaloDiscImportRecover(&rollback);if(error)*error=HaloBackupFailure(recovered?e.reason:[NSString stringWithFormat:@"%@ Recovery required: %@",e.reason,rollback.localizedDescription]);return NO;}
}
