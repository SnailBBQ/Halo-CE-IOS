#import "HaloSettingsViewController.h"
#import "HaloSettingsStore.h"
#import "HaloUI.h"
#import "HaloLibrary.h"
#import "HaloHudEditor.h"
#import "halo_ios_platform.h"
#import "halo_guest_runner.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface HaloOptionPicker : UITableViewController
@property(nonatomic,copy) NSArray<NSString *> *choices;
@property(nonatomic,copy) void (^pick)(NSUInteger);
@end
@implementation HaloOptionPicker
- (void)viewDidLoad { [super viewDidLoad];
    self.tableView.backgroundColor=HaloUIBackground();
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated];[self.tableView setContentOffset:CGPointMake(0,-self.tableView.adjustedContentInset.top) animated:NO]; }
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView;(void)section;return (NSInteger)self.choices.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"option"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"option"];
    cell.backgroundColor=HaloUICard();cell.textLabel.textColor=UIColor.whiteColor;
    cell.textLabel.text=self.choices[(NSUInteger)indexPath.row];return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;void (^pick)(NSUInteger)=self.pick;NSUInteger row=(NSUInteger)indexPath.row;
    [self dismissViewControllerAnimated:YES completion:^{ if (pick) pick(row); }];
}
@end

typedef NS_ENUM(NSInteger, HaloCategory) {
    HaloCategoryMultiplayer = 0, HaloCategoryControls, HaloCategoryDisplay, HaloCategoryAudio, HaloCategoryCheats, HaloCategoryMods, HaloCategoryOptions, HaloCategoryAdvanced,
    HaloCategoryLogs, HaloCategoryCount
};

@interface HaloSettingsViewController () <UITextFieldDelegate, UIDocumentPickerDelegate>
@property(nonatomic, strong) UIView *detail;
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) NSArray<UIButton *> *sidebar;
@property(nonatomic) HaloCategory selected;
@property(nonatomic,strong) id campaignObserver;
@property(nonatomic,strong) NSTimer *connectionTimer;
@property(nonatomic,strong) UILabel *connectionLabel;
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
        case HaloCategoryMods: return @"Mods";
        case HaloCategoryOptions: return @"Options";
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
        case HaloCategoryMods: return @"square.stack.3d.up.fill";
        case HaloCategoryOptions: return @"slider.horizontal.3";
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
    /* A header owns its height; a short landscape sidebar must never compress
       the title to zero or pull the dismissal button above the safe area. */
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];
    [header addSubview:title];
    [header addSubview:done];
    [title setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

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
    UIScrollView *categories = [[UIScrollView alloc] init];
    categories.translatesAutoresizingMaskIntoConstraints = NO;
    categories.alwaysBounceVertical = NO;
    [self.view addSubview:categories];
    [categories addSubview:list];

    self.detail = [[UIView alloc] init];
    self.detail.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.detail];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [header.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [header.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [header.heightAnchor constraintEqualToConstant:48],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:4],
        [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:done.leadingAnchor constant:-12],
        [done.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-4],
        [done.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [done.heightAnchor constraintEqualToConstant:44],
        [done.widthAnchor constraintEqualToConstant:130],
        [categories.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10],
        [categories.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [categories.widthAnchor constraintEqualToConstant:176],
        [categories.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10],
        [list.topAnchor constraintEqualToAnchor:categories.contentLayoutGuide.topAnchor],
        [list.bottomAnchor constraintEqualToAnchor:categories.contentLayoutGuide.bottomAnchor],
        [list.leadingAnchor constraintEqualToAnchor:categories.contentLayoutGuide.leadingAnchor],
        [list.trailingAnchor constraintEqualToAnchor:categories.contentLayoutGuide.trailingAnchor],
        [list.widthAnchor constraintEqualToAnchor:categories.frameLayoutGuide.widthAnchor],
        [list.heightAnchor constraintGreaterThanOrEqualToAnchor:categories.frameLayoutGuide.heightAnchor],
        [self.detail.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10],
        [self.detail.leadingAnchor constraintEqualToAnchor:categories.trailingAnchor constant:16],
        [self.detail.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.detail.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    self.stack = HaloUIScrollingStack(self.detail, 12);
    __weak HaloSettingsViewController *weakSelf=self;
    self.campaignObserver=[[NSNotificationCenter defaultCenter] addObserverForName:HaloCampaignStateChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note;[weakSelf renderSoon]; }];
    self.connectionTimer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t){(void)t;weakSelf.connectionLabel.text=HaloNetworkSummary();}];
    self.selected = HaloCategoryMultiplayer;
    [self renderDetail];
}

- (void)dealloc { [self.connectionTimer invalidate]; if (self.campaignObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.campaignObserver]; }

- (void)choose:(HaloCategory)category
{
    if(category==HaloCategoryMods) { UIViewController *c=HaloMapsController();c.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:c animated:YES completion:nil];return; }
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
    HaloUIApplyAccent(self.view);
    for (NSInteger i = 0; i < (NSInteger)self.sidebar.count; i++) {
        BOOL on = i == (NSInteger)self.selected;
        self.sidebar[i].backgroundColor = on ? HaloUIAccent() : (i == HaloCategoryLogs ? [UIColor colorWithWhite:0.14 alpha:1] : UIColor.clearColor);
    }
    for (UIView *view in self.stack.arrangedSubviews) { [self.stack removeArrangedSubview:view]; [view removeFromSuperview]; }
    self.stack.userInteractionEnabled = self.selected != HaloCategoryCheats || [[HaloSettingsStore shared] campaignActive];
    HsSettings settings = [[HaloSettingsStore shared] snapshot];
    switch (self.selected) {
        case HaloCategoryMultiplayer: [self buildMultiplayer:&settings]; break;
        case HaloCategoryControls: [self buildControls:&settings]; break;
        case HaloCategoryDisplay: [self buildDisplay:&settings]; break;
        case HaloCategoryAudio: [self buildAudio:&settings]; break;
        case HaloCategoryCheats: [self buildCheats:&settings]; break;
        case HaloCategoryOptions: [self buildOptions:&settings]; break;
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
    self.connectionLabel=HaloUILabel(HaloNetworkSummary(),13,UIFontWeightRegular,HaloUISecondaryText());
    UIButton *refresh=HaloUIButton(@"Refresh",0,^(UIButton *b){(void)b;self.connectionLabel.text=HaloNetworkSummary();});
    [refresh.widthAnchor constraintEqualToConstant:80].active=YES;
    UIStackView *connection=[[UIStackView alloc] initWithArrangedSubviews:@[self.connectionLabel,refresh]];connection.spacing=12;connection.alignment=UIStackViewAlignmentCenter;
    [self add:HaloUICardView(@"Connection status",@[connection])];
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Halo/debug.txt"];
    NSFileHandle *log=[NSFileHandle fileHandleForReadingAtPath:path];NSString *last=nil;
    @try { unsigned long long size=[log seekToEndOfFile];[log seekToFileOffset:size>65536?size-65536:0];NSString *tail=[[NSString alloc] initWithData:[log readDataOfLength:65536] encoding:NSUTF8StringEncoding];
        for(NSString *line in [tail componentsSeparatedByString:@"\n"]) { NSString *lower=line.lowercaseString;
            if([lower containsString:@"timed out"])last=@"A peer stopped responding and timed out.";
            else if([lower containsString:@"connection lost"])last=@"The game reported a lost connection.";
            else if([lower containsString:@"failed to connect"])last=@"The game could not establish a connection.";
        }
    } @catch(NSException *e){(void)e;} @finally {[log closeFile];}
    if(last)[self add:HaloUICardView(@"Last connection event in this log",@[HaloUINote(last)])];
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

    [self add:HaloUICardView(@"Invite file · iCloud Drive", @[
        HaloUINote(HaloInviteFileLocation()),
        HaloUINote(@"Choose a folder in iCloud Drive once. Hosting updates game_invite.txt there. Paste a PC invite into the same file, wait for iCloud to sync, then join below. Ending a hosted game clears only the code this app wrote; a different PC invite is preserved."),
        HaloUIButton(@"Choose iCloud Drive folder", 0, ^(UIButton *b) {
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
            picker.delegate = self;
            picker.allowsMultipleSelection = NO;
            [self presentViewController:picker animated:YES completion:nil];
        }),
        HaloUIButton(@"Join from game_invite.txt", 1, ^(UIButton *b) {
            b.enabled = NO;
            HaloReadInviteFile(^(NSString *text, NSError *error) {
                b.enabled = YES;
                if (error) { halo_ios_toast("Could not read invite file. Check iCloud sync or choose the folder again."); return; }
                if (HaloJoinInviteText(text)) [self dismissViewControllerAnimated:YES completion:nil];
            });
        })])];
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
        HaloUINote(invite ? @"Your current invite is written automatically to game_invite.txt in your selected folder. Share it below." : @"In the game, choose Multiplayer > System Link and start a game. The invite link is made and copied for you; it then appears here."),
        share])];

    [self add:HaloUICardView(@"Options", @[
        HaloUISwitchRow(@"Join links on the clipboard automatically", @"Off by default: reading the clipboard makes iOS ask for permission each time. Opening a halo:// link joins without it.",
                        settings->join_from_clipboard, ^(BOOL on) { [self update:^(HsSettings *s) { s->join_from_clipboard = on; }]; })])];
    [self add:HaloUICardView(@"Finding games on your Wi-Fi", @[
        HaloUINote(@"If games on the same network are not found, check iOS Settings > Privacy & Security > Local Network > Halo CE is on, and that both devices are on the same Wi-Fi.")])];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (!urls.count) return;
    HaloSelectInviteFolder(urls.firstObject, ^(NSError *error) {
        halo_ios_toast(error ? "Could not access that folder. Choose a writable iCloud Drive folder." : "Invite folder saved. game_invite.txt is ready there.");
        [self renderSoon];
    });
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
        UIButton *gear=HaloUIButton(@"",0,^(UIButton *b) { [self editPreset:i]; });
        [gear setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
        gear.accessibilityLabel=@"Edit preset";[gear.widthAnchor constraintEqualToConstant:48].active=YES;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[choose, gear, rename]];
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

- (UIView *)hudChoiceRow:(int)index {
    HsSettings current=[HaloSettingsStore.shared snapshot];NSMutableArray *names=[NSMutableArray arrayWithObject:@"Default"];
    for(int i=0;i<3;i++)[names addObject:[NSString stringWithUTF8String:current.hud_presets[i].name]];
    return HaloUISegmentRow(@"Game HUD preset",names,current.presets[index].hud_choice,^(NSInteger choice){[self update:^(HsSettings *s){s->presets[index].hud_choice=(int)choice;}];});
}
- (UIView *)startupRow:(int)index {
    HsSettings current=[HaloSettingsStore.shared snapshot];
    return HaloUISegmentRow(@"On app launch",@[@"Start Halo screen",@"Boot Halo immediately"],current.presets[index].startup_auto,^(NSInteger choice){[self update:^(HsSettings *s){s->presets[index].startup_auto=(int)choice;}];});
}
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
        HaloUISwitchRow(@"Show FPS", @"Display the frame-rate counter.", settings->show_fps, ^(BOOL on) { [self update:^(HsSettings *s) { s->show_fps = on; }]; }),
        HaloUINote(@"Switching between 30 and the other two takes effect the next time you open the app. Switching between 60 and Uncapped takes effect now.")])];

    [self add:HaloUICardView(@"Game HUD profile",@[[self hudChoiceRow:settings->active]])];
    [self add:HaloUICardView(@"Game HUD and FPS",@[
        HaloUINote(@"Separate controls for the game’s meters and FPS counter."),
        HaloUIButton(@"Edit game HUD",1,^(UIButton *b){(void)b;UIViewController *root=self.presentingViewController;[self dismissViewControllerAnimated:YES completion:^{UIViewController *editor=[HaloHudEditor new];editor.modalPresentationStyle=UIModalPresentationOverFullScreen;[root presentViewController:editor animated:YES completion:nil];}];})])];
    [self add:HaloUICardView(@"First-person view", @[
        HaloUISegmentRow(nil, @[@"Both", @"Weapon", @"Hands", @"Hidden"], settings->viewmodel_mode, ^(NSInteger i) {
            [self update:^(HsSettings *s) { s->viewmodel_mode = (int)i; }];
        }),
        HaloUINote(@"Choose which first-person models are visible. Changes apply immediately and do not affect your HUD, attacks or other players.")])];

    [self add:HaloUICardView(@"HUD and text", @[
        HaloUISwitchRow(@"High-res HUD", @"Sharper meters, radar and reticles.", settings->hires_hud, ^(BOOL on) { [self update:^(HsSettings *s) { s->hires_hud = on; }]; }),
        HaloUISwitchRow(@"High-res text", @"Menus and HUD text at the screen's resolution.", settings->hires_text, ^(BOOL on) { [self update:^(HsSettings *s) { s->hires_text = on; }]; }),
        HaloUINote(@"New in Halo CE Universal build 73 and off until you try them. They apply the next time you open the app; turn them off again if menus or the HUD stutter.")])];


}

#pragma mark - Audio

- (void)buildAudio:(const HsSettings *)settings
{
    [self add:HaloUICardView(@"Sound", @[
        HaloUISwitchRow(@"Sound", nil, settings->audio_enabled, ^(BOOL on) { [self update:^(HsSettings *s) { s->audio_enabled = on; }]; }),
        HaloUISliderRow(@"Master volume", 0.0f, 1.0f, settings->volume, @"%.2f", ^(float v) { [self update:^(HsSettings *s) { s->volume = v; }]; }),
        HaloUISliderRow(@"Music",0,1,settings->music_volume,@"%.2f",^(float v){[self update:^(HsSettings *s){s->music_volume=v;}];}),
        HaloUISliderRow(@"Dialogue",0,1,settings->dialogue_volume,@"%.2f",^(float v){[self update:^(HsSettings *s){s->dialogue_volume=v;}];}),
        HaloUISliderRow(@"Effects",0,1,settings->effects_volume,@"%.2f",^(float v){[self update:^(HsSettings *s){s->effects_volume=v;}];}),
        HaloUINote(@"Halo plays even when the ring/silent switch is on, like a game console.")])];
}

#pragma mark - Cheats

- (void)buildCheats:(const HsSettings *)settings
{
    [self add:HaloUINote(@"The selected control preset activates its saved cheat recipe automatically in solo campaign. Multiplayer disables all cheats.")];
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
        HaloUINote(@"Power-ups have dedicated sections below.")])];
    [self add:HaloUICardView(@"Active Camo",@[
        HaloUISwitchRow(@"Infinite Active Camo",@"Maintains camouflage while enabled in this campaign session.",settings->cheat_camo,^(BOOL on){[self update:^(HsSettings *s){s->cheat_camo=on;}];}),
        HaloUIButton(@"Spawn Active Camo",0,^(UIButton *b){[self queueCampaignAction:3];}),
        HaloUIButton(@"Apply Active Camo",0,^(UIButton *b){[self queueCampaignAction:1];}),
        HaloUINote(@"Apply is a single timed pickup. Infinite is a separate toggle.")])];
    [self add:HaloUICardView(@"Overshield",@[
        HaloUISwitchRow(@"Infinite Overshield",@"Replenishes the reserve while enabled in this campaign session.",settings->cheat_overshield,^(BOOL on){[self update:^(HsSettings *s){s->cheat_overshield=on;}];}),
        HaloUIButton(@"Spawn Overshield",0,^(UIButton *b){[self queueCampaignAction:2];}),
        HaloUIButton(@"Apply Overshield",0,^(UIButton *b){[self queueCampaignAction:4];}),
        HaloUINote(@"Apply charges once and follows Halo’s normal shield depletion rules. It does not continually refill.")])];
    [self add:HaloUICardView(nil, @[HaloUINote(@"Changes apply within a moment, also in the middle of a mission.")])];
}

- (void)queueCampaignAction:(uint32_t)action
{
    if (![[HaloSettingsStore shared] campaignActive]) { halo_ios_toast("Start a solo campaign before using cheats");return; }
    if (!halo_ios_queue_campaign_action(action)) halo_ios_toast("The campaign action queue is full or unavailable");
}

- (void)chooseCampaignAsset:(NSString *)title names:(NSArray<NSString *> *)names base:(uint32_t)base
{
    [self presentChoices:title names:names from:self pick:^(NSUInteger index) { [self queueCampaignAction:base+(uint32_t)index]; }];
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

- (void)presentChoices:(NSString *)title names:(NSArray<NSString *> *)names from:(UIViewController *)presenter pick:(void (^)(NSUInteger))pick {
    HaloOptionPicker *list=[[HaloOptionPicker alloc] initWithStyle:UITableViewStyleInsetGrouped];
    list.title=title;list.choices=names;list.pick=pick;
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:list];
    navigation.modalPresentationStyle=UIModalPresentationFullScreen;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
- (void)editPreset:(int)index {
    HsSettings current=[[HaloSettingsStore shared] snapshot];HsPreset p=current.presets[index];
    UIViewController *editor=[UIViewController new];editor.title=[NSString stringWithUTF8String:p.name];
    editor.view.backgroundColor=HaloUIBackground();
    __weak UIViewController *weakEditor=editor;
    UIView *content=[UIView new];content.translatesAutoresizingMaskIntoConstraints=NO;[editor.view addSubview:content];
    [NSLayoutConstraint activateConstraints:@[[content.topAnchor constraintEqualToAnchor:editor.view.safeAreaLayoutGuide.topAnchor],[content.bottomAnchor constraintEqualToAnchor:editor.view.safeAreaLayoutGuide.bottomAnchor],[content.leadingAnchor constraintEqualToAnchor:editor.view.safeAreaLayoutGuide.leadingAnchor constant:16],[content.trailingAnchor constraintEqualToAnchor:editor.view.safeAreaLayoutGuide.trailingAnchor constant:-16]]];
    UIStackView *rows=HaloUIScrollingStack(content,12);
    [rows addArrangedSubview:HaloUILabel([NSString stringWithUTF8String:p.name],22,UIFontWeightBold,nil)];
    [rows addArrangedSubview:HaloUIButton(@"Done",1,^(UIButton *b) { [weakEditor dismissViewControllerAnimated:YES completion:nil];[self renderSoon]; })];
    [rows addArrangedSubview:HaloUINote(@"Recipes activate when you select this preset or enter a solo campaign. One-shot items run once per activation; multiplayer always disables cheats.")];
    [rows addArrangedSubview:[self hudChoiceRow:index]];
    [rows addArrangedSubview:[self startupRow:index]];
    [rows addArrangedSubview:HaloUISegmentRow(@"Face buttons",@[@"Classic Xbox UI",@"Playstation UI"],p.face_style,^(NSInteger value) { [self update:^(HsSettings *s) { s->presets[index].face_style=(int)value; }]; })];
    NSArray<NSString *> *names=@[@"God mode",@"Infinite ammo",@"Infinite grenades",@"Bottomless clip",@"One-hit kills",@"Unlimited flashlight",@"No fall damage",@"Rapid fire",@"No recoil",@"Third person",@"Noclip",@"Infinite Active Camo",@"Infinite Overshield"];
    for (NSUInteger bit=0;bit<names.count;++bit) {
        unsigned flag=1u<<(unsigned)bit;
        [rows addArrangedSubview:HaloUISwitchRow(names[bit],nil,!!(p.cheat_flags&flag),^(BOOL on) { [self update:^(HsSettings *s) { if (on) s->presets[index].cheat_flags|=flag;else s->presets[index].cheat_flags&=~flag; }]; })];
    }
    NSArray<NSString *> *actions=@[@"Spawn Active Camo",@"Spawn Overshield",@"Apply Active Camo",@"Apply Overshield"];
    for (NSUInteger bit=0;bit<actions.count;++bit) {
        unsigned flag=1u<<(unsigned)bit;
        [rows addArrangedSubview:HaloUISwitchRow(actions[bit],@"Run once when applying the recipe",!!(p.cheat_actions&flag),^(BOOL on) { [self update:^(HsSettings *s) { if (on) s->presets[index].cheat_actions|=flag;else s->presets[index].cheat_actions&=~flag; }]; })];
    }
    NSArray<NSString *> *weapons=@[@"None",@"Pistol",@"Assault rifle",@"Shotgun",@"Sniper rifle",@"Rocket launcher",@"Plasma pistol",@"Plasma rifle",@"Needler",@"Flamethrower",@"Gravity rifle"];
    UIButton *weapon=HaloUIButton([@"Weapon giver: " stringByAppendingString:weapons[(NSUInteger)p.cheat_weapon]],0,^(UIButton *button) {
        [self presentChoices:@"Preset weapon giver" names:weapons from:weakEditor pick:^(NSUInteger choice) {
            [self update:^(HsSettings *s) { s->presets[index].cheat_weapon=(int)choice; }];
            [button setTitle:[@"Weapon giver: " stringByAppendingString:weapons[choice]] forState:UIControlStateNormal];
        }];
    });[rows addArrangedSubview:weapon];
    NSArray<NSString *> *values=@[@"Super jump",@"Super speed",@"Vertical FOV"];
    for (int field=0;field<3;++field) {
        float value=field==0?p.cheat_jump:field==1?p.cheat_speed:p.cheat_fov;
        UIButton *number=HaloUIButton([NSString stringWithFormat:@"%@: %.1f",values[field],value],0,^(UIButton *button) {
            HsSettings latest=[[HaloSettingsStore shared] snapshot];HsPreset recipe=latest.presets[index];
            float initial=field==0?recipe.cheat_jump:field==1?recipe.cheat_speed:recipe.cheat_fov;
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:values[field] message:field==2?@"0 = default; 20–90 degrees":field==0?@"1–10 multiplier":@"1–5 multiplier" preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField *text) { text.keyboardType=UIKeyboardTypeDecimalPad;text.text=[NSString stringWithFormat:@"%.1f",initial]; }];
            [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                NSScanner *scanner=[NSScanner scannerWithString:alert.textFields.firstObject.text?:@""];float v;
                if (![scanner scanFloat:&v]||!scanner.isAtEnd||!isfinite(v)|| (field==2 ? (v!=0&&(v<20||v>90)) : (v<1||v>(field==0?10:5)))) { halo_ios_toast("Enter a value in the displayed range");return; }
                [self update:^(HsSettings *s) { if (field==0) s->presets[index].cheat_jump=v;else if(field==1) s->presets[index].cheat_speed=v;else s->presets[index].cheat_fov=v; }];
                [button setTitle:[NSString stringWithFormat:@"%@: %.1f",values[field],v] forState:UIControlStateNormal];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [weakEditor presentViewController:alert animated:YES completion:nil];
        });[rows addArrangedSubview:number];
    }
    editor.modalPresentationStyle=UIModalPresentationFullScreen;
    [self presentViewController:editor animated:YES completion:^{ UIScrollView *scroll=(UIScrollView *)rows.superview;[scroll setContentOffset:CGPointMake(0,-scroll.adjustedContentInset.top) animated:NO]; }];
}

#pragma mark - Advanced

- (void)buildOptions:(const HsSettings *)settings {
    [self add:HaloUICardView(@"Settings button",@[
        HaloUISliderRow(@"Size",.75f,1.75f,settings->gear_scale,@"%.2f×",^(float value){[self update:^(HsSettings *s){s->gear_scale=value;}];}),
        HaloUINote(@"Touch and hold the gear to move it. Its touch target remains at least 44 points."),
        HaloUIButton(@"Reset size and position",0,^(UIButton *button){(void)button;[self update:^(HsSettings *s){s->gear_scale=1;s->gear_placed=0;}];[self renderSoon];})])];
    [self add:HaloUICardView(@"Color scheme",@[
        HaloUISegmentRow(@"Accent color",@[@"Blue",@"Green",@"Purple",@"Amber",@"Rose"],settings->ui_theme,^(NSInteger value){[self update:^(HsSettings *s){s->ui_theme=(int)value;}];[self renderSoon];}),
        HaloUINote(@"Applies to Settings buttons, switches, sliders and selections. Gameplay control colors remain part of your control profile.")])];
}
- (void)buildAdvanced:(const HsSettings *)settings
{
    [self add:HaloUICardView(@"Game",@[
        HaloUIButton(@"Quit Game",2,^(UIButton *b) { [self confirmAppQuit]; })])];
    [self add:HaloUICardView(@"Startup",@[[self startupRow:settings->active],HaloUINote(@"Saved with the current control profile. A recovery start always pauses at Start Halo.")])];
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

    [self add:HaloUICardView(@"Backups",@[
        HaloUINote(@"Save profiles, progress, preferences and layouts. Maps are optional. Export through Files; restore safely on the next launch."),
        HaloUIButton(@"Manage backups",1,^(UIButton *b){(void)b;UIViewController *c=HaloBackupsController();c.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:c animated:YES completion:nil];})])];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    [self add:HaloUICardView(@"About", @[
        HaloUIValueRow(@"App version", version, nil),
        HaloUIValueRow(@"Game", @"Halo CE Universal build 73", nil),
        HaloUINote(@"Everyone in a multiplayer game must be on the same game build.")])];
    [self add:HaloUICardView(@"Credits",@[
        HaloUINote(@"Halo CE Universal and the iOS port contributors."),
        HaloUIButton(@"Halo-CE-IOS on GitHub",0,^(UIButton *b) { [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/xSkullHD/Halo-CE-IOS"] options:@{} completionHandler:nil]; })])];
}
- (void)confirmAppQuit {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Quit Halo" message:@"Close Halo completely? Unsaved progress will be lost." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Quit" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { halo_ios_quit_app(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
