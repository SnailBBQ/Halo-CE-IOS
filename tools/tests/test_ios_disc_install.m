#import <Foundation/Foundation.h>
#import "HaloBackupArchive.h"
#import "HaloDiscImport.h"
#import "HaloMods.h"
#define CHECK(...) do{if(!(__VA_ARGS__)){fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__);return 1;}}while(0)
static NSURL *File(NSString *path){return [NSURL fileURLWithPath:[HaloBackupRoot() stringByAppendingPathComponent:path]];}
static void Put(NSURL *url,char marker){
    [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableData *data=[NSMutableData dataWithLength:4096];unsigned char *b=data.mutableBytes;uint32_t head=0x68656164,v=5,foot=0x666f6f74;
    memcpy(b,&head,4);memcpy(b+4,&v,4);memcpy(b+64,"01.10.12.2276",13);memcpy(b+2044,&foot,4);b[2048]=marker;[data writeToURL:url atomically:YES];
}
static char DiscTestMarker(NSURL *url){NSData *d=[NSData dataWithContentsOfURL:url];return d.length>2048?((const char *)d.bytes)[2048]:0;}
static NSURL *Stage(char marker){NSURL *s=[HaloBackupWork() URLByAppendingPathComponent:NSUUID.UUID.UUIDString];Put([s URLByAppendingPathComponent:@"a10.map"],marker);Put([s URLByAppendingPathComponent:@"ui.map"],marker);return s;}
int main(void){@autoreleasepool{
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];setenv("HALO_BACKUP_TEST_ROOT",root.UTF8String,1);
    NSURL *a10=File(@"maps/a10.map"),*ui=File(@"maps/UI.MAP");Put(a10,'O');Put(ui,'O');
    NSError *error=nil;NSUInteger added=0,kept=0;
    CHECK(HaloDiscInstall(Stage('N'),NO,nil,&added,&kept,&error));CHECK(added==0&&kept==2);CHECK(DiscTestMarker(a10)=='O');
    CHECK(HaloDiscInstall(Stage('N'),YES,nil,&added,&kept,&error));CHECK(added==2&&kept==0);CHECK(DiscTestMarker(a10)=='N');CHECK(DiscTestMarker(ui)=='N');
    __block int calls=0;CHECK(!HaloDiscInstall(Stage('C'),YES,^BOOL{return ++calls>=2;},&added,&kept,&error));CHECK(DiscTestMarker(a10)=='N');CHECK(DiscTestMarker(ui)=='N');CHECK(!HaloDiscImportPending());
    NSURL *mod=File(@"incoming/a10.map");Put(mod,'M');HaloModsImport(@[mod]);HaloModsSetEnabled(0,YES);CHECK(HaloModsApply(&error));CHECK(DiscTestMarker(a10)=='M');
    CHECK(HaloDiscInstall(Stage('D'),YES,nil,&added,&kept,&error));CHECK(DiscTestMarker(a10)=='M');CHECK(HaloModsPending());CHECK(HaloModsApply(&error));CHECK(DiscTestMarker(a10)=='M');
    HaloModsSetEnabled(0,NO);CHECK(HaloModsApply(&error));CHECK(DiscTestMarker(a10)=='D');
    /* Simulate termination after an original was moved and a new file installed. */
    NSURL *work=[HaloBackupWork() URLByAppendingPathComponent:@"disc-install"];[NSFileManager.defaultManager createDirectoryAtURL:work withIntermediateDirectories:YES attributes:nil error:nil];
    CHECK([NSFileManager.defaultManager moveItemAtURL:a10 toURL:[work URLByAppendingPathComponent:@"old-0"] error:nil]);Put(a10,'X');
    CHECK([@{@"files":@[@{@"maps":@YES,@"path":@"maps/a10.map",@"had":@YES}]} writeToURL:[work URLByAppendingPathComponent:@"journal.plist"] atomically:YES]);
    CHECK(HaloDiscImportPending());CHECK(HaloDiscImportRecover(&error));CHECK(DiscTestMarker(a10)=='D');CHECK(!HaloDiscImportPending());
    NSURL *bad=Stage('B');[[NSData data] writeToURL:[bad URLByAppendingPathComponent:@"ui.map"] atomically:YES];CHECK(!HaloDiscInstall(bad,YES,nil,&added,&kept,&error));CHECK(DiscTestMarker(a10)=='D');CHECK(DiscTestMarker(ui)=='D');
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];puts("disc install: keep, replace, cancel, recovery and mod-original tests passed");return 0;
}}
