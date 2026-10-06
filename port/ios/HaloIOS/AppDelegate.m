#import "AppDelegate.h"
#import "halo_boot_integration.h"
#import "halo_ios_gl_host.h"
#import "halo_guest_runner.h"
#import "halo_ios_controls.h"
#import "HaloSettingsViewController.h"
#import "HaloLogViewController.h"
#import "HaloSettingsStore.h"
#import "HaloLibrary.h"
#import "HaloMods.h"
#import "HaloDiscImport.h"
#import "HaloBackupArchive.h"
#include "halo_xiso.h"
#import "HaloUI.h"
#import "halo_ios_audio.h"
#import "halo_ios_platform.h"
#import "halo_crash_report.h"
#import "halo_launch_state.h"
#import <mach/mach.h>
#import <os/proc.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

extern NSString * const HaloIOSFirstFramePresentedNotification;

@interface HaloDiscJob : NSObject
@property(atomic) BOOL cancelled;
@property(nonatomic,copy) void (^progress)(NSString *,uint64_t,uint64_t);
@property(nonatomic) CFAbsoluteTime lastUpdate;
@end
@implementation HaloDiscJob
@end
static int DiscProgress(void *context,const char *name,uint64_t done,uint64_t total){
    HaloDiscJob *job=(__bridge HaloDiscJob *)context;
    CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
    if(now-job.lastUpdate>0.15 || (total&&done==total)){
        job.lastUpdate=now;if(job.progress)job.progress([NSString stringWithUTF8String:name],done,total);
    }
    return job.cancelled;
}

/* Keeps the screen edges for the game: no home-indicator swipe or status bar while playing. */
@interface HaloViewController : UIViewController
@end

@implementation HaloViewController
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (BOOL)prefersStatusBarHidden { return YES; }
@end

/* The second line of the performance overlay: the app's memory, estimated available memory, and how hot the phone is. */
static NSString *HaloPerfLine(void)
{
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    unsigned long long used = 0, left = (unsigned long long)os_proc_available_memory() >> 20;
    static NSString *const heat[] = { @"cool", @"warm", @"hot", @"critical" };
    NSInteger thermal = NSProcessInfo.processInfo.thermalState;

    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS)
        used = (unsigned long long)info.phys_footprint >> 20;
    if (thermal < 0 || thermal > 3) thermal = 0;
    return [NSString stringWithFormat:@"%llu MB · %llu free · %@", used, left, heat[thermal]];
}

@interface AppDelegate () <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIView *bootOverlay;
@property(nonatomic,strong) UILabel *launchHeading;
@property(nonatomic,strong) UILabel *launchDescription;
@property(nonatomic,strong) UIActivityIndicatorView *launchSpinner;
@property(nonatomic, strong) UIView *menuControls;
@property(nonatomic, strong) UILabel *loadingStatus;
@property(nonatomic, copy) NSString *loadingName;
@property(nonatomic, strong) NSDate *loadingStarted;
@property(nonatomic, strong) NSTimer *loadingTimer;
@property(nonatomic, strong) UITextView *bootLog;
@property(nonatomic, copy) NSString *bootText;
@property(nonatomic, strong) UISegmentedControl *logSource;
@property(nonatomic, strong) UIButton *importButton;
@property(nonatomic,strong) UIButton *discButton;
@property(nonatomic) BOOL choosingDisc;
@property(nonatomic, strong) UIButton *startButton;
@property(nonatomic, copy) void (^startBoot)(void);
@property(nonatomic) BOOL engineStarted;
@property(nonatomic) BOOL startupBlocked;
@property(nonatomic,strong) UIButton *startupHelpButton;
@property(nonatomic) BOOL importing;
@property(nonatomic) BOOL foldersReady;
@property(nonatomic) BOOL restoringBackup;
@property(nonatomic) BOOL engineProtectionRunning;
@property(nonatomic) BOOL engineProtectionChecked;
@property(nonatomic,strong) NSURL *deferredInvite;
@property(nonatomic) BOOL physicalPadConnected;
@property(nonatomic, strong) UIButton *settingsButton;
@property(nonatomic) CGPoint gearDragOffset;
@property(nonatomic) BOOL settingsHiddenByShortcut;
@property(nonatomic) BOOL draggingGear;
@property(nonatomic, strong) UILabel *fpsLabel;
@property(nonatomic, strong) NSTimer *fpsTimer;
@property(nonatomic) uint64_t fpsLastFrames;
@property(nonatomic) CFTimeInterval fpsLastTime;
@end

@implementation AppDelegate

- (void)loadingLine:(NSString *)line
{
    /* The "Loading: step" box used to appear here. Loading is fast now, so it stays hidden. */
    if ([line hasPrefix:@"[loading] begin: "]) {
        self.loadingName = [line substringFromIndex:17];
        self.loadingStarted = [NSDate date];
    } else if ([line hasPrefix:@"[loading] done: First game frame "] ||
               [line containsString:@"FULL GUEST STOPPED"] ||
               [line containsString:@"FULL GUEST BLOCKED"]) {
        self.loadingStatus.hidden = YES;
    } else if ([line hasPrefix:@"[loading] done: "]) {
        self.loadingName = @"Next initialization step";
        self.loadingStarted = [NSDate date];
    }
}

- (void)updateLoadingStatus
{
    if (!self.loadingStatus.hidden && self.loadingStarted) {
        self.loadingStatus.text = [NSString stringWithFormat:@"Loading: %@ · %.0f s",
            self.loadingName, -self.loadingStarted.timeIntervalSinceNow];
    }
}

- (NSString *)haloFolder {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Halo"];
}
- (NSString *)mapsFolder {
    return [[self haloFolder] stringByAppendingPathComponent:@"maps"];
}
- (BOOL)hasStartupMap {
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self mapsFolder] error:nil]) {
        if ([name caseInsensitiveCompare:@"ui.map"] == NSOrderedSame) {
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[self mapsFolder] stringByAppendingPathComponent:name] error:nil];
            if ([attributes[NSFileType] isEqual:NSFileTypeRegular] && [attributes[NSFileSize] unsignedLongLongValue] >= 2048) return YES;
        }
    }
    return NO;
}
- (void)refreshSetup {
    if (self.engineStarted || self.importing || self.engineProtectionRunning || !self.foldersReady) return;
    BOOL ready = [self hasStartupMap];
    HsSettings settings=[HaloSettingsStore.shared snapshot];
    if(ready && settings.presets[settings.active].startup_auto && !halo_ios_safe_level() && self.startBoot) {
        [self startHalo:nil];return;
    }
    self.startButton.enabled = ready;
    self.launchHeading.text=ready?@"Ready to play":@"Add your maps";
    self.launchDescription.text=ready?@"Your map library is ready. Start Halo when you’re ready to play.":@"Import your compatible .map files, including ui.map. You can also copy them in Files → On My iPhone → Halo CE → Halo → maps.";

}
- (void)startHalo:(UIButton *)sender {
    (void)sender;
    if (self.engineStarted || self.importing || self.engineProtectionRunning || !self.foldersReady || ![self hasStartupMap]) return;
    if(!self.engineProtectionChecked) {
        self.engineProtectionRunning=YES;self.startButton.enabled=NO;self.launchHeading.text=@"Protecting saves";self.launchDescription.text=@"Checking the engine identity before Halo opens your progress…";[self.launchSpinner startAnimating];
        __weak AppDelegate *weakSelf=self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            NSError *protectionError=nil;BOOL protected=HaloProtectEngineChange(&protectionError);
            dispatch_async(dispatch_get_main_queue(),^{
                AppDelegate *owner=weakSelf;if(!owner)return;owner.engineProtectionRunning=NO;
                if(!protected){[owner.launchSpinner stopAnimating];owner.startButton.enabled=YES;owner.launchHeading.text=@"Save protection required";owner.launchDescription.text=@"Halo did not start because the automatic .halobackup could not be created.";UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Could not protect your saves" message:protectionError.localizedDescription?:@"The engine changed and Halo could not create its safety backup." preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[[owner topPresenter] presentViewController:alert animated:YES completion:nil];return;}
                owner.engineProtectionChecked=YES;[owner startHalo:nil];
            });
        });
        return;
    }
    self.engineStarted = YES;
    self.launchHeading.text=@"Loading Halo CE";self.launchDescription.text=@"Preparing your game…";[self.launchSpinner startAnimating];
    halo_crash_phase("engine boot");
    /* The game is shown first. If it has drawn nothing after 25 seconds the screen is just black, so open the log
       (its Summary says how far the start got) instead of leaving a black screen with no explanation. */
    __weak AppDelegate *watchdogOwner = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AppDelegate *owner = watchdogOwner;
        if (!owner || owner.startupBlocked || halo_ios_presented_frames() > 0) return;
        if ([[owner topPresenter] isKindOfClass:HaloLogViewController.class]) return;
        halo_ios_toast("The game has not drawn anything yet - opening the log");
        [owner showLog:nil];
    });
    self.logSource.hidden = YES;
    self.importButton.hidden = YES;
    self.discButton.hidden = YES;
    self.startButton.hidden = YES;
    self.bootOverlay.hidden = NO;   /* clean launch card until the first presented frame */
    [self updateControlsVisibility];
    if (self.startBoot) self.startBoot();
    self.startBoot = nil;
}
- (void)startupHelp:(UIButton *)sender {
    (void)sender;
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
    NSString *startupMessage=@"This experimental build measures whether stock/free-signed iOS can reserve one exact 4 GiB guest span anywhere, even when no 4-GiB-aligned window exists. M2.6.80 still requires the aligned arena to actually run Halo; a successful Flexible 4 GiB line is evidence for the next flexible-base stage, not a successful game start.\n\nExecution: a compatible debugger/JIT method may still be needed on stock iOS.\n\nShare logs for the actual result. Never share Apple credentials or pairing files.";
#else
    NSString *startupMessage=@"Address space: the regular build uses Extended Virtual Addressing for its 4-GiB-aligned guest arena. Increased Memory Limit controls RAM allowance separately.\n\nExecution: a compatible debugger/JIT method may be needed on stock iOS. Support depends on the device and iOS version.\n\nShare logs for the actual failure. Never share Apple credentials or pairing files.";
#endif
    UIAlertController *help=[UIAlertController alertControllerWithTitle:@"Startup requirements" message:startupMessage preferredStyle:UIAlertControllerStyleAlert];
    [help addAction:[UIAlertAction actionWithTitle:@"SideStore JIT guide" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://docs.sidestore.io/docs/advanced/jit"] options:@{} completionHandler:nil];}]];
    [help addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    [[self topPresenter] presentViewController:help animated:YES completion:nil];
}
- (void)importMaps:(UIButton *)sender {
    (void)sender;
    if (self.engineStarted || self.importing) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self.window.rootViewController presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    if(self.choosingDisc){self.choosingDisc=NO;[self chooseDiscPolicy:urls.firstObject];return;}
    if (self.engineStarted || self.importing) return;
    self.importing = YES;
    self.importButton.enabled = NO;
    self.startButton.enabled = NO;
    self.launchHeading.text=@"Importing maps";self.launchDescription.text=@"Keep Halo open while files are copied. Existing maps are preserved.";[self.launchSpinner startAnimating];
    NSString *destination = [self mapsFolder];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSUInteger imported = 0, kept = 0;
        NSMutableArray<NSString *> *errors = [NSMutableArray array];
        for (NSURL *url in urls) {
            NSString *name = url.lastPathComponent;
            if ([name.pathExtension caseInsensitiveCompare:@"map"] != NSOrderedSame) {
                [errors addObject:[NSString stringWithFormat:@"%@: choose a .map file", name]];
                continue;
            }
            NSString *target = [destination stringByAppendingPathComponent:name];
            BOOL exists = NO;
            for (NSString *existing in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:destination error:nil]) {
                if ([existing caseInsensitiveCompare:name] == NSOrderedSame) { exists = YES; break; }
            }
            if (exists) { kept++; continue; }
            NSString *staging = [destination stringByAppendingPathComponent:
                [NSString stringWithFormat:@".import-%@", NSUUID.UUID.UUIDString]];
            BOOL scoped = [url startAccessingSecurityScopedResource];
            __block NSError *copyError = nil;
            NSError *coordinationError = nil;
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [coordinator coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *readURL) {
                [[NSFileManager defaultManager] copyItemAtURL:readURL toURL:[NSURL fileURLWithPath:staging] error:&copyError];
            }];
            if (scoped) [url stopAccessingSecurityScopedResource];
            NSError *error = coordinationError ?: copyError;
            if (!error) [[NSFileManager defaultManager] moveItemAtPath:staging toPath:target error:&error];
            if (error) [[NSFileManager defaultManager] removeItemAtPath:staging error:nil];
            if (error) [errors addObject:[NSString stringWithFormat:@"%@: %@", name, error.localizedDescription]];
            else imported++;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.importing = NO;[self.launchSpinner stopAnimating];
            self.importButton.enabled = YES;
            HsSettings settings=[HaloSettingsStore.shared snapshot];
            BOOL automatic=settings.presets[settings.active].startup_auto && !halo_ios_safe_level() && [self hasStartupMap];
            [self refreshSetup];
            if(automatic && !errors.count)return;
            NSString *message = [NSString stringWithFormat:@"Imported %lu maps. Kept %lu existing files.", (unsigned long)imported, (unsigned long)kept];
            if (errors.count) message = [message stringByAppendingFormat:@"\n\n%@", [errors componentsJoinedByString:@"\n"]];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Map import" message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
        });
    });
}
- (void)importDisc:(UIButton *)sender {
    (void)sender;if(self.engineStarted||self.importing)return;
    self.importing=YES;self.choosingDisc=YES;self.startButton.enabled=NO;self.importButton.enabled=NO;self.discButton.enabled=NO;self.settingsButton.enabled=NO;
    /* Open in place: do not duplicate a multi-GB ISO in the app's Inbox. The
     * coordinated security-scoped read lasts through the complete C job. */
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:NO];
    picker.delegate=self;picker.allowsMultipleSelection=NO;[self.window.rootViewController presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;if(!self.choosingDisc)return;self.choosingDisc=NO;[self finishDiscUI];
}
- (void)finishDiscUI {
    self.importing=NO;self.importButton.enabled=YES;self.discButton.enabled=YES;self.settingsButton.enabled=YES;[self.launchSpinner stopAnimating];
    if(!HaloDiscImportPending())[self refreshSetup];
    else {self.startButton.enabled=NO;self.launchHeading.text=@"Import recovery required";self.launchDescription.text=@"Close and reopen Halo to restore interrupted map changes.";}
}
- (void)chooseDiscPolicy:(NSURL *)url {
    if(!url){[self finishDiscUI];return;}
    NSString *ext=url.pathExtension.lowercaseString;
    if(![@[@"iso",@"xiso"] containsObject:ext]){
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Choose a disc image" message:@"Choose an Xbox Halo CE .iso or .xiso file. Use Import maps for .map files." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;[self finishDiscUI];}]];[self.window.rootViewController presentViewController:a animated:YES completion:nil];return;
    }
    BOOL existing=NO;for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:[self mapsFolder] error:nil])if([name.pathExtension.lowercaseString isEqual:@"map"])existing=YES;
    if(!existing){[self extractDisc:url replace:NO];return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Existing maps" message:@"Keep preserves matching maps and adds missing maps. Replace installs disc originals for matching maps. Enabled mods still apply on the next launch." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Keep" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;[self extractDisc:url replace:NO];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){(void)action;[self extractDisc:url replace:YES];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){(void)action;[self finishDiscUI];}]];
    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)extractDisc:(NSURL *)url replace:(BOOL)replace {
    HaloDiscJob *job=[HaloDiscJob new];self.launchHeading.text=@"Importing disc image";self.launchDescription.text=@"Validating Xbox Halo CE maps…";[self.launchSpinner startAnimating];
    UIAlertController *progress=[UIAlertController alertControllerWithTitle:@"Import disc image" message:@"Reading Xbox filesystem…" preferredStyle:UIAlertControllerStyleAlert];
    [progress addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){(void)action;job.cancelled=YES;}]];
    __weak AppDelegate *owner=self;
    job.progress=^(NSString *name,uint64_t done,uint64_t total){dispatch_async(dispatch_get_main_queue(),^{
        NSString *line=total?[NSString stringWithFormat:@"%@\n%.0f%% · %.1f / %.1f MB",name,100.0*done/total,done/1048576.0,total/1048576.0]:name;
        progress.message=line;owner.launchDescription.text=line;
    });};
    [self.window.rootViewController presentViewController:progress animated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            NSURL *stage=[HaloBackupWork() URLByAppendingPathComponent:[@"disc-stage-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
            NSFileManager *fm=NSFileManager.defaultManager;__block NSError *failure=nil;__block int result=0;NSUInteger installed=0,kept=0;
            BOOL scoped=[url startAccessingSecurityScopedResource];
            if(![fm createDirectoryAtURL:stage withIntermediateDirectories:YES attributes:nil error:&failure])result=0;
            else{
                NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];NSError *coordination=nil;
                [coordinator coordinateReadingItemAtURL:url options:0 error:&coordination byAccessor:^(NSURL *readURL){
                    char reason[512]={0};result=halo_xiso_extract(readURL.path.UTF8String,stage.path.UTF8String,DiscProgress,(__bridge void *)job,reason,sizeof(reason));
                    if(result==0)failure=HaloBackupFailure([NSString stringWithUTF8String:reason]);
                }];if(coordination){result=0;failure=coordination;}
            }
            if(scoped)[url stopAccessingSecurityScopedResource];
            if(result==1){
                job.progress(@"Installing validated maps…",0,0);
                if(!HaloDiscInstall(stage,replace,^BOOL{return job.cancelled;},&installed,&kept,&failure))result=job.cancelled?-1:0;
            }
            [fm removeItemAtURL:stage error:nil];
            job.progress=nil; /* break alert -> Cancel action -> job -> progress */
            dispatch_async(dispatch_get_main_queue(),^{
                void (^finish)(void)=^{
                    NSString *message=result==1?[NSString stringWithFormat:@"Imported %lu maps. Kept %lu existing maps.",(unsigned long)installed,(unsigned long)kept]:
                        (failure.localizedDescription?:@"Disc import cancelled. Existing maps were preserved.");
                    UIAlertController *a=[UIAlertController alertControllerWithTitle:result==1?@"Maps imported":result==-1?@"Import cancelled":@"Disc import stopped" message:message preferredStyle:UIAlertControllerStyleAlert];
                    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;[self finishDiscUI];}]];
                    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
                };
                if(progress.presentingViewController)[progress dismissViewControllerAnimated:YES completion:finish];else finish();
            });
        });
    }];
}
/* True when any log file exists, so Share logs and Copy logs can say so instead of sending an empty report. */
- (BOOL)hasLogFiles {
    for (NSString *name in @[@"start-history.txt", @"ios-boot.log", @"debug.txt", @"crash.txt", @"last-crash.txt", @"launch-phase.txt"]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:[[self haloFolder] stringByAppendingPathComponent:name]]) return YES;
    }
    return NO;
}

- (void)showLogAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    /* Present from whatever is on top. The log and settings screens cover the root view controller,
       and UIKit silently ignores a presentation from a controller that is not on top. */
    [[self topPresenter] presentViewController:alert animated:YES completion:nil];
}

/* Share logs sends ONE text file, the same report as Settings > Report a problem. Several raw files in one share sheet were hard to
   send from some phones. The files themselves are still in Files > Halo CE > Halo. */
- (void)shareLogs:(UIView *)sender {
    if (![self hasLogFiles]) { [self showLogAlert:@"No logs yet" message:@"Logs will be available after Halo starts."]; return; }
    UIViewController *presenter = [self topPresenter];
    NSDateFormatter *format = [NSDateFormatter new];
    format.dateFormat = @"yyyy-MM-dd HH.mm";
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Halo logs %@.txt", [format stringFromDate:NSDate.date]]]];
    NSError *error = nil;
    if (![HaloProblemReportText(NO) writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self showLogAlert:@"Could not prepare the logs" message:@"Try Copy logs instead."];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    UIView *anchor = sender ?: presenter.view;
    share.popoverPresentationController.sourceView = anchor;
    share.popoverPresentationController.sourceRect = sender ? sender.bounds : CGRectMake(CGRectGetMidX(anchor.bounds), 40, 1, 1);
    [presenter presentViewController:share animated:YES completion:nil];
}

/* Copy logs puts the same report, shortened to something that pastes into a message, on the clipboard. */
- (void)copyLogs:(UIView *)sender {
    (void)sender;
    if (![self hasLogFiles]) { [self showLogAlert:@"No logs yet" message:@"Logs will be available after Halo starts."]; return; }
    NSString *text = HaloProblemReportText(YES);
    UIPasteboard.generalPasteboard.string = text;
    [self showLogAlert:@"Logs copied" message:[NSString stringWithFormat:@"%lu KB of logs are on the clipboard. Paste them into your message to send them.", (unsigned long)((text.length + 1023) / 1024)]];
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    if(self.restoringBackup)return;
    [self refreshSetup];
    halo_ios_audio_resume();
    halo_ios_phase_foreground();
    halo_ios_post_focus_event(); /* lets the game look for an invite */
}

- (NSString *)gameLogTail {
    NSString *path = [[self haloFolder] stringByAppendingPathComponent:@"debug.txt"];
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!file) return @"No game log yet. Start Halo to create debug.txt.\n";
    NSError *error = nil;
    unsigned long long size = 0;
    const NSUInteger limit = 65536;
    NSData *data = nil;
    if ([file seekToEndReturningOffset:&size error:&error] &&
        [file seekToOffset:size > limit ? size - limit : 0 error:&error])
        data = [file readDataUpToLength:limit error:&error];
    [file closeAndReturnError:nil];
    if (!data) return [NSString stringWithFormat:@"Could not read game log: %@\n", error.localizedDescription ?: @"unknown error"];
    /* A bounded tail may start halfway through a UTF-8 line. */
    if (size > limit) {
        const unsigned char *bytes = data.bytes;
        NSUInteger start = 0;
        while (start < data.length && bytes[start] != '\n') ++start;
        if (start < data.length) data = [data subdataWithRange:NSMakeRange(start + 1, data.length - start - 1)];
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return text.length ? text : @"Game log is empty or could not be decoded.\n";
}
- (void)refreshLogView {
    BOOL gameLog = self.logSource.selectedSegmentIndex == 1;
    NSString *body = gameLog ? [self gameLogTail] : (self.bootText ?: @"Starting Halo…\n");
    self.bootLog.text = body;
    if (self.bootLog.text.length)
        [self.bootLog scrollRangeToVisible:NSMakeRange(self.bootLog.text.length - 1, 1)];
}
- (void)changeLogSource:(UISegmentedControl *)sender {
    (void)sender;
    if (self.engineStarted) [self refreshLogView];
}
- (void)menuPress:(UIButton *)sender { halo_ios_menu_button((int)sender.tag, 1); }
- (void)menuRelease:(UIButton *)sender { halo_ios_menu_button((int)sender.tag, 0); }
/* Settings owns the last hit-test layer, above every gameplay control. */
- (void)layoutSettingsButton {
    UIView *root=self.window.rootViewController.view;if(!self.settingsButton)return;
    CGRect safe=UIEdgeInsetsInsetRect(root.bounds,root.safeAreaInsets);
    HsSettings settings=[HaloSettingsStore.shared snapshot];
    self.settingsButton.alpha = settings.gear_opacity;
    NSArray *icons = @[@"gearshape.fill", @"slider.horizontal.3", @"gamecontroller.fill", @"circle.grid.2x2.fill"];
    UIImage *icon = settings.gear_icon < 4 ? [UIImage systemImageNamed:icons[settings.gear_icon]] :
        [UIImage imageWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Halo/settings-icon.png"]];
    if (settings.gear_icon==4) icon=[icon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.settingsButton setImage:icon ?: [UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    self.settingsButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    CGFloat x=settings.gear_placed?CGRectGetMinX(safe)+settings.gear_x*safe.size.width:CGRectGetMidX(safe);
    CGFloat y=settings.gear_placed?CGRectGetMinY(safe)+settings.gear_y*safe.size.height:CGRectGetMinY(safe)+26;
    CGFloat halfW=MAX(44,48*settings.gear_scale)/2,halfH=MAX(44,44*settings.gear_scale)/2;
    self.settingsButton.bounds=CGRectMake(0,0,halfW*2,halfH*2);
    [self.settingsButton setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20*settings.gear_scale weight:UIImageSymbolWeightSemibold] forImageInState:UIControlStateNormal];
    self.settingsButton.center=CGPointMake(MAX(CGRectGetMinX(safe)+halfW,MIN(CGRectGetMaxX(safe)-halfW,x)),MAX(CGRectGetMinY(safe)+halfH,MIN(CGRectGetMaxY(safe)-halfH,y)));
    [root bringSubviewToFront:self.settingsButton];
}
- (void)recoverSettings:(UITapGestureRecognizer *)gesture {
    (void)gesture;
    self.settingsHiddenByShortcut = NO;
    self.settingsButton.hidden = NO;
    [self layoutSettingsButton];
}
- (void)dragSettings:(UILongPressGestureRecognizer *)gesture {
    UIView *root=self.settingsButton.superview;CGPoint point=[gesture locationInView:root];
    if(gesture.state==UIGestureRecognizerStateBegan){self.draggingGear=YES;self.gearDragOffset=CGPointMake(self.settingsButton.center.x-point.x,self.settingsButton.center.y-point.y);[(HaloControlsView *)self.menuControls releaseAll];}
    if(gesture.state==UIGestureRecognizerStateChanged || gesture.state==UIGestureRecognizerStateBegan){
        CGRect safe=UIEdgeInsetsInsetRect(root.bounds,root.safeAreaInsets);CGFloat halfW=self.settingsButton.bounds.size.width/2,halfH=self.settingsButton.bounds.size.height/2;
        self.settingsButton.center=CGPointMake(MAX(CGRectGetMinX(safe)+halfW,MIN(CGRectGetMaxX(safe)-halfW,point.x+self.gearDragOffset.x)),MAX(CGRectGetMinY(safe)+halfH,MIN(CGRectGetMaxY(safe)-halfH,point.y+self.gearDragOffset.y)));
    }
    if(gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled){
        CGRect safe=UIEdgeInsetsInsetRect(root.bounds,root.safeAreaInsets);CGPoint center=self.settingsButton.center;
        if(safe.size.width>0 && safe.size.height>0)[HaloSettingsStore.shared update:^(HsSettings *s){s->gear_placed=1;s->gear_x=(center.x-safe.origin.x)/safe.size.width;s->gear_y=(center.y-safe.origin.y)/safe.size.height;}];
        self.draggingGear=NO;
    }
}
- (void)updateControlsVisibility {
    if(!self.draggingGear)[self layoutSettingsButton];
    /* On-screen controls only while the game is showing and no physical controller is connected. */
    BOOL editing = [(HaloControlsView *)self.menuControls editing];
    int mode = [[HaloSettingsStore shared] snapshot].controls_mode;   /* 0 auto, 1 always, 2 hidden */
    BOOL wanted = mode == 1 || (mode == 0 && (!self.physicalPadConnected || halo_ios_coop_touch_primary()));
    BOOL show = self.bootOverlay.hidden && (wanted || editing);
    self.menuControls.hidden = !show;
    if (!show) [(HaloControlsView *)self.menuControls releaseAll];
}
- (void)applicationWillResignActive:(UIApplication *)application {
    (void)application;
    halo_ios_menu_reset();
    [(HaloControlsView *)self.menuControls releaseAll];
}
- (UIViewController *)topPresenter {
    UIViewController *top = self.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}
- (void)showLog:(UIButton *)sender {
    (void)sender;
    UIViewController *top = [self topPresenter];
    if ([top isKindOfClass:HaloLogViewController.class]) return;
    HaloLogViewController *log = [[HaloLogViewController alloc] init];
    __weak AppDelegate *weakSelf = self;
    log.bootLogProvider = ^NSString *{ return weakSelf.bootText ?: @""; };
    log.gameLogProvider = ^NSString *{ return [weakSelf gameLogTail]; };
    log.onShare = ^(UIView *source) { [weakSelf shareLogs:source]; };
    log.onCopy = ^(UIView *source) { [weakSelf copyLogs:source]; };
    log.modalPresentationStyle = UIModalPresentationFullScreen;
    [(HaloControlsView *)self.menuControls releaseAll];
    [top presentViewController:log animated:YES completion:nil];
}
- (void)showSettings:(UIButton *)sender {
    (void)sender;
    UIViewController *top = [self topPresenter];
    if ([top isKindOfClass:HaloSettingsViewController.class]) return;
    HaloSettingsViewController *settings = [[HaloSettingsViewController alloc] init];
    __weak AppDelegate *weakSelf = self;
    settings.onEditLayout = ^{
        AppDelegate *owner = weakSelf;
        if (!owner) return;
        HaloControlsView *controls = (HaloControlsView *)owner.menuControls;
        owner.settingsButton.hidden = YES;
        controls.onEditFinished = ^{
            owner.settingsButton.hidden = owner.settingsHiddenByShortcut;
            [owner updateControlsVisibility];
        };
        owner.menuControls.hidden = NO;
        [controls beginEditing];
    };
    settings.onShowLog = ^{ [weakSelf showLog:nil]; };
    settings.onShareLogs = ^(UIView *source) { [weakSelf shareLogs:source]; };
    settings.onCopyLogs = ^(UIView *source) { [weakSelf copyLogs:source]; };
    settings.modalPresentationStyle = UIModalPresentationFullScreen;
    [(HaloControlsView *)self.menuControls releaseAll];
    [top presentViewController:settings animated:YES completion:nil];
}
/* The touch-layout editor can move the overlay directly. Save only HUD[0],
 * leaving the engine HUD and the control scheme's button placements intact. */
- (void)movePerformanceOverlay:(UIPanGestureRecognizer *)gesture {
    if(!((HaloControlsView *)self.menuControls).editing)return;
    if(gesture.state!=UIGestureRecognizerStateChanged&&gesture.state!=UIGestureRecognizerStateEnded)return;
    UIView *parent=self.fpsLabel.superview;CGRect safe=UIEdgeInsetsInsetRect(parent.bounds,parent.safeAreaInsets);
    if(safe.size.width<=0||safe.size.height<=0)return;
    CGPoint delta=[gesture translationInView:parent];CGPoint center=self.fpsLabel.center;
    center.x+=delta.x;center.y+=delta.y;[gesture setTranslation:CGPointZero inView:parent];
    float x=(float)((center.x-CGRectGetMinX(safe))/safe.size.width-.5);
    float y=(float)((center.y-CGRectGetMinY(safe))/safe.size.height-.14);
    [[HaloSettingsStore shared] update:^(HsSettings *next){next->hud[0].x=x;next->hud[0].y=y;}];
    self.fpsLabel.center=center;
}
- (void)updateFPS {
    if(!self.draggingGear)[self layoutSettingsButton];
    if(self.engineStarted && !self.bootOverlay.hidden && halo_ios_presented_frames()>0){self.bootOverlay.hidden=YES;[self.launchSpinner stopAnimating];[self updateControlsVisibility];}
    HsSettings settings = [[HaloSettingsStore shared] snapshot];
    HsHud h=settings.hud[0];
    BOOL editing=((HaloControlsView *)self.menuControls).editing;
    self.fpsLabel.userInteractionEnabled=editing;
    self.fpsLabel.hidden = (!editing && (!(settings.show_fps || settings.perf_overlay) || h.hidden)) || !self.bootOverlay.hidden;
    self.fpsLabel.alpha=editing?MAX(.3f,h.opacity):h.opacity;
    self.fpsLabel.font=[UIFont monospacedDigitSystemFontOfSize:13*h.scale weight:UIFontWeightBold];
    if (self.fpsLabel.hidden) { self.fpsLastTime = 0; return; }
    uint64_t frames = halo_ios_presented_frames();
    CFTimeInterval now = CACurrentMediaTime();
    if (self.fpsLastTime > 0 && now > self.fpsLastTime)
    {
        double fps = (double)(frames - self.fpsLastFrames) / (now - self.fpsLastTime);
        self.fpsLabel.numberOfLines = settings.perf_overlay ? 2 : 1;
        self.fpsLabel.textAlignment = NSTextAlignmentCenter;
        self.fpsLabel.text = settings.perf_overlay && fps > 0.5
            ? [NSString stringWithFormat:@" %.0f FPS · %.1f ms \n %@ ", fps, 1000.0 / fps, HaloPerfLine()]
            : [NSString stringWithFormat:@" %.0f FPS ", fps];
    }
    [self.fpsLabel sizeToFit];
    CGRect safe=UIEdgeInsetsInsetRect(self.fpsLabel.superview.bounds,self.fpsLabel.superview.safeAreaInsets);
    CGPoint center=CGPointMake(CGRectGetMinX(safe)+safe.size.width*(.5+h.x),CGRectGetMinY(safe)+safe.size.height*(.14+h.y));
    center.x=MAX(CGRectGetMinX(safe)+self.fpsLabel.bounds.size.width/2,MIN(CGRectGetMaxX(safe)-self.fpsLabel.bounds.size.width/2,center.x));
    center.y=MAX(CGRectGetMinY(safe)+self.fpsLabel.bounds.size.height/2,MIN(CGRectGetMaxY(safe)-self.fpsLabel.bounds.size.height/2,center.y));
    self.fpsLabel.center=center;
    self.fpsLastFrames = frames;
    self.fpsLastTime = now;
}
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    (void)app; (void)options;
    if ([url.scheme caseInsensitiveCompare:@"halo"] != NSOrderedSame) return NO;
    if(self.restoringBackup){self.deferredInvite=url;return YES;}
    HaloSetPendingInvite(url.absoluteString);
    halo_ios_toast("Joining the invite…");
    return YES;
}

/* Reads what the last start left behind, installs the crash reporter, and picks the start mode. */
- (void)prepareLaunchState {
    NSString *folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Halo"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    char phase[200] = "", crash[700] = "", note[300] = "";
    BOOL hadCrash = halo_crash_read_previous(folder.fileSystemRepresentation, phase, sizeof(phase), crash, sizeof(crash)) != 0;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    int level = halo_launch_next_level(phase, hadCrash, (int)[defaults integerForKey:@"HaloSafeLevel"]);
    [defaults setInteger:level forKey:@"HaloSafeLevel"];
    halo_launch_describe(phase, hadCrash, note, sizeof(note));
    {   /* This launch overwrites the phase file, so note now where the last run ended; a relaunch must not erase it. */
        NSDateFormatter *stamp = [NSDateFormatter new];
        stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        stamp.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        char line[400];
        if (halo_launch_history_line([stamp stringFromDate:NSDate.date].UTF8String, phase, hadCrash, line, sizeof(line))) {
            NSString *path = [folder stringByAppendingPathComponent:@"start-history.txt"];
            NSString *earlier = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
            char merged[4096];
            halo_launch_history_append(earlier.UTF8String, line, 20, merged, sizeof(merged));
            [[NSString stringWithUTF8String:merged] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
    if (hadCrash) {
        /* keep the report where Share logs can find it (crash.txt is cleared by a good run) */
        NSString *kept = [NSString stringWithFormat:@"last step: %s\n%s", phase, crash];
        [kept writeToFile:[folder stringByAppendingPathComponent:@"last-crash.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:HaloSettingsChangedNotification object:nil queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *note) { (void)note; [self updateControlsVisibility]; }];
    halo_ios_set_safe_level(level);
    halo_ios_set_launch_notes(note, hadCrash ? crash : "");
    halo_crash_install(folder.fileSystemRepresentation);   /* before the PAGEZERO bridge exists */
    halo_crash_phase("app launched");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    halo_crash_phase(HALO_PHASE_BACKGROUND);
}

/* Force quit while suspended may skip this callback. Next-launch owned-code
   cleanup remains authoritative; iOS terminates all guest/host threads itself. */
- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    halo_ios_menu_reset();
    halo_ios_set_hosted_invite(NULL);
    halo_crash_phase(HALO_PHASE_EXITED);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSString *pending=[[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject.path stringByAppendingPathComponent:@"HaloBackups"] stringByAppendingPathComponent:@"pending.plist"];
    if(![NSFileManager.defaultManager fileExistsAtPath:pending] && !HaloModsPending() && !HaloDiscImportPending())return [self finishLaunch:application options:launchOptions];
    self.restoringBackup=YES;
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];UIViewController *screen=[UIViewController new];screen.view.backgroundColor=UIColor.blackColor;self.window.rootViewController=screen;
    UILabel *message=[UILabel new];message.text=@"Preparing Halo…\nApplying library changes. Keep the app open.";message.textColor=UIColor.whiteColor;message.textAlignment=NSTextAlignmentCenter;message.numberOfLines=0;message.translatesAutoresizingMaskIntoConstraints=NO;[screen.view addSubview:message];[NSLayoutConstraint activateConstraints:@[[message.centerXAnchor constraintEqualToAnchor:screen.view.centerXAnchor],[message.centerYAnchor constraintEqualToAnchor:screen.view.centerYAnchor],[message.widthAnchor constraintLessThanOrEqualToAnchor:screen.view.widthAnchor constant:-40]]];[self.window makeKeyAndVisible];
    /* Large map hashing/copies must not block application launch or the UI thread. */
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;BOOL restored=HaloDiscImportRecover(&error);if(restored)restored=HaloApplyPendingRestore(&error);if(restored)restored=HaloModsApply(&error);
        dispatch_async(dispatch_get_main_queue(),^{
            if(restored){self.restoringBackup=NO;[self finishLaunch:application options:launchOptions];if(self.deferredInvite){HaloSetPendingInvite(self.deferredInvite.absoluteString);self.deferredInvite=nil;}return;}
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Restore stopped" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"Close Halo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;halo_ios_quit_app();}]];if(HaloModsPending())[alert addAction:[UIAlertAction actionWithTitle:@"Manage Mods" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;UIViewController *manager=HaloMapsController();manager.modalPresentationStyle=UIModalPresentationFullScreen;[screen presentViewController:manager animated:YES completion:nil];}]];[screen presentViewController:alert animated:YES completion:nil];
        });
    });return YES;
}
- (BOOL)finishLaunch:(UIApplication *)application options:(NSDictionary *)launchOptions {
    halo_ios_set_hosted_invite(NULL); /* discard any invite left by a terminated run */
    [self prepareLaunchState];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    UIViewController *vc = [HaloViewController new];
    vc.view.backgroundColor = UIColor.blackColor;

    UIView *gameView = halo_ios_gl_create_view();
    gameView.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:gameView];

    UIView *bootOverlay = [UIView new];
    bootOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    bootOverlay.backgroundColor = HaloUIBackground();

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Halo CE";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];

    UITextView *log = [[UITextView alloc] initWithFrame:CGRectZero];
    log.translatesAutoresizingMaskIntoConstraints = NO;
    log.backgroundColor = HaloUIBackground();
    log.hidden=YES;
    log.textColor = UIColor.greenColor;
    log.editable = NO;
    log.alwaysBounceVertical = YES;
    log.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];

    UILabel *notice = [UILabel new];
    notice.translatesAutoresizingMaskIntoConstraints = NO;
    notice.text = [NSString stringWithFormat:@"UNIVERSAL · iOS %@",[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@""];
    notice.numberOfLines = 2;
    notice.font = [UIFont systemFontOfSize:11];
    notice.textColor = HaloUISecondaryText();
    [bootOverlay addSubview:notice];
    [bootOverlay addSubview:title];
    [bootOverlay addSubview:log];
    [vc.view addSubview:bootOverlay];
    self.bootOverlay = bootOverlay;
    UIView *card=[UIView new];card.translatesAutoresizingMaskIntoConstraints=NO;card.backgroundColor=HaloUICard();card.layer.cornerRadius=20;[bootOverlay addSubview:card];
    UILabel *heading=HaloUILabel(@"Welcome to Halo CE",24,UIFontWeightSemibold,nil);
    UILabel *description=HaloUILabel(@"Prepare your map library to get started.",15,UIFontWeightRegular,HaloUISecondaryText());description.numberOfLines=0;
    UILabel *pathHint=HaloUILabel(@"Your maps and saves stay in Documents/Halo. Settings and logs are always available.",12,UIFontWeightRegular,HaloUISecondaryText());pathHint.numberOfLines=0;
    UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];spinner.hidesWhenStopped=YES;
    UIStackView *content=[[UIStackView alloc] initWithArrangedSubviews:@[heading,description,spinner,pathHint]];content.axis=UILayoutConstraintAxisVertical;content.spacing=14;content.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[[card.centerYAnchor constraintEqualToAnchor:bootOverlay.centerYAnchor],[card.leadingAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.leadingAnchor constant:32],[card.trailingAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.trailingAnchor constant:-32],[content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24],[content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24],[content.topAnchor constraintEqualToAnchor:card.topAnchor constant:22],[content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-22]]];
    self.launchHeading=heading;self.launchDescription=description;self.launchSpinner=spinner;


    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    gear.translatesAutoresizingMaskIntoConstraints = YES;
    gear.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.9];
    gear.layer.cornerRadius = 8;
    [gear setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    gear.tintColor=UIColor.whiteColor;
    gear.accessibilityHint=@"Tap to open settings. Touch and hold to move.";
    UILongPressGestureRecognizer *move=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dragSettings:)];move.minimumPressDuration=.35;move.allowableMovement=20;move.cancelsTouchesInView=YES;[gear addGestureRecognizer:move];
    gear.titleLabel.font = [UIFont systemFontOfSize:20];
    [gear setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    gear.accessibilityLabel = @"Settings";
    [gear addTarget:self action:@selector(showSettings:) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:gear];
    self.settingsButton = gear;
    __weak AppDelegate *shortcutOwner = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:@"HaloSettingsVisibilityShortcut" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        (void)note;
        AppDelegate *owner = shortcutOwner;
        owner.settingsHiddenByShortcut = !owner.settingsHiddenByShortcut;
        owner.settingsButton.hidden = owner.settingsHiddenByShortcut;
    }];
    UITapGestureRecognizer *recover = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(recoverSettings:)];
    recover.numberOfTouchesRequired = 3;
    recover.numberOfTapsRequired = 2;
    recover.cancelsTouchesInView = NO;
    vc.view.multipleTouchEnabled = YES;
    [vc.view addGestureRecognizer:recover];
    self.bootLog = log;
    HaloControlsView *menu = [[HaloControlsView alloc] initWithFrame:CGRectZero];
    menu.translatesAutoresizingMaskIntoConstraints = NO;
    menu.hidden = YES;
    [vc.view addSubview:menu];
    self.menuControls = menu;
    [NSLayoutConstraint activateConstraints:@[
        [menu.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [menu.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [menu.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
        [menu.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor]
    ]];
    UILabel *loading = [UILabel new];
    loading.translatesAutoresizingMaskIntoConstraints = NO;
    loading.textColor = UIColor.whiteColor;
    loading.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.9];
    loading.textAlignment = NSTextAlignmentCenter;
    loading.numberOfLines = 2;
    loading.font = [UIFont systemFontOfSize:15];
    loading.hidden = YES;
    self.loadingStatus = loading;  /* kept hidden: loading takes a moment, not a progress box */

    UILabel *fps = [UILabel new];
    [fps addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(movePerformanceOverlay:)]];
    fps.translatesAutoresizingMaskIntoConstraints = YES;
    fps.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    fps.textColor = UIColor.greenColor;
    fps.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    fps.layer.cornerRadius = 5;
    fps.clipsToBounds = YES;
    fps.hidden = YES;
    [vc.view addSubview:fps];
    self.fpsLabel = fps;
    __weak AppDelegate *fpsOwner = self;
    self.fpsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { [fpsOwner updateFPS]; }];
    UIButton *import = [UIButton buttonWithType:UIButtonTypeSystem];
    [import setTitle:@"Import maps" forState:UIControlStateNormal];
    [import addTarget:self action:@selector(importMaps:) forControlEvents:UIControlEventTouchUpInside];
    self.importButton = import;
    UIButton *disc=[UIButton buttonWithType:UIButtonTypeSystem];[disc setTitle:@"Import disc image" forState:UIControlStateNormal];[disc addTarget:self action:@selector(importDisc:) forControlEvents:UIControlEventTouchUpInside];self.discButton=disc;
    UIButton *start = [UIButton buttonWithType:UIButtonTypeSystem];
    [start setTitle:@"Play Halo CE" forState:UIControlStateNormal];
    [start addTarget:self action:@selector(startHalo:) forControlEvents:UIControlEventTouchUpInside];
    self.startButton = start;
    UIButton *share = [UIButton buttonWithType:UIButtonTypeSystem];
    [share setTitle:@"Share logs" forState:UIControlStateNormal];
    [share addTarget:self action:@selector(shareLogs:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyButton setTitle:@"Copy logs" forState:UIControlStateNormal];
    [copyButton addTarget:self action:@selector(copyLogs:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *help=[UIButton buttonWithType:UIButtonTypeSystem];[help setTitle:@"Startup help" forState:UIControlStateNormal];
    [help addTarget:self action:@selector(startupHelp:) forControlEvents:UIControlEventTouchUpInside];help.hidden=YES;self.startupHelpButton=help;
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[import, disc, start, share, copyButton, help]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 24;
    actions.distribution=UIStackViewDistributionFillEqually;actions.spacing=12;
    for(UIButton *button in @[import,disc,start,share,copyButton,help]){button.backgroundColor=button==start?HaloUIAccent():HaloUICard();button.layer.cornerRadius=12;[button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];button.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];button.titleLabel.adjustsFontSizeToFitWidth=YES;button.titleLabel.minimumScaleFactor=0.75;}
    [bootOverlay addSubview:actions];
    UISegmentedControl *source = [[UISegmentedControl alloc] initWithItems:@[@"Boot log", @"Game log"]];
    source.translatesAutoresizingMaskIntoConstraints = NO;
    source.selectedSegmentIndex = 0;
    source.hidden = YES;
    [source addTarget:self action:@selector(changeLogSource:) forControlEvents:UIControlEventValueChanged];
    [bootOverlay addSubview:source];
    self.logSource = source;


    [NSLayoutConstraint activateConstraints:@[
        [gameView.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [gameView.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [gameView.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
        [gameView.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor],

        [bootOverlay.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [bootOverlay.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [bootOverlay.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
        [bootOverlay.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor],

        [title.leadingAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.leadingAnchor constant:14],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:bootOverlay.safeAreaLayoutGuide.trailingAnchor constant:-80],
        [title.topAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.topAnchor constant:8],
        [log.leadingAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.leadingAnchor constant:12],
        [log.trailingAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [notice.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5],
        [notice.leadingAnchor constraintEqualToAnchor:log.leadingAnchor],
        [notice.trailingAnchor constraintEqualToAnchor:log.trailingAnchor],
        [log.topAnchor constraintEqualToAnchor:notice.bottomAnchor constant:5],
        [log.bottomAnchor constraintEqualToAnchor:source.topAnchor constant:-8],
        [source.centerXAnchor constraintEqualToAnchor:bootOverlay.centerXAnchor],
        [source.widthAnchor constraintEqualToConstant:240],
        [source.heightAnchor constraintEqualToConstant:32],
        [source.bottomAnchor constraintEqualToAnchor:actions.topAnchor constant:-8],
        [actions.leadingAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.leadingAnchor constant:32],
        [actions.trailingAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.trailingAnchor constant:-32],
        [actions.bottomAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [actions.heightAnchor constraintEqualToConstant:44]
    ]];

    HsSettings launchSettings=[HaloSettingsStore.shared snapshot];
    if(launchSettings.presets[launchSettings.active].startup_auto && !halo_ios_safe_level() && [self hasStartupMap]) {
        self.launchHeading.text=@"Loading Halo CE";
        self.launchDescription.text=@"Preparing the main menu…";
        import.hidden=YES;start.hidden=YES;[self.launchSpinner startAnimating];
    }
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    /* Controller-only play sends no touches, so the screen must not dim. */
    application.idleTimerDisabled = YES;
    __weak AppDelegate *padOwner = self;
    halo_ios_controllers_start(^(BOOL connected) {
        AppDelegate *owner = padOwner;
        if (!owner) return;
        owner.physicalPadConnected = connected;
        [owner updateControlsVisibility];
    });

    __block id firstFrameObserver = nil;
    firstFrameObserver =
        [[NSNotificationCenter defaultCenter]
            addObserverForName:HaloIOSFirstFramePresentedNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) {
        (void)note;

        if (firstFrameObserver) {
            [[NSNotificationCenter defaultCenter] removeObserver:firstFrameObserver];
            firstFrameObserver = nil;
        }
    }];

    NSError *folderError = nil;
    self.foldersReady = [[NSFileManager defaultManager] createDirectoryAtPath:[self mapsFolder]
        withIntermediateDirectories:YES attributes:nil error:&folderError];
    __weak AppDelegate *weakSelf = self;
    self.startBoot = ^{
    NSMutableString *text = [NSMutableString string];
    NSString *folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Halo"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder
                            withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *logPath = [folder stringByAppendingPathComponent:@"ios-boot.log"];
    BOOL logCreated = [[NSFileManager defaultManager] createFileAtPath:logPath
                                                       contents:[NSData data] attributes:nil];
    NSFileHandle *logFile = logCreated ? [NSFileHandle fileHandleForWritingAtPath:logPath] : nil;
    dispatch_queue_t logQueue = dispatch_queue_create("HaloIOS.boot-log", DISPATCH_QUEUE_SERIAL);
    log.text = @"Starting Halo. Boot diagnostics remain visible until you select Show game.\n";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        halo_ios_start_game_boot(^(const char *s) {
            NSString *line = [NSString stringWithUTF8String:s ?: ""] ?: @"<invalid UTF-8>";
            NSLog(@"[HaloIOS-Boot] %@", line);

            dispatch_async(logQueue, ^{
                NSData *bytes = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
                if (logFile) {
                    NSError *error = nil;
                    if (![logFile writeData:bytes error:&error])
                        NSLog(@"[HaloIOS-Boot] Could not save boot log: %@", error);
                }
            });
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([line hasPrefix:@"STARTUP BLOCKED:"] && halo_ios_presented_frames()==0) {
                    AppDelegate *owner=weakSelf;
                    if (!owner.startupBlocked) {
                        owner.startupBlocked=YES;
                        owner.startupHelpButton.hidden=NO;
                        [owner.launchSpinner stopAnimating];
                        owner.launchHeading.text=@"Halo could not start";
                        if ([line hasSuffix:@"ADDRESS SPACE"])
                            owner.launchDescription.text=@"iOS could not reserve the engine’s address space. Verify that your signing profile authorizes Extended Virtual Addressing. Lowering graphics settings or replacing maps will not fix this startup failure. Share logs for the exact allocation error.";
                        else if ([line hasSuffix:@"EXECUTABLE MEMORY"])
                            owner.launchDescription.text=@"iOS rejected executable memory for the engine. Your installation may need a compatible debugger/JIT method. Memory entitlements alone do not enable execution. Share logs before changing your setup.";
                        else owner.launchDescription.text=@"The engine could not complete startup. Open Settings → Logs or use Share logs to review the failure.";
                    }
                }
                if ([line hasPrefix:@"FULL GUEST STOPPED:"] ||
                    [line hasPrefix:@"FULL GUEST BLOCKED:"]) {
                    halo_ios_menu_reset();
                    [weakSelf showLog:nil];
                }
                [text appendFormat:@"%@\n", line];
                if (text.length > 300000)
                    [text deleteCharactersInRange:NSMakeRange(0, text.length - 240000)];
                AppDelegate *owner = weakSelf;
                [owner loadingLine:line];
                owner.bootText = [text copy];
                if (!bootOverlay.hidden && owner.engineStarted) [owner refreshLogView];
            });
        });
    });

    };
    if (!self.foldersReady) {
        self.launchHeading.text=@"Could not prepare your library";
        self.launchDescription.text=folderError.localizedDescription;
        import.enabled = NO;
        start.enabled = NO;
    } else if ([self hasStartupMap]) {
        HsSettings settings=[HaloSettingsStore.shared snapshot];
        if(settings.presets[settings.active].startup_auto && !halo_ios_safe_level())[self startHalo:nil];
        else [self refreshSetup];
    } else {
        halo_crash_phase("waiting for maps");
        [self refreshSetup];
    }
    [vc.view layoutIfNeeded];[self layoutSettingsButton];
    return YES;
}
@end
