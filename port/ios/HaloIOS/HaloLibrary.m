#import "HaloLibrary.h"
#import "HaloBackupArchive.h"
#import "HaloSettingsStore.h"
#import "HaloUI.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
@interface HaloLibraryController:UIViewController<UIDocumentPickerDelegate>
@property BOOL maps;
@property unsigned mask;
@property NSInteger pickerKind;
@property(nonatomic,copy) NSString *thumbnailName;
@property(nonatomic,strong) UIStackView *rows;
@property BOOL busy;
@property(nonatomic,strong) NSURL *temporaryExport;
@end
@implementation HaloLibraryController
- (void)viewDidLoad { [super viewDidLoad];self.view.backgroundColor=HaloUIBackground();self.title=self.maps?@"Installed Maps":@"Backups";self.mask=7;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];self.rows=HaloUIScrollingStack(self.view,12);[self render]; }
- (void)close { if(!self.busy)[self dismissViewControllerAnimated:YES completion:nil]; }
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;if(self.temporaryExport){[NSFileManager.defaultManager removeItemAtURL:self.temporaryExport error:nil];self.temporaryExport=nil;}
}
- (void)message:(NSString *)text { UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Halo" message:text preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil]; }
- (void)run:(NSURL *(^)(void))job completion:(void(^)(NSURL *))completion {
    if(self.busy)return;self.busy=YES;self.rows.userInteractionEnabled=NO;self.navigationItem.prompt=@"Working…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ NSURL *result=nil;NSString *failure=nil;@try {result=job();}@catch(NSException *e){failure=e.reason;}
        dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.rows.userInteractionEnabled=YES;self.navigationItem.prompt=nil;if(failure)[self message:failure];else if(completion)completion(result);}); });
}
- (void)render {
    for(UIView *v in self.rows.arrangedSubviews){[self.rows removeArrangedSubview:v];[v removeFromSuperview];}
    if(self.maps){[self renderMaps];return;}
    [self.rows addArrangedSubview:HaloUICardView(@"Backup contents",@[
        HaloUINote(@"Back up on-disk progress after saving. Maps are optional. Files lets you choose iCloud Drive or another destination. Active cheats, invite links and temporary sessions are excluded."),
        HaloUISwitchRow(@"Saves and profiles",nil,!!(self.mask&1),^(BOOL on){self.mask=on?self.mask|1:self.mask&~1u;}),
        HaloUISwitchRow(@"App preferences",nil,!!(self.mask&2),^(BOOL on){self.mask=on?self.mask|2:self.mask&~2u;}),
        HaloUISwitchRow(@"Touch / HUD layouts and presets",nil,!!(self.mask&4),^(BOOL on){self.mask=on?self.mask|4:self.mask&~4u;}),
        HaloUISwitchRow(@"Map files and thumbnails",@"May require substantial storage. No compression is applied.",!!(self.mask&8),^(BOOL on){self.mask=on?self.mask|8:self.mask&~8u;}),
        HaloUIButton(@"HaloBackupExport selected backup",1,^(UIButton *b){(void)b;unsigned mask=self.mask;if(!mask){[self message:@"Choose at least one section."];return;}[self run:^NSURL *{return HaloBackupExport(mask);} completion:^(NSURL *url){self.temporaryExport=url;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];picker.delegate=self;self.pickerKind=4;[self presentViewController:picker animated:YES completion:nil];}];}),
        HaloUIButton(@"Restore selected sections…",0,^(UIButton *b){(void)b;if(!self.mask){[self message:@"Choose sections to restore first."];return;}self.pickerKind=1;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];p.delegate=self;[self presentViewController:p animated:YES completion:nil];}),
        HaloUINote(@"Restore merges selected files and replaces matching names. Extra files remain. Restores apply before Halo starts on your next launch, with a recovery backup first.")])];
    NSString *recovery=[NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastRecoveryBackup"];
    if(recovery&&[NSFileManager.defaultManager fileExistsAtPath:recovery])[self.rows addArrangedSubview:HaloUIButton(@"HaloBackupExport last recovery backup",0,^(UIButton *b){(void)b;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[[NSURL fileURLWithPath:recovery]] asCopy:YES];self.pickerKind=4;p.delegate=self;[self presentViewController:p animated:YES completion:nil];})];
}
- (void)renderMaps {
    [self.rows addArrangedSubview:HaloUICardView(@"Maps",@[
        HaloUINote(@"Halo loads the same Documents/Halo/maps directory. This build requires Xbox version 5 maps, including ui.map. Header checks do not prove every asset is intact. Matching builds are required for multiplayer."),
        HaloUIButton(@"Import maps",1,^(UIButton *b){(void)b;self.pickerKind=2;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];p.allowsMultipleSelection=YES;p.delegate=self;[self presentViewController:p animated:YES completion:nil];}),
        HaloUIButton(@"Refresh installed maps",0,^(UIButton *b){(void)b;[self render];})])];
    NSString *folder=[HaloBackupRoot() stringByAppendingPathComponent:@"maps"];NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];BOOL ui=NO;NSUInteger count=0;
    for(NSString *name in names) {
        if(![name.pathExtension.lowercaseString isEqual:@"map"])continue;NSURL *url=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]];if(!HaloBackupRegular(url))continue;count++;if([name.lowercaseString isEqual:@"ui.map"])ui=YES;
        NSFileHandle *f=[NSFileHandle fileHandleForReadingFromURL:url error:nil];NSData *header=nil;@try {header=[f readDataOfLength:2048];}@catch(NSException *e){(void)e;}@finally {[f closeFile];}
        uint32_t magic=0,version=0,foot=0;BOOL valid=NO;if(header.length==2048){memcpy(&magic,header.bytes,4);memcpy(&version,(char *)header.bytes+4,4);memcpy(&foot,(char *)header.bytes+2044,4);valid=CFSwapInt32LittleToHost(magic)==0x68656164 && CFSwapInt32LittleToHost(foot)==0x666f6f74 && CFSwapInt32LittleToHost(version)==5;}
        NSString *base=name.stringByDeletingPathExtension.lowercaseString;BOOL campaign=[@[@"a10",@"a30",@"a50",@"b30",@"b40",@"c10",@"c20",@"c40",@"d20",@"d40"] containsObject:base];
        NSString *kind=[base isEqual:@"ui"]?@"Main menu":campaign?@"Campaign":@"Multiplayer / custom";
        NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];NSString *size=[NSByteCountFormatter stringFromByteCount:[attrs[NSFileSize] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        UIImageView *image=[UIImageView new];image.contentMode=UIViewContentModeScaleAspectFit;image.clipsToBounds=YES;image.backgroundColor=[UIColor colorWithWhite:.16 alpha:1];image.layer.cornerRadius=10;[image.heightAnchor constraintEqualToConstant:110].active=YES;
        NSString *thumb=[[HaloBackupRoot() stringByAppendingPathComponent:@"map_thumbnails"] stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"png"]];image.image=[UIImage imageWithContentsOfFile:thumb]?:[UIImage systemImageNamed:campaign?@"mountain.2.fill":@"map.fill"];image.tintColor=HaloUIAccent();
        [self.rows addArrangedSubview:HaloUICardView(name,@[image,HaloUINote([NSString stringWithFormat:@"%@ · %@\n%@",kind,size,valid?@"Version 5 header verified":@"Invalid / unsupported header: reimport a compatible map"]),HaloUIButton(@"Choose map picture",0,^(UIButton *b){(void)b;self.thumbnailName=base;self.pickerKind=3;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];p.delegate=self;[self presentViewController:p animated:YES completion:nil];})])];
    }
    if(!count)[self.rows addArrangedSubview:HaloUINote(@"No maps installed. Import your compatible map files above.")];
    if(!ui)[self.rows addArrangedSubview:HaloUINote(@"ui.map is missing. Halo needs it to start.")];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;if(!urls.count)return;NSInteger kind=self.pickerKind;if(kind==4){if(self.temporaryExport){[NSFileManager.defaultManager removeItemAtURL:self.temporaryExport error:nil];self.temporaryExport=nil;}return;}
    if(kind==1) {
        NSURL *url=urls.firstObject;unsigned mask=self.mask;
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Restore on next launch?" message:@"Selected files will replace matching saves, profiles, settings or maps. A recovery backup will be created first. Close and reopen Halo after staging." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"HaloBackupStage restore" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){(void)action;[self run:^NSURL *{
            NSFileManager *fm=NSFileManager.defaultManager;NSURL *stage=[HaloBackupWork() URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
            @try { NSDictionary *manifest=HaloBackupStage(url,stage);HaloBackupRequire([manifest writeToURL:[stage URLByAppendingPathComponent:@"manifest.plist"] atomically:YES],@"Cannot save restore manifest.");
                NSURL *dest=[HaloBackupWork() URLByAppendingPathComponent:@"staged" isDirectory:YES];[fm removeItemAtURL:dest error:nil];HaloBackupRequire([fm moveItemAtURL:stage toURL:dest error:nil],@"Cannot stage restore.");HaloBackupRequire([@{@"mask":@(mask)} writeToURL:[HaloBackupWork() URLByAppendingPathComponent:@"pending.plist"] atomically:YES],@"Cannot queue restore.");return dest;
            } @catch(NSException *e){[fm removeItemAtURL:stage error:nil];@throw e;}
        } completion:^(NSURL *result){(void)result;[self message:@"Backup verified. Close and reopen Halo to restore before the game starts."];}];}]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
    } else if(kind==2) {
        UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"Import maps on next launch?" message:@"Matching filenames will be replaced after a recovery backup. Existing maps remain usable until you close and reopen Halo." preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"HaloBackupStage import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;[self run:^NSURL *{
            NSFileManager *fm=NSFileManager.defaultManager;NSURL *stage=[HaloBackupWork() URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];NSMutableArray *records=[NSMutableArray array];NSMutableSet *seen=[NSMutableSet set];
            HaloBackupRequire([fm createDirectoryAtURL:[stage URLByAppendingPathComponent:@"maps"] withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot stage map import.");
            @try {
                for(NSURL *url in urls) {
                    NSString *name=url.lastPathComponent;HaloBackupRequire([name.pathExtension.lowercaseString isEqual:@"map"]&&![seen containsObject:name.lowercaseString],@"Choose distinct .map files.");[seen addObject:name.lowercaseString];NSString *path=[@"maps" stringByAppendingPathComponent:name];HaloBackupRequire(HaloBackupAllowed(path)&&HaloBackupRegular(url),@"Invalid map file.");
                    NSFileHandle *in=[NSFileHandle fileHandleForReadingFromURL:url error:nil];NSData *header=[in readDataOfLength:2048];[in closeFile];uint32_t magic=0,version=0,foot=0;HaloBackupRequire(header.length==2048,@"Map header is truncated.");memcpy(&magic,header.bytes,4);memcpy(&version,(char *)header.bytes+4,4);memcpy(&foot,(char *)header.bytes+2044,4);HaloBackupRequire(CFSwapInt32LittleToHost(magic)==0x68656164&&CFSwapInt32LittleToHost(foot)==0x666f6f74&&CFSwapInt32LittleToHost(version)==5,@"This build requires Xbox version 5 maps.");
                    NSURL *target=[stage URLByAppendingPathComponent:path];HaloBackupRequire([fm copyItemAtURL:url toURL:target error:nil],@"Cannot stage map; check free space.");NSDictionary *a=[fm attributesOfItemAtPath:target.path error:nil];[records addObject:@{@"path":path,@"size":a[NSFileSize],@"sha256":HaloBackupHashFile(target)}];
                }
                HaloBackupRequire([@{@"format":@1,@"files":records} writeToURL:[stage URLByAppendingPathComponent:@"manifest.plist"] atomically:YES],@"Cannot save import manifest.");NSURL *dest=[HaloBackupWork() URLByAppendingPathComponent:@"staged" isDirectory:YES];[fm removeItemAtURL:dest error:nil];HaloBackupRequire([fm moveItemAtURL:stage toURL:dest error:nil],@"Cannot stage import.");HaloBackupRequire([@{@"mask":@8} writeToURL:[HaloBackupWork() URLByAppendingPathComponent:@"pending.plist"] atomically:YES],@"Cannot queue map import.");return dest;
            } @catch(NSException *e) {[fm removeItemAtURL:stage error:nil];@throw e;}
        } completion:^(NSURL *result){(void)result;[self message:@"Maps are staged. Close and reopen Halo to install them safely."];}];}]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:confirm animated:YES completion:nil];
    } else if(kind==3) {
        NSURL *url=urls.firstObject;NSString *name=self.thumbnailName;[self run:^NSURL *{
            NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];HaloBackupRequire([a[NSFileSize] unsignedLongLongValue]<=20*1024*1024,@"Choose an image smaller than 20 MB.");UIImage *image=[UIImage imageWithContentsOfFile:url.path];HaloBackupRequire(image!=nil,@"Cannot read picture.");
            UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(512,288)];UIImage *small=[renderer imageWithActions:^(UIGraphicsImageRendererContext *c){(void)c;[image drawInRect:CGRectMake(0,0,512,288)];}];
            NSString *folder=[HaloBackupRoot() stringByAppendingPathComponent:@"map_thumbnails"];HaloBackupRequire([NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot create thumbnails folder.");NSURL *target=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]]];HaloBackupRequire([UIImagePNGRepresentation(small) writeToURL:target atomically:YES],@"Cannot save thumbnail.");return target;
        } completion:^(NSURL *url){(void)url;[self render];}];
    }
}
@end
UIViewController *HaloBackupsController(void) { HaloLibraryController *c=[HaloLibraryController new];c.maps=NO;return [[UINavigationController alloc] initWithRootViewController:c]; }
UIViewController *HaloMapsController(void) { HaloLibraryController *c=[HaloLibraryController new];c.maps=YES;return [[UINavigationController alloc] initWithRootViewController:c]; }
