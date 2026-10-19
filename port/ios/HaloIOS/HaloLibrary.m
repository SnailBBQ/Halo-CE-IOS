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
/* A section's title and one short line under it, outside the cards, so a long page reads in blocks. */
static UIView *HaloLibrarySection(NSString *title, NSString *note) {
    NSMutableArray<UIView *> *items=[NSMutableArray arrayWithObject:HaloUILabel(title,22,UIFontWeightBold,nil)];
    if(note.length)[items addObject:HaloUINote(note)];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:items];
    stack.axis=UILayoutConstraintAxisVertical;stack.spacing=4;
    stack.layoutMargins=UIEdgeInsetsMake(16,4,0,4);stack.layoutMarginsRelativeArrangement=YES;
    return stack;
}
/* The list's choices in one row: Hide, All, Multiplayer, Campaign. */
static NSArray<NSString *> *HaloLibraryShowChoices(void) { return @[@"Hide",@"All",@"Multiplayer",@"Campaign"]; }
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
@property(nonatomic,copy) NSString *modsFingerprint;
@property(nonatomic,strong) NSTimer *modsTimer;
@property BOOL embedded;
@property(nonatomic,strong) NSMutableSet<NSString *> *openModules;
@property BOOL extrasChecked;
@property(nonatomic,copy) NSString *extrasSummary;
@end
@implementation HaloLibraryController
- (void)viewDidLoad { [super viewDidLoad];self.view.backgroundColor=HaloUIBackground();self.title=self.maps?@"Mods":@"Backups";self.navigationController.navigationBar.tintColor=HaloUIAccent();self.mask=self.initialMask?self.initialMask:54;if(!self.embedded)self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];if(self.maps&&!self.embedded)self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain target:self action:@selector(render)];self.rows=HaloUIScrollingStack(self.view,12);[self render];if(self.embedded)[self startModsTimer]; }
/* The game's own Mods menu and this list share mods/load_order.toml and the mod folders. While this screen is open, a change
 * made from the game (or from the Files app) shows here within a couple of seconds. */
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startModsTimer];
}
- (void)startModsTimer {
    if(!self.maps)return;
    __weak typeof(self) weakSelf=self;
    [self.modsTimer invalidate];
    self.modsTimer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){(void)timer;
        HaloLibraryController *strong=weakSelf;
        if(!strong||strong.busy||strong.presentedViewController||!strong.view.window||strong.view.hidden)return;
        if(![HaloModPackFingerprint() isEqualToString:strong.modsFingerprint?:@""])[strong render];}];
}
- (void)viewWillDisappear:(BOOL)animated {[super viewWillDisappear:animated];[self.modsTimer invalidate];self.modsTimer=nil;}
- (void)dealloc {[self.modsTimer invalidate];}
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
    [self.rows addArrangedSubview:HaloUICardView(@"1. Choose what to include",@[
        HaloUINote(@"These ticks are used by both Export and Restore below. Maps are optional and can be large. Active cheats, invite links and temporary sessions are never saved."),
        HaloUISwitchRow(@"Campaign saves",@"Persistent checkpoints and their save metadata. Temporary map caches are excluded.",!!(self.mask&16),^(BOOL on){weakSelf.mask=on?weakSelf.mask|16:weakSelf.mask&~16u;}),
        HaloUISwitchRow(@"Halo player profiles",@"Player profiles, playlists and last-used profile references. Restore the matching profile with a campaign save on a fresh installation.",!!(self.mask&32),^(BOOL on){weakSelf.mask=on?weakSelf.mask|32:weakSelf.mask&~32u;}),
        HaloUISwitchRow(@"App preferences",nil,!!(self.mask&2),^(BOOL on){weakSelf.mask=on?weakSelf.mask|2:weakSelf.mask&~2u;}),
        HaloUISwitchRow(@"Touch / HUD layouts and presets",nil,!!(self.mask&4),^(BOOL on){weakSelf.mask=on?weakSelf.mask|4:weakSelf.mask&~4u;}),
        HaloUISwitchRow(@"Maps, Custom Edition & movies",@"Includes Xbox maps, Custom Edition content, thumbnails and user-supplied MP4 movies. May require substantial storage; no compression is applied.",!!(self.mask&8),^(BOOL on){weakSelf.mask=on?weakSelf.mask|8:weakSelf.mask&~8u;}),
        HaloUIButton(@"Export a backup file (Files)…",1,^(UIButton *b){(void)b;unsigned mask=weakSelf.mask;if(!mask){[weakSelf message:@"Choose at least one section."];return;}[weakSelf run:^NSURL *{return HaloBackupExport(mask);} completion:^(NSURL *url){weakSelf.temporaryExport=url;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];picker.delegate=weakSelf;weakSelf.pickerKind=4;[weakSelf presentViewController:picker animated:YES completion:nil];}];}),
        HaloUINote(@"Saves a .halobackup file wherever you choose in Files (iCloud Drive, On My iPhone, a USB drive).")])];
    [self.rows addArrangedSubview:HaloUICardView(@"2. Restore",@[
        HaloUIButton(@"Restore from a backup file…",0,^(UIButton *b){(void)b;if(!weakSelf.mask){[weakSelf message:@"Choose sections to restore first."];return;}weakSelf.pickerKind=1;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];}),
        HaloUINote(@"Choose a .halobackup file. Only the sections ticked above come back. A recovery backup is made first and the restore finishes the next time you open Halo.")])];
    NSURL *external=HaloExternalSaveFolder();
    [self.rows addArrangedSubview:HaloUICardView(@"3. Backup folder (optional)",@[
        HaloUINote(@"Pick a folder outside Halo, such as iCloud Drive, so your saves and profiles survive deleting the app. Back up here before deleting Halo; iCloud upload may take a moment."),
        HaloUIValueRow(@"Folder",external.lastPathComponent?:@"Not selected",nil),
        HaloUIButton(@"Choose external backup folder",0,^(UIButton *b){(void)b;weakSelf.pickerKind=5;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}),
        HaloUIButton(@"Back up saves and profiles to this folder",1,^(UIButton *b){(void)b;[weakSelf run:^NSURL *{return HaloExportExternalSaves();} completion:^(NSURL *url){(void)url;[weakSelf message:@"Save backup written to the selected folder. Confirm iCloud has uploaded it before deleting Halo. Previous backups are kept."];}];}),
        HaloUIButton(@"Restore from this folder…",0,^(UIButton *b){(void)b;weakSelf.mask=1;weakSelf.pickerKind=1;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];picker.directoryURL=external;picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}),
        HaloUINote(@"After reinstalling, choose the same folder again and restore. Updating over the same app keeps local saves.")])];
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
/* A tappable module header: the contents are listed only while it is open. Returns whether it is open. */
- (BOOL)addModule:(NSString *)title summary:(NSString *)summary {
    if(!self.openModules)self.openModules=[NSMutableSet set];
    BOOL open=[self.openModules containsObject:title];
    __weak typeof(self) weakSelf=self;
    [self.rows addArrangedSubview:HaloUIDisclosureHeader(title,summary,open,^{
        if(open)[weakSelf.openModules removeObject:title];else [weakSelf.openModules addObject:title];
        [weakSelf render];})];
    return open;
}
/* OpenCE's Mods (folders of tag files in Documents/Halo/mods): on or off, load order, remove, add. */
- (void)renderModPacks {
    __weak typeof(self) weakSelf=self;
    self.modsFingerprint=HaloModPackFingerprint();
    NSArray<NSDictionary *> *mods=HaloModPackList();
    NSMutableArray<NSString *> *order=[NSMutableArray array];NSMutableSet<NSString *> *off=[NSMutableSet set];
    for(NSDictionary *mod in mods){[order addObject:mod[@"folder"]];if(![mod[@"on"] boolValue])[off addObject:mod[@"folder"]];}
    void (^save)(NSArray<NSString *> *,NSSet<NSString *> *)=^(NSArray<NSString *> *newOrder,NSSet<NSString *> *newOff){
        @try{HaloModPackSave(newOrder,newOff);}@catch(NSException *e){[weakSelf message:e.reason];}
        [weakSelf render];};
    [self.rows addArrangedSubview:HaloUICardView(@"Add",@[
        HaloUIButton(@"Add a mod folder…",1,^(UIButton *b){(void)b;weakSelf.pickerKind=9;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];picker.allowsMultipleSelection=YES;picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}),
        HaloUINote(@"Textures, sounds, text and models that change how the game looks and sounds, on this iPhone only. Unzip the mod in the Files app first."),
        HaloUIButton(@"Import Custom Edition maps…",1,^(UIButton *b){(void)b;weakSelf.pickerKind=7;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];picker.allowsMultipleSelection=YES;picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}),
        HaloUINote(@"Extra multiplayer maps (.map files). Pick bitmaps.map, sounds.map and loc.map in the same selection if a map needs them.")])];
    [self.rows addArrangedSubview:HaloLibrarySection(@"Mod order",@"The mod at the top plays over the ones below it. This is the same list as the game's Mods menu.")];
    if(!mods.count){[self.rows addArrangedSubview:HaloUICardView(nil,@[HaloUINote(@"No mods yet. Tap “Add a mod folder…” above.")])];return;}
    NSInteger count=(NSInteger)mods.count;
    NSMutableArray<UIView *> *modRows=[NSMutableArray array];
    for(NSInteger shown=0;shown<count;shown++){
        NSInteger index=count-1-shown;   /* the game's menu shows the mod that loads last on top */
        NSDictionary *mod=mods[(NSUInteger)index];NSString *folder=mod[@"folder"];BOOL isOn=[mod[@"on"] boolValue];
        NSString *title=[mod[@"version"] length]?[NSString stringWithFormat:@"%@ %@",mod[@"name"],mod[@"version"]]:mod[@"name"];
        NSMutableString *details=[NSMutableString stringWithFormat:@"%@  ·  Priority %ld of %ld",isOn?@"On":@"Off",(long)(shown+1),(long)count];
        if([mod[@"authors"] length])[details appendFormat:@"  ·  By %@",mod[@"authors"]];
        if([mod[@"maps"] length])[details appendFormat:@"  ·  For: %@",mod[@"maps"]];
        if([mod[@"description"] length])[details appendFormat:@"\n%@",mod[@"description"]];
        if([mod[@"note"] length])[details appendFormat:@"\n⚠︎ %@",mod[@"note"]];
        UILabel *name=HaloUILabel(title,16,UIFontWeightSemibold,nil);name.numberOfLines=0;
        UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[name,HaloUINote(details)]];text.axis=UILayoutConstraintAxisVertical;text.spacing=2;
        [text setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        UISwitch *toggle=[UISwitch new];toggle.on=isOn;toggle.onTintColor=HaloUIAccent();toggle.accessibilityLabel=[title stringByAppendingString:@" on or off"];
        [toggle addAction:[UIAction actionWithHandler:^(UIAction *action){(void)action;
            NSMutableSet *next=[off mutableCopy];if(toggle.on)[next removeObject:folder];else [next addObject:folder];save(order,next);}] forControlEvents:UIControlEventValueChanged];
        UIButton *(^icon)(NSString *,NSString *,BOOL,void (^)(void))=^UIButton *(NSString *symbol,NSString *label,BOOL enabled,void (^act)(void)){
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
            [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];button.tintColor=HaloUIAccent();button.enabled=enabled;button.accessibilityLabel=label;
            [button.widthAnchor constraintEqualToConstant:34].active=YES;[button.heightAnchor constraintEqualToConstant:34].active=YES;
            [button addAction:[UIAction actionWithHandler:^(UIAction *action){(void)action;act();}] forControlEvents:UIControlEventTouchUpInside];
            return button;};
        UIButton *up=icon(@"chevron.up",@"Move up",shown>0,^{   /* (the top mod cannot go higher, the bottom one lower) */
            NSMutableArray *next=[order mutableCopy];[next exchangeObjectAtIndex:(NSUInteger)index withObjectAtIndex:(NSUInteger)index+1];save(next,off);});
        UIButton *down=icon(@"chevron.down",@"Move down",shown<count-1,^{
            NSMutableArray *next=[order mutableCopy];[next exchangeObjectAtIndex:(NSUInteger)index withObjectAtIndex:(NSUInteger)index-1];save(next,off);});
        UIButton *remove=icon(@"trash",@"Remove mod",YES,^{
            UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Remove this mod?" message:[NSString stringWithFormat:@"“%@” and its files will be deleted from this device.",folder] preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){(void)action;
                @try{HaloModPackRemove(folder);}@catch(NSException *e){[weakSelf message:e.reason];}
                [weakSelf render];}]];
            [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [weakSelf presentViewController:a animated:YES completion:nil];});
        remove.tintColor=UIColor.systemRedColor;
        UIStackView *line=[[UIStackView alloc] initWithArrangedSubviews:@[text,toggle,up,down,remove]];
        line.axis=UILayoutConstraintAxisHorizontal;line.spacing=6;line.alignment=UIStackViewAlignmentCenter;
        [modRows addObject:line];
    }
    [self.rows addArrangedSubview:HaloUICardView(nil,modRows)];
}
- (void)renderMaps {
    [self loadMapPictures];
    __weak typeof(self) weakSelf=self;
    [self renderModPacks];
    HsSettings opts=[HaloSettingsStore.shared snapshot];int mapMode=opts.maps_campaign_only?2:opts.maps_mp_only?1:0;BOOL sortAlpha=(mapMode==1);

    NSDictionary *resources=HaloCustomResourcesStatus();
    NSArray *custom=nil;@try{custom=HaloCustomMapsList();}@catch(NSException *exception){[self.rows addArrangedSubview:HaloUINote(exception.reason)];custom=@[];}
    NSString *resourceSummary=[NSString stringWithFormat:@"bitmaps.map %@  ·  sounds.map %@  ·  loc.map %@",
        [resources[@"bitmaps.map"] boolValue]?@"✓":@"—",[resources[@"sounds.map"] boolValue]?@"✓":@"—",[resources[@"loc.map"] boolValue]?@"✓":@"—"];
    NSInteger customChoice=opts.custom_hide?0:opts.custom_filter==1?2:opts.custom_filter==2?3:1;
    if([self addModule:@"Custom Edition maps" summary:[NSString stringWithFormat:@"%lu map%@  ·  %@",(unsigned long)custom.count,custom.count==1?@"":@"s",resourceSummary]]) {
    [self.rows addArrangedSubview:HaloUINote(@"Standard Custom Edition (version 609) maps. They never replace your Xbox maps. OpenSauce maps are not supported.")];
    [self.rows addArrangedSubview:HaloUICardView(nil,@[
        HaloUIValueRow(@"Shared files",resourceSummary,nil),
        HaloUINote(([resources[@"bitmaps.map"] boolValue]&&[resources[@"sounds.map"] boolValue]&&[resources[@"loc.map"] boolValue])?@"Maps that need shared files can load.":@"Most maps from halomaps.org need bitmaps.map, sounds.map and loc.map from a Halo Custom Edition (PC) install. Without them such a map only shows a blue screen. Add the three files with “Import Custom Edition maps…” above."),
        HaloUISegmentRow(@"Show in list",HaloLibraryShowChoices(),customChoice,^(NSInteger choice){[HaloSettingsStore.shared update:^(HsSettings *s2){s2->custom_hide=(choice==0);if(choice>0)s2->custom_filter=choice==2?1:choice==3?2:0;}];[weakSelf render];})])];
    NSArray *shownCustom=custom;
    if(opts.custom_hide)shownCustom=@[];
    else{
        NSMutableArray *kept=[NSMutableArray array];
        for(NSDictionary *map in custom)if(hm_custom_visible([map[@"type"] intValue],opts.custom_filter))[kept addObject:map];
        if(opts.custom_filter==1)[kept sortUsingComparator:^NSComparisonResult(NSDictionary *x,NSDictionary *y){return [x[@"file"] localizedCaseInsensitiveCompare:y[@"file"]];}];
        shownCustom=kept;
    }
    for(NSDictionary *map in shownCustom){
        NSString *file=map[@"file"];BOOL enabled=[map[@"enabled"] boolValue],valid=[map[@"valid"] boolValue];
        NSString *size=[NSByteCountFormatter stringFromByteCount:[map[@"size"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        NSMutableArray *items=[NSMutableArray arrayWithObject:HaloUINote([NSString stringWithFormat:@"%@ · %@\n%@%@%@",size,valid?@"Custom Edition v609 header verified":@"Invalid / unsupported CE header",[map[@"picture"] boolValue]?@"Picture ✓  ":@"",[map[@"description"] boolValue]?@"Description ✓  ":@"",enabled?@"Active in OpenCE custom_maps":@"Disabled (kept on device)"])];
        [items addObject:HaloUISwitchRow(@"Enabled",@"Off keeps the map on this iPhone but hides it from the game.",enabled,^(BOOL on){@try{HaloCustomMapSetEnabled(file,on);[weakSelf render];}@catch(NSException *e){[weakSelf message:e.reason];}})];
        [items addObject:HaloUIButton(@"Remove custom map",2,^(UIButton *b){(void)b;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Remove Custom Edition map?" message:[NSString stringWithFormat:@"%@ and its optional picture/description will be deleted from Halo. Shared resource maps are not touched.",file] preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){(void)x;[weakSelf run:^NSURL *{HaloCustomMapRemove(file);return nil;} completion:^(NSURL *u){(void)u;[weakSelf render];}];}]];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[weakSelf presentViewController:a animated:YES completion:nil];})];
        [self.rows addArrangedSubview:HaloUICardView(file,items)];
    }
    if(opts.custom_hide&&custom.count)[self.rows addArrangedSubview:HaloUINote([NSString stringWithFormat:@"%lu Custom Edition maps are hidden. Choose All, Multiplayer or Campaign above to list them.",(unsigned long)custom.count])];
    else if(custom.count&&!shownCustom.count)[self.rows addArrangedSubview:HaloUINote(@"No Custom Edition maps match this filter.")];
    if(!custom.count)[self.rows addArrangedSubview:HaloUICardView(nil,@[HaloUINote(@"No Custom Edition maps yet. Tap “Import Custom Edition maps…” above.")])];
    }

    NSInteger xboxChoice=!opts.maps_show_files?0:mapMode==1?2:mapMode==2?3:1;
    NSUInteger xboxCount=0;for(NSString *n in [NSFileManager.defaultManager contentsOfDirectoryAtPath:[HaloBackupRoot() stringByAppendingPathComponent:@"maps"] error:nil])if([n.pathExtension.lowercaseString isEqual:@"map"])xboxCount++;
    if([self addModule:@"Installed Xbox game files" summary:[NSString stringWithFormat:@"%lu file%@",(unsigned long)xboxCount,xboxCount==1?@"":@"s"]]) {
    [self.rows addArrangedSubview:HaloUINote(@"Your original Halo maps (Xbox version 5, with ui.map). Custom Edition maps never replace them.")];
    [self.rows addArrangedSubview:HaloUICardView(nil,@[
        HaloUIButton(@"Import Xbox maps",1,^(UIButton *b){(void)b;weakSelf.pickerKind=2;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];p.allowsMultipleSelection=YES;p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];}),
        HaloUISegmentRow(@"Show in list",HaloLibraryShowChoices(),xboxChoice,^(NSInteger choice){[HaloSettingsStore.shared update:^(HsSettings *s2){s2->maps_show_files=(choice!=0);if(choice>0){s2->maps_mp_only=(choice==2);s2->maps_campaign_only=(choice==3);}}];[weakSelf render];})])];
    NSString *folder=[HaloBackupRoot() stringByAppendingPathComponent:@"maps"];NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){int c=hm_compare(a.stringByDeletingPathExtension.lowercaseString.UTF8String,b.stringByDeletingPathExtension.lowercaseString.UTF8String,sortAlpha);return c<0?NSOrderedAscending:c>0?NSOrderedDescending:[a localizedCaseInsensitiveCompare:b];}];BOOL ui=NO;NSUInteger count=0,hidden=0;
    for(NSString *name in names) {
        if(![name.pathExtension.lowercaseString isEqual:@"map"])continue;NSURL *url=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]];if(!HaloBackupRegular(url))continue;count++;if([name.lowercaseString isEqual:@"ui.map"])ui=YES;
        {NSString *shownBase=name.stringByDeletingPathExtension.lowercaseString;if(!(opts.maps_show_files&&hm_visible_mode(shownBase.UTF8String,mapMode))){hidden++;continue;}}
        NSFileHandle *f=[NSFileHandle fileHandleForReadingFromURL:url error:nil];NSData *header=nil;@try {header=[f readDataOfLength:2048];}@catch(NSException *e){(void)e;}@finally {[f closeFile];}
        uint32_t magic=0,version=0,foot=0;BOOL valid=NO;if(header.length==2048){memcpy(&magic,header.bytes,4);memcpy(&version,(char *)header.bytes+4,4);memcpy(&foot,(char *)header.bytes+2044,4);valid=CFSwapInt32LittleToHost(magic)==0x68656164 && CFSwapInt32LittleToHost(foot)==0x666f6f74 && CFSwapInt32LittleToHost(version)==5;}
        NSString *base=name.stringByDeletingPathExtension.lowercaseString;BOOL campaign=[@[@"a10",@"a30",@"a50",@"b30",@"b40",@"c10",@"c20",@"c40",@"d20",@"d40"] containsObject:base];
        NSString *kind=[base isEqual:@"ui"]?@"Main menu":campaign?@"Campaign":@"Multiplayer / custom";
        NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];NSString *size=[NSByteCountFormatter stringFromByteCount:[attrs[NSFileSize] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        UIImageView *image=[UIImageView new];image.contentMode=UIViewContentModeScaleAspectFit;image.clipsToBounds=YES;image.backgroundColor=UIColor.clearColor;image.layer.cornerRadius=0;[image.heightAnchor constraintEqualToConstant:190].active=YES;
        NSString *thumb=[[HaloBackupRoot() stringByAppendingPathComponent:@"map_thumbnails"] stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"png"]];image.image=[UIImage imageWithContentsOfFile:thumb]?:self.mapPictures[base]?:[UIImage systemImageNamed:campaign?@"mountain.2.fill":@"map.fill"];image.tintColor=HaloUIAccent();
        [self.rows addArrangedSubview:HaloUICardView((hm_index(base.UTF8String)>=0||hm_is_ui(base.UTF8String))?[NSString stringWithUTF8String:hm_title(base.UTF8String)]:name,@[image,HaloUINote([NSString stringWithFormat:@"%@ · %@ · %@\n%@",name,kind,size,valid?@"Version 5 header verified":@"Invalid / unsupported header: reimport a compatible map"]),HaloUIButton(@"Choose map picture",0,^(UIButton *b){(void)b;weakSelf.thumbnailName=base;weakSelf.pickerKind=3;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];p.delegate=weakSelf;[weakSelf presentViewController:p animated:YES completion:nil];})])];
    }
    if(count&&!opts.maps_show_files)[self.rows addArrangedSubview:HaloUICardView(nil,@[HaloUINote([NSString stringWithFormat:@"%lu installed Xbox game files are hidden. Choose All, Multiplayer or Campaign above to list them, change map pictures or read their header checks.",(unsigned long)count])])];
    else if(opts.maps_show_files&&mapMode&&hidden)[self.rows addArrangedSubview:HaloUINote([NSString stringWithFormat:@"%lu maps are hidden by the %@ filter.",(unsigned long)hidden,mapMode==1?@"Multiplayer only":@"Campaign only"])];
    if(!count)[self.rows addArrangedSubview:HaloUINote(@"No Xbox maps installed. Import your compatible version 5 map files above.")];
    if(!ui)[self.rows addArrangedSubview:HaloUINote(@"ui.map is missing. Halo needs it to start.")];
    }
    NSArray *movies=HaloMoviesList();NSMutableDictionary *movieFiles=[NSMutableDictionary dictionary];for(NSDictionary *movie in movies)movieFiles[[movie[@"file"] lowercaseString]]=movie;
    NSMutableArray *movieStatus=[NSMutableArray array];
    for(NSArray *slot in @[@[@"Intro",@"intro.mp4"],@[@"Credits",@"credits.mp4"],@[@"Attract 1",@"attract1.mp4"],@[@"Attract 2",@"attract2.mp4"],@[@"Attract 3",@"attract3.mp4"]])
        [movieStatus addObject:[NSString stringWithFormat:@"%@ %@",slot[0],movieFiles[slot[1]]?@"✓":@"—"]];
    if([self addModule:@"Movies (MP4)" summary:[NSString stringWithFormat:@"Optional  ·  %lu installed",(unsigned long)movies.count]]) {
    [self.rows addArrangedSubview:HaloUINote(@"Optional. Your own MP4 files play in place of Halo's intro, credits and attract movies. Tap a movie to skip it.")];
    [self.rows addArrangedSubview:HaloUICardView(nil,@[
        HaloUIButton(@"Import MP4 movies",1,^(UIButton *b){(void)b;weakSelf.pickerKind=8;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeMPEG4Movie] asCopy:YES];picker.allowsMultipleSelection=YES;picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}),
        HaloUINote([movieStatus componentsJoinedByString:@"  ·  "])])];
    for(NSDictionary *movie in movies){NSString *file=movie[@"file"];NSString *size=[NSByteCountFormatter stringFromByteCount:[movie[@"size"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];[self.rows addArrangedSubview:HaloUICardView(file,@[HaloUINote([NSString stringWithFormat:@"%@ · %@",size,[movie[@"recognized"] boolValue]?@"recognized Halo movie slot":@"not requested by Halo"]),HaloUIButton(@"Remove movie",2,^(UIButton *b){(void)b;@try{HaloMovieRemove(file);[weakSelf render];}@catch(NSException *e){[weakSelf message:e.reason];}})])];}
    }
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
    } else if(kind==9) {
        [self run:^NSURL *{HaloModPackImport(urls);return urls.firstObject;} completion:^(NSURL *result){(void)result;[weakSelf render];[weakSelf message:@"Mod added. It is on; the game uses it the next time a map loads, or at once in a running game."];}];
    } else if(kind==7) {
        [self run:^NSURL *{HaloCustomContentImport(urls);return urls.firstObject;} completion:^(NSURL *result){(void)result;[weakSelf render];[weakSelf message:@"Custom Edition content installed. OpenCE will rescan custom_maps when its map list opens."];}];
    } else if(kind==8) {
        [self run:^NSURL *{HaloMoviesImport(urls);return urls.firstObject;} completion:^(NSURL *result){(void)result;[weakSelf render];[weakSelf message:@"MP4 movie fallback installed. Halo will use it when the matching BIK movie is requested."];}];
    } else if(kind==2&&!self.extrasChecked) {
        /* shared files (bitmaps/sounds/loc.map) and MP4 movies in the same pick install now; the Xbox maps go on to the staged import */
        __block NSArray<NSURL *> *rest=nil;__block NSString *summary=nil;__block NSMutableArray<NSString *> *problems=[NSMutableArray array];
        [self run:^NSURL *{rest=HaloImportSharedAndMovies(urls,&summary,problems);return nil;} completion:^(NSURL *u){(void)u;
            NSString *text=summary?:@"";
            if(problems.count)text=[text stringByAppendingFormat:@"%@%@",text.length?@"\n\n":@"",[problems componentsJoinedByString:@"\n"]];
            weakSelf.extrasSummary=text;
            if(rest.count){weakSelf.extrasChecked=YES;[weakSelf documentPicker:controller didPickDocumentsAtURLs:rest];weakSelf.extrasChecked=NO;}
            else {weakSelf.extrasSummary=nil;[weakSelf render];[weakSelf message:text.length?text:@"Choose .map files, shared files or MP4 movies."];}
        }];
    } else if(kind==2) {
        NSString *extrasText=self.extrasSummary;self.extrasSummary=nil;
        UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"Import maps on next launch?" message:[(extrasText.length?[extrasText stringByAppendingString:@"\n\n"]:@"") stringByAppendingString:@"Matching filenames will be replaced after a recovery backup. Existing maps remain usable until you close and reopen Halo."] preferredStyle:UIAlertControllerStyleAlert];
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
UIViewController *HaloModsPageController(void) { HaloLibraryController *c=[HaloLibraryController new];c.maps=YES;c.embedded=YES;return c; }
UIViewController *HaloMapsController(void) { HaloLibraryController *c=[HaloLibraryController new];c.maps=YES;return [[UINavigationController alloc] initWithRootViewController:c]; }
