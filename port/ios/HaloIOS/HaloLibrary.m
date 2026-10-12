#import "HaloLibrary.h"
#import "HaloMods.h"
#import "HaloMapPictures.h"
#import "HaloBackupArchive.h"
#import "HaloSettingsStore.h"
#import "HaloUI.h"
#import "halo_map_order.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
/* Folder permission is opt-in and separate from the invite-file folder. The
 * bookmark lives in app storage; after deletion, the user selects it again. */
static NSURL *HaloExternalSaveFolder(void) {
    NSData *data=[NSUserDefaults.standardUserDefaults dataForKey:@"HaloExternalSaveFolder"];
    if(!data)return nil;
    BOOL stale=NO;NSError *error=nil;
    NSURL *url=[NSURL URLByResolvingBookmarkData:data options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
    if(stale||error)return nil;
    return url;
}
static NSURL *HaloExportExternalSaves(void) {
    NSURL *folder=HaloExternalSaveFolder();
    HaloBackupRequire(folder!=nil,@"Choose your external backup folder again.");
    BOOL access=[folder startAccessingSecurityScopedResource];
    NSURL *archive=nil;__block NSURL *result=nil;NSError *coordinationError=nil;
    @try {
        NSURL *save=[NSURL fileURLWithPath:[HaloBackupRoot() stringByAppendingPathComponent:@"save"] isDirectory:YES];
        BOOL hasSaves=NO;
        NSDirectoryEnumerator *saved=[NSFileManager.defaultManager enumeratorAtURL:save includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey] options:0 errorHandler:nil];
        for(NSURL *file in saved){NSNumber *link=nil;[file getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];if(link.boolValue){[saved skipDescendants];continue;}if(HaloBackupRegular(file)){hasSaves=YES;break;}}
        HaloBackupRequire(hasSaves,@"No saved profiles or progress found. Save in Halo before backing up.");
        archive=HaloBackupExport(1); /* saves/profiles only; preserves save/ paths */
        NSString *app=[NSBundle.mainBundle.bundleIdentifier hasSuffix:@".modtest"]?@"HaloCE-ModTest":@"HaloCE";
        NSString *name=[NSString stringWithFormat:@"%@-Saves-%@.halobackup",app,NSUUID.UUID.UUIDString];
        NSURL *target=[folder URLByAppendingPathComponent:name];
        NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateWritingItemAtURL:target options:0 error:&coordinationError byAccessor:^(NSURL *dest){
            NSFileManager *fm=NSFileManager.defaultManager;
            NSURL *temp=[dest.URLByDeletingLastPathComponent URLByAppendingPathComponent:[@".halo-save-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            @try {
                HaloBackupRequire([fm copyItemAtURL:archive toURL:temp error:nil],@"Cannot write backup; check folder access and free space.");
                HaloBackupRequire([fm moveItemAtURL:temp toURL:dest error:nil],@"Cannot finish the external save backup.");
                result=dest;
            } @finally { [fm removeItemAtURL:temp error:nil]; }
        }];
        HaloBackupRequire(!coordinationError&&result!=nil,coordinationError.localizedDescription?:@"Cannot access the external folder.");
        return result;
    } @finally {
        if(archive)[NSFileManager.defaultManager removeItemAtURL:archive error:nil];
        if(access)[folder stopAccessingSecurityScopedResource];
    }
}
@interface HaloLibraryController:UIViewController<UIDocumentPickerDelegate>
@property BOOL maps;
@property unsigned mask;
@property unsigned initialMask;
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
- (void)viewDidLoad { [super viewDidLoad];self.view.backgroundColor=HaloUIBackground();self.title=self.maps?@"Mods":@"Backups";self.navigationController.navigationBar.tintColor=HaloUIAccent();self.mask=self.initialMask?self.initialMask:54;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];self.rows=HaloUIScrollingStack(self.view,12);[self render]; }
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
        HaloUISwitchRow(@"Campaign saves",@"Persistent checkpoints and their save metadata. Temporary map caches are excluded.",!!(self.mask&16),^(BOOL on){weakSelf.mask=on?weakSelf.mask|16:weakSelf.mask&~16u;}),
        HaloUISwitchRow(@"Halo player profiles",@"Player profiles, playlists and last-used profile references. Restore the matching profile with a campaign save on a fresh installation.",!!(self.mask&32),^(BOOL on){weakSelf.mask=on?weakSelf.mask|32:weakSelf.mask&~32u;}),
        HaloUISwitchRow(@"App preferences",nil,!!(self.mask&2),^(BOOL on){weakSelf.mask=on?weakSelf.mask|2:weakSelf.mask&~2u;}),
        HaloUISwitchRow(@"Touch / HUD layouts and presets",nil,!!(self.mask&4),^(BOOL on){weakSelf.mask=on?weakSelf.mask|4:weakSelf.mask&~4u;}),
        HaloUISwitchRow(@"Maps, Custom Edition & movies",@"Includes Xbox maps, Custom Edition content, thumbnails and user-supplied MP4 movies. May require substantial storage; no compression is applied.",!!(self.mask&8),^(BOOL on){weakSelf.mask=on?weakSelf.mask|8:weakSelf.mask&~8u;}),
        HaloUIButton(@"Export selected backup",1,^(UIButton *b){(void)b;unsigned mask=weakSelf.mask;if(!mask){[weakSelf message:@"Choose at least one section."];return;}[weakSelf run:^NSURL *{return HaloBackupExport(mask);} completion:^(NSURL *url){weakSelf.temporaryExport=url;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];picker.delegate=weakSelf;weakSelf.pickerKind=4;[weakSelf presentViewController:picker animated:YES completion:nil];}];}),
        HaloUIButton(@"Restore selected sections…",0,^(UIButton *b){(void)b;if(!weakSelf.mask){[weakSelf message:@"Choose sections to restore first."];return;}weakSelf.pickerKind=1;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];}),
        HaloUINote(@"Restore merges selected files and replaces matching names. Extra files remain. Restores apply before Halo starts on your next launch, with a recovery backup first.")])];
    NSURL *external=HaloExternalSaveFolder();
    [self.rows addArrangedSubview:HaloUICardView(@"Saves outside the app",@[
        HaloUINote(@"External backups survive app deletion when stored in iCloud Drive or another folder outside Halo. Save in the game, then back up here before deleting. Backups are manual; iCloud upload may take time."),
        HaloUIValueRow(@"Folder",external.lastPathComponent?:@"Not selected",nil),
        HaloUIButton(@"Choose external backup folder",0,^(UIButton *b){(void)b;weakSelf.pickerKind=5;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}),
        HaloUIButton(@"Back up saves and profiles now",1,^(UIButton *b){(void)b;[weakSelf run:^NSURL *{return HaloExportExternalSaves();} completion:^(NSURL *url){(void)url;[weakSelf message:@"Save backup written to the selected folder. Confirm iCloud has uploaded it before deleting Halo. Previous backups are kept."];}];}),
        HaloUIButton(@"Restore external saves…",0,^(UIButton *b){(void)b;weakSelf.mask=1;weakSelf.pickerKind=1;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];picker.directoryURL=external;picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}),
        HaloUINote(@"After reinstalling, select your folder again and restore a .halobackup file. Files return to Halo/save with a recovery backup before replacement. If no backup exists, Halo starts normally. Updates installed over the same app retain local saves.")])];
    NSString *recovery=[NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastRecoveryBackup"];
    if(recovery&&[NSFileManager.defaultManager fileExistsAtPath:recovery])[self.rows addArrangedSubview:HaloUIButton(@"Export last recovery backup",0,^(UIButton *b){(void)b;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[[NSURL fileURLWithPath:recovery]] asCopy:YES];weakSelf.pickerKind=4;p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];})];
    NSString *engineChange=[NSUserDefaults.standardUserDefaults stringForKey:@"HaloLastEngineChangeBackup"];
    if(engineChange&&[NSFileManager.defaultManager fileExistsAtPath:engineChange])[self.rows addArrangedSubview:HaloUIButton(@"Export last engine-change backup",0,^(UIButton *b){(void)b;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[[NSURL fileURLWithPath:engineChange]] asCopy:YES];weakSelf.pickerKind=4;p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];})];
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
    HsSettings opts=[HaloSettingsStore.shared snapshot];BOOL sortAlpha=opts.maps_mp_alpha;

    NSDictionary *resources=HaloCustomResourcesStatus();
    NSArray *custom=nil;@try{custom=HaloCustomMapsList();}@catch(NSException *exception){[self.rows addArrangedSubview:HaloUINote(exception.reason)];custom=@[];}
    NSString *resourceSummary=[NSString stringWithFormat:@"bitmaps.map %@  ·  sounds.map %@  ·  loc.map %@",
        [resources[@"bitmaps.map"] boolValue]?@"✓":@"—",[resources[@"sounds.map"] boolValue]?@"✓":@"—",[resources[@"loc.map"] boolValue]?@"✓":@"—"];
    [self.rows addArrangedSubview:HaloUICardView(@"Custom Edition Maps",@[
        HaloUINote(@"OpenCE build 201 loads standard Halo Custom Edition version 609 maps beside the original Xbox maps. Nothing here replaces Documents/Halo/maps. Import CE .map files plus bitmaps.map, sounds.map and loc.map when a map needs the shared resource caches. Optional <map>.bmp and <map>.txt files provide the in-game picture and description. OpenSauce maps are intentionally unsupported upstream."),
        HaloUIValueRow(@"Shared resources",resourceSummary,nil),
        HaloUIButton(@"Import Custom Edition content",1,^(UIButton *b){(void)b;weakSelf.pickerKind=7;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];picker.allowsMultipleSelection=YES;picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}),
        HaloUIButton(@"Refresh Custom Edition library",0,^(UIButton *b){(void)b;[weakSelf render];})])];
    for(NSDictionary *map in custom){
        NSString *file=map[@"file"];BOOL enabled=[map[@"enabled"] boolValue],valid=[map[@"valid"] boolValue];
        NSString *size=[NSByteCountFormatter stringFromByteCount:[map[@"size"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        NSMutableArray *items=[NSMutableArray arrayWithObject:HaloUINote([NSString stringWithFormat:@"%@ · %@\n%@%@%@",size,valid?@"Custom Edition v609 header verified":@"Invalid / unsupported CE header",[map[@"picture"] boolValue]?@"Picture ✓  ":@"",[map[@"description"] boolValue]?@"Description ✓  ":@"",enabled?@"Active in OpenCE custom_maps":@"Disabled (kept on device)"])];
        [items addObject:HaloUISwitchRow(@"Enabled",@"Enabled maps are scanned by OpenCE the next time its map list opens. Disabling moves the map and its .bmp/.txt sidecars out of custom_maps without deleting them.",enabled,^(BOOL on){@try{HaloCustomMapSetEnabled(file,on);[weakSelf render];}@catch(NSException *e){[weakSelf message:e.reason];}})];
        [items addObject:HaloUIButton(@"Remove custom map",2,^(UIButton *b){(void)b;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Remove Custom Edition map?" message:[NSString stringWithFormat:@"%@ and its optional picture/description will be deleted from Halo. Shared resource maps are not touched.",file] preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){(void)x;[weakSelf run:^NSURL *{HaloCustomMapRemove(file);return nil;} completion:^(NSURL *u){(void)u;[weakSelf render];}];}]];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[weakSelf presentViewController:a animated:YES completion:nil];})];
        [self.rows addArrangedSubview:HaloUICardView(file,items)];
    }
    if(!custom.count)[self.rows addArrangedSubview:HaloUICardView(nil,@[HaloUINote(@"No Custom Edition maps installed yet. Importing CE content writes directly to Documents/Halo/custom_maps, the folder OpenCE build 201 scans.")])];

    NSArray *movies=HaloMoviesList();NSMutableDictionary *movieFiles=[NSMutableDictionary dictionary];for(NSDictionary *movie in movies)movieFiles[[movie[@"file"] lowercaseString]]=movie;
    NSMutableArray *movieStatus=[NSMutableArray array];
    for(NSArray *slot in @[@[@"Intro",@"intro.mp4"],@[@"Credits",@"credits.mp4"],@[@"Attract 1",@"attract1.mp4"],@[@"Attract 2",@"attract2.mp4"],@[@"Attract 3",@"attract3.mp4"]])
        [movieStatus addObject:HaloUIValueRow(slot[0],movieFiles[slot[1]]?@"Installed":@"Missing",nil)];
    NSMutableArray *movieCard=[NSMutableArray arrayWithObjects:HaloUINote(@"Optional movie support: provide your own MP4 with the same logical name as Halo's BIK movie. The iOS host plays it fullscreen with AVPlayer while Halo keeps its normal movie flow. Tap the movie or use Halo's normal controller skip input to skip. Missing MP4s are simply skipped, matching the native port's previous behavior."),HaloUIButton(@"Import MP4 movies",1,^(UIButton *b){(void)b;weakSelf.pickerKind=8;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeMPEG4Movie] asCopy:YES];picker.allowsMultipleSelection=YES;picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}) ,nil];
    [movieCard addObjectsFromArray:movieStatus];
    [self.rows addArrangedSubview:HaloUICardView(@"Movies (MP4 fallback)",movieCard)];
    for(NSDictionary *movie in movies){NSString *file=movie[@"file"];NSString *size=[NSByteCountFormatter stringFromByteCount:[movie[@"size"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];[self.rows addArrangedSubview:HaloUICardView(file,@[HaloUINote([NSString stringWithFormat:@"%@ · %@",size,[movie[@"recognized"] boolValue]?@"recognized Halo movie slot":@"not requested by Halo"]),HaloUIButton(@"Remove movie",2,^(UIButton *b){(void)b;@try{HaloMovieRemove(file);[weakSelf render];}@catch(NSException *e){[weakSelf message:e.reason];}})])];}

    [self.rows addArrangedSubview:HaloUICardView(@"Installed Xbox game files",@[
        HaloUINote(@"Original/Xbox maps remain in Documents/Halo/maps and are never replaced by Custom Edition maps. This list requires Xbox version 5 maps, including ui.map. Matching network builds are required for multiplayer. Menu pictures are read from ui.map where its layout is supported; custom pictures override them."),
        HaloUIButton(@"Import Xbox maps",1,^(UIButton *b){(void)b;weakSelf.pickerKind=2;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];p.allowsMultipleSelection=YES;p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];}),
        HaloUIButton(@"Refresh installed maps",0,^(UIButton *b){(void)b;[weakSelf render];}),
        HaloUISwitchRow(@"Show installed game files",@"Lists every map in Documents/Halo/maps with its picture and header check. Hidden by default because the list is long.",opts.maps_show_files,^(BOOL on){[HaloSettingsStore.shared update:^(HsSettings *s2){s2->maps_show_files=on;}];[weakSelf render];}),
        HaloUISwitchRow(@"Sort multiplayer maps A–Z",@"Off: the order the game's own menu shows them. Campaign maps always stay in mission order at the top.",opts.maps_mp_alpha,^(BOOL on){[HaloSettingsStore.shared update:^(HsSettings *s2){s2->maps_mp_alpha=on;}];[weakSelf render];}),
        HaloUISwitchRow(@"Multiplayer only",@"Hides the campaign maps from this list. Nothing is deleted or unloaded.",opts.maps_mp_only,^(BOOL on){[HaloSettingsStore.shared update:^(HsSettings *s2){s2->maps_mp_only=on;}];[weakSelf render];})])];
    NSString *folder=[HaloBackupRoot() stringByAppendingPathComponent:@"maps"];NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){int c=hm_compare(a.stringByDeletingPathExtension.lowercaseString.UTF8String,b.stringByDeletingPathExtension.lowercaseString.UTF8String,sortAlpha);return c<0?NSOrderedAscending:c>0?NSOrderedDescending:[a localizedCaseInsensitiveCompare:b];}];BOOL ui=NO;NSUInteger count=0,hidden=0;
    for(NSString *name in names) {
        if(![name.pathExtension.lowercaseString isEqual:@"map"])continue;NSURL *url=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]];if(!HaloBackupRegular(url))continue;count++;if([name.lowercaseString isEqual:@"ui.map"])ui=YES;
        {NSString *shownBase=name.stringByDeletingPathExtension.lowercaseString;if(!(opts.maps_show_files&&hm_visible(shownBase.UTF8String,opts.maps_mp_only))){hidden++;continue;}}
        NSFileHandle *f=[NSFileHandle fileHandleForReadingFromURL:url error:nil];NSData *header=nil;@try {header=[f readDataOfLength:2048];}@catch(NSException *e){(void)e;}@finally {[f closeFile];}
        uint32_t magic=0,version=0,foot=0;BOOL valid=NO;if(header.length==2048){memcpy(&magic,header.bytes,4);memcpy(&version,(char *)header.bytes+4,4);memcpy(&foot,(char *)header.bytes+2044,4);valid=CFSwapInt32LittleToHost(magic)==0x68656164 && CFSwapInt32LittleToHost(foot)==0x666f6f74 && CFSwapInt32LittleToHost(version)==5;}
        NSString *base=name.stringByDeletingPathExtension.lowercaseString;BOOL campaign=[@[@"a10",@"a30",@"a50",@"b30",@"b40",@"c10",@"c20",@"c40",@"d20",@"d40"] containsObject:base];
        NSString *kind=[base isEqual:@"ui"]?@"Main menu":campaign?@"Campaign":@"Multiplayer / custom";
        NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];NSString *size=[NSByteCountFormatter stringFromByteCount:[attrs[NSFileSize] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        UIImageView *image=[UIImageView new];image.contentMode=UIViewContentModeScaleAspectFit;image.clipsToBounds=YES;image.backgroundColor=UIColor.clearColor;image.layer.cornerRadius=0;[image.heightAnchor constraintEqualToConstant:190].active=YES;
        NSString *thumb=[[HaloBackupRoot() stringByAppendingPathComponent:@"map_thumbnails"] stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"png"]];image.image=[UIImage imageWithContentsOfFile:thumb]?:self.mapPictures[base]?:[UIImage systemImageNamed:campaign?@"mountain.2.fill":@"map.fill"];image.tintColor=HaloUIAccent();
        [self.rows addArrangedSubview:HaloUICardView((hm_index(base.UTF8String)>=0||hm_is_ui(base.UTF8String))?[NSString stringWithUTF8String:hm_title(base.UTF8String)]:name,@[image,HaloUINote([NSString stringWithFormat:@"%@ · %@ · %@\n%@",name,kind,size,valid?@"Version 5 header verified":@"Invalid / unsupported header: reimport a compatible map"]),HaloUIButton(@"Choose map picture",0,^(UIButton *b){(void)b;weakSelf.thumbnailName=base;weakSelf.pickerKind=3;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];})])];
    }
    if(count&&!opts.maps_show_files)[self.rows addArrangedSubview:HaloUICardView(nil,@[HaloUINote([NSString stringWithFormat:@"%lu installed Xbox game files are hidden. Turn on “Show installed game files” above to list them, choose map pictures or read their header checks.",(unsigned long)count])])];
    else if(opts.maps_show_files&&opts.maps_mp_only&&hidden)[self.rows addArrangedSubview:HaloUINote([NSString stringWithFormat:@"%lu campaign maps are hidden by Multiplayer only.",(unsigned long)hidden])];
    if(!count)[self.rows addArrangedSubview:HaloUINote(@"No Xbox maps installed. Import your compatible version 5 map files above.")];
    if(!ui)[self.rows addArrangedSubview:HaloUINote(@"ui.map is missing. Halo needs it to start.")];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    __weak typeof(self) weakSelf=self;

    (void)controller;if(!urls.count)return;NSInteger kind=self.pickerKind;if(kind==4){if(self.temporaryExport){[NSFileManager.defaultManager removeItemAtURL:self.temporaryExport error:nil];self.temporaryExport=nil;}return;}
    if(kind==5) {
        NSURL *url=urls.firstObject;BOOL access=[url startAccessingSecurityScopedResource];NSError *error=nil;
        NSString *home=[NSHomeDirectory().stringByStandardizingPath stringByAppendingString:@"/"];
        if([url.URLByResolvingSymlinksInPath.path.stringByStandardizingPath hasPrefix:home]) {
            if(access)[url stopAccessingSecurityScopedResource];[self message:@"Choose iCloud Drive or a folder outside this app so backups survive deletion."];return;
        }
        NSData *bookmark=[url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
        if(access)[url stopAccessingSecurityScopedResource];
        if(!bookmark){[self message:error.localizedDescription?:@"Cannot remember this folder."];return;}
        [NSUserDefaults.standardUserDefaults setObject:bookmark forKey:@"HaloExternalSaveFolder"];[self render];return;
    }
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
    } else if(kind==7) {
        [self run:^NSURL *{HaloCustomContentImport(urls);return urls.firstObject;} completion:^(NSURL *result){(void)result;[weakSelf render];[weakSelf message:@"Custom Edition content installed. OpenCE will rescan custom_maps when its map list opens."];}];
    } else if(kind==8) {
        [self run:^NSURL *{HaloMoviesImport(urls);return urls.firstObject;} completion:^(NSURL *result){(void)result;[weakSelf render];[weakSelf message:@"MP4 movie fallback installed. Halo will use it when the matching BIK movie is requested."];}];
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
UIViewController *HaloBackupsControllerForSections(unsigned sections) { HaloLibraryController *c=[HaloLibraryController new];c.initialMask=sections&63u;return [[UINavigationController alloc] initWithRootViewController:c]; }
UIViewController *HaloMapsController(void) { HaloLibraryController *c=[HaloLibraryController new];c.maps=YES;return [[UINavigationController alloc] initWithRootViewController:c]; }
