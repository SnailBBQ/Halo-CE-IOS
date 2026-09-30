#import "AppDelegate.h"
#import "halo_boot_integration.h"

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.blackColor;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"HALO iOS";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:20];

    UITextView *log = [[UITextView alloc] initWithFrame:(CGRect){0}];
    log.translatesAutoresizingMaskIntoConstraints = NO;
    log.backgroundColor = UIColor.blackColor;
    log.textColor = UIColor.greenColor;
    log.editable = NO;
    log.alwaysBounceVertical = YES;
    log.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];

    [vc.view addSubview:title];
    [vc.view addSubview:log];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:14],
        [title.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:8],
        [log.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [log.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [log.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [log.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-12]
    ]];

    NSMutableString *text = [NSMutableString string];

    halo_ios_start_game_boot(^(const char *s) {
        NSString *line = [NSString stringWithUTF8String:s ?: ""];
        [text appendFormat:@"%@\n", line];
        NSLog(@"[HaloIOS-Boot] %@", line);
    });

    log.text = text;

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}
@end
