#import "HaloLogViewController.h"
#import "HaloUI.h"
#import "halo_log_report.h"

@interface HaloLogViewController ()
@property(nonatomic, strong) UISegmentedControl *tabs;
@property(nonatomic, strong) UIView *body;
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) NSTimer *refreshTimer;
@property(nonatomic, strong) UIScrollView *scroll;
@end

@implementation HaloLogViewController {
    HaloReport _report;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = HaloUIBackground();

    UILabel *title = HaloUILabel(@"Diagnostics", 22, UIFontWeightBold, nil);
    title.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *close = HaloUIButton(@"Back to game", 1, ^(UIButton *b) { [self dismissViewControllerAnimated:YES completion:nil]; });
    close.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *share = HaloUIButton(@"Share logs", 0, ^(UIButton *b) { if (self.onShare) self.onShare(b); });
    share.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *copyButton = HaloUIButton(@"Copy logs", 0, ^(UIButton *b) { if (self.onCopy) self.onCopy(b); });
    copyButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.tabs = [[UISegmentedControl alloc] initWithItems:@[@"Summary", @"Problems"]];
    self.tabs.selectedSegmentIndex = 0;
    self.tabs.selectedSegmentTintColor = HaloUIAccent();
    [self.tabs setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor } forState:UIControlStateNormal];
    [self.tabs setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor } forState:UIControlStateSelected];
    self.tabs.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];

    self.body = [[UIView alloc] init];
    self.body.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];
    [self.view addSubview:share];
    [self.view addSubview:copyButton];
    [self.view addSubview:close];
    [self.view addSubview:self.tabs];
    [self.view addSubview:self.body];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [close.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:130],
        [share.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-10],
        [share.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [share.widthAnchor constraintEqualToConstant:110],
        [copyButton.trailingAnchor constraintEqualToAnchor:share.leadingAnchor constant:-10],
        [copyButton.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [copyButton.widthAnchor constraintEqualToConstant:110],
        [self.tabs.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
        [self.tabs.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [self.tabs.widthAnchor constraintEqualToConstant:300],
        [self.body.topAnchor constraintEqualToAnchor:self.tabs.bottomAnchor constant:12],
        [self.body.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.body.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [self.body.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    self.stack = HaloUIScrollingStack(self.body, 12);
    self.scroll = (UIScrollView *)self.stack.superview;
    [self render];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    __weak HaloLogViewController *weak = self;
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *t) {
        HaloLogViewController *strong = weak;
        if (strong && !strong.scroll.isDragging && !strong.scroll.isDecelerating) [strong render];
    }];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)tabChanged
{
    self.scroll.contentOffset = CGPointZero;
    [self render];
}

#pragma mark - content

static NSString *HaloText(const char *c) { return [NSString stringWithUTF8String:c] ?: @""; }

- (void)clear
{
    for (UIView *view in self.stack.arrangedSubviews) { [self.stack removeArrangedSubview:view]; [view removeFromSuperview]; }
}

- (void)render
{
    NSString *boot = self.bootLogProvider ? self.bootLogProvider() : @"";
    NSString *game = self.gameLogProvider ? self.gameLogProvider() : @"";
    halo_report_build(&_report, boot.UTF8String ?: "", game.UTF8String ?: "");
    NSInteger count = _report.problem_count;
    [self.tabs setTitle:count ? [NSString stringWithFormat:@"Problems (%ld)", (long)count] : @"Problems" forSegmentAtIndex:1];
    CGPoint offset = self.scroll.contentOffset;
    [self clear];
    if (self.tabs.selectedSegmentIndex == 0) [self renderSummary:boot.length > 0];
    else [self renderProblems];
    [self.view layoutIfNeeded];
    self.scroll.contentOffset = offset;
}

- (void)renderSummary:(BOOL)haveLog
{
    HaloReport *r = &_report;

    /* ---- status */
    NSString *state; UIColor *color;
    if (!haveLog) { state = @"Waiting"; color = HaloUIAmber(); }
    else if (r->stopped) { state = @"Stopped"; color = HaloUIRed(); }
    else if (r->engine_started && r->fps_samples > 0) { state = @"Running"; color = HaloUIGreen(); }
    else { state = @"Starting"; color = HaloUIAmber(); }
    NSMutableArray<UIView *> *status = [NSMutableArray array];
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[HaloUILabel(@"Game engine", 15.5, UIFontWeightRegular, nil), HaloUIPill(state, color)]];
    head.axis = UILayoutConstraintAxisHorizontal;
    head.alignment = UIStackViewAlignmentCenter;
    head.distribution = UIStackViewDistributionEqualSpacing;
    [status addObject:head];
    if (r->stopped) [status addObject:HaloUINote(HaloText(r->stop_reason))];
    if (r->build[0]) [status addObject:HaloUIValueRow(@"Game", HaloText(r->build), nil)];
    if (r->app_version[0]) [status addObject:HaloUIValueRow(@"App version", HaloText(r->app_version), nil)];
    if (r->map[0]) [status addObject:HaloUIValueRow(@"Current map", HaloText(r->map), nil)];
    if (r->maps_total) [status addObject:HaloUIValueRow(@"Maps found", [NSString stringWithFormat:@"%d of %d", r->maps_found, r->maps_total], r->maps_found == r->maps_total ? HaloUIGreen() : HaloUIAmber())];
    [self.stack addArrangedSubview:HaloUICardView(@"Status", status)];

    /* ---- where a fatal fault happened */
    if (r->fault_count > 0) {
        NSMutableArray<UIView *> *rows = [NSMutableArray arrayWithObject:HaloUINote(@"The game stopped in the first function below, called from the ones after it. Please share the logs.")];
        for (int i = 0; i < r->fault_count; i++) [rows addObject:HaloUILabel(HaloText(r->fault[i]), 12.5, UIFontWeightRegular, HaloUISecondaryText())];
        [self.stack addArrangedSubview:HaloUICardView(@"Where it stopped", rows)];
    }

    /* ---- how the last start went */
    if (r->previous_start[0] || r->safe_start) {
        NSMutableArray<UIView *> *rows = [NSMutableArray array];
        if (r->previous_start[0]) [rows addObject:HaloUILabel(HaloText(r->previous_start), 15, UIFontWeightRegular, HaloUIAmber())];
        for (int i = 0; i < r->crash_count; i++) [rows addObject:HaloUILabel(HaloText(r->crash[i]), 12.5, UIFontWeightRegular, HaloUISecondaryText())];
        if (r->safe_start) [rows addObject:HaloUINote(@"Safe start is on: sound, internet play, smooth 60 FPS, hi-res HUD and text and the profiler are off until a start runs for 15 seconds. Settings > Advanced has Leave safe mode.")];
        [self.stack addArrangedSubview:HaloUICardView(@"Last start", rows)];
    }

    /* ---- performance */
    NSMutableArray<UIView *> *speed = [NSMutableArray array];
    if (r->fps_samples == 0) {
        [speed addObject:HaloUINote(@"No frame rate measured yet. It is reported every 10 seconds.")];
    } else {
        const char *verdict = halo_report_verdict(r->fps_average);
        UIColor *fpsColor = r->fps_average >= 28 ? HaloUIGreen() : (r->fps_average >= 15 ? HaloUIAmber() : HaloUIRed());
        [speed addObject:HaloUIValueRow(@"Frame rate", [NSString stringWithFormat:@"%.0f FPS · %s", r->fps_average, verdict], fpsColor)];
        [speed addObject:HaloUINote(@"The typical rate over the last five reports; a loading screen can briefly show a much higher number.")];
        if (r->render_ms >= 0) [speed addObject:HaloUIValueRow(@"Drawing a frame", [NSString stringWithFormat:@"%.1f ms", r->render_ms], nil)];
        if (r->waiting_percent >= 0) {
            [speed addObject:HaloUIValueRow(@"Game thread waiting", [NSString stringWithFormat:@"%.0f%%", r->waiting_percent], nil)];
            [speed addObject:HaloUINote(r->waiting_percent >= 40 ? @"Mostly waiting for the screen: the game has headroom and the display is the limit."
                                                                  : @"The game thread is busy most of the time; it is the limit, not the screen.")];
        }
    }
    [self.stack addArrangedSubview:HaloUICardView(@"Performance", speed)];
    if (r->top_count > 0) {
        NSMutableArray<UIView *> *rows = [NSMutableArray array];
        for (int i = 0; i < r->top_count; i++) {
            NSString *line = HaloText(r->top[i]);
            NSRange gap = [line rangeOfString:@"  "];
            NSString *percent = gap.location == NSNotFound ? line : [line substringToIndex:gap.location];
            NSString *name = gap.location == NSNotFound ? @"" : [[line substringFromIndex:gap.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            [rows addObject:HaloUIValueRow(name, percent, HaloUISecondaryText())];
        }
        [self.stack addArrangedSubview:HaloUICardView(@"Busiest game functions", rows)];
    }

    /* ---- memory: a game that runs out of it stops, so this shows how close it is */
    NSMutableArray<UIView *> *memory = [NSMutableArray array];
    if (r->mem_used_mib >= 0 && r->mem_region_mib > 0) {
        double share = (double)r->mem_used_mib / (double)r->mem_region_mib;
        UIColor *tint = share > 0.9 ? HaloUIRed() : (share > 0.75 ? HaloUIAmber() : HaloUIGreen());
        [memory addObject:HaloUIValueRow(@"Game address space", [NSString stringWithFormat:@"%ld of %ld MiB", r->mem_used_mib, r->mem_region_mib], tint)];
        if (r->mem_peak_mib >= 0) [memory addObject:HaloUIValueRow(@"Highest so far", [NSString stringWithFormat:@"%ld MiB", r->mem_peak_mib], nil)];
        if (r->mem_failures > 0) [memory addObject:HaloUIValueRow(@"Requests that found no room", [NSString stringWithFormat:@"%ld", r->mem_failures], HaloUIRed())];
    }
    if (r->device_left_mib >= 0) {
        UIColor *tint = r->device_left_mib < 300 ? HaloUIRed() : (r->device_left_mib < 700 ? HaloUIAmber() : HaloUIGreen());
        if (r->device_footprint_mib >= 0) [memory addObject:HaloUIValueRow(@"App memory", [NSString stringWithFormat:@"%ld MiB", r->device_footprint_mib], nil)];
        [memory addObject:HaloUIValueRow(@"Left before iOS closes the app", [NSString stringWithFormat:@"%ld MiB", r->device_left_mib], tint)];
    }
    if (!memory.count) [memory addObject:HaloUINote(@"No memory report yet. It is reported every 10 seconds.")];
    [self.stack addArrangedSubview:HaloUICardView(@"Memory", memory)];

    /* ---- sound and multiplayer */
    NSMutableArray<UIView *> *sound = [NSMutableArray array];
    if (r->audio_text[0]) {
        [sound addObject:HaloUIValueRow(@"Output", HaloText(r->audio_text), r->audio_open ? HaloUIGreen() : HaloUIRed())];
        if (r->audio_open) [sound addObject:HaloUIValueRow(@"Gaps in the sound", r->underruns ? [NSString stringWithFormat:@"%u", r->underruns] : @"None", r->underruns ? HaloUIAmber() : HaloUIGreen())];
    } else {
        [sound addObject:HaloUINote(@"No sound report yet.")];
    }
    [self.stack addArrangedSubview:HaloUICardView(@"Sound", sound)];

    NSMutableArray<UIView *> *net = [NSMutableArray array];
    if (r->network_count == 0) [net addObject:HaloUINote(@"No multiplayer activity this session. Join or host from Settings > Multiplayer.")];
    for (int i = 0; i < r->network_count; i++) [net addObject:HaloUILabel(HaloText(r->network[i]), 12.5, UIFontWeightRegular, HaloUISecondaryText())];
    [self.stack addArrangedSubview:HaloUICardView(@"Multiplayer", net)];
}

- (void)renderProblems
{
    HaloReport *r = &_report;
    if (r->problem_count == 0) {
        UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[HaloUILabel(@"Problems found", 15.5, UIFontWeightRegular, nil), HaloUIPill(@"None", HaloUIGreen())]];
        head.axis = UILayoutConstraintAxisHorizontal;
        head.alignment = UIStackViewAlignmentCenter;
        head.distribution = UIStackViewDistributionEqualSpacing;
        [self.stack addArrangedSubview:HaloUICardView(nil, @[head, HaloUINote(@"Nothing in the logs needs attention.")])];
    }
    for (int i = 0; i < r->problem_count; i++) {
        const HrProblem *p = &r->problems[i];
        UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[
            HaloUILabel(HaloText(p->title), 16, UIFontWeightSemibold, nil),
            HaloUIPill(p->severity == 0 ? @"Error" : @"Warning", p->severity == 0 ? HaloUIRed() : HaloUIAmber())]];
        head.axis = UILayoutConstraintAxisHorizontal;
        head.alignment = UIStackViewAlignmentTop;
        head.spacing = 10;
        NSMutableArray<UIView *> *rows = [NSMutableArray arrayWithObject:head];
        if (p->detail[0]) [rows addObject:HaloUILabel(HaloText(p->detail), 14, UIFontWeightRegular, HaloUISecondaryText())];
        if (p->count > 1) [rows addObject:HaloUILabel([NSString stringWithFormat:@"Happened %d times", p->count], 12.5, UIFontWeightRegular, HaloUISecondaryText())];
        [self.stack addArrangedSubview:HaloUICardView(nil, rows)];
    }
    if (r->expected_count > 0) {
        NSString *text = [NSString stringWithFormat:@"%d messages in the logs are normal on iOS (skipped videos, Xbox hard-disk files and console services that do not exist here). They are hidden. Share logs sends everything, including them.", r->expected_count];
        [self.stack addArrangedSubview:HaloUICardView(@"Normal messages", @[HaloUINote(text)])];
    }
}

@end
