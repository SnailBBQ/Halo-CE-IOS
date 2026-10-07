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
    CHECK(!HaloBackupAllowed(@"../save/file"));CHECK(!HaloBackupAllowed(@"save/../escape"));CHECK(!HaloBackupAllowed(@"game_invite.txt"));CHECK(!HaloBackupAllowed(@"/save/test"));CHECK(!HaloBackupAllowed(@"maps/test.exe"));CHECK(HaloBackupAllowed(@"save/c/profiles/player.bin"));CHECK(HaloBackupAllowed(@"maps/a10.map"));CHECK(HaloBackupAllowed(@"custom_maps/example.map"));CHECK(HaloBackupAllowed(@"custom_maps_disabled/example.txt"));CHECK(HaloBackupAllowed(@"videos/intro.mp4"));CHECK(!HaloBackupAllowed(@"videos/intro.bik"));
    Put([root stringByAppendingPathComponent:@"save/c/profiles/player.bin"],@"original profile");Put([root stringByAppendingPathComponent:@"maps/a10.map"],@"original map");Put([root stringByAppendingPathComponent:@"game_invite.txt"],@"must not export");Put([root stringByAppendingPathComponent:@"debug.txt"],@"must not export");
    Put([root stringByAppendingPathComponent:@"save/z/cache000.map"],@"temporary cache");
    Put([root stringByAppendingPathComponent:@"save/z/savegame.bin"],@"volatile checkpoint");
    Put([root stringByAppendingPathComponent:@"save/u/UDATA/test/savegame.bin"],@"persistent checkpoint");
    NSURL *onlySaves=HaloBackupExport(16),*onlyProfiles=HaloBackupExport(32);
    NSDictionary *saveList=HaloBackupStage(onlySaves,[HaloBackupWork() URLByAppendingPathComponent:@"saves-only"]);
    NSDictionary *profileList=HaloBackupStage(onlyProfiles,[HaloBackupWork() URLByAppendingPathComponent:@"profiles-only"]);
    CHECK([saveList[@"files"] count]==1);CHECK([profileList[@"files"] count]==1);
    CHECK([saveList[@"files"][0][@"path"] isEqual:@"save/u/UDATA/test/savegame.bin"]);
    CHECK([profileList[@"files"][0][@"path"] isEqual:@"save/c/profiles/player.bin"]);
    Put([root stringByAppendingPathComponent:@"save/u/UDATA/test/blam.sav"],@"Halo player profile");
    NSURL *actualProfiles=HaloBackupExport(32);
    NSDictionary *actualList=HaloBackupStage(actualProfiles,[HaloBackupWork() URLByAppendingPathComponent:@"udata-profiles"]);
    CHECK([actualList[@"files"] count]==2);
    for(NSDictionary *file in actualList[@"files"])CHECK(![file[@"path"] hasSuffix:@"savegame.bin"]);
    HsSettings settings;hs_defaults(&settings);settings.presets[0].place[0].opacity=.5f;settings.cheat_camo=1;char buffer[32768];CHECK(hs_serialize(&settings,buffer,sizeof(buffer))>0);[NSUserDefaults.standardUserDefaults setObject:[NSString stringWithUTF8String:buffer] forKey:@"HaloSettingsV1"];
    NSURL *archive=HaloBackupExport(7),*stage=[HaloBackupWork() URLByAppendingPathComponent:@"staged"];
    NSDictionary *manifest=HaloBackupStage(archive,stage);CHECK([manifest[@"files"] count]==4);CHECK(![NSFileManager.defaultManager fileExistsAtPath:[stage URLByAppendingPathComponent:@"maps/a10.map"].path]);
    CHECK([manifest writeToURL:[stage URLByAppendingPathComponent:@"manifest.plist"] atomically:YES]);CHECK([@{@"mask":@7} writeToURL:[HaloBackupWork() URLByAppendingPathComponent:@"pending.plist"] atomically:YES]);
    Put([root stringByAppendingPathComponent:@"save/c/profiles/player.bin"],@"newer profile");NSError *error=nil;CHECK(HaloApplyPendingRestore(&error));CHECK([[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"save/c/profiles/player.bin"] encoding:NSUTF8StringEncoding error:nil] isEqual:@"original profile"]);
    CHECK([[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"maps/a10.map"] encoding:NSUTF8StringEncoding error:nil] isEqual:@"original map"]);CHECK([NSFileManager.defaultManager fileExistsAtPath:[NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastRecoveryBackup"]]);
    HsSettings restored;CHECK(hs_parse(&restored,[NSUserDefaults.standardUserDefaults stringForKey:@"HaloSettingsV1"].UTF8String));CHECK(!restored.cheat_camo&&restored.presets[0].place[0].opacity==.5f);
    NSMutableData *bad=[[NSData dataWithContentsOfURL:archive] mutableCopy];((char *)bad.mutableBytes)[bad.length-1]^=1;NSURL *corrupt=[HaloBackupWork() URLByAppendingPathComponent:@"corrupt.halobackup"];[bad writeToURL:corrupt atomically:YES];BOOL rejected=NO;@try {HaloBackupStage(corrupt,[HaloBackupWork() URLByAppendingPathComponent:@"bad"]);} @catch(NSException *e){(void)e;rejected=YES;}CHECK(rejected);
    NSData *truncated=[bad subdataWithRange:NSMakeRange(0,10)];[truncated writeToURL:corrupt atomically:YES];rejected=NO;@try{HaloBackupStage(corrupt,[HaloBackupWork() URLByAppendingPathComponent:@"short"]);} @catch(NSException *e){(void)e;rejected=YES;}CHECK(rejected);
    Put([root stringByAppendingPathComponent:@"custom_maps/example.map"],@"custom edition map");Put([root stringByAppendingPathComponent:@"custom_maps/example.txt"],@"description");Put([root stringByAppendingPathComponent:@"custom_maps_disabled/off.map"],@"disabled map");Put([root stringByAppendingPathComponent:@"videos/intro.mp4"],@"user movie");
    NSURL *mapsArchive=HaloBackupExport(8);NSDictionary *maps=HaloBackupStage(mapsArchive,[HaloBackupWork() URLByAppendingPathComponent:@"maps-only"]);CHECK([maps[@"files"] count]==5);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloLastEngineIdentityV1"];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloLastEngineChangeBackup"];
    setenv("HALO_BACKUP_TEST_ENGINE_IDENTITY","engine-A",1);error=nil;CHECK(HaloProtectEngineChange(&error));CHECK([[NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastEngineIdentityV1"] isEqual:@"engine-A"]);CHECK(![NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastEngineChangeBackup"]);
    setenv("HALO_BACKUP_TEST_ENGINE_IDENTITY","engine-B",1);error=nil;CHECK(HaloProtectEngineChange(&error));NSString *engineBackup=[NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastEngineChangeBackup"];CHECK(engineBackup.length&&[NSFileManager.defaultManager fileExistsAtPath:engineBackup]);CHECK([[NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastEngineIdentityV1"] isEqual:@"engine-B"]);
    NSDictionary *engineManifest=HaloBackupStage([NSURL fileURLWithPath:engineBackup],[HaloBackupWork() URLByAppendingPathComponent:@"engine-change-check"]);CHECK([engineManifest[@"engine_identity"] isEqual:@"engine-A"]);CHECK([engineManifest[@"files"] count]>=2);
    error=nil;CHECK(HaloProtectEngineChange(&error));CHECK([[NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastEngineChangeBackup"] isEqual:engineBackup]);
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloSettingsV1"];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloLastRecoveryBackup"];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloLastEngineIdentityV1"];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloLastEngineChangeBackup"];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloLastProtectedEngineIdentity"];unsetenv("HALO_BACKUP_TEST_ENGINE_IDENTITY");
    puts("backup archive roundtrip, selection, recovery, engine-change protection, checksum and truncation: PASS");return 0;
} }
