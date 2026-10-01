#import "AppDelegate.h"
#import "halo_boot_integration.h"
#import "halo_ios_gl_host.h"
#import "halo_guest_runner.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

extern NSString * const HaloIOSFirstFramePresentedNotification;

@interface AppDelegate () <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIView *bootOverlay;
@property(nonatomic, strong) UIView *menuControls;
@property(nonatomic, strong) UILabel *loadingStatus;
@property(nonatomic, copy) NSString *loadingName;
@property(nonatomic, strong) NSDate *loadingStarted;
@property(nonatomic, strong) NSTimer *loadingTimer;
@property(nonatomic, strong) UIButton *logToggle;
@property(nonatomic, strong) UITextView *bootLog;
@property(nonatomic, copy) NSString *bootText;
@property(nonatomic, strong) UISegmentedControl *logSource;
@property(nonatomic, strong) UIButton *importButton;
@property(nonatomic, strong) UIButton *startButton;
@property(nonatomic, copy) void (^startBoot)(void);
@property(nonatomic) BOOL engineStarted;
@property(nonatomic) BOOL importing;
@property(nonatomic) BOOL foldersReady;
@end

@implementation AppDelegate

- (void)loadingLine:(NSString *)line
{
    if ([line hasPrefix:@"[loading] begin: "]) {
        self.loadingName = [line substringFromIndex:17];
        self.loadingStarted = [NSDate date];
        self.loadingStatus.hidden = NO;
        [self updateLoadingStatus];
    } else if ([line hasPrefix:@"[loading] done: First game frame "] ||
               [line containsString:@"FULL GUEST STOPPED"] ||
               [line containsString:@"FULL GUEST BLOCKED"]) {
        self.loadingStatus.hidden = YES;
    } else if ([line hasPrefix:@"[loading] done: "]) {
        self.loadingName = @"Next initialization step";
        self.loadingStarted = [NSDate date];
        [self updateLoadingStatus];
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
    self.logSource.hidden = NO;
    self.importButton.hidden = YES;
    self.startButton.hidden = YES;
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
- (void)shareLogs:(UIButton *)sender {
    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    for (NSString *name in @[@"ios-boot.log", @"debug.txt", @"gamestate.txt"]) {
        NSString *path = [[self haloFolder] stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) [files addObject:[NSURL fileURLWithPath:path]];
    }
    if (!files.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No logs yet" message:@"Logs will be available after Halo starts." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
    share.popoverPresentationController.sourceView = sender;
    share.popoverPresentationController.sourceRect = sender.bounds;
    [self.window.rootViewController presentViewController:share animated:YES completion:nil];
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    [self refreshSetup];
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
- (void)applicationWillResignActive:(UIApplication *)application {
    (void)application;
    halo_ios_menu_reset();
}
- (void)toggleBootLog:(UIButton *)sender {
    self.bootOverlay.hidden = !self.bootOverlay.hidden;
    self.menuControls.hidden = !self.bootOverlay.hidden;
    halo_ios_menu_reset();
    if (!self.bootOverlay.hidden && self.engineStarted) [self refreshLogView];
    [sender setTitle:self.bootOverlay.hidden ? @"Show log" : @"Show game"
           forState:UIControlStateNormal];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.blackColor;

    UIView *gameView = halo_ios_gl_create_view();
    gameView.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:gameView];

    UIView *bootOverlay = [UIView new];
    bootOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    bootOverlay.backgroundColor = UIColor.blackColor;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"HALO iOS — M2.6.18 Startup";
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

    UIButton *toggle = [UIButton buttonWithType:UIButtonTypeSystem];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.9];
    [toggle setTitle:@"Starting…" forState:UIControlStateNormal];
    [toggle setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    toggle.enabled = NO;
    [toggle addTarget:self action:@selector(toggleBootLog:)
       forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:toggle];
    self.logToggle = toggle;
    self.bootLog = log;
    UIView *menu = [UIView new];
    menu.translatesAutoresizingMaskIntoConstraints = NO;
    menu.hidden = YES;
    NSArray<NSString *> *labels = @[@"←", @"↑", @"↓", @"→", @"A", @"B", @"X", @"Y", @"Black", @"White"];
    NSArray<NSNumber *> *buttons = @[@13, @11, @12, @14, @0, @1, @2, @3, @10, @9];
    NSArray<NSString *> *accessibility = @[@"Left", @"Up", @"Down", @"Right", @"A", @"B", @"X", @"Y", @"Black", @"White"];
    NSArray<UIColor *> *faceColors = @[
        [UIColor colorWithRed:0.10 green:0.65 blue:0.22 alpha:0.95],
        [UIColor colorWithRed:0.85 green:0.13 blue:0.16 alpha:0.95],
        [UIColor colorWithRed:0.12 green:0.38 blue:0.90 alpha:0.95],
        [UIColor colorWithRed:0.97 green:0.78 blue:0.10 alpha:0.95],
        UIColor.blackColor, UIColor.whiteColor
    ];
    for (NSUInteger i = 0; i < labels.count; ++i) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button setTitle:labels[i] forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.accessibilityLabel = accessibility[i];
        button.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.8];
        button.layer.cornerRadius = i < 4 ? 12 : 24;
        if (i >= 4) {
            button.backgroundColor = faceColors[i - 4];
            [button setTitleColor:(i == 7 || i == 9) ? UIColor.blackColor : UIColor.whiteColor
                         forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont boldSystemFontOfSize:i >= 8 ? 11 : 20];
            button.layer.borderWidth = 1;
            button.layer.borderColor = [UIColor colorWithWhite:0.65 alpha:0.8].CGColor;
        }
        button.tag = buttons[i].integerValue;
        [button.widthAnchor constraintEqualToConstant:48].active = YES;
        [button.heightAnchor constraintEqualToConstant:48].active = YES;
        [button addTarget:self action:@selector(menuPress:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(menuRelease:)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [menu addSubview:button];
        if (i < 4) {
            CGFloat x[] = {0, 52, 52, 104};
            CGFloat y[] = {52, 0, 104, 52};
            [button.leadingAnchor constraintEqualToAnchor:menu.leadingAnchor constant:x[i]].active = YES;
            [button.topAnchor constraintEqualToAnchor:menu.topAnchor constant:y[i]].active = YES;
        } else {
            /* A/B/X/Y diamond, with Black and White flanking A. */
            CGFloat x[] = {52, 104, 0, 52, 104, 0};
            CGFloat y[] = {104, 52, 52, 0, 104, 104};
            [button.trailingAnchor constraintEqualToAnchor:menu.trailingAnchor constant:x[i - 4] - 104].active = YES;
            [button.topAnchor constraintEqualToAnchor:menu.topAnchor constant:y[i - 4]].active = YES;
        }
    }
    [vc.view addSubview:menu];
    self.menuControls = menu;
    [NSLayoutConstraint activateConstraints:@[
        [menu.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [menu.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [menu.heightAnchor constraintEqualToConstant:152],
        [menu.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-12]
    ]];
    UILabel *loading = [UILabel new];
    loading.translatesAutoresizingMaskIntoConstraints = NO;
    loading.textColor = UIColor.whiteColor;
    loading.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.9];
    loading.textAlignment = NSTextAlignmentCenter;
    loading.numberOfLines = 2;
    loading.font = [UIFont systemFontOfSize:15];
    loading.hidden = YES;
    [vc.view addSubview:loading];
    self.loadingStatus = loading;
    [NSLayoutConstraint activateConstraints:@[
        [loading.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [loading.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:68],
        [loading.widthAnchor constraintEqualToConstant:300],
        [loading.heightAnchor constraintEqualToConstant:48]
    ]];
    __weak AppDelegate *loadingOwner = self;
    self.loadingTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        [loadingOwner updateLoadingStatus];
    }];
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
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-8],
        [toggle.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [toggle.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:4],
        [toggle.widthAnchor constraintEqualToConstant:100],
        [toggle.heightAnchor constraintEqualToConstant:36],
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

    __block id firstFrameObserver = nil;
    firstFrameObserver =
        [[NSNotificationCenter defaultCenter]
            addObserverForName:HaloIOSFirstFramePresentedNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) {
        (void)note;
        toggle.enabled = YES;
        [toggle setTitle:@"Show game" forState:UIControlStateNormal];
        // A successful presentation can contain only black pixels.
        // Keep diagnostics visible until the user chooses the game surface.

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
                    bootOverlay.hidden = NO;
                    menu.hidden = YES;
                    halo_ios_menu_reset();
                    [toggle setTitle:@"Show game" forState:UIControlStateNormal];
                }
                [text appendFormat:@"%@\n", line];
                if (text.length > 50000)
                    [text deleteCharactersInRange:NSMakeRange(0, text.length - 40000)];
                AppDelegate *owner = weakSelf;
                [owner loadingLine:line];
                owner.bootText = [text copy];
                if (!bootOverlay.hidden) [owner refreshLogView];
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
        [toggle setTitle:@"Add maps" forState:UIControlStateNormal];
        [self refreshSetup];
    }
    return YES;
}
@end
