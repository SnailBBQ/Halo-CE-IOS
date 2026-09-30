#import "AppDelegate.h"
#import "halo_boot_integration.h"
#import "halo_ios_gl_host.h"

extern NSString * const HaloIOSFirstFramePresentedNotification;

@interface AppDelegate ()
@property(nonatomic, strong) UIView *bootOverlay;
@property(nonatomic, strong) UIButton *logToggle;
@end

@implementation AppDelegate
- (void)toggleBootLog:(UIButton *)sender {
    self.bootOverlay.hidden = !self.bootOverlay.hidden;
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
    title.text = @"HALO iOS — M2.6.6 Startup";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:18];

    UITextView *log = [[UITextView alloc] initWithFrame:CGRectZero];
    log.translatesAutoresizingMaskIntoConstraints = NO;
    log.backgroundColor = UIColor.blackColor;
    log.textColor = UIColor.greenColor;
    log.editable = NO;
    log.alwaysBounceVertical = YES;
    log.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];

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
        [log.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5],
        [log.bottomAnchor constraintEqualToAnchor:bootOverlay.safeAreaLayoutGuide.bottomAnchor constant:-10]
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
                if ([line hasPrefix:@"M2.5 FULL GUEST STOPPED:"] ||
                    [line hasPrefix:@"FULL GUEST BLOCKED:"]) {
                    bootOverlay.hidden = NO;
                    [toggle setTitle:@"Show game" forState:UIControlStateNormal];
                }
                [text appendFormat:@"%@\n", line];
                if (text.length > 50000)
                    [text deleteCharactersInRange:NSMakeRange(0, text.length - 40000)];
                log.text = text;
                if (log.text.length > 0) {
                    NSRange bottom = NSMakeRange(log.text.length - 1, 1);
                    [log scrollRangeToVisible:bottom];
                }
            });
        });
    });

    return YES;
}
@end
