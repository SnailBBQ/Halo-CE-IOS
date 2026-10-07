#import "HaloMods.h"
#import "HaloBackupArchive.h"
#define CHECK(x) do { if(!(x)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);return 1;} }while(0)

static void Map(NSString *path, uint32_t version, unsigned char marker) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableData *data=[NSMutableData dataWithLength:4096];uint32_t magic=CFSwapInt32HostToLittle(0x68656164),v=CFSwapInt32HostToLittle(version),foot=CFSwapInt32HostToLittle(0x666f6f74);
    memcpy(data.mutableBytes,&magic,4);memcpy((char *)data.mutableBytes+4,&v,4);memcpy((char *)data.mutableBytes+2044,&foot,4);((unsigned char *)data.mutableBytes)[2048]=marker;[data writeToFile:path atomically:YES];
}
static unsigned char Marker(NSString *path) { NSData *data=[NSData dataWithContentsOfFile:path];return data.length>2048?((const unsigned char *)data.bytes)[2048]:0; }
static void Bytes(NSString *path, const char *text) { [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];[[NSData dataWithBytes:text length:strlen(text)] writeToFile:path atomically:YES]; }

int main(void){@autoreleasepool{
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];setenv("HALO_BACKUP_TEST_ROOT",root.UTF8String,1);
    NSFileManager *fm=NSFileManager.defaultManager;

    /* Simulate an M2.6.87-era enabled replacement: the live map is the overlay,
       while the old durable base store still has the user's original. */
    NSString *target=[root stringByAppendingPathComponent:@"maps/a10.map"];Map(target,5,3);
    NSURL *mods=[HaloBackupWork() URLByAppendingPathComponent:@"mods" isDirectory:YES];
    NSString *identifier=NSUUID.UUID.UUIDString;NSURL *folder=[mods URLByAppendingPathComponent:identifier isDirectory:YES];
    Map([[folder URLByAppendingPathComponent:@"a10.map"] path],5,3);Map([[mods URLByAppendingPathComponent:@"base/a10.map"] path],5,1);
    CHECK([@[@{@"id":identifier,@"file":@"a10.map",@"enabled":@YES,@"hash":@"0000000000000000000000000000000000000000000000000000000000000000"}] writeToURL:[mods URLByAppendingPathComponent:@"list.plist"] atomically:YES]);
    CHECK([@{@"a10.map":@YES} writeToURL:[mods URLByAppendingPathComponent:@"base.plist"] atomically:YES]);
    CHECK(HaloModsLegacyExists());NSError *error=nil;CHECK(HaloModsRetireLegacy(&error));CHECK(!HaloModsLegacyExists());CHECK(Marker(target)==1);

    /* Standard CE v609 maps coexist in custom_maps; resource maps and optional
       picture/description files are accepted without touching maps/. */
    NSString *incoming=[root stringByAppendingPathComponent:@"incoming"],*ce=[incoming stringByAppendingPathComponent:@"my_level.map"];
    Map(ce,609,6);Bytes([incoming stringByAppendingPathComponent:@"my_level.bmp"],"BMfixture");Bytes([incoming stringByAppendingPathComponent:@"my_level.txt"],"fixture description");Bytes([incoming stringByAppendingPathComponent:@"bitmaps.map"],"resource");
    HaloCustomContentImport(@[[NSURL fileURLWithPath:ce],[NSURL fileURLWithPath:[incoming stringByAppendingPathComponent:@"my_level.bmp"]],[NSURL fileURLWithPath:[incoming stringByAppendingPathComponent:@"my_level.txt"]],[NSURL fileURLWithPath:[incoming stringByAppendingPathComponent:@"bitmaps.map"]]]);
    NSArray *maps=HaloCustomMapsList();CHECK(maps.count==1);NSDictionary *entry=maps[0];CHECK([entry[@"valid"] boolValue]&&[entry[@"enabled"] boolValue]&&[entry[@"picture"] boolValue]&&[entry[@"description"] boolValue]);
    CHECK([HaloCustomResourcesStatus()[@"bitmaps.map"] boolValue]);CHECK([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"custom_maps/my_level.map"]]);CHECK(Marker(target)==1);
    HaloCustomMapSetEnabled(@"my_level.map",NO);CHECK([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"custom_maps_disabled/my_level.map"]]);CHECK(![fm fileExistsAtPath:[root stringByAppendingPathComponent:@"custom_maps/my_level.map"]]);
    HaloCustomMapSetEnabled(@"my_level.map",YES);CHECK([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"custom_maps/my_level.map"]]);

    NSString *xbox=[incoming stringByAppendingPathComponent:@"wrong.map"];Map(xbox,5,9);BOOL rejected=NO;@try{HaloCustomContentImport(@[[NSURL fileURLWithPath:xbox]]);}@catch(NSException *e){(void)e;rejected=YES;}CHECK(rejected);

    /* MP4 files are user-supplied. A localized BIK request may fall back to the
       unsuffixed MP4; the Foundation-only harness does not start AVPlayer. */
    NSString *intro=[incoming stringByAppendingPathComponent:@"intro.mp4"];Bytes(intro,"not-real-video-but-nonempty");HaloMoviesImport(@[[NSURL fileURLWithPath:intro]]);CHECK(HaloMoviesList().count==1);CHECK(HaloMovieAvailablePath("d:\\bink\\intro_fr.bik"));HaloMovieRemove(@"intro.mp4");CHECK(!HaloMovieAvailablePath("d:\\bink\\intro.bik"));

    HaloCustomMapRemove(@"my_level.map");CHECK(HaloCustomMapsList().count==0);CHECK([HaloCustomResourcesStatus()[@"bitmaps.map"] boolValue]);
    [fm removeItemAtPath:root error:nil];puts("PASS: legacy replacement retirement, CE v609 library/resources, enable-disable, Xbox rejection and MP4 filename mapping");
}return 0;}
