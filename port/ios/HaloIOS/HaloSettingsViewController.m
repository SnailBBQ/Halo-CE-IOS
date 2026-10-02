#import "HaloSettingsViewController.h"
#import "HaloSettingsStore.h"
#import "halo_ios_platform.h"

@interface HaloSettingsViewController ()
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, strong) UIStackView *stack;
@end

@implementation HaloSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"Settings";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:22];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [done addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:title];
    [self.view addSubview:done];

    self.scroll = [[UIScrollView alloc] init];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.alwaysBounceVertical = YES;
    [self.view addSubview:self.scroll];
    self.stack = [[UIStackView alloc] init];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 10;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scroll addSubview:self.stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [done.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [done.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [self.scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [self.scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:4],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-40],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.leadingAnchor constant:20],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.trailingAnchor constant:-20]]];
    [self rebuild];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

#pragma mark - form helpers

- (UILabel *)labelWithText:(NSString *)text size:(CGFloat)size bold:(BOOL)bold color:(UIColor *)color
{
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.numberOfLines = 0;
    label.textColor = color;
    label.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    return label;
}

- (void)addSection:(NSString *)title
{
    UILabel *label = [self labelWithText:title.uppercaseString size:13 bold:YES color:[UIColor colorWithWhite:0.6 alpha:1]];
    [self.stack setCustomSpacing:18 afterView:self.stack.arrangedSubviews.lastObject ?: label];
    [self.stack addArrangedSubview:label];
}

- (void)addNote:(NSString *)text
{
    [self.stack addArrangedSubview:[self labelWithText:text size:13 bold:NO color:[UIColor colorWithWhite:0.62 alpha:1]]];
}

- (UIView *)card:(NSArray<UIView *> *)views
{
    UIStackView *inner = [[UIStackView alloc] initWithArrangedSubviews:views];
    inner.axis = UILayoutConstraintAxisHorizontal;
    inner.spacing = 12;
    inner.alignment = UIStackViewAlignmentCenter;
    inner.layoutMargins = UIEdgeInsetsMake(10, 14, 10, 14);
    inner.layoutMarginsRelativeArrangement = YES;
    inner.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1];
    inner.layer.cornerRadius = 10;
    return inner;
}

- (void)addSwitch:(NSString *)title value:(BOOL)value change:(void (^)(HsSettings *s, BOOL on))change
{
    UILabel *label = [self labelWithText:title size:16 bold:NO color:UIColor.whiteColor];
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = value;
    [toggle addAction:[UIAction actionWithHandler:^(UIAction *action) {
        BOOL on = toggle.on;
        [[HaloSettingsStore shared] update:^(HsSettings *s) { change(s, on); }];
    }] forControlEvents:UIControlEventValueChanged];
    [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.stack addArrangedSubview:[self card:@[label, toggle]]];
}

- (void)addSlider:(NSString *)title min:(float)min max:(float)max value:(float)value
           format:(NSString *)format change:(void (^)(HsSettings *s, float v))change
{
    UILabel *label = [self labelWithText:[NSString stringWithFormat:format, value] size:15 bold:NO color:UIColor.whiteColor];
    UILabel *name = [self labelWithText:title size:16 bold:NO color:UIColor.whiteColor];
    UISlider *slider = [[UISlider alloc] init];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    __weak UILabel *weakLabel = label;
    [slider addAction:[UIAction actionWithHandler:^(UIAction *action) {
        float v = slider.value;
        weakLabel.text = [NSString stringWithFormat:format, v];
        [[HaloSettingsStore shared] update:^(HsSettings *s) { change(s, v); }];
    }] forControlEvents:UIControlEventValueChanged];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[name, label]];
    top.distribution = UIStackViewDistributionEqualSpacing;
    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[top, slider]];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 4;
    UIStackView *wrap = (UIStackView *)[self card:@[column]];
    [column.widthAnchor constraintEqualToAnchor:wrap.widthAnchor constant:-28].active = YES;
    [self.stack addArrangedSubview:wrap];
}

- (UIButton *)pillButton:(NSString *)title
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    button.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
    button.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
    button.layer.cornerRadius = 8;
    return button;
}

- (void)addButton:(NSString *)title enabled:(BOOL)enabled action:(void (^)(UIButton *sender))action
{
    UIButton *button = [self pillButton:title];
    button.enabled = enabled;
    __weak UIButton *weak = button;
    [button addAction:[UIAction actionWithHandler:^(UIAction *a) { if (weak) action(weak); }] forControlEvents:UIControlEventTouchUpInside];
    [button setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = (UIStackView *)[self card:@[button]];
    [button.widthAnchor constraintEqualToAnchor:row.widthAnchor constant:-28].active = YES;
    [self.stack addArrangedSubview:row];
}

#pragma mark - content

- (void)rebuild
{
    for (UIView *view in self.stack.arrangedSubviews) { [self.stack removeArrangedSubview:view]; [view removeFromSuperview]; }
    HsSettings settings = [[HaloSettingsStore shared] snapshot];
    HsPreset preset = settings.presets[settings.active];

    [self addSection:@"Control schemes"];
    [self addNote:@"Five schemes you can rename. Each remembers where every button sits, its size, and the aim settings below."];
    for (int i = 0; i < HS_PRESET_COUNT; i++) {
        BOOL active = i == settings.active;
        UIButton *choose = [self pillButton:[NSString stringWithFormat:@"%@  %s", active ? @"●" : @"○", settings.presets[i].name]];
        choose.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        choose.backgroundColor = active ? [UIColor colorWithRed:0.12 green:0.38 blue:0.7 alpha:1] : [UIColor colorWithWhite:0.22 alpha:1];
        [choose addAction:[UIAction actionWithHandler:^(UIAction *a) {
            [[HaloSettingsStore shared] update:^(HsSettings *s) { s->active = i; }];
            [self rebuild];
        }] forControlEvents:UIControlEventTouchUpInside];
        UIButton *rename = [self pillButton:@"Rename"];
        [rename addAction:[UIAction actionWithHandler:^(UIAction *a) { [self renamePreset:i]; }] forControlEvents:UIControlEventTouchUpInside];
        [choose setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[choose, rename]];
        row.spacing = 8;
        [self.stack addArrangedSubview:row];
    }
    [self addButton:@"Edit button layout…" enabled:YES action:^(UIButton *sender) {
        void (^go)(void) = self.onEditLayout;
        [self dismissViewControllerAnimated:YES completion:^{ if (go) go(); }];
    }];
    [self addButton:@"Reset this scheme to the Xbox layout" enabled:YES action:^(UIButton *sender) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset layout?"
            message:@"Buttons return to their standard places and sizes in this scheme." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [[HaloSettingsStore shared] update:^(HsSettings *s) { hs_reset_layout(&s->presets[s->active]); }];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];

    [self addSection:@"Aim and sticks (this scheme)"];
    [self addSwitch:@"Drag to look (touch-look)" value:preset.touch_look change:^(HsSettings *s, BOOL on) { s->presets[s->active].touch_look = on; }];
    [self addSlider:@"Look speed" min:0.25f max:3.0f value:preset.look_sensitivity format:@"%.2f×"
             change:^(HsSettings *s, float v) { s->presets[s->active].look_sensitivity = v; }];
    [self addSwitch:@"Invert look (up looks down)" value:preset.invert_look_y change:^(HsSettings *s, BOOL on) { s->presets[s->active].invert_look_y = on; }];
    [self addSlider:@"Look acceleration" min:1.0f max:3.0f value:preset.look_curve format:@"%.1f"
             change:^(HsSettings *s, float v) { s->presets[s->active].look_curve = v; }];
    [self addSwitch:@"Floating sticks (stick starts where your thumb lands)" value:preset.floating_sticks
            change:^(HsSettings *s, BOOL on) { s->presets[s->active].floating_sticks = on; }];
    [self addSlider:@"Stick dead zone" min:0.0f max:0.4f value:preset.stick_dead_zone format:@"%.0f%%"
             change:^(HsSettings *s, float v) { s->presets[s->active].stick_dead_zone = v; }];
    [self addSlider:@"Move stick response" min:1.0f max:3.0f value:preset.move_curve format:@"%.1f"
             change:^(HsSettings *s, float v) { s->presets[s->active].move_curve = v; }];
    [self addSlider:@"Button opacity" min:0.25f max:1.0f value:preset.opacity format:@"%.2f"
             change:^(HsSettings *s, float v) { s->presets[s->active].opacity = v; }];
    [self addSwitch:@"Haptic feedback" value:preset.haptics change:^(HsSettings *s, BOOL on) { s->presets[s->active].haptics = on; }];
    [self addNote:@"Dead zone shows as a fraction of the stick; response above 1.0 gives finer control near the centre."];

    [self addSection:@"Audio"];
    [self addSwitch:@"Sound" value:settings.audio_enabled change:^(HsSettings *s, BOOL on) { s->audio_enabled = on; }];
    [self addSlider:@"Volume" min:0.0f max:1.0f value:settings.volume format:@"%.2f"
             change:^(HsSettings *s, float v) { s->volume = v; }];

    [self addSection:@"Multiplayer"];
    [self addNote:@"Host from Multiplayer → System Link. The invite link is copied for you; send it to friends. Opening it on their device (or tapping Join below) puts them in your game. Works across iPhone, iPad, Android, Windows and Linux."];
    UITextField *paste = [[UITextField alloc] init];
    paste.placeholder = @"Paste an invite link here (halo://join/…)";
    paste.textColor = UIColor.whiteColor;
    paste.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1];
    paste.layer.cornerRadius = 10;
    paste.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 10)];
    paste.leftViewMode = UITextFieldViewModeAlways;
    paste.clearButtonMode = UITextFieldViewModeWhileEditing;
    paste.autocorrectionType = UITextAutocorrectionTypeNo;
    paste.autocapitalizationType = UITextAutocapitalizationTypeNone;
    paste.keyboardType = UIKeyboardTypeURL;
    [paste.heightAnchor constraintEqualToConstant:44].active = YES;
    [self.stack addArrangedSubview:paste];
    [self addButton:@"Join this invite" enabled:YES action:^(UIButton *sender) {
        [paste resignFirstResponder];
        if (HaloJoinInviteText(paste.text)) [self dismissViewControllerAnimated:YES completion:nil];
    }];
    [self addButton:@"Join invite from clipboard" enabled:YES action:^(UIButton *sender) {
        if (HaloJoinInviteFromClipboard()) [self dismissViewControllerAnimated:YES completion:nil];
    }];
    NSString *invite = HaloLastHostedInvite();
    [self addButton:invite ? @"Share my invite link…" : @"Share my invite link (host a game first)" enabled:invite != nil action:^(UIButton *sender) {
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[invite] applicationActivities:nil];
        share.popoverPresentationController.sourceView = sender;
        share.popoverPresentationController.sourceRect = sender.bounds;
        [self presentViewController:share animated:YES completion:nil];
    }];
    [self addSwitch:@"Join links on the clipboard automatically" value:settings.join_from_clipboard
             change:^(HsSettings *s, BOOL on) { s->join_from_clipboard = on; }];
    [self addNote:@"Off by default: reading the clipboard makes iOS ask for permission to paste. Opening a halo:// link joins without it."];

    [self addSection:@"Frame rate"];
    [self addSwitch:@"Smooth 60 FPS (the original game runs at 30)" value:settings.smooth_fps
            change:^(HsSettings *s, BOOL on) { s->smooth_fps = on; }];
    [self addNote:@"Takes effect the next time you open the app. Turn it off if the game stutters or the phone gets hot."];

    [self addSection:@"Diagnostics"];
    [self addSwitch:@"Show frame rate on screen" value:settings.show_fps change:^(HsSettings *s, BOOL on) { s->show_fps = on; }];
    [self addSwitch:@"Performance profiler (adds a Where the time goes report to the log)" value:settings.profiler
             change:^(HsSettings *s, BOOL on) { s->profiler = on; }];
    [self addButton:@"View log…" enabled:YES action:^(UIButton *sender) {
        void (^go)(void) = self.onShowLog;
        [self dismissViewControllerAnimated:YES completion:^{ if (go) go(); }];
    }];
    [self addButton:@"Share log files…" enabled:YES action:^(UIButton *sender) { if (self.onShareLogs) self.onShareLogs(sender); }];
}

- (void)renamePreset:(int)index
{
    HsSettings settings = [[HaloSettingsStore shared] snapshot];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename scheme"
        message:[NSString stringWithFormat:@"Up to %d characters.", HS_NAME_MAX] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [NSString stringWithUTF8String:settings.presets[index].name];
        field.clearButtonMode = UITextFieldViewModeAlways;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        [[HaloSettingsStore shared] update:^(HsSettings *s) {
            hs_set_name(s->presets[index].name, text.UTF8String);
            if (!s->presets[index].name[0]) hs_set_name(s->presets[index].name, [NSString stringWithFormat:@"Preset %d", index + 1].UTF8String);
        }];
        [self rebuild];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
