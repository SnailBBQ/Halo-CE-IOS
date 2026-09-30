#import "AppDelegate.h"
#import "halo_ios_probe.h"

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.blackColor;

    UITextView *log = [[UITextView alloc] initWithFrame:CGRectZero];
    log.translatesAutoresizingMaskIntoConstraints = NO;
    log.backgroundColor = UIColor.blackColor;
    log.textColor = UIColor.greenColor;
    log.editable = NO;
    log.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    [vc.view addSubview:log];
    [NSLayoutConstraint activateConstraints:@[
        [log.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [log.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [log.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:12],
        [log.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-12]
    ]];

    NSMutableString *text = [NSMutableString stringWithString:@"Halo CE Universal - iOS M0\n\n"];
    halo_ios_run_m0_probe(^(const char *s) {
        [text appendFormat:@"%s\n", s];
        NSLog(@"[HaloM0] %s", s);
    });
    log.text = text;
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}
@end
