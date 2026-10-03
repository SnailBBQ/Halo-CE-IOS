#import <Foundation/Foundation.h>
#import "HaloBackupArchive.h"
#include "halo_settings_core.h"
#define CHECK(x) do { if(!(x)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);return 1;} } while(0)
static void Put(NSString *path,NSString *text) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
int main(void) { @autoreleasepool {
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];setenv("HALO_BACKUP_TEST_ROOT",root.UTF8String,1);
    CHECK(!HaloBackupAllowed(@"../save/file"));CHECK(!HaloBackupAllowed(@"save/../escape"));CHECK(!HaloBackupAllowed(@"game_invite.txt"));CHECK(!HaloBackupAllowed(@"/save/test"));CHECK(!HaloBackupAllowed(@"maps/test.exe"));CHECK(HaloBackupAllowed(@"save/c/profiles/player.bin"));CHECK(HaloBackupAllowed(@"maps/a10.map"));
    Put([root stringByAppendingPathComponent:@"save/c/profiles/player.bin"],@"original profile");Put([root stringByAppendingPathComponent:@"maps/a10.map"],@"original map");Put([root stringByAppendingPathComponent:@"game_invite.txt"],@"must not export");Put([root stringByAppendingPathComponent:@"debug.txt"],@"must not export");
    HsSettings settings;hs_defaults(&settings);settings.presets[0].place[0].opacity=.5f;settings.cheat_camo=1;char buffer[32768];CHECK(hs_serialize(&settings,buffer,sizeof(buffer))>0);[NSUserDefaults.standardUserDefaults setObject:[NSString stringWithUTF8String:buffer] forKey:@"HaloSettingsV1"];
    NSURL *archive=HaloBackupExport(7),*stage=[HaloBackupWork() URLByAppendingPathComponent:@"staged"];
    NSDictionary *manifest=HaloBackupStage(archive,stage);CHECK([manifest[@"files"] count]==2);CHECK(![NSFileManager.defaultManager fileExistsAtPath:[stage URLByAppendingPathComponent:@"maps/a10.map"].path]);
    CHECK([manifest writeToURL:[stage URLByAppendingPathComponent:@"manifest.plist"] atomically:YES]);CHECK([@{@"mask":@7} writeToURL:[HaloBackupWork() URLByAppendingPathComponent:@"pending.plist"] atomically:YES]);
    Put([root stringByAppendingPathComponent:@"save/c/profiles/player.bin"],@"newer profile");NSError *error=nil;CHECK(HaloApplyPendingRestore(&error));CHECK([[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"save/c/profiles/player.bin"] encoding:NSUTF8StringEncoding error:nil] isEqual:@"original profile"]);
    CHECK([[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"maps/a10.map"] encoding:NSUTF8StringEncoding error:nil] isEqual:@"original map"]);CHECK([NSFileManager.defaultManager fileExistsAtPath:[NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastRecoveryBackup"]]);
    HsSettings restored;CHECK(hs_parse(&restored,[NSUserDefaults.standardUserDefaults stringForKey:@"HaloSettingsV1"].UTF8String));CHECK(!restored.cheat_camo&&restored.presets[0].place[0].opacity==.5f);
    NSMutableData *bad=[[NSData dataWithContentsOfURL:archive] mutableCopy];((char *)bad.mutableBytes)[bad.length-1]^=1;NSURL *corrupt=[HaloBackupWork() URLByAppendingPathComponent:@"corrupt.halobackup"];[bad writeToURL:corrupt atomically:YES];BOOL rejected=NO;@try {HaloBackupStage(corrupt,[HaloBackupWork() URLByAppendingPathComponent:@"bad"]);} @catch(NSException *e){(void)e;rejected=YES;}CHECK(rejected);
    NSData *truncated=[bad subdataWithRange:NSMakeRange(0,10)];[truncated writeToURL:corrupt atomically:YES];rejected=NO;@try{HaloBackupStage(corrupt,[HaloBackupWork() URLByAppendingPathComponent:@"short"]);} @catch(NSException *e){(void)e;rejected=YES;}CHECK(rejected);
    NSURL *mapsArchive=HaloBackupExport(8);NSDictionary *maps=HaloBackupStage(mapsArchive,[HaloBackupWork() URLByAppendingPathComponent:@"maps-only"]);CHECK([maps[@"files"] count]==1);
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloSettingsV1"];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloLastRecoveryBackup"];
    puts("backup archive roundtrip, selection, recovery, checksum and truncation: PASS");return 0;
} }
