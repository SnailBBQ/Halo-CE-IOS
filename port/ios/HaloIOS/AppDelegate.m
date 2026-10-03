#import "AppDelegate.h"
#import "halo_boot_integration.h"
#import "halo_ios_gl_host.h"
#import "halo_guest_runner.h"
#import "halo_ios_controls.h"
#import "HaloSettingsViewController.h"
#import "HaloLogViewController.h"
#import "HaloSettingsStore.h"
#import "halo_ios_audio.h"
#import "halo_ios_platform.h"
#import "halo_crash_report.h"
#import "halo_launch_state.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

extern NSString * const HaloIOSFirstFramePresentedNotification;

/* Keeps the screen edges for the game: no home-indicator swipe or status bar while playing. */
@interface HaloViewController : UIViewController
@end

@implementation HaloViewController
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface AppDelegate () <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIView *bootOverlay;
@property(nonatomic, strong) UIView *menuControls;
@property(nonatomic, strong) UILabel *loadingStatus;
@property(nonatomic, copy) NSString *loadingName;
@property(nonatomic, strong) NSDate *loadingStarted;
@property(nonatomic, strong) NSTimer *loadingTimer;
@property(nonatomic, strong) UITextView *bootLog;
@property(nonatomic, copy) NSString *bootText;
@property(nonatomic, strong) UISegmentedControl *logSource;
@property(nonatomic, strong) UIButton *importButton;
@property(nonatomic, strong) UIButton *startButton;
@property(nonatomic, copy) void (^startBoot)(void);
@property(nonatomic) BOOL engineStarted;
@property(nonatomic) BOOL importing;
@property(nonatomic) BOOL foldersReady;
@property(nonatomic) BOOL physicalPadConnected;
@property(nonatomic, strong) UIButton *settingsButton;
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
    if (self.engineStarted || self.importing || !self.foldersReady) return;
    BOOL ready = [self hasStartupMap];
    self.startButton.enabled = ready;
    self.bootLog.text = ready ? @"Maps are ready. Tap Start Halo.\n" :
        @"Add your Halo maps\n\nTap Import maps to choose your .map files, including ui.map.\n\nYou can also copy them in Files to:\nOn My iPhone → this app → Halo → maps\n\nThe folder is ready. Halo will start after ui.map has been added. Existing map files are kept.\n";
}
- (void)startHalo:(UIButton *)sender {
    (void)sender;
    if (self.engineStarted || self.importing || !self.foldersReady || ![self hasStartupMap]) return;
    self.engineStarted = YES;
    halo_crash_phase("engine boot");
    /* The game is shown first. If it has drawn nothing after 25 seconds the screen is just black, so open the log
       (its Summary says how far the start got) instead of leaving a black screen with no explanation. */
    __weak AppDelegate *watchdogOwner = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AppDelegate *owner = watchdogOwner;
        if (!owner || halo_ios_presented_frames() > 0) return;
        if ([[owner topPresenter] isKindOfClass:HaloLogViewController.class]) return;
        halo_ios_toast("The game has not drawn anything yet - opening the log");
        [owner showLog:nil];
    });
    self.logSource.hidden = NO;
    self.importButton.hidden = YES;
    self.startButton.hidden = YES;
    self.bootOverlay.hidden = YES;   /* the game is what you see first */
    [self updateControlsVisibility];
    if (self.startBoot) self.startBoot();
    self.startBoot = nil;
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
    if (self.engineStarted || self.importing) return;
    self.importing = YES;
    self.importButton.enabled = NO;
    self.startButton.enabled = NO;
    self.bootLog.text = @"Importing maps… Please keep Halo open.\n";
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
            self.importing = NO;
            self.importButton.enabled = YES;
            [self refreshSetup];
            NSString *message = [NSString stringWithFormat:@"Imported %lu maps. Kept %lu existing files.", (unsigned long)imported, (unsigned long)kept];
            if (errors.count) message = [message stringByAppendingFormat:@"\n\n%@", [errors componentsJoinedByString:@"\n"]];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Map import" message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
        });
    });
}
- (void)shareLogs:(UIView *)sender {
    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    for (NSString *name in @[@"ios-boot.log", @"debug.txt", @"gamestate.txt", @"crash.txt", @"last-crash.txt", @"launch-phase.txt"]) {
        NSString *path = [[self haloFolder] stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) [files addObject:[NSURL fileURLWithPath:path]];
    }
    /* Present from whatever is on top. The log and settings screens cover the root view controller,
       and UIKit silently ignores a presentation from a controller that is not on top. */
    UIViewController *presenter = [self topPresenter];
    if (!files.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No logs yet" message:@"Logs will be available after Halo starts." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
    UIView *anchor = sender ?: presenter.view;
    share.popoverPresentationController.sourceView = anchor;
    share.popoverPresentationController.sourceRect = sender ? sender.bounds : CGRectMake(CGRectGetMidX(anchor.bounds), 40, 1, 1);
    [presenter presentViewController:share animated:YES completion:nil];
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
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
- (void)updateControlsVisibility {
    /* On-screen controls only while the game is showing and no physical controller is connected. */
    BOOL editing = [(HaloControlsView *)self.menuControls editing];
    int mode = [[HaloSettingsStore shared] snapshot].controls_mode;   /* 0 auto, 1 always, 2 hidden */
    BOOL wanted = mode == 1 || (mode == 0 && !self.physicalPadConnected);
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
            owner.settingsButton.hidden = NO;
            [owner updateControlsVisibility];
        };
        owner.menuControls.hidden = NO;
        [controls beginEditing];
    };
    settings.onShowLog = ^{ [weakSelf showLog:nil]; };
    settings.onShareLogs = ^(UIView *source) { [weakSelf shareLogs:source]; };
    settings.modalPresentationStyle = UIModalPresentationFullScreen;
    [(HaloControlsView *)self.menuControls releaseAll];
    [top presentViewController:settings animated:YES completion:nil];
}
- (void)updateFPS {
    HsSettings settings = [[HaloSettingsStore shared] snapshot];
    self.fpsLabel.hidden = !settings.show_fps || !self.bootOverlay.hidden;
    if (self.fpsLabel.hidden) { self.fpsLastTime = 0; return; }
    uint64_t frames = halo_ios_presented_frames();
    CFTimeInterval now = CACurrentMediaTime();
    if (self.fpsLastTime > 0 && now > self.fpsLastTime)
        self.fpsLabel.text = [NSString stringWithFormat:@" %.0f FPS ", (double)(frames - self.fpsLastFrames) / (now - self.fpsLastTime)];
    self.fpsLastFrames = frames;
    self.fpsLastTime = now;
}
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    (void)app; (void)options;
    if ([url.scheme caseInsensitiveCompare:@"halo"] != NSOrderedSame) return NO;
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
    bootOverlay.backgroundColor = UIColor.blackColor;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"HALO iOS — M2.6.41 · add your maps";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:18];

    UITextView *log = [[UITextView alloc] initWithFrame:CGRectZero];
    log.translatesAutoresizingMaskIntoConstraints = NO;
    log.backgroundColor = UIColor.blackColor;
    log.textColor = UIColor.greenColor;
    log.editable = NO;
    log.alwaysBounceVertical = YES;
    log.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];

    UILabel *notice = [UILabel new];
    notice.translatesAutoresizingMaskIntoConstraints = NO;
    notice.text = @"Bink movie playback is not implemented; videos are skipped. Audio is muted.\nImportant messages are available in Game log and Share logs.";
    notice.numberOfLines = 2;
    notice.font = [UIFont systemFontOfSize:11];
    notice.textColor = UIColor.systemOrangeColor;
    [bootOverlay addSubview:notice];
    [bootOverlay addSubview:title];
    [bootOverlay addSubview:log];
    [vc.view addSubview:bootOverlay];
    self.bootOverlay = bootOverlay;

    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    gear.translatesAutoresizingMaskIntoConstraints = NO;
    gear.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.9];
    gear.layer.cornerRadius = 8;
    [gear setTitle:@"⚙︎" forState:UIControlStateNormal];
    gear.titleLabel.font = [UIFont systemFontOfSize:20];
    [gear setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    gear.accessibilityLabel = @"Settings";
    [gear addTarget:self action:@selector(showSettings:) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:gear];
    self.settingsButton = gear;
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
    fps.translatesAutoresizingMaskIntoConstraints = NO;
    fps.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    fps.textColor = UIColor.greenColor;
    fps.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    fps.layer.cornerRadius = 5;
    fps.clipsToBounds = YES;
    fps.hidden = YES;
    [vc.view addSubview:fps];
    self.fpsLabel = fps;
    [NSLayoutConstraint activateConstraints:@[
        [fps.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [fps.topAnchor constraintEqualToAnchor:gear.bottomAnchor constant:4]]];
    __weak AppDelegate *fpsOwner = self;
    self.fpsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { [fpsOwner updateFPS]; }];
    UIButton *import = [UIButton buttonWithType:UIButtonTypeSystem];
    [import setTitle:@"Import maps" forState:UIControlStateNormal];
    [import addTarget:self action:@selector(importMaps:) forControlEvents:UIControlEventTouchUpInside];
    self.importButton = import;
    UIButton *start = [UIButton buttonWithType:UIButtonTypeSystem];
    [start setTitle:@"Start Halo" forState:UIControlStateNormal];
    [start addTarget:self action:@selector(startHalo:) forControlEvents:UIControlEventTouchUpInside];
    self.startButton = start;
    UIButton *share = [UIButton buttonWithType:UIButtonTypeSystem];
    [share setTitle:@"Share logs" forState:UIControlStateNormal];
    [share addTarget:self action:@selector(shareLogs:) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[import, start, share]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 24;
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
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:gear.leadingAnchor constant:-8],
        [gear.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [gear.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:4],
        [gear.widthAnchor constraintEqualToConstant:48],
        [gear.heightAnchor constraintEqualToConstant:36],
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
        [actions.leadingAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.leadingAnchor constant:14],
        [actions.bottomAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [actions.heightAnchor constraintEqualToConstant:44]
    ]];

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
        log.text = [NSString stringWithFormat:@"Could not create the maps folder: %@", folderError.localizedDescription];
        import.enabled = NO;
        start.enabled = NO;
    } else if ([self hasStartupMap]) {
        [self startHalo:nil];
    } else {
        halo_crash_phase("waiting for maps");
        [self refreshSetup];
    }
    return YES;
}
@end
