#import "HaloSettingsViewController.h"
#import "HaloSettingsStore.h"
#import "HaloUI.h"
#import "halo_ios_platform.h"
#import "halo_guest_runner.h"

typedef NS_ENUM(NSInteger, HaloCategory) {
    HaloCategoryMultiplayer = 0, HaloCategoryControls, HaloCategoryDisplay, HaloCategoryAudio, HaloCategoryCheats, HaloCategoryAdvanced,
    HaloCategoryLogs, HaloCategoryCount
};

@interface HaloSettingsViewController () <UITextFieldDelegate>
@property(nonatomic, strong) UIView *detail;
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) NSArray<UIButton *> *sidebar;
@property(nonatomic) HaloCategory selected;
@end

@implementation HaloSettingsViewController

static NSString *HaloCategoryTitle(HaloCategory c)
{
    switch (c) {
        case HaloCategoryMultiplayer: return @"Multiplayer";
        case HaloCategoryControls: return @"Controls";
        case HaloCategoryDisplay: return @"Display";
        case HaloCategoryAudio: return @"Audio";
        case HaloCategoryCheats: return @"Cheats";
        case HaloCategoryAdvanced: return @"Advanced";
        default: return @"Logs";
    }
}

static NSString *HaloCategorySymbol(HaloCategory c)
{
    switch (c) {
        case HaloCategoryMultiplayer: return @"person.2.fill";
        case HaloCategoryControls: return @"gamecontroller.fill";
        case HaloCategoryDisplay: return @"display";
        case HaloCategoryAudio: return @"speaker.wave.2.fill";
        case HaloCategoryCheats: return @"sparkles";
        case HaloCategoryAdvanced: return @"wrench.and.screwdriver.fill";
        default: return @"doc.text.magnifyingglass";
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = HaloUIBackground();
    UILabel *title = HaloUILabel(@"Settings", 22, UIFontWeightBold, nil);
    title.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *done = HaloUIButton(@"Back to game", 1, ^(UIButton *b) { [self dismissViewControllerAnimated:YES completion:nil]; });
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];
    [self.view addSubview:done];

    /* the category list: the first six in order, Logs pinned to the bottom */
    UIStackView *list = [[UIStackView alloc] init];
    list.axis = UILayoutConstraintAxisVertical;
    list.spacing = 6;
    list.translatesAutoresizingMaskIntoConstraints = NO;
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSInteger i = 0; i < HaloCategoryCount; i++) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *icon = [UIImage systemImageNamed:HaloCategorySymbol((HaloCategory)i)];
        [row setImage:icon forState:UIControlStateNormal];
        [row setTitle:[@"  " stringByAppendingString:HaloCategoryTitle((HaloCategory)i)] forState:UIControlStateNormal];
        row.titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];
        row.tintColor = UIColor.whiteColor;
        [row setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        row.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
        row.layer.cornerRadius = 10;
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        NSInteger index = i;
        [row addAction:[UIAction actionWithHandler:^(UIAction *action) { [self choose:(HaloCategory)index]; }] forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:row];
        if (i == HaloCategoryLogs) {
            UIView *spacer = [[UIView alloc] init];
            [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
            [list addArrangedSubview:spacer];
        }
        [list addArrangedSubview:row];
    }
    self.sidebar = buttons;
    [self.view addSubview:list];

    self.detail = [[UIView alloc] init];
    self.detail.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.detail];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [done.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [done.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [done.widthAnchor constraintEqualToConstant:130],
        [list.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
        [list.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [list.widthAnchor constraintEqualToConstant:176],
        [list.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10],
        [self.detail.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [self.detail.leadingAnchor constraintEqualToAnchor:list.trailingAnchor constant:16],
        [self.detail.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.detail.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    self.stack = HaloUIScrollingStack(self.detail, 12);
    self.selected = HaloCategoryMultiplayer;
    [self renderDetail];
}

- (void)choose:(HaloCategory)category
{
    if (category == HaloCategoryLogs) {
        void (^go)(void) = self.onShowLog;
        [self dismissViewControllerAnimated:YES completion:^{ if (go) go(); }];
        return;
    }
    self.selected = category;
    [(UIScrollView *)self.stack.superview setContentOffset:CGPointZero animated:NO];
    [self renderDetail];
}

/* Rebuild after an action finishes, never from inside the control that triggered it. */
- (void)renderSoon
{
    dispatch_async(dispatch_get_main_queue(), ^{ [self renderDetail]; });
}

- (void)renderDetail
{
    for (NSInteger i = 0; i < (NSInteger)self.sidebar.count; i++) {
        BOOL on = i == (NSInteger)self.selected;
        self.sidebar[i].backgroundColor = on ? HaloUIAccent() : (i == HaloCategoryLogs ? [UIColor colorWithWhite:0.14 alpha:1] : UIColor.clearColor);
    }
    for (UIView *view in self.stack.arrangedSubviews) { [self.stack removeArrangedSubview:view]; [view removeFromSuperview]; }
    HsSettings settings = [[HaloSettingsStore shared] snapshot];
    switch (self.selected) {
        case HaloCategoryMultiplayer: [self buildMultiplayer:&settings]; break;
        case HaloCategoryControls: [self buildControls:&settings]; break;
        case HaloCategoryDisplay: [self buildDisplay:&settings]; break;
        case HaloCategoryAudio: [self buildAudio:&settings]; break;
        case HaloCategoryCheats: [self buildCheats:&settings]; break;
        default: [self buildAdvanced:&settings]; break;
    }
}

- (void)add:(UIView *)view { [self.stack addArrangedSubview:view]; }

#pragma mark - small helpers

- (void)update:(void (^)(HsSettings *s))block
{
    [[HaloSettingsStore shared] update:block];
}

#pragma mark - Multiplayer

- (void)buildMultiplayer:(const HsSettings *)settings
{
    UITextField *paste = [[UITextField alloc] init];
    paste.placeholder = @"halo://join/…";
    paste.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"halo://join/…" attributes:@{ NSForegroundColorAttributeName: HaloUISecondaryText() }];
    paste.textColor = UIColor.whiteColor;
    paste.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    paste.layer.cornerRadius = 10;
    paste.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 10)];
    paste.leftViewMode = UITextFieldViewModeAlways;
    paste.clearButtonMode = UITextFieldViewModeWhileEditing;
    paste.autocorrectionType = UITextAutocorrectionTypeNo;
    paste.autocapitalizationType = UITextAutocapitalizationTypeNone;
    paste.keyboardType = UIKeyboardTypeURL;
    paste.returnKeyType = UIReturnKeyDone;
    paste.delegate = self;
    [paste.heightAnchor constraintEqualToConstant:44].active = YES;
    UIButton *join = HaloUIButton(@"Join this invite", 1, ^(UIButton *b) {
        [paste resignFirstResponder];
        if (HaloJoinInviteText(paste.text)) [self dismissViewControllerAnimated:YES completion:nil];
    });
    UIButton *fromClipboard = HaloUIButton(@"Join the invite on the clipboard", 0, ^(UIButton *b) {
        if (HaloJoinInviteFromClipboard()) [self dismissViewControllerAnimated:YES completion:nil];
    });
    [self add:HaloUICardView(@"Join a game", @[
        HaloUINote(@"Paste the invite link a friend sent you. It works across iPhone, iPad, Android, Windows and Linux, as long as everyone is on the same Halo CE Universal build."),
        paste, join, fromClipboard])];

    [self add:HaloUICardView(@"Invite file", @[HaloUINote(@"While hosting, Documents/Halo/game_invite.txt contains your current invite. Share it in Files. Leaving the hosted game empties it; each app launch clears the previous session.")])];
    NSString *invite = HaloLastHostedInvite();
    UIButton *share = HaloUIButton(invite ? @"Share my invite link" : @"Share my invite link", 1, ^(UIButton *b) {
        NSString *link = HaloLastHostedInvite();
        if (!link) return;
        UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[link] applicationActivities:nil];
        sheet.popoverPresentationController.sourceView = b;
        sheet.popoverPresentationController.sourceRect = b.bounds;
        [self presentViewController:sheet animated:YES completion:nil];
    });
    share.enabled = invite != nil;
    [self add:HaloUICardView(@"Host a game", @[
        HaloUINote(invite ? @"Your game is ready to share." : @"In the game, choose Multiplayer > System Link and start a game. The invite link is made and copied for you; it then appears here."),
        share])];

    [self add:HaloUICardView(@"Options", @[
        HaloUISwitchRow(@"Join links on the clipboard automatically", @"Off by default: reading the clipboard makes iOS ask for permission each time. Opening a halo:// link joins without it.",
                        settings->join_from_clipboard, ^(BOOL on) { [self update:^(HsSettings *s) { s->join_from_clipboard = on; }]; })])];
    [self add:HaloUICardView(@"Finding games on your Wi-Fi", @[
        HaloUINote(@"If games on the same network are not found, check iOS Settings > Privacy & Security > Local Network > Halo CE is on, and that both devices are on the same Wi-Fi.")])];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }

#pragma mark - Controls

- (void)buildControls:(const HsSettings *)settings
{
    HsPreset preset = settings->presets[settings->active];

    [self add:HaloUICardView(@"On-screen controls", @[
        HaloUISegmentRow(nil, @[@"Auto", @"Always show", @"Hide"], settings->controls_mode, ^(NSInteger i) {
            [self update:^(HsSettings *s) { s->controls_mode = (int)i; }];
            [self renderSoon];
        }),
        HaloUINote(settings->controls_mode == 0 ? @"Auto hides them while a controller is connected and brings them back when it disconnects."
                   : settings->controls_mode == 1 ? @"Shown even with a controller connected; touch and controller work together."
                   : @"Hidden: use a controller.")])];

    NSMutableArray<UIView *> *schemes = [NSMutableArray array];
    [schemes addObject:HaloUINote(@"Five schemes you can rename. Each remembers where every button sits, how big it is, and the aim settings below.")];
    for (int i = 0; i < HS_PRESET_COUNT; i++) {
        BOOL active = i == settings->active;
        UIButton *choose = HaloUIButton([NSString stringWithUTF8String:settings->presets[i].name], active ? 1 : 0, ^(UIButton *b) {
            [self update:^(HsSettings *s) { s->active = i; }];
            [self renderSoon];
        });
        choose.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        choose.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
        UIButton *rename = HaloUIButton(@"Rename", 0, ^(UIButton *b) { [self renamePreset:i]; });
        [rename.widthAnchor constraintEqualToConstant:90].active = YES;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[choose, rename]];
        row.spacing = 8;
        [schemes addObject:row];
    }
    [schemes addObject:HaloUIButton(@"Edit button layout…", 0, ^(UIButton *b) {
        void (^go)(void) = self.onEditLayout;
        [self dismissViewControllerAnimated:YES completion:^{ if (go) go(); }];
    })];
    [schemes addObject:HaloUIButton(@"Reset this scheme to the Xbox layout", 2, ^(UIButton *b) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset layout?" message:@"Buttons return to their standard places and sizes in this scheme." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [self update:^(HsSettings *s) { hs_reset_layout(&s->presets[s->active]); }];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    })];
    [self add:HaloUICardView(@"Control scheme", schemes)];

    [self add:HaloUICardView(@"Looking", @[
        HaloUISwitchRow(@"Drag to look", @"Drag a finger anywhere on the right of the screen.", preset.touch_look, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].touch_look = on; }]; }),
        HaloUISliderRow(@"Look speed", 0.25f, 3.0f, preset.look_sensitivity, @"%.2f×", ^(float v) { [self update:^(HsSettings *s) { s->presets[s->active].look_sensitivity = v; }]; }),
        HaloUISliderRow(@"Look acceleration", 1.0f, 3.0f, preset.look_curve, @"%.1f", ^(float v) { [self update:^(HsSettings *s) { s->presets[s->active].look_curve = v; }]; }),
        HaloUISwitchRow(@"Invert look", @"Up on the screen looks down.", preset.invert_look_y, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].invert_look_y = on; }]; })])];

    [self add:HaloUICardView(@"Sticks", @[
        HaloUISwitchRow(@"Floating sticks", @"The stick starts where your thumb lands.", preset.floating_sticks, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].floating_sticks = on; }]; }),
        HaloUISliderRow(@"Dead zone", 0.0f, 0.4f, preset.stick_dead_zone, @"%.2f", ^(float v) { [self update:^(HsSettings *s) { s->presets[s->active].stick_dead_zone = v; }]; }),
        HaloUISliderRow(@"Move stick response", 1.0f, 3.0f, preset.move_curve, @"%.1f", ^(float v) { [self update:^(HsSettings *s) { s->presets[s->active].move_curve = v; }]; }),
        HaloUINote(@"Response above 1.0 gives finer control near the centre.")])];

    [self add:HaloUICardView(@"Buttons", @[
        HaloUISliderRow(@"Opacity", 0.25f, 1.0f, preset.opacity, @"%.2f", ^(float v) { [self update:^(HsSettings *s) { s->presets[s->active].opacity = v; }]; }),
        HaloUISwitchRow(@"Haptic feedback", nil, preset.haptics, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].haptics = on; }]; })])];
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
        [self update:^(HsSettings *s) {
            hs_set_name(s->presets[index].name, text.UTF8String);
            if (!s->presets[index].name[0]) hs_set_name(s->presets[index].name, [NSString stringWithFormat:@"Preset %d", index + 1].UTF8String);
        }];
        [self renderSoon];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Display

- (void)buildDisplay:(const HsSettings *)settings
{
    NSString *note = settings->fps_mode == 0 ? @"The original game's 30 frames a second."
        : settings->fps_mode == 1 ? @"A frame for every screen refresh, held at 60. Smooth and easy on the battery."
        : @"Draws as fast as the screen can show: up to 120 on ProMotion iPhones and iPads, 60 on other screens. Uses more battery and gets warmer.";
    [self add:HaloUICardView(@"Frame rate", @[
        HaloUISegmentRow(nil, @[@"30 · Original", @"60 · Smooth", @"Uncapped"], settings->fps_mode, ^(NSInteger i) {
            [self update:^(HsSettings *s) { s->fps_mode = (int)i; }];
            [self renderSoon];
        }),
        HaloUINote(note),
        HaloUINote(@"Switching between 30 and the other two takes effect the next time you open the app. Switching between 60 and Uncapped takes effect now.")])];

    [self add:HaloUICardView(@"HUD and text", @[
        HaloUISwitchRow(@"High-res HUD", @"Sharper meters, radar and reticles.", settings->hires_hud, ^(BOOL on) { [self update:^(HsSettings *s) { s->hires_hud = on; }]; }),
        HaloUISwitchRow(@"High-res text", @"Menus and HUD text at the screen's resolution.", settings->hires_text, ^(BOOL on) { [self update:^(HsSettings *s) { s->hires_text = on; }]; }),
        HaloUINote(@"New in Halo CE Universal build 73 and off until you try them. They apply the next time you open the app; turn them off again if menus or the HUD stutter.")])];

    [self add:HaloUICardView(@"On screen", @[
        HaloUISwitchRow(@"Show frame rate", @"A small counter under the Settings button.", settings->show_fps, ^(BOOL on) { [self update:^(HsSettings *s) { s->show_fps = on; }]; })])];
}

#pragma mark - Audio

- (void)buildAudio:(const HsSettings *)settings
{
    [self add:HaloUICardView(@"Sound", @[
        HaloUISwitchRow(@"Sound", nil, settings->audio_enabled, ^(BOOL on) { [self update:^(HsSettings *s) { s->audio_enabled = on; }]; }),
        HaloUISliderRow(@"Volume", 0.0f, 1.0f, settings->volume, @"%.2f", ^(float v) { [self update:^(HsSettings *s) { s->volume = v; }]; }),
        HaloUINote(@"Halo plays even when the ring/silent switch is on, like a game console.")])];
}

#pragma mark - Cheats

- (void)buildCheats:(const HsSettings *)settings
{
    [self add:HaloUICardView(@"Campaign cheats", @[
        HaloUINote(@"These use the game's own cheat flags. They work only in the campaign and switch off by themselves in multiplayer and network games, so nobody cheats where others play."),
        HaloUISwitchRow(@"God mode", @"You cannot die.", settings->cheat_god, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_god = on; }]; }),
        HaloUISwitchRow(@"Infinite ammo", @"Weapons never run out; plasma weapons never need a new battery.", settings->cheat_ammo, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_ammo = on; }]; }),
        HaloUISwitchRow(@"Infinite grenades", @"Throw as many as you like.", settings->cheat_grenades, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_grenades = on; }]; }),
        HaloUISwitchRow(@"Bottomless clip", @"A magazine never empties.", settings->cheat_reload, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_reload = on; }]; })])];
    [self add:HaloUICardView(@"Player tools", @[
        HaloUISwitchRow(@"One-hit kills", @"Hostile units only; friendly units are protected.", settings->cheat_one_hit, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_one_hit = on; }]; }),
        HaloUISwitchRow(@"Unlimited flashlight", @"Keeps its battery full; you still toggle the light.", settings->cheat_flashlight, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_flashlight = on; }]; }),
        HaloUISwitchRow(@"No fall damage", @"The local player takes no falling or collision damage.", settings->cheat_no_fall, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_no_fall = on; }]; }),
        HaloUISwitchRow(@"Rapid fire", @"Removes shot-rate and trigger-latch delays; charging and overheating remain.", settings->cheat_rapid, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_rapid = on; }]; }),
        HaloUISwitchRow(@"No recoil", @"Removes the weapon kick; projectile spread is unchanged.", settings->cheat_no_recoil, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_no_recoil = on; }]; }),
        HaloUISwitchRow(@"Third person", @"Follow the player with the existing third-person camera.", settings->cheat_third_person, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_third_person = on; }]; }),
        HaloUISwitchRow(@"Noclip", @"Fly through walls. Aim to move; jump rises and crouch descends. Disable inside clear space.", settings->cheat_noclip, ^(BOOL on) { [self update:^(HsSettings *s) { s->cheat_noclip = on; }]; })])];
    [self add:HaloUICardView(@"Super jump", @[HaloUISliderRow(@"Value", 1, 10, settings->cheat_jump, @"%.1f", ^(float value) { [self update:^(HsSettings *s) { s->cheat_jump = value; }]; }), HaloUIButton(@"Enter value", 0, ^(UIButton *b) { HsSettings current = [[HaloSettingsStore shared] snapshot]; [self enterCampaignValue:@"Super jump" value:current.cheat_jump minimum:1 maximum:10 apply:^(float value) { [self update:^(HsSettings *s) { s->cheat_jump = value; }]; }]; })])];
    [self add:HaloUICardView(@"Player speed", @[HaloUISliderRow(@"Value", 1, 5, settings->cheat_speed, @"%.1f", ^(float value) { [self update:^(HsSettings *s) { s->cheat_speed = value; }]; }), HaloUIButton(@"Enter value", 0, ^(UIButton *b) { HsSettings current = [[HaloSettingsStore shared] snapshot]; [self enterCampaignValue:@"Player speed" value:current.cheat_speed minimum:1 maximum:5 apply:^(float value) { [self update:^(HsSettings *s) { s->cheat_speed = value; }]; }]; })])];
    [self add:HaloUICardView(@"Vertical FOV (0 = default)", @[HaloUISliderRow(@"Value", 0, 90, settings->cheat_fov, @"%.1f", ^(float value) { [self update:^(HsSettings *s) { s->cheat_fov = value; }]; }), HaloUIButton(@"Enter value", 0, ^(UIButton *b) { HsSettings current = [[HaloSettingsStore shared] snapshot]; [self enterCampaignValue:@"Vertical FOV (0 = default)" value:current.cheat_fov minimum:0 maximum:90 apply:^(float value) { [self update:^(HsSettings *s) { s->cheat_fov = value; }]; }]; })])];
    [self add:HaloUICardView(@"Spawn loaded map assets", @[
        HaloUINote(@"Pickups appear in front of you. Only assets already loaded by the current map are supported; unavailable assets report a message."),
        HaloUIButton(@"Weapon giver", 0, ^(UIButton *b) { [self chooseCampaignAsset:@"Weapon" names:@[@"Pistol", @"Assault rifle", @"Shotgun", @"Sniper rifle", @"Rocket launcher", @"Plasma pistol", @"Plasma rifle", @"Needler", @"Flamethrower", @"Gravity rifle"] base:100]; }),
        HaloUIButton(@"Vehicle spawner", 0, ^(UIButton *b) { [self chooseCampaignAsset:@"Vehicle" names:@[@"Warthog", @"Ghost", @"Banshee", @"Scorpion"] base:200]; }),
        HaloUIButton(@"Spawn overshield", 0, ^(UIButton *b) { [self queueCampaignAction:2]; }),
        HaloUIButton(@"Spawn invisibility", 0, ^(UIButton *b) { [self queueCampaignAction:3]; }),
        HaloUIButton(@"Apply active camouflage", 0, ^(UIButton *b) { [self queueCampaignAction:1]; })])];
    [self add:HaloUICardView(nil, @[HaloUINote(@"Changes apply within a moment, also in the middle of a mission.")])];
}

- (void)queueCampaignAction:(uint32_t)action
{
    if (!halo_ios_queue_campaign_action(action)) halo_ios_toast("An action is already waiting for the game");
}

- (void)chooseCampaignAsset:(NSString *)title names:(NSArray<NSString *> *)names base:(uint32_t)base
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:@"Only the current map's loaded assets can be spawned." preferredStyle:UIAlertControllerStyleAlert];
    [names enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, BOOL *stop) {
        [alert addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self queueCampaignAction:base + (uint32_t)index]; }]];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)enterCampaignValue:(NSString *)title value:(float)value minimum:(float)minimum maximum:(float)maximum apply:(void (^)(float))apply
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:[NSString stringWithFormat:@"Allowed range: %.0f–%.0f", minimum, maximum] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.keyboardType = UIKeyboardTypeDecimalPad; field.text = [NSString stringWithFormat:@"%.1f", value]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSScanner *scanner = [NSScanner scannerWithString:alert.textFields.firstObject.text ?: @""];
        float parsed;
        if (![scanner scanFloat:&parsed] || !scanner.isAtEnd || !isfinite(parsed) || parsed < minimum || parsed > maximum || ([title hasPrefix:@"Vertical FOV"] && parsed != 0 && parsed < 20)) {
            halo_ios_toast("Enter a number in the supported range (FOV: 0 or 20–90)"); return;
        }
        apply(parsed); [self renderSoon];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Advanced

- (void)buildAdvanced:(const HsSettings *)settings
{
    NSMutableArray<UIView *> *diag = [NSMutableArray array];
    [diag addObject:HaloUISwitchRow(@"Performance profiler", @"Samples the game thread so Diagnostics can show where the time goes. About 1% of one CPU core.", settings->profiler, ^(BOOL on) { [self update:^(HsSettings *s) { s->profiler = on; }]; })];
    [diag addObject:HaloUIButton(@"Share log files", 0, ^(UIButton *b) { if (self.onShareLogs) self.onShareLogs(b); })];
    [self add:HaloUICardView(@"Diagnostics", diag)];

    if (halo_ios_safe_level()) {
        [self add:HaloUICardView(@"Safe start is on", @[
            HaloUINote(@"The last start did not finish, so sound, internet play, smooth 60 FPS, hi-res HUD and text and the profiler are off for now. A start that runs for 15 seconds turns safe start off by itself."),
            HaloUIButton(@"Leave safe mode (the next start is normal)", 1, ^(UIButton *b) {
                halo_ios_leave_safe_mode();
                halo_ios_toast("The next start will be a normal one");
                [self renderSoon];
            })])];
    }

    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    [self add:HaloUICardView(@"About", @[
        HaloUIValueRow(@"App version", version, nil),
        HaloUIValueRow(@"Game", @"Halo CE Universal build 73", nil),
        HaloUINote(@"Everyone in a multiplayer game must be on the same game build.")])];
}

@end
