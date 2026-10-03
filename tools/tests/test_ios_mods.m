#import "HaloMods.h"
#import "HaloBackupArchive.h"
#define CHECK(x) do { if(!(x)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);return 1;} }while(0)
static void Map(NSString *path,unsigned char marker) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableData *data=[NSMutableData dataWithLength:2050];uint32_t magic=CFSwapInt32HostToLittle(0x68656164),version=CFSwapInt32HostToLittle(5),foot=CFSwapInt32HostToLittle(0x666f6f74);
    memcpy(data.mutableBytes,&magic,4);memcpy((char *)data.mutableBytes+4,&version,4);memcpy((char *)data.mutableBytes+2044,&foot,4);((unsigned char *)data.mutableBytes)[2048]=marker;[data writeToFile:path atomically:YES];
}
static unsigned char ReadModFixtureMarker(NSString *path) { NSData *data=[NSData dataWithContentsOfFile:path];return data.length>2048?((unsigned char *)data.bytes)[2048]:0; }
int main(void){@autoreleasepool{
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];setenv("HALO_BACKUP_TEST_ROOT",root.UTF8String,1);
    NSString *target=[root stringByAppendingPathComponent:@"maps/a10.map"],*a=[root stringByAppendingPathComponent:@"one/a10.map"],*b=[root stringByAppendingPathComponent:@"two/a10.map"];
    Map(target,1);Map(a,2);Map(b,3);HaloModsImport(@[[NSURL fileURLWithPath:a],[NSURL fileURLWithPath:b]]);
    CHECK(HaloModsList().count==2 && HaloModsPending());CHECK(ReadModFixtureMarker(target)==1);
    HaloModsSetEnabled(0,YES);HaloModsSetEnabled(1,YES);NSError *error=nil;CHECK(HaloModsApply(&error));CHECK(ReadModFixtureMarker(target)==3 && !HaloModsPending());
    HaloModsMove(1,-1);CHECK(HaloModsApply(&error));CHECK(ReadModFixtureMarker(target)==2);
    HaloModsSetEnabled(0,NO);HaloModsSetEnabled(1,NO);CHECK(HaloModsApply(&error));CHECK(ReadModFixtureMarker(target)==1);
    NSString *newMap=[root stringByAppendingPathComponent:@"new/custom.map"];Map(newMap,4);HaloModsImport(@[[NSURL fileURLWithPath:newMap]]);HaloModsSetEnabled(2,YES);CHECK(HaloModsApply(&error));CHECK(ReadModFixtureMarker([root stringByAppendingPathComponent:@"maps/custom.map"])==4);
    HaloModsSetEnabled(2,NO);CHECK(HaloModsApply(&error));CHECK(![NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@"maps/custom.map"]]);
    /* Failed validation cannot change installed maps. */
    NSURL *export=HaloModsExport(1);Map(export.path,9);HaloModsSetEnabled(1,YES);CHECK(!HaloModsApply(&error));CHECK(ReadModFixtureMarker(target)==1);
    BOOL rejected=NO;@try{HaloModsImport(@[[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"test.weapon"]]]);}@catch(NSException *exception){(void)exception;rejected=YES;}CHECK(rejected);
    /* Simulate termination after a replacement but before transaction commit. */
    NSURL *mods=[HaloBackupWork() URLByAppendingPathComponent:@"mods"],*rollback=[mods URLByAppendingPathComponent:@"rollback/a10.map"];
    Map(rollback.path,1);Map(target,7);CHECK([@{@"files":@{@"a10.map":@YES}} writeToURL:[mods URLByAppendingPathComponent:@"journal.plist"] atomically:YES]);
    CHECK(!HaloModsApply(&error));CHECK(ReadModFixtureMarker(target)==1);
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    puts("PASS: map mod order, no live writes, original restoration, new-map unloading, hash rejection, interrupted-install recovery");
}return 0;}
