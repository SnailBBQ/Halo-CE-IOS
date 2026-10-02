#import "HaloLogViewController.h"
#import "halo_log_classify.h"

typedef NS_ENUM(NSInteger, HaloLogTab) { HaloLogTabSummary = 0, HaloLogTabProblems, HaloLogTabAll, HaloLogTabGame };

@interface HaloLogViewController () <UITextFieldDelegate>
@property(nonatomic, strong) UISegmentedControl *tabs;
@property(nonatomic, strong) UITextView *text;
@property(nonatomic, strong) UITextField *filter;
@property(nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation HaloLogViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];

    self.tabs = [[UISegmentedControl alloc] initWithItems:@[@"Summary", @"Problems", @"Full log", @"Game log"]];
    self.tabs.selectedSegmentIndex = 0;
    self.tabs.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tabs addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"Close" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    UIButton *share = [UIButton buttonWithType:UIButtonTypeSystem];
    [share setTitle:@"Share" forState:UIControlStateNormal];
    share.titleLabel.font = [UIFont systemFontOfSize:17];
    share.translatesAutoresizingMaskIntoConstraints = NO;
    [share addTarget:self action:@selector(shareTapped:) forControlEvents:UIControlEventTouchUpInside];

    self.filter = [[UITextField alloc] init];
    self.filter.placeholder = @"Filter (for example: map, audio, error)";
    self.filter.textColor = UIColor.whiteColor;
    self.filter.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    self.filter.layer.cornerRadius = 8;
    self.filter.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    self.filter.leftViewMode = UITextFieldViewModeAlways;
    self.filter.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.filter.autocorrectionType = UITextAutocorrectionTypeNo;
    self.filter.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.filter.returnKeyType = UIReturnKeyDone;
    self.filter.delegate = self;
    self.filter.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filter addTarget:self action:@selector(refresh) forControlEvents:UIControlEventEditingChanged];

    self.text = [[UITextView alloc] init];
    self.text.editable = NO;
    self.text.backgroundColor = UIColor.clearColor;
    self.text.alwaysBounceVertical = YES;
    self.text.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:self.tabs];
    [self.view addSubview:close];
    [self.view addSubview:share];
    [self.view addSubview:self.filter];
    [self.view addSubview:self.text];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [close.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [close.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [share.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-18],
        [share.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],
        [self.tabs.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.tabs.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],
        [self.tabs.trailingAnchor constraintEqualToAnchor:share.leadingAnchor constant:-18],
        [self.filter.topAnchor constraintEqualToAnchor:close.bottomAnchor constant:8],
        [self.filter.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.filter.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.filter.heightAnchor constraintEqualToConstant:34],
        [self.text.topAnchor constraintEqualToAnchor:self.filter.bottomAnchor constant:6],
        [self.text.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [self.text.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [self.text.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]]];
    [self refresh];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    __weak HaloLogViewController *weak = self;
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *t) {
        HaloLogViewController *strong = weak;
        if (strong && !strong.filter.isFirstResponder && !strong.text.isDragging && !strong.text.isDecelerating) [strong refresh];
    }];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)shareTapped:(UIButton *)sender { if (self.onShare) self.onShare(sender); }
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }

#pragma mark - text

static NSArray<NSString *> *HaloLines(NSString *text)
{
    NSMutableArray *lines = [NSMutableArray array];
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSString *clean = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (clean.length) [lines addObject:line];
    }];
    return lines;
}

static UIColor *HaloLineColor(int category, BOOL expected)
{
    if (expected) return [UIColor colorWithWhite:0.5 alpha:1];
    switch (category) {
        case HALO_LOG_ERROR:       return [UIColor colorWithRed:1.0 green:0.42 blue:0.42 alpha:1];
        case HALO_LOG_WARNING:     return [UIColor colorWithRed:1.0 green:0.72 blue:0.30 alpha:1];
        case HALO_LOG_PERFORMANCE: return [UIColor colorWithRed:0.45 green:0.85 blue:0.95 alpha:1];
        case HALO_LOG_LOADING:     return [UIColor colorWithWhite:0.62 alpha:1];
        case HALO_LOG_NETWORK:     return [UIColor colorWithRed:0.55 green:0.90 blue:0.55 alpha:1];
        case HALO_LOG_NOISE:       return [UIColor colorWithWhite:0.38 alpha:1];
        default:                   return [UIColor colorWithWhite:0.88 alpha:1];
    }
}

- (UIFont *)mono { return [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular]; }

- (NSAttributedString *)colored:(NSArray<NSString *> *)lines filter:(NSString *)filter onlyProblems:(BOOL)problems
{
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    NSDictionary *plain = @{ NSFontAttributeName: [self mono], NSForegroundColorAttributeName: UIColor.whiteColor };
    NSUInteger shown = 0, hidden = 0;
    NSUInteger start = lines.count > 4000 ? lines.count - 4000 : 0; /* the newest 4000 lines */
    for (NSUInteger i = start; i < lines.count; i++) {
        NSString *line = [lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
        int category = halo_log_category(line.UTF8String);
        BOOL expected = (category == HALO_LOG_ERROR || category == HALO_LOG_WARNING) && halo_log_expected(line.UTF8String);
        if (problems && !((category == HALO_LOG_ERROR || category == HALO_LOG_WARNING))) continue;
        if (filter.length && [line rangeOfString:filter options:NSCaseInsensitiveSearch].location == NSNotFound) { hidden++; continue; }
        NSMutableDictionary *attrs = [plain mutableCopy];
        attrs[NSForegroundColorAttributeName] = HaloLineColor(category, expected);
        if (category == HALO_LOG_ERROR && !expected) attrs[NSFontAttributeName] = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"] attributes:attrs]];
        shown++;
    }
    if (!shown) {
        NSString *none = problems ? @"No problems logged." : @"Nothing matches.";
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:none attributes:plain]];
    }
    (void)hidden;
    return out;
}

- (void)appendHeading:(NSString *)heading to:(NSMutableAttributedString *)out
{
    [out appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@\n", heading]
        attributes:@{ NSFontAttributeName: [UIFont boldSystemFontOfSize:17], NSForegroundColorAttributeName: UIColor.whiteColor }]];
}

- (void)appendBody:(NSString *)body color:(UIColor *)color to:(NSMutableAttributedString *)out
{
    [out appendAttributedString:[[NSAttributedString alloc] initWithString:[body stringByAppendingString:@"\n"]
        attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:15], NSForegroundColorAttributeName: color }]];
}

- (void)appendMono:(NSString *)body color:(UIColor *)color to:(NSMutableAttributedString *)out
{
    [out appendAttributedString:[[NSAttributedString alloc] initWithString:[body stringByAppendingString:@"\n"]
        attributes:@{ NSFontAttributeName: [self mono], NSForegroundColorAttributeName: color }]];
}

- (NSAttributedString *)summary
{
    NSArray<NSString *> *boot = HaloLines(self.bootLogProvider ? self.bootLogProvider() : @"");
    NSArray<NSString *> *game = HaloLines(self.gameLogProvider ? self.gameLogProvider() : @"");
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    UIColor *good = [UIColor colorWithRed:0.45 green:0.9 blue:0.5 alpha:1];
    UIColor *warn = [UIColor colorWithRed:1.0 green:0.72 blue:0.30 alpha:1];
    UIColor *bad = [UIColor colorWithRed:1.0 green:0.42 blue:0.42 alpha:1];
    UIColor *normal = [UIColor colorWithWhite:0.88 alpha:1];

    double fps = -1, renderMs = -1;
    NSInteger lastProfile = -1;
    BOOL stopped = NO;
    NSString *audioLine = nil, *version = nil;
    NSMutableArray<NSString *> *network = [NSMutableArray array];
    NSMutableArray<NSString *> *faults = [NSMutableArray array];
    for (NSUInteger i = 0; i < boot.count; i++) {
        const char *c = boot[i].UTF8String;
        double v = halo_log_fps(c);
        if (v >= 0) fps = v;
        v = halo_log_render_ms(c);
        if (v >= 0) renderMs = v;
        if (!strncmp(c, "profile:", 8)) lastProfile = (NSInteger)i;
        if (strstr(c, "FULL GUEST STOPPED") || strstr(c, "FULL GUEST BLOCKED")) stopped = YES;
        if (!strncmp(c, "audio:", 6)) audioLine = boot[i];
        if (!version && strstr(c, "M2.6.") && strstr(c, "arena fast path")) version = boot[i];
        if (halo_log_category(c) == HALO_LOG_NETWORK && network.count < 6) [network addObject:boot[i]];
    }
    for (NSUInteger i = 0; i < boot.count; i++)
        if (!strncmp(boot[i].UTF8String, "pointer faults this interval", 28)) { [faults removeAllObjects]; for (NSUInteger k = i + 1; k < boot.count && k < i + 4; k++) if (strstr(boot[k].UTF8String, "fault hot spot")) [faults addObject:boot[k]]; }

    [self appendHeading:@"Status" to:out];
    if (!boot.count) [self appendBody:@"Waiting for the engine to start…" color:normal to:out];
    else [self appendBody:stopped ? @"The engine stopped. Open the Problems tab to see why." : @"The game engine is running." color:stopped ? bad : good to:out];

    [self appendHeading:@"Speed" to:out];
    if (fps < 0) [self appendBody:@"No frame rate measured yet (it is reported every 10 seconds)." color:normal to:out];
    else {
        NSString *verdict = fps >= 28 ? @"smooth" : (fps >= 20 ? @"playable" : (fps >= 12 ? @"choppy" : @"slow"));
        [self appendBody:[NSString stringWithFormat:@"%.0f frames per second — %@", fps, verdict] color:fps >= 28 ? good : (fps >= 15 ? warn : bad) to:out];
        if (renderMs >= 0) [self appendBody:[NSString stringWithFormat:@"Drawing a frame takes about %.0f ms on the CPU (30 FPS needs under 33).", renderMs] color:normal to:out];
    }

    if (lastProfile >= 0) {
        [self appendHeading:@"Where the time goes" to:out];
        [self appendBody:@"Share of the game thread's time, sampled 500 times a second:" color:normal to:out];
        for (NSInteger k = lastProfile; k < (NSInteger)boot.count && k < lastProfile + 12; k++) {
            if (k > lastProfile && strncmp(boot[k].UTF8String, "  profile", 9)) break;
            [self appendMono:boot[k] color:HaloLineColor(HALO_LOG_PERFORMANCE, NO) to:out];
        }
    }
    if (faults.count) {
        [self appendHeading:@"Pointer faults (slow memory accesses left)" to:out];
        for (NSString *line in faults) [self appendMono:line color:HaloLineColor(HALO_LOG_PERFORMANCE, NO) to:out];
    }

    [self appendHeading:@"Sound" to:out];
    [self appendBody:audioLine ?: @"No sound report yet." color:normal to:out];

    NSMutableArray<NSString *> *real = [NSMutableArray array];
    NSUInteger expected = 0;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSArray<NSString *> *lines in @[boot, game]) {
        for (NSString *line in lines) {
            int category = halo_log_category(line.UTF8String);
            if (category != HALO_LOG_ERROR && category != HALO_LOG_WARNING) continue;
            if (halo_log_expected(line.UTF8String)) { expected++; continue; }
            /* the same message with a different time stamp is one problem */
            NSString *key = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (key.length > 18 && [key characterAtIndex:2] == '.') key = [key substringFromIndex:18];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            [real addObject:line];
        }
    }
    [self appendHeading:real.count ? [NSString stringWithFormat:@"Problems (%lu)", (unsigned long)real.count] : @"Problems" to:out];
    if (!real.count) [self appendBody:@"None." color:good to:out];
    for (NSUInteger i = 0; i < real.count && i < 10; i++) {
        NSString *line = [real[i] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
        [self appendMono:line color:HaloLineColor(halo_log_category(line.UTF8String), NO) to:out];
    }
    if (expected) [self appendBody:[NSString stringWithFormat:@"%lu more messages are normal on iOS (videos and Xbox hard-disk files don't exist here). They are greyed out in the full log.", (unsigned long)expected]
                             color:[UIColor colorWithWhite:0.55 alpha:1] to:out];

    if (network.count) {
        [self appendHeading:@"Multiplayer" to:out];
        for (NSString *line in network) [self appendMono:line color:HaloLineColor(HALO_LOG_NETWORK, NO) to:out];
    }
    (void)version;
    [self appendBody:@"\nUse Share to send the log files." color:[UIColor colorWithWhite:0.5 alpha:1] to:out];
    return out;
}

- (void)refresh
{
    NSInteger tab = self.tabs.selectedSegmentIndex;
    self.filter.hidden = tab == HaloLogTabSummary;
    NSString *filter = self.filter.text ?: @"";
    NSAttributedString *content;
    if (tab == HaloLogTabSummary) content = [self summary];
    else if (tab == HaloLogTabGame) content = [self colored:HaloLines(self.gameLogProvider ? self.gameLogProvider() : @"") filter:filter onlyProblems:NO];
    else content = [self colored:HaloLines(self.bootLogProvider ? self.bootLogProvider() : @"") filter:filter onlyProblems:tab == HaloLogTabProblems];
    CGPoint offset = self.text.contentOffset;
    BOOL atEnd = self.text.contentOffset.y + self.text.bounds.size.height >= self.text.contentSize.height - 40;
    self.text.attributedText = content;
    if (tab == HaloLogTabSummary) {
        self.text.contentOffset = CGPointZero;
    } else if (atEnd || self.text.contentOffset.y == 0) {
        if (self.text.text.length) [self.text scrollRangeToVisible:NSMakeRange(self.text.text.length - 1, 1)];
    } else {
        self.text.contentOffset = offset;
    }
}

@end
