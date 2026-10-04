#import "HaloSettingsViewController.h"
#import "HaloSettingsStore.h"
#import "HaloUI.h"
#import "HaloLibrary.h"
#import "HaloHudEditor.h"
#import "halo_ios_platform.h"
#import "halo_color.h"
#import "halo_ios_audio.h"
#import "halo_pad_input.h"
#import <CoreImage/CoreImage.h>
#import <sys/utsname.h>

static NSString *HaloAge(NSTimeInterval stamp);   /* defined further down; the Multiplayer screen uses it first */
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
    HaloCategoryMultiplayer = 0, HaloCategoryControls, HaloCategoryDisplay, HaloCategoryAudio, HaloCategoryCheats, HaloCategoryMods, HaloCategoryProfiles, HaloCategoryOptions, HaloCategoryAdvanced,
    HaloCategoryLogs, HaloCategoryCount
};

@interface HaloSettingsViewController () <UITextFieldDelegate, UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate>
@property(nonatomic, strong) UIView *detail;
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) NSArray<UIButton *> *sidebar;
@property(nonatomic) HaloCategory selected;
@property(nonatomic,strong) id campaignObserver;
@property(nonatomic,strong) NSTimer *connectionTimer;
@property(nonatomic,strong) NSTimer *chromaTimer;
@property(nonatomic,strong) NSMutableSet<NSString *> *openCheatSections;
@property(nonatomic) NSInteger pickerKind; /* 0 invite folder, 2 profile import */
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
        case HaloCategoryProfiles: return @"Profiles";
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
        case HaloCategoryProfiles: return @"person.crop.rectangle.fill";
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
        UIImage *icon = [[UIImage systemImageNamed:HaloCategorySymbol((HaloCategory)i)] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        row.accessibilityIdentifier = @"HaloSidebarRow";   /* HaloUIApplyAccent leaves these white */
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
    self.chromaTimer=[NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t){(void)t;
        HaloSettingsViewController *strong=weakSelf;
        if(!strong||!strong.isViewLoaded||!strong.view.window)return;
        if([[HaloSettingsStore shared] snapshot].accent_mode!=2)return;
        HaloUIApplyAccent(strong.view);[strong paintSidebar];}];
    self.selected = HaloCategoryMultiplayer;
    [self renderDetail];
}

- (void)paintSidebar {
    for (NSInteger i = 0; i < (NSInteger)self.sidebar.count; i++) {
        BOOL on = i == (NSInteger)self.selected;
        self.sidebar[i].backgroundColor = on ? HaloUIAccent() : (i == HaloCategoryLogs ? [UIColor colorWithWhite:0.14 alpha:1] : UIColor.clearColor);
    }
}

- (void)dealloc { [self.chromaTimer invalidate];[self.connectionTimer invalidate]; if (self.campaignObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.campaignObserver]; }

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
    self.stack.userInteractionEnabled = YES;   /* the Cheats sections can always be opened; their controls are disabled outside a solo campaign */
    HsSettings settings = [[HaloSettingsStore shared] snapshot];
    switch (self.selected) {
        case HaloCategoryMultiplayer: [self buildMultiplayer:&settings]; break;
        case HaloCategoryControls: [self buildControls:&settings]; break;
        case HaloCategoryDisplay: [self buildDisplay:&settings]; break;
        case HaloCategoryAudio: [self buildAudio:&settings]; break;
        case HaloCategoryCheats: [self buildCheats:&settings]; break;
        case HaloCategoryProfiles: [self buildProfiles:&settings]; break;
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
            self.pickerKind = 0;
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

    NSString *hostingInvite = HaloLastHostedInvite();
    if (hostingInvite) {
        [self add:HaloUICardView(@"Invite QR code", @[
            HaloUINote(@"Someone next to you can point their camera at this to open the invite in Halo."),
            HaloUIButton(@"Show QR code", 1, ^(UIButton *b) { (void)b; [self showQR:hostingInvite]; })])];
    }
    NSArray<NSDictionary *> *recent = HaloRecentGames();
    NSMutableArray<UIView *> *recentRows = [NSMutableArray array];
    if (!recent.count) [recentRows addObject:HaloUINote(@"Games you host or join appear here. An invite stops working when the host ends the game, so Join again only works while that game is still running.")];
    for (NSDictionary *entry in recent) {
        NSString *invite = entry[@"invite"];
        NSString *tail = invite.length > 8 ? [invite substringFromIndex:invite.length - 8] : invite;
        NSString *title = [NSString stringWithFormat:@"%@ · %@ · …%@", entry[@"role"] ?: @"Joined", HaloAge([entry[@"date"] doubleValue]), tail];
        UIButton *join = HaloUIButton(@"Join again", 1, ^(UIButton *b) { (void)b; if (HaloJoinInviteText(invite)) [self dismissViewControllerAnimated:YES completion:nil]; });
        UIButton *qr = HaloUIButton(@"QR", 0, ^(UIButton *b) { (void)b; [self showQR:invite]; });
        [qr.widthAnchor constraintEqualToConstant:70].active = YES;
        UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[join, qr]];
        line.spacing = 8;
        [recentRows addObject:HaloUILabel(title, 14, UIFontWeightRegular, HaloUISecondaryText())];
        [recentRows addObject:line];
    }
    if (recent.count) [recentRows addObject:HaloUIButton(@"Clear recent games", 2, ^(UIButton *b) { (void)b; HaloClearRecentGames(); [self renderSoon]; })];
    [self add:HaloUICardView(@"Recent games", recentRows)];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (!urls.count) return;
    if (self.pickerKind == 2) {   /* a profile file to import */
        self.pickerKind = 0;
        NSData *data = [NSData dataWithContentsOfURL:urls.firstObject options:0 error:nil];
        NSString *text = (data.length >= 8 && data.length <= 65536) ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        HsSettings imported;
        if (!text || !hs_parse(&imported, text.UTF8String)) { halo_ios_toast("That is not a Halo profile file"); return; }
        hs_clear_cheats(&imported);
        [self update:^(HsSettings *s) { *s = imported; }];
        halo_ios_toast("Profile imported");
        [self renderSoon];
        return;
    }
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

    [self add:HaloUICardView(@"Touch aiming", @[
        HaloUISwitchRow(@"Auto-fire on enemies", @"Fire while using touch controls when the crosshair directly meets a living enemy. Physical controllers are unaffected.", preset.auto_fire, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].auto_fire = on; }]; }),
        HaloUISwitchRow(@"Aim with the Fire button", @"Hold Fire and drag to look without lifting your finger.", preset.fire_drag, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].fire_drag = on; }]; }),
        HaloUISwitchRow(@"Fire with the right stick", @"Moving the right stick also holds Fire. Re-centre or release to stop firing.", preset.stick_fire, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].stick_fire = on; }]; }),
        HaloUINote(@"These options are saved with your control scheme. Auto-fire requires touch input and does not act in menus or cinematics.")])];

    [self add:HaloUICardView(@"Sticks", @[
        HaloUISwitchRow(@"Floating sticks", @"The stick starts where your thumb lands.", preset.floating_sticks, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].floating_sticks = on; }]; }),
        HaloUISliderRow(@"Dead zone", 0.0f, 0.4f, preset.stick_dead_zone, @"%.2f", ^(float v) { [self update:^(HsSettings *s) { s->presets[s->active].stick_dead_zone = v; }]; }),
        HaloUISliderRow(@"Move stick response", 1.0f, 3.0f, preset.move_curve, @"%.1f", ^(float v) { [self update:^(HsSettings *s) { s->presets[s->active].move_curve = v; }]; }),
        HaloUINote(@"Response above 1.0 gives finer control near the centre.")])];

    [self add:HaloUICardView(@"Buttons", @[
        HaloUISliderRow(@"Opacity", 0.25f, 1.0f, preset.opacity, @"%.2f", ^(float v) { [self update:^(HsSettings *s) { s->presets[s->active].opacity = v; }]; }),
        HaloUISwitchRow(@"Haptic feedback", nil, preset.haptics, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].haptics = on; }]; })])];

    /* ---- this profile: left-handed layout and latching buttons */
    unsigned toggleMask = preset.toggle_mask;
    [self add:HaloUICardView(@"Layout and latching", @[
        HaloUISwitchRow(@"Left-handed layout", @"Mirrors the whole layout: move with the right thumb, look and the face buttons on the left. Layouts you edit stay in the unmirrored layout and are mirrored when drawn.", preset.mirror, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].mirror = on; }]; }),
        HaloUISwitchRow(@"Toggle crouch", @"One tap on the left stick click crouches, the next tap stands up, instead of holding it down.", !!(toggleMask & (1u << HC_LS)), ^(BOOL on) {
            [self update:^(HsSettings *s) { unsigned m = s->presets[s->active].toggle_mask; s->presets[s->active].toggle_mask = on ? (m | (1u << HC_LS)) : (m & ~(1u << HC_LS)); }]; }),
        HaloUISwitchRow(@"Toggle zoom", @"One tap on the right stick click zooms, the next tap zooms out.", !!(toggleMask & (1u << HC_RS)), ^(BOOL on) {
            [self update:^(HsSettings *s) { unsigned m = s->presets[s->active].toggle_mask; s->presets[s->active].toggle_mask = on ? (m | (1u << HC_RS)) : (m & ~(1u << HC_RS)); }]; })])];

    /* ---- this profile: gyro aiming */
    [self add:HaloUICardView(@"Gyro aiming", @[
        HaloUISwitchRow(@"Aim by turning the device", @"Fine aim comes from tilting and turning the phone while you hold it; keep using the stick or drag for big turns.", preset.gyro, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].gyro = on; }]; }),
        HaloUISliderRow(@"Gyro speed", 0.25f, 3.0f, preset.gyro_sens, @"%.2f×", ^(float v) { [self update:^(HsSettings *s) { s->presets[s->active].gyro_sens = v; }]; }),
        HaloUISwitchRow(@"Flip left and right", @"Turn this on if the view turns the wrong way when you turn the device.", preset.gyro_flip_yaw, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].gyro_flip_yaw = on; }]; }),
        HaloUISwitchRow(@"Flip up and down", @"Turn this on if the view tilts the wrong way when you tilt the device.", preset.gyro_flip_pitch, ^(BOOL on) { [self update:^(HsSettings *s) { s->presets[s->active].gyro_flip_pitch = on; }]; }),
        HaloUINote(@"Gyro also moves the view in menus. If the direction is wrong in one landscape orientation, use the two flip switches; they apply to this profile.")])];

    /* ---- a physical controller: stick feel and which button does what (all profiles) */
    NSMutableArray<UIView *> *padRows = [NSMutableArray array];
    [padRows addObject:HaloUINote(@"For a connected Xbox, PlayStation or other controller. The defaults pass the stick straight through.")];
    [padRows addObject:HaloUISliderRow(@"Stick dead zone", 0.0f, 0.4f, settings->pad_dead, @"%.2f", ^(float v) { [self update:^(HsSettings *s) { s->pad_dead = v; }]; })];
    [padRows addObject:HaloUISliderRow(@"Stick response", 1.0f, 3.0f, settings->pad_curve, @"%.1f", ^(float v) { [self update:^(HsSettings *s) { s->pad_curve = v; }]; })];
    [padRows addObject:HaloUINote(@"The dead zone is removed rather than cut off, so movement still starts from zero. A response above 1.0 gives finer control near the centre.")];
    [self add:HaloUICardView(@"Controller", padRows)];

    NSMutableArray<NSString *> *buttonNames = [NSMutableArray array];
    for (int b = 0; b < HP_BUTTONS; b++) [buttonNames addObject:[NSString stringWithUTF8String:hp_names[b]]];
    if (!self.openCheatSections) self.openCheatSections = [NSMutableSet set];
    BOOL remapOpen = [self.openCheatSections containsObject:@"Controller button remap"];
    [self add:HaloUIDisclosureHeader(@"Controller button remap", hp_is_identity(settings->pad_map) ? @"Standard layout" : @"Changed", remapOpen, ^{
        if (remapOpen) [self.openCheatSections removeObject:@"Controller button remap"]; else [self.openCheatSections addObject:@"Controller button remap"];
        [self renderSoon];
    })];
    if (remapOpen) {
        NSMutableArray<UIView *> *remap = [NSMutableArray array];
        [remap addObject:HaloUINote(@"Choose what each physical button does. Two buttons can do the same thing.")];
        for (int b = 0; b < HP_BUTTONS; b++) {
            int source = b;
            NSString *title = [NSString stringWithFormat:@"%s  →  %s", hp_names[b], hp_names[settings->pad_map[b] < HP_BUTTONS ? settings->pad_map[b] : b]];
            [remap addObject:HaloUIButton(title, settings->pad_map[b] == b ? 0 : 1, ^(UIButton *button) { (void)button;
                [self presentChoices:[NSString stringWithFormat:@"When you press %s", hp_names[source]] names:buttonNames from:self pick:^(NSUInteger choice) {
                    [self update:^(HsSettings *s) { s->pad_map[source] = (unsigned char)(choice < HP_BUTTONS ? choice : (NSUInteger)source); }];
                    [self renderSoon];
                }];
            })];
        }
        [remap addObject:HaloUIButton(@"Reset to the standard layout", 2, ^(UIButton *button) { (void)button;
            [self update:^(HsSettings *s) { for (int b = 0; b < HP_BUTTONS; b++) s->pad_map[b] = (unsigned char)b; }];
            [self renderSoon];
        })];
        [self add:HaloUICardView(nil, remap)];
    }
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

    [self add:HaloUICardView(@"Game picture", @[
        HaloUISegmentRow(@"Aspect ratio", @[@"Default · 4:3", @"Widescreen · 16:9", @"Fullscreen"], settings->display_mode, ^(NSInteger i) { [self update:^(HsSettings *s) { s->display_mode = (int)i; }]; }),
        HaloUISegmentRow(@"Render detail", @[@"Standard · 480p", @"High · 720p", @"Very high · 960p"], settings->render_quality, ^(NSInteger i) { [self update:^(HsSettings *s) { s->render_quality = (int)i; }]; }),
        HaloUINote(@"A wider picture shows more of the scene without stretching it. Fullscreen matches your device. Higher detail draws more pixels and uses more power; Standard is the performance default. Picture changes apply on the next app launch.")])];
    [self add:HaloUICardView(@"AirPlay and external screens", @[
        HaloUINote(@"Open iOS Control Center, choose Screen Mirroring, then select your Apple TV or compatible AirPlay display. You can also connect a supported display adapter. The game and touch controls are mirrored together. Use a physical controller for a clearer TV view. Your device and AirPlay receiver must be on a network that supports discovery; latency depends on the connection.")])];

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


    [self add:HaloUICardView(@"Heat and battery", @[
        HaloUISwitchRow(@"Lower the frame rate when the phone is hot", @"Smooth 60 and Uncapped drop to 45 when iOS reports serious heat or Low Power Mode, and to 30 when it is critical, and return when the phone cools. The original 30 FPS mode is never changed.", settings->thermal_cap, ^(BOOL on) { [self update:^(HsSettings *s) { s->thermal_cap = on; }]; }),
        HaloUISwitchRow(@"Performance overlay", @"Under the frame rate: how long a frame takes, the app's memory and what is left before iOS closes it, and how hot the phone is.", settings->perf_overlay, ^(BOOL on) { [self update:^(HsSettings *s) { s->perf_overlay = on; }]; })])];
    [self add:HaloUICardView(@"Menus", @[
        HaloUISegmentRow(nil, @[@"PC menus (new)", @"Xbox menus"], settings->menu_style, ^(NSInteger index) {
            [self update:^(HsSettings *s) { s->menu_style = (int)index; }]; [self renderSoon]; }),
        HaloUINote(settings->menu_style == 0
            ? @"The Halo Custom Edition menus from Halo CE Universal: Join Game (LAN and Direct Link; the public Server Browser list is still empty upstream), Create Game for the Internet or your LAN, and the redrawn screens. Navigate with the on-screen D-pad, A and B, or a controller."
            : @"The original Xbox menus, including System Link."),
        HaloUINote(@"Takes effect the next time you open the app. If the game ever fails to start, the next start (Safe Start) uses the Xbox menus automatically.")])];
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
    [self add:HaloUICardView(@"Ambient sound", @[
        HaloUISliderRow(@"Ambient volume", 0.0f, 1.0f, settings->ambient_volume, @"%.2f", ^(float v) { [self update:^(HsSettings *s) { s->ambient_volume = v; }]; }),
        HaloUINote(@"The environment: water, wind, machinery and computer hum, and the sounds of doors and devices. If a strange background noise bothers you, lower this to find out whether it is one of these.")])];
    [self add:HaloUICardView(@"If sound misbehaves", @[
        HaloUIButton(@"Restart audio output", 0, ^(UIButton *b) { (void)b; halo_ios_audio_restart(); halo_ios_toast("Audio output restarted"); }),
        HaloUINote(@"Stops and starts the phone's audio engine without touching the game. Try it if sound cuts out or crackles after a call, headphones or Bluetooth changes.")])];
}

#pragma mark - Cheats

- (void)addCheatSection:(NSString *)title summary:(NSString *)summary views:(NSArray<UIView *> *)views
{
    if (!self.openCheatSections) self.openCheatSections = [NSMutableSet set];
    BOOL open = [self.openCheatSections containsObject:title];
    [self add:HaloUIDisclosureHeader(title, summary, open, ^{
        if (open) [self.openCheatSections removeObject:title]; else [self.openCheatSections addObject:title];
        [self renderSoon];
    })];
    if (open) {
        BOOL usable = [[HaloSettingsStore shared] campaignActive];
        for (UIView *view in views) { view.userInteractionEnabled = usable; view.alpha = usable ? 1.f : 0.45f; [self add:view]; }
    }
}

static NSString *HaloOnCount(int count) { return count ? [NSString stringWithFormat:@"%d on", count] : @"All off"; }

- (void)buildCheats:(const HsSettings *)settings
{
    [self add:HaloUINote(@"The selected control preset activates its saved cheat recipe automatically in solo campaign. Multiplayer disables all cheats.")];
    [self add:HaloUINote(@"Tap a section to open it. Everything here works only in the solo campaign and switches itself off in multiplayer and network games.")];
#define CHEAT_SWITCH(title, sub, field) HaloUISwitchRow(title, sub, settings->field, ^(BOOL on) { [self update:^(HsSettings *s) { s->field = on; }]; })
    NSMutableArray<UIView *> *cards;

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(nil, @[
        CHEAT_SWITCH(@"God mode", @"You cannot die.", cheat_god),
        CHEAT_SWITCH(@"One-hit kills", @"Hostile units only; friendly units are protected.", cheat_one_hit),
        CHEAT_SWITCH(@"No fall damage", @"The local player takes no falling or collision damage.", cheat_no_fall),
        HaloUIButton(@"Restore health and shield", 0, ^(UIButton *b) { (void)b; [self queueCampaignAction:10]; }),
        HaloUINote(@"Restore fills health and the normal shield once; an over-charged shield is never lowered. Ammo is covered by Infinite ammo.")])];
    [self addCheatSection:@"Survival" summary:HaloOnCount(settings->cheat_god + settings->cheat_one_hit + settings->cheat_no_fall) views:cards];

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(nil, @[
        CHEAT_SWITCH(@"Infinite ammo", @"Weapons never run out; plasma weapons never need a new battery.", cheat_ammo),
        CHEAT_SWITCH(@"Infinite grenades", @"Throw as many as you like.", cheat_grenades),
        CHEAT_SWITCH(@"Bottomless clip", @"A magazine never empties.", cheat_reload),
        CHEAT_SWITCH(@"Rapid fire", @"Removes shot-rate and trigger-latch delays; charging and overheating remain.", cheat_rapid),
        CHEAT_SWITCH(@"No recoil", @"Removes the weapon kick; projectile spread is unchanged.", cheat_no_recoil)])];
    [self addCheatSection:@"Weapons" summary:HaloOnCount(settings->cheat_ammo + settings->cheat_grenades + settings->cheat_reload + settings->cheat_rapid + settings->cheat_no_recoil) views:cards];

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(@"Active Camo",@[
        HaloUISwitchRow(@"Infinite Active Camo",@"Maintains camouflage while enabled in this campaign session.",settings->cheat_camo,^(BOOL on){[self update:^(HsSettings *s){s->cheat_camo=on;}];}),
        HaloUIButton(@"Spawn Active Camo",0,^(UIButton *b){[self queueCampaignAction:3];}),
        HaloUIButton(@"Apply Active Camo",0,^(UIButton *b){[self queueCampaignAction:1];}),
        HaloUINote(@"Apply is a single timed pickup. Infinite is a separate toggle.")])];
    [cards addObject:HaloUICardView(@"Overshield",@[
        HaloUISwitchRow(@"Infinite Overshield",@"Replenishes the reserve while enabled in this campaign session.",settings->cheat_overshield,^(BOOL on){[self update:^(HsSettings *s){s->cheat_overshield=on;}];}),
        HaloUIButton(@"Spawn Overshield",0,^(UIButton *b){[self queueCampaignAction:2];}),
        HaloUIButton(@"Apply Overshield",0,^(UIButton *b){[self queueCampaignAction:4];}),
        HaloUINote(@"Apply charges once and follows Halo’s normal shield depletion rules. It does not continually refill.")])];
    [self addCheatSection:@"Power-ups" summary:HaloOnCount(settings->cheat_camo + settings->cheat_overshield) views:cards];

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(nil, @[
        CHEAT_SWITCH(@"Jetpack", @"The game's own jetpack: hold jump to rise.", cheat_jetpack),
        CHEAT_SWITCH(@"Noclip", @"Fly through walls. Aim to move; jump rises and crouch descends. Disable inside clear space.", cheat_noclip)])];
    [cards addObject:HaloUICardView(@"Super jump", @[HaloUISliderRow(@"Value", 1, 10, settings->cheat_jump, @"%.1f", ^(float value) { [self update:^(HsSettings *s) { s->cheat_jump = value; }]; }), HaloUIButton(@"Enter value", 0, ^(UIButton *b) { HsSettings current = [[HaloSettingsStore shared] snapshot]; [self enterCampaignValue:@"Super jump" value:current.cheat_jump minimum:1 maximum:10 apply:^(float value) { [self update:^(HsSettings *s) { s->cheat_jump = value; }]; }]; })])];
    [cards addObject:HaloUICardView(@"Player speed", @[HaloUISliderRow(@"Value", 1, 5, settings->cheat_speed, @"%.1f", ^(float value) { [self update:^(HsSettings *s) { s->cheat_speed = value; }]; }), HaloUIButton(@"Enter value", 0, ^(UIButton *b) { HsSettings current = [[HaloSettingsStore shared] snapshot]; [self enterCampaignValue:@"Player speed" value:current.cheat_speed minimum:1 maximum:5 apply:^(float value) { [self update:^(HsSettings *s) { s->cheat_speed = value; }]; }]; })])];
    [self addCheatSection:@"Movement" summary:HaloOnCount(settings->cheat_jetpack + settings->cheat_noclip + (settings->cheat_jump > 1.01f) + (settings->cheat_speed > 1.01f)) views:cards];

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(@"Slow motion", @[
        HaloUISegmentRow(nil, @[@"Off", @"75%", @"50%", @"25%", @"10%"], settings->cheat_slow, ^(NSInteger index) {
            [self update:^(HsSettings *s) { s->cheat_slow = (int)index; }]; }),
        HaloUINote(@"Slows the whole game, including cutscenes. Off returns to normal speed.")])];
    [cards addObject:HaloUICardView(nil, @[
        CHEAT_SWITCH(@"AI ignores you", @"Hostile units no longer notice the local player. They still fight each other and react to what they already know.", cheat_ai_ignore),
        CHEAT_SWITCH(@"Third person", @"Follow the player with the existing third-person camera.", cheat_third_person),
        CHEAT_SWITCH(@"Unlimited flashlight", @"Keeps its battery full; you still toggle the light.", cheat_flashlight)])];
    [cards addObject:HaloUICardView(@"Vertical FOV (0 = default)", @[HaloUISliderRow(@"Value", 0, 90, settings->cheat_fov, @"%.1f", ^(float value) { [self update:^(HsSettings *s) { s->cheat_fov = value; }]; }), HaloUIButton(@"Enter value", 0, ^(UIButton *b) { HsSettings current = [[HaloSettingsStore shared] snapshot]; [self enterCampaignValue:@"Vertical FOV (0 = default)" value:current.cheat_fov minimum:0 maximum:90 apply:^(float value) { [self update:^(HsSettings *s) { s->cheat_fov = value; }]; }]; })])];
    [self addCheatSection:@"World" summary:HaloOnCount((settings->cheat_slow != 0) + settings->cheat_ai_ignore + settings->cheat_third_person + settings->cheat_flashlight + (settings->cheat_fov > 0.5f)) views:cards];

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(nil, @[
        HaloUIButton(@"Save checkpoint (when safe)", 1, ^(UIButton *b) { (void)b; [self queueCampaignAction:5]; }),
        HaloUIButton(@"Force checkpoint now", 0, ^(UIButton *b) { (void)b; [self queueCampaignAction:6]; }),
        HaloUIButton(@"Revert to last checkpoint", 2, ^(UIButton *b) { (void)b;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Revert to the last checkpoint?" message:@"You lose all progress since it was saved." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Revert" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { (void)action; [self queueCampaignAction:7]; }]];
            [self presentViewController:alert animated:YES completion:nil]; }),
        HaloUINote(@"This is Halo's own checkpoint, the same one it makes automatically (you see \"Checkpoint... done\"). Save, play on, then Revert to come back to it. The safe save waits up to 8 seconds for a moment without combat; Force saves immediately, even with enemies close. Revert needs a checkpoint to exist.")])];
    [self addCheatSection:@"Checkpoints" summary:@"Save and revert" views:cards];

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(@"To your crosshair", @[
        HaloUIButton(@"Teleport me to crosshair", 0, ^(UIButton *b) { (void)b; [self queueCampaignAction:8]; }),
        HaloUIButton(@"Teleport enemies to crosshair", 0, ^(UIButton *b) { (void)b; [self queueCampaignAction:9]; }),
        HaloUINote(@"The target is the first level surface in front of the camera, up to a long way off. Enemies means living, hostile, AI-controlled units that are not in a vehicle (up to 24), placed in a ring around the point.")])];
    NSMutableArray<UIView *> *slots = [NSMutableArray array];
    for (int slot = 0; slot < 3; slot++) {
        UIButton *save = HaloUIButton([NSString stringWithFormat:@"Save position %d", slot + 1], 0, ^(UIButton *b) { (void)b; [self queueCampaignAction:300 + slot]; });
        UIButton *back = HaloUIButton([NSString stringWithFormat:@"Return to %d", slot + 1], 1, ^(UIButton *b) { (void)b; [self queueCampaignAction:310 + slot]; });
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[save, back]];
        row.spacing = 8; row.distribution = UIStackViewDistributionFillEqually;
        [slots addObject:row];
    }
    [slots addObject:HaloUINote(@"Three slots remember where you stood (and the vehicle you were in). They are forgotten when the mission changes.")];
    [cards addObject:HaloUICardView(@"Saved positions", slots)];
    [self addCheatSection:@"Teleport" summary:@"Crosshair and saved positions" views:cards];

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(@"Spawn loaded map assets", @[
        HaloUINote(@"Pickups appear in front of you. Only assets already loaded by the current map are supported; unavailable assets report a message."),
        HaloUIButton(@"Weapon giver", 0, ^(UIButton *b) { [self chooseCampaignAsset:@"Weapon" names:@[@"Pistol", @"Assault rifle", @"Shotgun", @"Sniper rifle", @"Rocket launcher", @"Plasma pistol", @"Plasma rifle", @"Needler", @"Flamethrower", @"Gravity rifle"] base:100]; }),
        HaloUIButton(@"Vehicle spawner", 0, ^(UIButton *b) { [self chooseCampaignAsset:@"Vehicle" names:@[@"Warthog", @"Ghost", @"Banshee", @"Scorpion"] base:200]; }),
        HaloUINote(@"Power-ups have dedicated sections below.")])];
    [self addCheatSection:@"Spawn" summary:@"Weapons and vehicles" views:cards];
#undef CHEAT_SWITCH
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
    NSArray<NSString *> *names=@[@"God mode",@"Infinite ammo",@"Infinite grenades",@"Bottomless clip",@"One-hit kills",@"Unlimited flashlight",@"No fall damage",@"Rapid fire",@"No recoil",@"Third person",@"Noclip",@"Infinite Active Camo",@"Infinite Overshield",@"Jetpack",@"AI ignores you"];
    for (NSUInteger bit=0;bit<names.count;++bit) {
        unsigned flag=1u<<(unsigned)bit;
        [rows addArrangedSubview:HaloUISwitchRow(names[bit],nil,!!(p.cheat_flags&flag),^(BOOL on) { [self update:^(HsSettings *s) { if (on) s->presets[index].cheat_flags|=flag;else s->presets[index].cheat_flags&=~flag; }]; })];
    }
    [rows addArrangedSubview:HaloUISegmentRow(@"Slow motion",@[@"Off",@"75%",@"50%",@"25%",@"10%"],p.cheat_slow,^(NSInteger value) { [self update:^(HsSettings *s) { s->presets[index].cheat_slow=(int)value; }]; })];
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

static NSString *HaloAge(NSTimeInterval stamp)
{
    NSTimeInterval seconds = MAX(0, [NSDate date].timeIntervalSince1970 - stamp);
    if (seconds < 90) return @"just now";
    if (seconds < 5400) return [NSString stringWithFormat:@"%.0f min ago", seconds / 60];
    if (seconds < 172800) return [NSString stringWithFormat:@"%.0f h ago", seconds / 3600];
    return [NSString stringWithFormat:@"%.0f days ago", seconds / 86400];
}

/* An invite as a QR code on a plain white card (the quiet border a scanner needs). */
- (void)showQR:(NSString *)invite
{
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:[invite dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *code = [filter.outputImage imageByApplyingTransform:CGAffineTransformMakeScale(10, 10)];
    CGImageRef cg = code ? [[CIContext contextWithOptions:nil] createCGImage:code fromRect:code.extent] : NULL;
    if (!cg) { halo_ios_toast("Could not make the QR code"); return; }
    UIImage *image = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    UIViewController *sheet = [UIViewController new];
    sheet.view.backgroundColor = HaloUIBackground();
    UIImageView *picture = [[UIImageView alloc] initWithImage:image];
    picture.layer.magnificationFilter = kCAFilterNearest;
    picture.contentMode = UIViewContentModeScaleAspectFit;
    picture.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.whiteColor; card.layer.cornerRadius = 12;
    [card addSubview:picture];
    [NSLayoutConstraint activateConstraints:@[
        [picture.topAnchor constraintEqualToAnchor:card.topAnchor constant:16], [picture.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [picture.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16], [picture.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [card.widthAnchor constraintEqualToConstant:230], [card.heightAnchor constraintEqualToConstant:230]]];
    __weak UIViewController *weakSheet = sheet;
    UIButton *done = HaloUIButton(@"Done", 1, ^(UIButton *b) { (void)b; [weakSheet dismissViewControllerAnimated:YES completion:nil]; });
    UIButton *share = HaloUIButton(@"Share the link", 0, ^(UIButton *b) {
        UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[invite] applicationActivities:nil];
        activity.popoverPresentationController.sourceView = b; activity.popoverPresentationController.sourceRect = b.bounds;
        [weakSheet presentViewController:activity animated:YES completion:nil]; });
    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[HaloUILabel(@"Scan to join", 20, UIFontWeightBold, nil), card, HaloUINote(@"Works while this game is still running."), share, done]];
    column.axis = UILayoutConstraintAxisVertical; column.spacing = 12; column.alignment = UIStackViewAlignmentCenter;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [sheet.view addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [column.centerXAnchor constraintEqualToAnchor:sheet.view.centerXAnchor], [column.centerYAnchor constraintEqualToAnchor:sheet.view.centerYAnchor],
        [share.widthAnchor constraintEqualToConstant:230], [done.widthAnchor constraintEqualToConstant:230]]];
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Profiles

- (void)buildProfiles:(const HsSettings *)settings
{
    HsPreset preset = settings->presets[settings->active];
    NSArray<NSString *> *frameModes = @[@"30 · Original", @"60 · Smooth", @"Uncapped"];
    NSString *hud = preset.hud_choice == 0 ? @"Default" : [NSString stringWithUTF8String:settings->hud_presets[preset.hud_choice - 1].name];
    unsigned recipeCount = (unsigned)__builtin_popcount(preset.cheat_flags) + (preset.cheat_slow ? 1u : 0u);
    [self add:HaloUICardView(@"What a profile holds", @[
        HaloUINote(@"A profile is everything you have set up: your five control schemes with their layouts and cheat recipes, the HUD, display, audio and accent color choices. It does not include maps, saves, or cheats that are running right now. Backups (Advanced) can also keep it with your saves."),
        HaloUIValueRow(@"Control scheme in use", [NSString stringWithUTF8String:preset.name], nil),
        HaloUIValueRow(@"Game HUD", hud, nil),
        HaloUIValueRow(@"Frame rate", frameModes[(NSUInteger)settings->fps_mode % 3], nil),
        HaloUIValueRow(@"Volumes", [NSString stringWithFormat:@"Master %d · Music %d · Voices %d · Effects %d · Ambient %d", (int)lround(settings->volume * 100), (int)lround(settings->music_volume * 100), (int)lround(settings->dialogue_volume * 100), (int)lround(settings->effects_volume * 100), (int)lround(settings->ambient_volume * 100)], nil),
        HaloUIValueRow(@"Left-handed · Gyro", [NSString stringWithFormat:@"%@ · %@", preset.mirror ? @"On" : @"Off", preset.gyro ? @"On" : @"Off"], nil),
        HaloUIValueRow(@"Cheat recipe in this scheme", recipeCount ? [NSString stringWithFormat:@"%u items", recipeCount] : @"None", nil)])];
    [self add:HaloUICardView(@"Share or move a profile", @[
        HaloUIButton(@"Export profile…", 1, ^(UIButton *b) { [self exportProfile:b]; }),
        HaloUIButton(@"Import profile…", 0, ^(UIButton *b) { (void)b;
            self.pickerKind = 2;
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
            picker.delegate = self; picker.allowsMultipleSelection = NO;
            [self presentViewController:picker animated:YES completion:nil]; }),
        HaloUINote(@"Export makes a .haloprofile file you can save to Files, AirDrop or send. Importing replaces everything above with the file's settings, so export first if you want to keep what you have.")])];
    [self add:HaloUICardView(@"Start over", @[
        HaloUIButton(@"Reset all settings to defaults", 2, ^(UIButton *b) { (void)b;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset every setting?" message:@"Control schemes, HUD, display, audio and colors all return to their defaults. Maps, saves and mods are not touched. Export a profile first if you may want this back." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Reset everything" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { (void)action;
                [self update:^(HsSettings *s) { hs_defaults(s); }];
                halo_ios_toast("All settings reset");
                [self renderSoon]; }]];
            [self presentViewController:alert animated:YES completion:nil]; })])];
}

- (void)exportProfile:(UIView *)source
{
    HsSettings snapshot = [[HaloSettingsStore shared] snapshot];
    char *text = malloc(32768);
    int length = text ? hs_serialize(&snapshot, text, 32768) : -1;
    if (length <= 0 || length >= 32768) { free(text); halo_ios_toast("Could not make the profile file"); return; }
    NSData *data = [NSData dataWithBytes:text length:(NSUInteger)length];
    free(text);
    NSDateFormatter *format = [NSDateFormatter new];
    format.dateFormat = @"yyyy-MM-dd HH.mm";
    NSString *name = [NSString stringWithFormat:@"Halo Profile %@.haloprofile", [format stringFromDate:NSDate.date]];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    if (![data writeToURL:url atomically:YES]) { halo_ios_toast("Could not make the profile file"); return; }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = source; activity.popoverPresentationController.sourceRect = source.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

/* One text file for a bug report: the device, the settings (running cheats are never in them) and the ends of the logs. */
static NSString *HaloLogTail(NSString *name, NSUInteger limit)
{
    NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Halo"] stringByAppendingPathComponent:name];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    if (data.length > limit) data = [data subdataWithRange:NSMakeRange(data.length - limit, limit)];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

- (void)reportProblem:(UIView *)source
{
    struct utsname system;
    uname(&system);
    NSProcessInfo *info = NSProcessInfo.processInfo;
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    NSMutableString *report = [NSMutableString stringWithFormat:@"HALO CE iOS - problem report\nCreated: %@\nApp version: %@ (%@)\nDevice: %s, iOS %@\nThermal state: %ld (0 cool .. 3 critical), Low Power Mode: %@, memory: %llu MB\n",
        [NSDate date], version, build, system.machine, UIDevice.currentDevice.systemVersion, (long)info.thermalState, info.isLowPowerModeEnabled ? @"on" : @"off", info.physicalMemory >> 20];
    HsSettings snapshot = [[HaloSettingsStore shared] snapshot];
    char *text = malloc(32768);
    if (text && hs_serialize(&snapshot, text, 32768) > 0) [report appendFormat:@"\n--- settings (running cheats are not included) ---\n%s\n", text];
    free(text);
    for (NSArray *item in @[@[@"ios-boot.log", @200000], @[@"debug.txt", @100000], @[@"crash.txt", @4000], @[@"last-crash.txt", @4000], @[@"launch-phase.txt", @1000]]) {
        NSString *body = HaloLogTail(item[0], [item[1] unsignedIntegerValue]);
        if (body.length) [report appendFormat:@"\n--- %@ (the end of it) ---\n%@\n", item[0], body];
    }
    NSDateFormatter *format = [NSDateFormatter new];
    format.dateFormat = @"yyyy-MM-dd HH.mm";
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Halo problem report %@.txt", [format stringFromDate:NSDate.date]]]];
    NSError *error = nil;
    if (![report writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error]) { halo_ios_toast("Could not make the report"); return; }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = source; activity.popoverPresentationController.sourceRect = source.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

static UIColor *HaloColorFromRGB(unsigned rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}

- (void)buildOptions:(const HsSettings *)settings {
    [self add:HaloUICardView(@"Settings button",@[
        HaloUISliderRow(@"Size",.75f,1.75f,settings->gear_scale,@"%.2f×",^(float value){[self update:^(HsSettings *s){s->gear_scale=value;}];}),
        HaloUINote(@"Touch and hold the gear to move it. Its touch target remains at least 44 points."),
        HaloUIButton(@"Reset size and position",0,^(UIButton *button){(void)button;[self update:^(HsSettings *s){s->gear_scale=1;s->gear_placed=0;}];[self renderSoon];})])];

    NSString *mode=settings->accent_mode==0?@"Using a preset color.":settings->accent_mode==1?@"Using your custom color. Choosing a preset switches back to it.":@"Chroma mode is on: the accent color is cycling.";
    [self add:HaloUICardView(@"Accent color",@[
        HaloUISegmentRow(@"Preset colors",@[@"Blue",@"Green",@"Purple",@"Amber",@"Rose"],settings->accent_mode==0?settings->ui_theme:UISegmentedControlNoSegment,^(NSInteger value){[self update:^(HsSettings *s){s->ui_theme=(int)value;s->accent_mode=0;}];[self renderSoon];}),
        HaloUINote([mode stringByAppendingString:@" Applies to Settings buttons, switches, sliders and selections. Gameplay control colors remain part of your control profile."])])];

    unsigned currentRGB=settings->accent_rgb&0xFFFFFFu;   /* blocks below run later: never read `settings` inside them */
    UIView *swatch=[UIView new];
    swatch.backgroundColor=HaloColorFromRGB(hx_clamp_accent(currentRGB));
    swatch.layer.cornerRadius=8;swatch.layer.borderWidth=1;swatch.layer.borderColor=[UIColor colorWithWhite:1 alpha:.35].CGColor;
    [swatch.widthAnchor constraintEqualToConstant:44].active=YES;[swatch.heightAnchor constraintEqualToConstant:44].active=YES;
    UITextField *hex=[UITextField new];
    hex.attributedPlaceholder=[[NSAttributedString alloc] initWithString:@"#RRGGBB" attributes:@{NSForegroundColorAttributeName:HaloUISecondaryText()}];
    hex.text=[NSString stringWithFormat:@"#%06X",settings->accent_rgb&0xFFFFFFu];
    hex.textColor=UIColor.whiteColor;hex.backgroundColor=[UIColor colorWithWhite:0.18 alpha:1];hex.layer.cornerRadius=10;
    hex.leftView=[[UIView alloc] initWithFrame:CGRectMake(0,0,12,10)];hex.leftViewMode=UITextFieldViewModeAlways;
    hex.autocorrectionType=UITextAutocorrectionTypeNo;hex.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;
    hex.keyboardType=UIKeyboardTypeASCIICapable;hex.returnKeyType=UIReturnKeyDone;hex.delegate=self;
    [hex.heightAnchor constraintEqualToConstant:44].active=YES;
    UIStackView *hexRow=[[UIStackView alloc] initWithArrangedSubviews:@[swatch,hex]];hexRow.spacing=10;hexRow.alignment=UIStackViewAlignmentCenter;
    [self add:HaloUICardView(@"Custom color",@[
        HaloUINote(@"Pick any color on the wheel, or type a hex value. Very dark or very light colors are adjusted a little so button text stays readable; the swatch shows what is actually used."),
        hexRow,
        HaloUIButton(@"Use this hex color",1,^(UIButton *b){(void)b;
            [hex resignFirstResponder];
            unsigned rgb=0;
            if(!hx_parse(hex.text.UTF8String,&rgb)){halo_ios_toast("Enter a color like #3385FA (three or six hex digits)");return;}
            [self update:^(HsSettings *s){s->accent_rgb=rgb&0xFFFFFFu;s->accent_mode=1;}];[self renderSoon];}),
        HaloUIButton(@"Open color wheel…",0,^(UIButton *b){(void)b;
            UIColorPickerViewController *picker=[UIColorPickerViewController new];
            picker.supportsAlpha=NO;picker.selectedColor=HaloColorFromRGB(currentRGB);picker.delegate=self;picker.title=@"Accent color";
            [self presentViewController:picker animated:YES completion:nil];})])];

    [self add:HaloUICardView(@"Chroma (RGB) mode",@[
        HaloUISwitchRow(@"Chroma mode",@"The accent color slowly cycles through the whole spectrum while Settings is open.",settings->accent_mode==2,^(BOOL on){
            [self update:^(HsSettings *s){s->accent_mode=on?2:(s->accent_rgb!=HX_DEFAULT_ACCENT?1:0);}];[self renderSoon];}),
        HaloUISliderRow(@"Seconds per full cycle",3,60,settings->chroma_seconds,@"%.0f s",^(float value){[self update:^(HsSettings *s){s->chroma_seconds=value;}];}),
        HaloUINote(@"A fast cycle is bright and busy; a slow one is calm. The color always stays readable.")])];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    (void)viewController;
    CGFloat r=0,g=0,b=0,a=0;
    if(![color getRed:&r green:&g blue:&b alpha:&a])return;
    if(r<0)r=0;if(r>1)r=1;if(g<0)g=0;if(g>1)g=1;if(b<0)b=0;if(b>1)b=1;
    unsigned rgb=((unsigned)lround(r*255)<<16)|((unsigned)lround(g*255)<<8)|(unsigned)lround(b*255);
    [self update:^(HsSettings *s){s->accent_rgb=rgb;s->accent_mode=1;}];
    if(!continuously)[self renderSoon];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController { (void)viewController;[self renderSoon]; }

- (void)buildAdvanced:(const HsSettings *)settings
{
    [self add:HaloUICardView(@"Game",@[
        HaloUIButton(@"Quit Game",2,^(UIButton *b) { [self confirmAppQuit]; })])];
    [self add:HaloUICardView(@"Startup",@[[self startupRow:settings->active],HaloUINote(@"Saved with the current control profile. A recovery start always pauses at Start Halo.")])];
    NSMutableArray<UIView *> *diag = [NSMutableArray array];
    [diag addObject:HaloUISwitchRow(@"Performance profiler", @"Samples the game thread so Diagnostics can show where the time goes. About 1% of one CPU core.", settings->profiler, ^(BOOL on) { [self update:^(HsSettings *s) { s->profiler = on; }]; })];
    [diag addObject:HaloUIButton(@"Share log files", 0, ^(UIButton *b) { if (self.onShareLogs) self.onShareLogs(b); })];
    [diag addObject:HaloUIButton(@"Report a problem…", 0, ^(UIButton *b) { [self reportProblem:b]; })];
    [diag addObject:HaloUINote(@"Makes one text file with your device, your settings (never active cheats) and the end of the logs, and opens the share sheet. Look it over before posting it publicly.")];
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
        HaloUIValueRow(@"Game", @"Halo CE Universal (PC menus update)", nil),
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
