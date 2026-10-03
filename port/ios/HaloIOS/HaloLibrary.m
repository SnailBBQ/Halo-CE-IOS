#import "HaloLibrary.h"
#import "HaloMods.h"
#import "HaloMapPictures.h"
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
@property(nonatomic,copy) NSDictionary<NSString *,UIImage *> *mapPictures;
@property(nonatomic,copy) NSString *pictureFingerprint;
@property BOOL readingPictures;
@property(nonatomic,strong) NSURL *temporaryExport;
@end
@implementation HaloLibraryController
- (void)viewDidLoad { [super viewDidLoad];self.view.backgroundColor=HaloUIBackground();self.title=self.maps?@"Mods":@"Backups";self.mask=7;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];self.rows=HaloUIScrollingStack(self.view,12);[self render]; }
- (void)close { if(!self.busy)[self dismissViewControllerAnimated:YES completion:nil]; }
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;if(self.temporaryExport){[NSFileManager.defaultManager removeItemAtURL:self.temporaryExport error:nil];self.temporaryExport=nil;}
}
- (void)message:(NSString *)text { UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Halo" message:text preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil]; }
- (void)run:(NSURL *(^)(void))job completion:(void(^)(NSURL *))completion {
    __weak typeof(self) weakSelf=self;

    if(weakSelf.busy)return;weakSelf.busy=YES;weakSelf.rows.userInteractionEnabled=NO;weakSelf.navigationItem.prompt=@"Working…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ NSURL *result=nil;NSString *failure=nil;@try {result=job();}@catch(NSException *e){failure=e.reason;}
        dispatch_async(dispatch_get_main_queue(),^{weakSelf.busy=NO;weakSelf.rows.userInteractionEnabled=YES;weakSelf.navigationItem.prompt=nil;if(failure)[weakSelf message:failure];else if(completion)completion(result);}); });
}
- (void)render {
    __weak typeof(self) weakSelf=self;

    for(UIView *v in self.rows.arrangedSubviews){[self.rows removeArrangedSubview:v];[v removeFromSuperview];}
    if(self.maps){[self renderMaps];return;}
    [self.rows addArrangedSubview:HaloUICardView(@"Backup contents",@[
        HaloUINote(@"Back up on-disk progress after saving. Maps are optional. Files lets you choose iCloud Drive or another destination. Active cheats, invite links and temporary sessions are excluded."),
        HaloUISwitchRow(@"Saves and profiles",nil,!!(self.mask&1),^(BOOL on){weakSelf.mask=on?weakSelf.mask|1:weakSelf.mask&~1u;}),
        HaloUISwitchRow(@"App preferences",nil,!!(self.mask&2),^(BOOL on){weakSelf.mask=on?weakSelf.mask|2:weakSelf.mask&~2u;}),
        HaloUISwitchRow(@"Touch / HUD layouts and presets",nil,!!(self.mask&4),^(BOOL on){weakSelf.mask=on?weakSelf.mask|4:weakSelf.mask&~4u;}),
        HaloUISwitchRow(@"Map files and thumbnails",@"May require substantial storage. No compression is applied.",!!(self.mask&8),^(BOOL on){weakSelf.mask=on?weakSelf.mask|8:weakSelf.mask&~8u;}),
        HaloUIButton(@"Export selected backup",1,^(UIButton *b){(void)b;unsigned mask=weakSelf.mask;if(!mask){[weakSelf message:@"Choose at least one section."];return;}[weakSelf run:^NSURL *{return HaloBackupExport(mask);} completion:^(NSURL *url){weakSelf.temporaryExport=url;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];picker.delegate=weakSelf;weakSelf.pickerKind=4;[weakSelf presentViewController:picker animated:YES completion:nil];}];}),
        HaloUIButton(@"Restore selected sections…",0,^(UIButton *b){(void)b;if(!weakSelf.mask){[weakSelf message:@"Choose sections to restore first."];return;}weakSelf.pickerKind=1;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];}),
        HaloUINote(@"Restore merges selected files and replaces matching names. Extra files remain. Restores apply before Halo starts on your next launch, with a recovery backup first.")])];
    NSString *recovery=[NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastRecoveryBackup"];
    if(recovery&&[NSFileManager.defaultManager fileExistsAtPath:recovery])[self.rows addArrangedSubview:HaloUIButton(@"Export last recovery backup",0,^(UIButton *b){(void)b;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[[NSURL fileURLWithPath:recovery]] asCopy:YES];weakSelf.pickerKind=4;p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];})];
}
- (void)loadMapPictures {
    if(self.readingPictures)return;
    NSString *folder=[HaloBackupRoot() stringByAppendingPathComponent:@"maps"];NSString *ui=nil;
    for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil])if([name.lowercaseString isEqual:@"ui.map"]){ui=[folder stringByAppendingPathComponent:name];break;}
    NSDictionary *attrs=ui?[NSFileManager.defaultManager attributesOfItemAtPath:ui error:nil]:nil;
    NSString *fingerprint=[NSString stringWithFormat:@"%@-%@-%@",ui,attrs[NSFileSize],attrs[NSFileModificationDate]];
    if([self.pictureFingerprint isEqual:fingerprint])return;
    self.pictureFingerprint=fingerprint;self.readingPictures=YES;__weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSDictionary *images=ui?HaloReadMapPictures([NSURL fileURLWithPath:ui]):@{};
        dispatch_async(dispatch_get_main_queue(),^{weakSelf.mapPictures=images;weakSelf.readingPictures=NO;if(weakSelf.maps)[weakSelf render];});
    });
}
- (void)renderMaps {
    [self loadMapPictures];
    __weak typeof(self) weakSelf=self;
    NSArray *mods=nil;@try{mods=HaloModsList();}@catch(NSException *exception){[self.rows addArrangedSubview:HaloUINote(exception.reason)];return;}
    [self.rows addArrangedSubview:HaloUICardView(@"Mod library",@[
        HaloUINote(@"Import compiled Xbox version 5 map mods. Weapon, character and other tag changes must be compiled into these maps; loose tags and executable plugins are not supported. Changes load on the next app launch. Later enabled entries override earlier entries with the same filename. Original maps are preserved for unloading."),
        HaloUIButton(@"Import mods",1,^(UIButton *button){(void)button;weakSelf.pickerKind=5;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];picker.allowsMultipleSelection=YES;picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}),
        HaloUINote(HaloModsPending()?@"Changes pending — quit and reopen Halo to apply safely.":@"The selected mod order is installed.")])];
    for(NSUInteger index=0;index<mods.count;index++){
        NSDictionary *mod=mods[index];NSMutableArray *items=[NSMutableArray array];
        [items addObject:HaloUISwitchRow(@"Loaded on next launch",nil,[mod[@"enabled"] boolValue],^(BOOL enabled){@try{HaloModsSetEnabled(index,enabled);[weakSelf render];}@catch(NSException *exception){[weakSelf message:exception.reason];}})];
        if(index)[items addObject:HaloUIButton(@"Move earlier",0,^(UIButton *button){(void)button;@try{HaloModsMove(index,-1);[weakSelf render];}@catch(NSException *exception){[weakSelf message:exception.reason];}})];
        if(index+1<mods.count)[items addObject:HaloUIButton(@"Move later",0,^(UIButton *button){(void)button;@try{HaloModsMove(index,1);[weakSelf render];}@catch(NSException *exception){[weakSelf message:exception.reason];}})];
        [items addObject:HaloUIButton(@"Export mod",0,^(UIButton *button){(void)button;@try{UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[HaloModsExport(index)] asCopy:YES];picker.delegate=weakSelf;weakSelf.pickerKind=6;[weakSelf presentViewController:picker animated:YES completion:nil];}@catch(NSException *exception){[weakSelf message:exception.reason];}})];
        [self.rows addArrangedSubview:HaloUICardView([NSString stringWithFormat:@"%lu · %@",(unsigned long)index+1,mod[@"file"]],items)];
    }
    if(!mods.count)[self.rows addArrangedSubview:HaloUINote(@"No mods imported. Your installed game maps remain available below.")];

    [self.rows addArrangedSubview:HaloUICardView(@"Installed game files",@[
        HaloUINote(@"Halo loads the same Documents/Halo/maps directory. This build requires Xbox version 5 maps, including ui.map. Header checks do not prove every asset is intact. Matching builds are required for multiplayer. Menu pictures are read from ui.map where its layout is supported; custom pictures override them."),
        HaloUIButton(@"Import maps",1,^(UIButton *b){(void)b;weakSelf.pickerKind=2;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];p.allowsMultipleSelection=YES;p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];}),
        HaloUIButton(@"Refresh installed maps",0,^(UIButton *b){(void)b;[weakSelf render];})])];
    NSString *folder=[HaloBackupRoot() stringByAppendingPathComponent:@"maps"];NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];BOOL ui=NO;NSUInteger count=0;
    for(NSString *name in names) {
        if(![name.pathExtension.lowercaseString isEqual:@"map"])continue;NSURL *url=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]];if(!HaloBackupRegular(url))continue;count++;if([name.lowercaseString isEqual:@"ui.map"])ui=YES;
        NSFileHandle *f=[NSFileHandle fileHandleForReadingFromURL:url error:nil];NSData *header=nil;@try {header=[f readDataOfLength:2048];}@catch(NSException *e){(void)e;}@finally {[f closeFile];}
        uint32_t magic=0,version=0,foot=0;BOOL valid=NO;if(header.length==2048){memcpy(&magic,header.bytes,4);memcpy(&version,(char *)header.bytes+4,4);memcpy(&foot,(char *)header.bytes+2044,4);valid=CFSwapInt32LittleToHost(magic)==0x68656164 && CFSwapInt32LittleToHost(foot)==0x666f6f74 && CFSwapInt32LittleToHost(version)==5;}
        NSString *base=name.stringByDeletingPathExtension.lowercaseString;BOOL campaign=[@[@"a10",@"a30",@"a50",@"b30",@"b40",@"c10",@"c20",@"c40",@"d20",@"d40"] containsObject:base];
        NSString *kind=[base isEqual:@"ui"]?@"Main menu":campaign?@"Campaign":@"Multiplayer / custom";
        NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];NSString *size=[NSByteCountFormatter stringFromByteCount:[attrs[NSFileSize] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        UIImageView *image=[UIImageView new];image.contentMode=UIViewContentModeScaleAspectFit;image.clipsToBounds=YES;image.backgroundColor=[UIColor colorWithWhite:.16 alpha:1];image.layer.cornerRadius=10;[image.heightAnchor constraintEqualToConstant:110].active=YES;
        NSString *thumb=[[HaloBackupRoot() stringByAppendingPathComponent:@"map_thumbnails"] stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"png"]];image.image=[UIImage imageWithContentsOfFile:thumb]?:self.mapPictures[base]?:[UIImage systemImageNamed:campaign?@"mountain.2.fill":@"map.fill"];image.tintColor=HaloUIAccent();
        [self.rows addArrangedSubview:HaloUICardView(name,@[image,HaloUINote([NSString stringWithFormat:@"%@ · %@\n%@",kind,size,valid?@"Version 5 header verified":@"Invalid / unsupported header: reimport a compatible map"]),HaloUIButton(@"Choose map picture",0,^(UIButton *b){(void)b;weakSelf.thumbnailName=base;weakSelf.pickerKind=3;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];})])];
    }
    if(!count)[self.rows addArrangedSubview:HaloUINote(@"No maps installed. Import your compatible map files above.")];
    if(!ui)[self.rows addArrangedSubview:HaloUINote(@"ui.map is missing. Halo needs it to start.")];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    __weak typeof(self) weakSelf=self;

    (void)controller;if(!urls.count)return;NSInteger kind=self.pickerKind;if(kind==4){if(self.temporaryExport){[NSFileManager.defaultManager removeItemAtURL:self.temporaryExport error:nil];self.temporaryExport=nil;}return;}
    if(kind==1) {
        NSURL *url=urls.firstObject;unsigned mask=self.mask;
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Restore on next launch?" message:@"Selected files will replace matching saves, profiles, settings or maps. A recovery backup will be created first. Close and reopen Halo after staging." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Stage restore" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){(void)action;[weakSelf run:^NSURL *{
            NSFileManager *fm=NSFileManager.defaultManager;NSURL *stage=[HaloBackupWork() URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
            @try { NSDictionary *manifest=HaloBackupStage(url,stage);HaloBackupRequire([manifest writeToURL:[stage URLByAppendingPathComponent:@"manifest.plist"] atomically:YES],@"Cannot save restore manifest.");
                NSURL *dest=[HaloBackupWork() URLByAppendingPathComponent:@"staged" isDirectory:YES];[fm removeItemAtURL:dest error:nil];HaloBackupRequire([fm moveItemAtURL:stage toURL:dest error:nil],@"Cannot stage restore.");HaloBackupRequire([@{@"mask":@(mask)} writeToURL:[HaloBackupWork() URLByAppendingPathComponent:@"pending.plist"] atomically:YES],@"Cannot queue restore.");return dest;
            } @catch(NSException *e){[fm removeItemAtURL:stage error:nil];@throw e;}
        } completion:^(NSURL *result){(void)result;[weakSelf message:@"Backup verified. Close and reopen Halo to restore before the game starts."];}];}]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
    } else if(kind==5) {
        [self run:^NSURL *{HaloModsImport(urls);return urls.firstObject;} completion:^(NSURL *result){(void)result;[weakSelf render];}];
    } else if(kind==2) {
        UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"Import maps on next launch?" message:@"Matching filenames will be replaced after a recovery backup. Existing maps remain usable until you close and reopen Halo." preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Stage import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;[weakSelf run:^NSURL *{
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
        } completion:^(NSURL *result){(void)result;[weakSelf message:@"Maps are staged. Close and reopen Halo to install them safely."];}];}]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:confirm animated:YES completion:nil];
    } else if(kind==3) {
        NSURL *url=urls.firstObject;NSString *name=self.thumbnailName;[self run:^NSURL *{
            NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];HaloBackupRequire([a[NSFileSize] unsignedLongLongValue]<=20*1024*1024,@"Choose an image smaller than 20 MB.");UIImage *image=[UIImage imageWithContentsOfFile:url.path];HaloBackupRequire(image!=nil,@"Cannot read picture.");
            UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(512,288)];UIImage *small=[renderer imageWithActions:^(UIGraphicsImageRendererContext *c){(void)c;[image drawInRect:CGRectMake(0,0,512,288)];}];
            NSString *folder=[HaloBackupRoot() stringByAppendingPathComponent:@"map_thumbnails"];HaloBackupRequire([NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil],@"Cannot create thumbnails folder.");NSURL *target=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]]];HaloBackupRequire([UIImagePNGRepresentation(small) writeToURL:target atomically:YES],@"Cannot save thumbnail.");return target;
        } completion:^(NSURL *url){(void)url;[weakSelf render];}];
    }
}
@end
UIViewController *HaloBackupsController(void) { HaloLibraryController *c=[HaloLibraryController new];c.maps=NO;return [[UINavigationController alloc] initWithRootViewController:c]; }
UIViewController *HaloMapsController(void) { HaloLibraryController *c=[HaloLibraryController new];c.maps=YES;return [[UINavigationController alloc] initWithRootViewController:c]; }
