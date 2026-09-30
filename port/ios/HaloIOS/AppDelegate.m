#import "AppDelegate.h"
#import "halo_ios_probe.h"

@interface AppDelegate ()
@property(nonatomic, strong) UITextView *logView;
@property(nonatomic, strong) UIButton *guestCodeButton;
@property(nonatomic, strong) NSMutableString *logText;
@end

@implementation AppDelegate

- (void)appendProbeLine:(const char *)s {
    NSString *line = [NSString stringWithUTF8String:s ?: ""];
    [self.logText appendFormat:@"%@\n", line];
    self.logView.text = self.logText;
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length, 0)];
    NSLog(@"[HaloIOS-M0.5] %@", line);
}

- (void)runGuestCodeTest:(UIButton *)sender {
    sender.enabled = NO;
    [self.logText appendString:@"\n=== Manual Guest Code Execution Test ===\n"];
    self.logView.text = self.logText;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:@"running" forKey:@"HaloM05DynamicState"];
    [defaults synchronize];

    int ok = halo_ios_run_m05_dynamic_probe(^(const char *s) {
        [self appendProbeLine:s];
    });

    [defaults setObject:(ok ? @"passed" : @"blocked") forKey:@"HaloM05DynamicState"];
    [defaults synchronize];
    sender.enabled = YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.blackColor;

    self.logView = [[UITextView alloc] initWithFrame:(CGRect){0}];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logView.backgroundColor = UIColor.blackColor;
    self.logView.textColor = UIColor.greenColor;
    self.logView.editable = NO;
    self.logView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];

    self.guestCodeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.guestCodeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.guestCodeButton setTitle:@"Run Guest Code Test" forState:UIControlStateNormal];
    self.guestCodeButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.guestCodeButton addTarget:self action:@selector(runGuestCodeTest:) forControlEvents:UIControlEventTouchUpInside];

    [vc.view addSubview:self.logView];
    [vc.view addSubview:self.guestCodeButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.logView.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.logView.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [self.logView.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.guestCodeButton.topAnchor constant:-8],
        [self.guestCodeButton.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.guestCodeButton.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [self.guestCodeButton.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [self.guestCodeButton.heightAnchor constraintEqualToConstant:48]
    ]];

    self.logText = [NSMutableString stringWithString:@"Halo iOS - M0.5 Guest Code Execution Strategy\n\n"];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *previous = [defaults stringForKey:@"HaloM05DynamicState"];
    if ([previous isEqualToString:@"running"]) {
        [self.logText appendString:@"PREVIOUS DYNAMIC TEST: INTERRUPTED\n"];
        [self.logText appendString:@"The process did not return from the copied-code call. iOS likely terminated execution.\n\n"];
        [defaults setObject:@"interrupted" forKey:@"HaloM05DynamicState"];
        [defaults synchronize];
    } else if ([previous isEqualToString:@"passed"]) {
        [self.logText appendString:@"Previous dynamic guest-code test: PASS\n\n"];
    } else if ([previous isEqualToString:@"blocked"]) {
        [self.logText appendString:@"Previous dynamic guest-code test: BLOCKED before execution\n\n"];
    }

    halo_ios_run_m0_probe(^(const char *s) {
        [self appendProbeLine:s];
    });

    self.logView.text = self.logText;
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}
@end
