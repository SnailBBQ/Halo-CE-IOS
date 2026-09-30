#import "AppDelegate.h"
#import "halo_ios_probe.h"

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.blackColor;

    UITextView *log = [[UITextView alloc] initWithFrame:(CGRect){0}];
    log.translatesAutoresizingMaskIntoConstraints = NO;
    log.backgroundColor = UIColor.blackColor;
    log.textColor = UIColor.greenColor;
    log.editable = NO;
    log.alwaysBounceVertical = YES;
    log.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    [vc.view addSubview:log];
    [NSLayoutConstraint activateConstraints:@[
        [log.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [log.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [log.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:12],
        [log.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-12]
    ]];

    NSMutableString *text =
        [NSMutableString stringWithString:@"Halo iOS - M1.2 + M1.3 Combined Integration\n\n"];

    halo_ios_run_combined_m12_m13_probe(^(const char *s) {
        NSString *line = [NSString stringWithUTF8String:s ?: ""];
        [text appendFormat:@"%@\n", line];
        NSLog(@"[HaloIOS-M1.3] %@", line);
    });

    log.text = text;
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}
@end
