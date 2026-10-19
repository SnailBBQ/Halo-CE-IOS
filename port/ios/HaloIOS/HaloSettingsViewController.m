#import "HaloCheckpointEditor.h"
#import "HaloSettingsViewController.h"
#import "HaloSettingsStore.h"
#import "HaloUI.h"
#import "HaloLibrary.h"
#import "HaloMods.h"
#import "HaloBackupArchive.h"
#import "HaloHudEditor.h"
#import "halo_ios_platform.h"
#import "halo_color.h"
#import "halo_ios_audio.h"
#import "halo_pad_input.h"
#import "halo_ios_controls.h"
#import <CoreImage/CoreImage.h>
#import <sys/utsname.h>

#import <ctype.h>
static NSString *HaloAge(NSTimeInterval stamp);
static NSString *HaloSaveGearPhoto(UIImage *image);   /* the Settings button pictures, defined at the end of this file */
static void HaloApplyGearToken(NSString *token);   /* defined further down; the Multiplayer screen uses it first */
#import "halo_guest_runner.h"
#import "halo_settings_search.h"
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


static NSArray<NSString *> *HaloShortcutActions(void);
static NSArray<NSString *> *HaloShortcutKeys(void) {
    return @[@"A / Cross",@"B / Circle",@"X / Square",@"Y / Triangle",@"Back",@"Guide",@"Start",@"LS / L3",@"RS / R3",@"White / L1",@"Black / R1",@"Up",@"Down",@"Left",@"Right",@"LT / L2",@"RT / R2"];
}
@interface HaloShortcutEditor : UIViewController
@property(nonatomic) int slot;
@property(nonatomic) int action;
@property(nonatomic) float gap;
@property(nonatomic) float total;
@property(nonatomic) BOOL recording;
@property(nonatomic,strong) NSMutableArray<NSNumber *> *steps;
@property(nonatomic,strong) UILabel *sequenceLabel;
@property(nonatomic,strong) UIButton *recordButton;
@property(nonatomic,copy) void (^saved)(void);
@end
@implementation HaloShortcutEditor
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=HaloUIBackground();
    self.title=self.slot?[NSString stringWithFormat:@"Cheat Shortcut %d",self.slot]:@"Settings Shortcut";
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
    HsSettings settings=[HaloSettingsStore.shared snapshot];HsShortcut q=settings.shortcuts[self.slot];
    self.action=q.action;self.gap=q.gap;self.total=q.total;self.steps=[NSMutableArray array];
    for(NSString *part in [[NSString stringWithUTF8String:q.sequence] componentsSeparatedByString:@","])
        if(part.length && part.intValue>=0 && part.intValue<17 && part.intValue!=5)[self.steps addObject:@(part.intValue)];
    UIStackView *stack=HaloUIScrollingStack(self.view,12);
    __weak HaloShortcutEditor *weakSelf=self;
    if(self.slot) {
        UIButton *choose=HaloUIButton(HaloShortcutActions()[self.action],1,^(UIButton *button){
            HaloShortcutEditor *editor=weakSelf;if(!editor)return;
            HaloOptionPicker *picker=[HaloOptionPicker new];picker.title=@"Choose Cheat";
            NSMutableArray *names=[NSMutableArray array];NSMutableArray *ids=[NSMutableArray array];
            for(NSUInteger i=0;i<HaloShortcutActions().count;i++)if(i!=29){[names addObject:HaloShortcutActions()[i]];[ids addObject:@(i)];}
            picker.choices=names;picker.pick=^(NSUInteger row){weakSelf.action=[ids[row] intValue];[button setTitle:names[row] forState:UIControlStateNormal];};
            [editor presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
        });
        [stack addArrangedSubview:HaloUICardView(@"Cheat action",@[choose,HaloUINote(@"Available only in solo campaign. Toggle cheats switch on or off; pickup and spawn actions run once.")])];
    }
    self.sequenceLabel=HaloUILabel(@"",18,UIFontWeightMedium,nil);
    self.recordButton=HaloUIButton(@"Record gamepad buttons",1,^(UIButton *button){(void)button;weakSelf.recording=!weakSelf.recording;[weakSelf refreshSequence];});
    [stack addArrangedSubview:HaloUICardView(@"Button sequence",@[
        self.sequenceLabel,self.recordButton,
        HaloUIButton(@"Undo last button",0,^(UIButton *b){(void)b;if(weakSelf.steps.count)[weakSelf.steps removeLastObject];[weakSelf refreshSequence];}),
        HaloUIButton(@"Clear sequence",2,^(UIButton *b){(void)b;[weakSelf.steps removeAllObjects];[weakSelf refreshSequence];}),
        HaloUINote(@"Tap the touch buttons below, or start recording and press your controller buttons. Up to 16 presses. An empty sequence disables the shortcut. Gameplay controller input is paused while this editor is open.")])];
    NSMutableArray *rows=[NSMutableArray array];
    for(NSArray<NSNumber *> *group in @[@[@11,@12,@13,@14],@[@0,@1,@2,@3],@[@15,@16,@9,@10],@[@7,@8,@4,@6]]) {
        NSMutableArray *buttons=[NSMutableArray array];
        for(NSNumber *key in group)[buttons addObject:HaloUIButton(HaloShortcutKeys()[key.unsignedIntegerValue],0,^(UIButton *b){(void)b;[weakSelf appendKey:key.intValue];})];
        for(UIButton *button in buttons){button.titleLabel.adjustsFontSizeToFitWidth=YES;button.titleLabel.minimumScaleFactor=.6;}
        UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:buttons];row.spacing=8;row.distribution=UIStackViewDistributionFillEqually;
        [rows addObject:row];
    }
    [stack addArrangedSubview:HaloUICardView(@"Touch button input",rows)];
    [stack addArrangedSubview:HaloUICardView(@"Timing",@[
        HaloUISliderRow(@"Maximum gap between presses",.25f,10,self.gap,@"%.2f s",^(float v){weakSelf.gap=v;}),
        HaloUISliderRow(@"Maximum sequence duration",1,60,self.total,@"%.1f s",^(float v){weakSelf.total=v;})])];
    [self refreshSequence];HaloUIApplyAccent(self.view);
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];__weak HaloShortcutEditor *weakSelf=self;
    halo_ios_shortcut_capture(^(int key){if(weakSelf.recording)[weakSelf appendKey:key];});
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];self.recording=NO;[self refreshSequence];halo_ios_shortcut_capture(nil);
}
- (void)appendKey:(int)key {
    if(key<0 || key>=17 || key==5 || self.steps.count>=16)return;
    [self.steps addObject:@(key)];[self refreshSequence];
}
- (void)refreshSequence {
    NSMutableArray *labels=[NSMutableArray array];for(NSNumber *key in self.steps)[labels addObject:HaloShortcutKeys()[key.unsignedIntegerValue]];
    self.sequenceLabel.text=labels.count?[labels componentsJoinedByString:@" → "]:@"No buttons selected";
    [self.recordButton setTitle:self.recording?@"Stop recording":@"Record gamepad buttons" forState:UIControlStateNormal];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)save {
    NSString *sequence=[self.steps componentsJoinedByString:@","];int slot=self.slot,action=self.action;float gap=self.gap,total=self.total;
    [HaloSettingsStore.shared update:^(HsSettings *s){snprintf(s->shortcuts[slot].sequence,sizeof(s->shortcuts[slot].sequence),"%s",sequence.UTF8String);s->shortcuts[slot].gap=gap;s->shortcuts[slot].total=total;if(slot)s->shortcuts[slot].action=action;}];
    void (^saved)(void)=self.saved;[self dismissViewControllerAnimated:YES completion:^{if(saved)saved();}];
}
@end

typedef NS_ENUM(NSInteger, HaloCategory) {
    HaloCategoryMultiplayer = 0, HaloCategoryControls, HaloCategoryDisplay, HaloCategoryAudio, HaloCategoryCheats, HaloCategoryProfiles, HaloCategoryOptions, HaloCategoryMods, HaloCategoryAdvanced,
    HaloCategoryLogs, HaloCategoryCount
};

@interface HaloSettingsViewController () <UITextFieldDelegate, UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property(nonatomic, strong) UIView *detail;
@property(nonatomic,strong) NSNetServiceBrowser *localNetworkProbe;
@property(nonatomic,strong) NSNetService *localNetworkPublisher;
@property(nonatomic,strong) UILabel *localNetworkStatus;
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) NSArray<UIButton *> *sidebar;
@property(nonatomic) HaloCategory selected;
@property(nonatomic,strong) UIViewController *modsPage;
@property(nonatomic,strong) id campaignObserver;
@property(nonatomic,strong) NSTimer *connectionTimer;
@property(nonatomic,strong) NSTimer *chromaTimer;
@property(nonatomic,strong) NSMutableSet<NSString *> *openCheatSections;
@property(nonatomic) NSInteger pickerKind; /* 0 invite folder, 2 profile import */
@property(nonatomic,strong) UILabel *connectionLabel;
- (void)editShortcut:(int)slot;
- (UIView *)engineControllerCard:(const HsSettings *)settings;
@end


/* The search sheet behind the magnifier next to "Settings": suggestions first, matches as the person types. */
@interface HaloSettingsSearch : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property(nonatomic,copy) void (^pick)(int category, NSString *title);
@property(nonatomic,strong) UISearchBar *bar;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic) int *rows;
@property(nonatomic) int rowCount;
@property(nonatomic,copy) NSString *query;
@end
/* "Choose icon": built-in pictures, emoji, photos and favourites (a star on the right of each row). */
@interface HaloIconPicker : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic,copy) void (^onFiles)(void);
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) UITextField *field;
@property(nonatomic,strong) NSArray<NSArray<NSString *> *> *sections;
@property(nonatomic,strong) NSArray<NSString *> *titles;
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
    UIButton *search = [UIButton buttonWithType:UIButtonTypeSystem];
    search.translatesAutoresizingMaskIntoConstraints = NO;
    [search setImage:[UIImage systemImageNamed:@"magnifyingglass"] forState:UIControlStateNormal];
    search.tintColor = UIColor.whiteColor;
    search.accessibilityLabel = @"Search settings";
    search.accessibilityIdentifier = @"HaloSidebarRow";
    search.backgroundColor = HaloUICard();
    search.layer.cornerRadius = 18;
    [search addAction:[UIAction actionWithHandler:^(UIAction *action) { (void)action; [self openSearch]; }] forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:title];
    [header addSubview:search];
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
        [search.leadingAnchor constraintEqualToAnchor:title.trailingAnchor constant:12],
        [search.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [search.widthAnchor constraintEqualToConstant:44],
        [search.heightAnchor constraintEqualToConstant:36],
        [search.trailingAnchor constraintLessThanOrEqualToAnchor:done.leadingAnchor constant:-12],
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

/* The magnifier: pick a result and the Settings screen jumps to its category and flashes the row. */
- (void)openSearch {
    HaloSettingsSearch *sheet = [HaloSettingsSearch new];
    __weak HaloSettingsViewController *weakSelf = self;
    sheet.pick = ^(int category, NSString *title) { [weakSelf showSearchResult:(HaloCategory)category title:title]; };
    sheet.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:sheet animated:YES completion:nil];
}

static UIView *HaloFindLabel(UIView *root, NSString *title) {
    NSString *wanted = [title.lowercaseString stringByReplacingOccurrencesOfString:@"…" withString:@""];
    NSString *text = nil;
    if ([root isKindOfClass:UILabel.class]) text = ((UILabel *)root).text;
    else if ([root isKindOfClass:UIButton.class]) text = [(UIButton *)root titleForState:UIControlStateNormal];
    if (text.length) {
        NSString *have = [[text.lowercaseString stringByReplacingOccurrencesOfString:@"…" withString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([have isEqualToString:wanted] || [have hasPrefix:wanted]) return root;
    }
    for (UIView *child in root.subviews) { UIView *hit = HaloFindLabel(child, title); if (hit) return hit; }
    return nil;
}

- (void)showSearchResult:(HaloCategory)category title:(NSString *)title {
    self.selected = category;
    [self renderDetail];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIScrollView *scroll = (UIScrollView *)self.stack.superview;
        [scroll layoutIfNeeded];
        UIView *hit = HaloFindLabel(self.stack, title);
        if (!hit) { [scroll setContentOffset:CGPointZero animated:NO]; return; }
        UIView *row = hit;
        while (row.superview && row.superview != self.stack) row = row.superview;   /* the card that holds it */
        CGRect frame = [scroll convertRect:row.bounds fromView:row];
        [scroll scrollRectToVisible:CGRectInset(frame, 0, -24) animated:YES];
        UIColor *old = row.backgroundColor ?: UIColor.clearColor;
        row.backgroundColor = [HaloUIAccent() colorWithAlphaComponent:0.45];
        [UIView animateWithDuration:1.4 delay:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:^{ row.backgroundColor = old; } completion:nil];
    });
}

- (void)paintSidebar {
    for (NSInteger i = 0; i < (NSInteger)self.sidebar.count; i++) {
        BOOL on = i == (NSInteger)self.selected;
        self.sidebar[i].backgroundColor = on ? HaloUIAccent() : (i == HaloCategoryLogs ? [UIColor colorWithWhite:0.14 alpha:1] : UIColor.clearColor);
    }
}

- (void)dealloc { [self.localNetworkProbe stop];[self.localNetworkPublisher stop]; [self.chromaTimer invalidate];[self.connectionTimer invalidate]; if (self.campaignObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.campaignObserver]; }

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
    HaloUIApplyAccent(self.view);
    for (NSInteger i = 0; i < (NSInteger)self.sidebar.count; i++) {
        BOOL on = i == (NSInteger)self.selected;
        self.sidebar[i].backgroundColor = on ? HaloUIAccent() : (i == HaloCategoryLogs ? [UIColor colorWithWhite:0.14 alpha:1] : UIColor.clearColor);
    }
    if (self.selected == HaloCategoryMods) {   /* the Mods page lives right here, like the other sections, and keeps its own refresh */
        self.stack.superview.hidden = YES;
        if (!self.modsPage) {
            UIViewController *page = HaloModsPageController();
            [self addChildViewController:page];
            page.view.translatesAutoresizingMaskIntoConstraints = NO;
            [self.detail addSubview:page.view];
            [NSLayoutConstraint activateConstraints:@[
                [page.view.topAnchor constraintEqualToAnchor:self.detail.topAnchor],
                [page.view.bottomAnchor constraintEqualToAnchor:self.detail.bottomAnchor],
                [page.view.leadingAnchor constraintEqualToAnchor:self.detail.leadingAnchor],
                [page.view.trailingAnchor constraintEqualToAnchor:self.detail.trailingAnchor]]];
            [page didMoveToParentViewController:self];
            self.modsPage = page;
        }
        self.modsPage.view.hidden = NO;
        return;
    }
    self.stack.superview.hidden = NO;
    self.modsPage.view.hidden = YES;
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
                        settings->join_from_clipboard, ^(BOOL on) { [self update:^(HsSettings *s) { s->join_from_clipboard = on; }]; }),
        HaloUISwitchRow(@"Internet play", nil, settings->game_online, ^(BOOL on) { [self update:^(HsSettings *s) { s->game_online = on; }]; }),
        HaloUISwitchRow(@"UPnP port forwarding", @"Allow the engine to ask your router for a port mapping. Router support is required.", settings->game_upnp, ^(BOOL on) { [self update:^(HsSettings *s) { s->game_upnp = on; }]; }),
        HaloUISwitchRow(@"Share maps with other players", @"Off by default. When on, this iPhone sends Custom Edition maps (and the resource maps they need) to players who join without them, and helps others send them, using your upload and mobile data. Downloading a map a game needs is not affected. Takes effect the next time the game starts.", HaloMapSharingEnabled(), ^(BOOL on) { if (!HaloMapSharingSet(on)) halo_ios_toast("Could not save the map sharing setting"); }),
        HaloUINote(@"Internet play and UPnP are shared with the in-game Network Setup. Connection options may require leaving and reopening a network session. This does not change iOS Local Network permission or router settings directly.")])];
    NSArray<NSString *> *levels=@[@"Off",@"Severe",@"Strong",@"Mild"];
    [self add:HaloUICardView(@"Streamer mode", @[
        HaloUISwitchRow(@"Streamer mode", @"Hides offensive words from other players' names and chat so a stream or recording stays clean.", settings->streamer, ^(BOOL on) { [self update:^(HsSettings *s) { s->streamer = on; }]; }),
        HaloUISegmentRow(@"Slurs", levels, settings->streamer_slurs, ^(NSInteger i) { [self update:^(HsSettings *s) { s->streamer_slurs = (int)i; }]; }),
        HaloUISegmentRow(@"Swearing", levels, settings->streamer_swearing, ^(NSInteger i) { [self update:^(HsSettings *s) { s->streamer_swearing = (int)i; }]; }),
        HaloUISegmentRow(@"Insults", levels, settings->streamer_insults, ^(NSInteger i) { [self update:^(HsSettings *s) { s->streamer_insults = (int)i; }]; }),
        HaloUINote(@"Shared with the in-game streamer settings. Off hides nothing in that group; Severe hides the worst words only; Mild hides the most.")])];
    [self add:HaloUICardView(@"Finding games on your Wi-Fi", @[
        (self.localNetworkStatus=HaloUILabel(@"Permission has not been checked. A missing Settings entry does not mean access is granted.",14,UIFontWeightRegular,HaloUISecondaryText())),
        HaloUIButton(@"Check Local Network access",0,^(UIButton *b){(void)b;[self requestLocalNetworkAccess];}),
        HaloUIButton(@"Open iOS app settings",0,^(UIButton *b){(void)b;[UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];}),
        HaloUINote(@"Connect to Wi-Fi, then check access above. Allow access if iOS asks. Halo can appear in Local Network settings only after iOS processes a request. LAN broadcast discovery also requires Apple’s multicast entitlement in the signed app; an ordinary sideload may not include it. Permission alone does not prove discovery works. Invite links remain available.")])];

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
    if (self.pickerKind == 3) {
        self.pickerKind = 0;
        NSURL *url = urls.firstObject;
        BOOL access = [url startAccessingSecurityScopedResource];
        NSNumber *size = nil;
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        NSData *data = size && size.unsignedLongLongValue > 0 && size.unsignedLongLongValue <= 8*1024*1024 ? [NSData dataWithContentsOfURL:url] : nil;
        if (access) [url stopAccessingSecurityScopedResource];
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        if (!image || !image.CGImage || CGImageGetWidth(image.CGImage) > 2048 || CGImageGetHeight(image.CGImage) > 2048) { halo_ios_toast("Choose an image up to 8 MB and 2048 pixels"); return; }
        NSString *token = HaloSaveGearPhoto(image);
        if (!token) { halo_ios_toast("Could not save the icon"); return; }
        HaloApplyGearToken(token); [self renderSoon]; return;
    }
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

    [self add:HaloUILabel(@"Touch Controls",22,UIFontWeightSemibold,nil)];
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
        HaloUINote(@"Turn left to look left and tilt up to look up. The flip switches customize either direction for this control scheme.")])];

    /* ---- a physical controller: stick feel and which button does what (all profiles) */
    NSMutableArray<UIView *> *padRows = [NSMutableArray array];
    [padRows addObject:HaloUINote(@"For a connected Xbox, PlayStation or other controller. The defaults pass the stick straight through.")];
    [padRows addObject:HaloUISliderRow(@"Stick dead zone", 0.0f, 0.4f, settings->pad_dead, @"%.2f", ^(float v) { [self update:^(HsSettings *s) { s->pad_dead = v; }]; })];
    [padRows addObject:HaloUISliderRow(@"Stick response", 1.0f, 3.0f, settings->pad_curve, @"%.1f", ^(float v) { [self update:^(HsSettings *s) { s->pad_curve = v; }]; })];
    [padRows addObject:HaloUINote(@"The dead zone is removed rather than cut off, so movement still starts from zero. A response above 1.0 gives finer control near the centre.")];
    [self add:HaloUILabel(@"Gamepad Controls",22,UIFontWeightSemibold,nil)];
    [self add:HaloUICardView(@"Stick tuning", padRows)];

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
    [self add:HaloUILabel(@"Halo Controller Settings",22,UIFontWeightSemibold,nil)];
    [self add:[self engineControllerCard:settings]];
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
    NSArray<NSString *> *choices=@[@"Start Halo CE iOS Title Screen",@"Boot Halo to Main Menu"];
    UIButton *button=HaloUIButton(choices[(NSUInteger)!!current.presets[index].startup_auto],0,^(UIButton *b){
        [self presentChoices:@"On app launch" names:choices from:self pick:^(NSUInteger choice){
            [self update:^(HsSettings *s){s->presets[index].startup_auto=(int)choice;}];
            [b setTitle:choices[choice] forState:UIControlStateNormal];}];});
    return button;
}
static NSArray<NSString *> *HaloArmorColorNames(void) {
    return @[@"White",@"Black",@"Red",@"Blue",@"Gray",@"Yellow",@"Green",@"Pink",@"Purple",@"Cyan",@"Cobalt",@"Orange",@"Teal",@"Sage",@"Brown",@"Tan",@"Maroon",@"Salmon"];
}
static NSArray<NSString *> *HaloShieldColorNames(void) {
    return [@[@"Default"] arrayByAddingObjectsFromArray:HaloArmorColorNames()];
}
/* field of view choices: the game's own (0), then 80 ... 150 in steps of 5 */
static NSArray<NSString *> *HaloFovNames(void) {
    NSMutableArray *names=[NSMutableArray arrayWithObject:@"Default"];
    for(int degrees=80;degrees<=150;degrees+=5)[names addObject:[NSString stringWithFormat:@"%d°",degrees]];
    return names;
}
static NSInteger HaloFovIndex(float fov) { return fov<1.f ? 0 : (NSInteger)lroundf((hs_clampf(fov,80.f,150.f)-80.f)/5.f)+1; }
static float HaloFovValue(NSInteger index) { return index<=0 ? 0.f : 80.f+5.f*(float)(index-1); }
static NSInteger HaloIndexOf(int value,const int *values,int count) { for(int i=0;i<count;i++)if(values[i]==value)return i; return -1; }
static NSInteger HaloNameScaleIndex(float scale) {
    const float scales[6]={0.5f,0.75f,1.f,1.25f,1.5f,2.f};NSInteger best=2;float distance=99.f;
    for(int i=0;i<6;i++){float d=fabsf(scales[i]-scale);if(d<distance){distance=d;best=i;}}
    return best;
}

/* A button that shows the current choice and opens a list with a check mark on it. */
- (UIView *)choiceButton:(NSString *)title names:(NSArray<NSString *> *)names current:(NSInteger)current pick:(void (^)(NSInteger))pick {
    NSString *now=current>=0&&current<(NSInteger)names.count?names[(NSUInteger)current]:@"Custom";
    return HaloUIButton([NSString stringWithFormat:@"%@ · %@",title,now],0,^(UIButton *b){(void)b;
        NSMutableArray *marked=[NSMutableArray array];
        for(NSUInteger i=0;i<names.count;i++)[marked addObject:[NSString stringWithFormat:@"%@%@",(NSInteger)i==current?@"✓  ":@"",names[i]]];
        [self presentChoices:title names:marked from:self pick:^(NSUInteger choice){pick((NSInteger)choice);[self renderSoon];}];});
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
        HaloUISwitchRow(@"VSync", @"Shared with the in-game video setting. iOS still controls EAGL presentation timing; switching this off cannot force tearing or exceed the screen’s refresh rate.",settings->game_vsync,^(BOOL on){[self update:^(HsSettings *s){s->game_vsync=on;}];}),
        HaloUISwitchRow(@"Smooth motion", @"Shared with in-game interpolation. Changing between original 30 FPS and smooth rendering requires an app relaunch.",settings->fps_mode!=0,^(BOOL on){[self update:^(HsSettings *s){s->fps_mode=on?(s->fps_mode?s->fps_mode:1):0;}];[self renderSoon];}),
        HaloUISwitchRow(@"Show FPS", @"Display the frame-rate counter.", settings->show_fps, ^(BOOL on) { [self update:^(HsSettings *s) { s->show_fps = on; }]; }),
        HaloUINote(@"Switching between 30 and the other two takes effect the next time you open the app. Switching between 60 and Uncapped takes effect now.")])];

    [self add:HaloUICardView(@"Game picture", @[
        HaloUISegmentRow(@"Aspect ratio", @[@"Default · 4:3", @"Widescreen · 16:9", @"Fullscreen"], settings->display_mode, ^(NSInteger i) { [self update:^(HsSettings *s) { s->display_mode = (int)i; }]; }),
        HaloUISegmentRow(@"Render resolution", @[@"480p", @"720p", @"960p", @"1080p"], settings->render_quality, ^(NSInteger i) { [self update:^(HsSettings *s) { s->render_quality = (int)i; }]; }),
        HaloUINote(@"A wider picture shows more of the scene without stretching it. Fullscreen matches your device. Higher detail draws more pixels and uses more power; 480p is the performance default. The selected resolution specifies vertical pixels; width follows the aspect ratio. Picture changes apply on the next app launch.")])];


    [self add:HaloUICardView(@"Game HUD",@[
        [self hudChoiceRow:settings->active],
        HaloUINote(@"Separate controls for the game’s meters and FPS counter."),
        HaloUIButton(@"Edit game HUD",1,^(UIButton *b){(void)b;UIViewController *root=self.presentingViewController;[self dismissViewControllerAnimated:YES completion:^{UIViewController *editor=[HaloHudEditor new];editor.modalPresentationStyle=UIModalPresentationOverFullScreen;[root presentViewController:editor animated:YES completion:nil];}];})])];
    [self add:HaloUICardView(@"Video options", @[
        [self choiceButton:@"Anti-aliasing" names:@[@"Off",@"FXAA",@"MSAA 2x",@"MSAA 4x"] current:HaloIndexOf(settings->aa_mode,(const int[]){0,1,4,5},4) pick:^(NSInteger i){
            const int modes[4]={0,1,4,5};[self update:^(HsSettings *s){s->aa_mode=modes[i];}];}],
        HaloUISegmentRow(@"Shadow resolution", @[@"128",@"256",@"512",@"1024"], settings->shadow_res, ^(NSInteger i) { [self update:^(HsSettings *s) { s->shadow_res = (int)i; }]; }),
        HaloUISwitchRow(@"Per-pixel lighting", @"Smoother lighting on objects, at a cost in speed.", settings->per_pixel, ^(BOOL on) { [self update:^(HsSettings *s) { s->per_pixel = on; }]; }),
        HaloUISwitchRow(@"Shield glow", @"The glow around a shielded character.", settings->shield_glow, ^(BOOL on) { [self update:^(HsSettings *s) { s->shield_glow = on; }]; }),
        HaloUISegmentRow(@"Glow intensity", @[@"Default",@"Light show"], settings->glow_light_show, ^(NSInteger i) { [self update:^(HsSettings *s) { s->glow_light_show = (int)i; }]; }),
        [self choiceButton:@"Shield color" names:HaloShieldColorNames() current:settings->shield_color pick:^(NSInteger i){[self update:^(HsSettings *s){s->shield_color=(int)i;}];}],
        [self choiceButton:@"Field of view" names:HaloFovNames() current:HaloFovIndex(settings->fov) pick:^(NSInteger i){[self update:^(HsSettings *s){s->fov=HaloFovValue(i);}];}],
        [self choiceButton:@"Weapon and hands field of view" names:HaloFovNames() current:HaloFovIndex(settings->viewmodel_fov) pick:^(NSInteger i){[self update:^(HsSettings *s){s->viewmodel_fov=HaloFovValue(i);}];}],
        HaloUISwitchRow(@"Arm shields", @"Shows the shield's flare on your arms.", settings->vm_shield, ^(BOOL on) { [self update:^(HsSettings *s) { s->vm_shield = on; }]; }),
        HaloUISwitchRow(@"Legs", @"Shows your legs when you look down in first person.", settings->legs, ^(BOOL on) { [self update:^(HsSettings *s) { s->legs = on; }]; }),
        HaloUISwitchRow(@"High-res HUD", @"Sharper meters, radar and reticles.", settings->hires_hud, ^(BOOL on) { [self update:^(HsSettings *s) { s->hires_hud = on; }]; }),
        HaloUISwitchRow(@"High-res text", @"Menus and HUD text at the screen's resolution.", settings->hires_text, ^(BOOL on) { [self update:^(HsSettings *s) { s->hires_text = on; }]; }),
        HaloUINote(@"Shared with the in-game Video Setup, so a change in either place shows up in the other. Default field of view is the game's own; this one is the display setting and is separate from the Cheats field of view. High-res HUD and text apply the next time you open the app; turn them off again if menus or the HUD stutter.")])];

    [self add:HaloUICardView(@"Player names", @[
        HaloUISegmentRow(@"Show names of", @[@"All",@"Allies",@"Enemies",@"None"], settings->game_player_names, ^(NSInteger choice) { [self update:^(HsSettings *s) { s->game_player_names = (int)choice; }]; }),
        HaloUISegmentRow(@"Name size", @[@"50%",@"75%",@"100%",@"125%",@"150%",@"200%"], HaloNameScaleIndex(settings->name_scale), ^(NSInteger i) {
            const float scales[6]={0.5f,0.75f,1.f,1.25f,1.5f,2.f};[self update:^(HsSettings *s){s->name_scale=scales[i];}];}),
        HaloUINote(@"Shared with the in-game Network Setup and Video Setup.")])];
    [self add:HaloUICardView(@"First-person view", @[
        HaloUISegmentRow(nil, @[@"Both", @"Weapon", @"Hands", @"Hidden"], settings->viewmodel_mode, ^(NSInteger i) {
            [self update:^(HsSettings *s) { s->viewmodel_mode = (int)i; }];
        }),
        HaloUINote(@"Choose which first-person models are visible. Changes apply immediately and do not affect your HUD, attacks or other players.")])];
    [self add:HaloUICardView(@"Scoreboard", @[
        HaloUISegmentRow(@"Layout", @[@"By team",@"By score"], settings->sb_layout, ^(NSInteger i) { [self update:^(HsSettings *s) { s->sb_layout = (int)i; }]; }),
        HaloUISwitchRow(@"Panel behind the scoreboard", @"A dark panel that makes the scoreboard easier to read.", settings->sb_panel, ^(BOOL on) { [self update:^(HsSettings *s) { s->sb_panel = on; }]; })])];
    [self add:HaloUICardView(@"Text chat", @[
        HaloUISwitchRow(@"Show text chat", nil, settings->text_chat, ^(BOOL on) { [self update:^(HsSettings *s) { s->text_chat = on; }]; }),
        HaloUISegmentRow(@"Chat text", @[@"Colored names",@"All white"], settings->chat_style, ^(NSInteger i) { [self update:^(HsSettings *s) { s->chat_style = (int)i; }]; })])];

    [self add:HaloUICardView(@"Menus", @[
        HaloUISegmentRow(nil, @[@"PC menus (new)", @"Xbox menus"], settings->menu_style, ^(NSInteger index) {
            [self update:^(HsSettings *s) { s->menu_style = (int)index; }]; [self renderSoon]; }),
        HaloUINote(settings->menu_style == 0
            ? @"The Halo Custom Edition menus from Halo CE Universal: Join Game (public Server Browser, LAN and Direct Link), Create Game for the Internet or your LAN, and the redrawn screens. Navigate with the on-screen D-pad, A and B, or a controller."
            : @"The original Xbox menus, including System Link."),
        HaloUINote(@"Takes effect the next time you open the app. If the game ever fails to start, the next start (Safe Start) uses the Xbox menus automatically.")])];
    [self add:HaloUICardView(@"AirPlay and external screens", @[
        HaloUINote(@"Open iOS Control Center, choose Screen Mirroring, then select your Apple TV or compatible AirPlay display. You can also connect a supported display adapter. The game and touch controls are mirrored together. Use a physical controller for a clearer TV view. Your device and AirPlay receiver must be on a network that supports discovery; latency depends on the connection.")])];
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
        HaloUISliderRow(@"Ambient",0,1,settings->ambient_volume,@"%.2f",^(float v){[self update:^(HsSettings *s){s->ambient_volume=v;}];}),
        HaloUISwitchRow(@"Reverb",@"Echo and room sound from the places in each map, as on the original Xbox. Off keeps sounds dry.",settings->reverb,^(BOOL on){[self update:^(HsSettings *s){s->reverb=on;}];}),
        HaloUINote(@"Master, Music, Effects, Reverb and Sound stay in step with the in-game audio menu. Dialogue and Ambient (water, wind, machinery, doors) are extra iOS controls: lower Ambient if a background noise bothers you. Halo plays even when the ring/silent switch is on.")])];
    [self add:HaloUICardView(@"Voice chat", @[
        HaloUISegmentRow(@"Your microphone", @[@"Off", @"Open mic", @"Push to talk"], settings->voice_mode, ^(NSInteger i) {
            [self update:^(HsSettings *s) { s->voice_mode = (int)i; }]; }),
        HaloUISliderRow(@"Voice volume",0,2,settings->voice_volume,@"%.2f",^(float v){[self update:^(HsSettings *s){s->voice_volume=v;}];}),
        HaloUINote(@"The microphone is off by default. Open mic sends your voice whenever you speak, and a Mute button appears between Back and Start. Push to talk puts a Talk button there that you hold to speak. Off closes the microphone; you still hear other players. Voice volume is how loud they are. AirPods and other headsets with a microphone are used when connected. iOS asks for microphone access the first time. This matches the in-game Audio > Voice Chat setting.")])];
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

static NSString *HaloActiveNames(NSArray<NSString *> *names) {
    NSMutableArray *active=[NSMutableArray array];
    for(NSString *name in names)if(name.length)[active addObject:name];
    return active.count?[active componentsJoinedByString:@", "]:@"All off";
}
static NSArray<NSString *> *HaloShortcutActions(void) {
    return @[@"Disabled",@"God mode",@"Infinite ammo",@"Infinite grenades",@"Bottomless clip",@"Jetpack",@"Noclip",@"Infinite Active Camo",@"Infinite Overshield",@"Low Gravity",@"Third person",@"Wireframe",@"Unlimited flashlight",@"Rapid fire",@"No recoil",@"One-hit kills",@"No fall damage",@"AI ignores you",@"Medusa Mode",@"Infinite Vehicle Health",@"Detach Camera",@"Bumper Cars",@"Hijack NPCs",@"Apply Active Camo",@"Spawn Active Camo",@"Apply Overshield",@"Spawn Overshield",@"Restore health and shields",@"Drop Weapon Ring",@"Disabled",@"Teleport To Camera",@"Erase All AI"];
}

- (void)editShortcut:(int)slot {
    HaloShortcutEditor *editor=[HaloShortcutEditor new];editor.slot=slot;
    __weak HaloSettingsViewController *weakSelf=self;
    editor.saved=^{[weakSelf renderSoon];};
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:editor];
    nav.modalPresentationStyle=UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)buildCheats:(const HsSettings *)settings
{
    [self add:HaloUINote(@"The selected control preset activates its saved cheat recipe automatically in solo campaign. Multiplayer disables all cheats.")];
    [self add:HaloUINote(@"Tap a section to open it. Everything here works only in the solo campaign and switches itself off in multiplayer and network games.")];
    [self add:HaloUICardView(@"Splitscreen campaign", @[
        HaloUISegmentRow(@"Cheats act on", @[@"Player 1",@"Player 2",@"Both players"], settings->cheat_target, ^(NSInteger i) { [self update:^(HsSettings *s) { s->cheat_target = (int)i; }]; }),
        HaloUINote(@"In a two-player campaign, cheats such as god mode, ammo, jetpack, noclip and speed apply only to the player you choose. Game-wide cheats, like wireframe rendering and the enemy-AI ones, always stay global. One-time actions, such as restoring health or giving a weapon, go to the chosen player (Player 1 when Both is selected).")])];
#define CHEAT_SWITCH(title, sub, field) HaloUISwitchRow(title, sub, settings->field, ^(BOOL on) { [self update:^(HsSettings *s) { s->field = on; }]; })
    NSMutableArray<UIView *> *cards;

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(nil, @[
        CHEAT_SWITCH(@"God mode", @"You cannot die.", cheat_god),
        CHEAT_SWITCH(@"Infinite ammo", @"Weapons never run out; plasma weapons never need a new battery.", cheat_ammo),
        CHEAT_SWITCH(@"One-hit kills", @"Hostile units only; friendly units are protected.", cheat_one_hit),
        CHEAT_SWITCH(@"Unlimited flashlight", @"Keeps its battery full; you still toggle the light.", cheat_flashlight),
        CHEAT_SWITCH(@"No fall damage", @"The local player takes no falling or collision damage.", cheat_no_fall),
        HaloUIButton(@"Restore health and shield", 0, ^(UIButton *b) { (void)b; [self queueCampaignAction:10]; }),
        HaloUINote(@"Restore fills health and the normal shield once; an over-charged shield is never lowered. Ammo is covered by Infinite ammo.")])];
    [self addCheatSection:@"Survival" summary:HaloActiveNames(@[(settings->cheat_god)?@"God mode":@"",(settings->cheat_ammo)?@"Infinite ammo":@"",(settings->cheat_one_hit)?@"One-hit kills":@"",(settings->cheat_flashlight)?@"Unlimited flashlight":@"",(settings->cheat_no_fall)?@"No fall damage":@""]) views:cards];

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(nil, @[
        CHEAT_SWITCH(@"Bottomless clip", @"A magazine never empties.", cheat_reload),
        CHEAT_SWITCH(@"Infinite grenades", @"Throw as many as you like.", cheat_grenades),
        CHEAT_SWITCH(@"Rapid fire", @"Removes shot-rate and trigger-latch delays; charging and overheating remain.", cheat_rapid),
        CHEAT_SWITCH(@"No recoil", @"Removes the weapon kick; projectile spread is unchanged.", cheat_no_recoil)])];
    [cards addObject:HaloUICardView(@"Weapon giver",@[
        HaloUIButton(@"Weapon giver", 0, ^(UIButton *b) { [self chooseCampaignAsset:@"Weapon" names:@[@"Pistol", @"Assault rifle", @"Shotgun", @"Sniper rifle", @"Rocket launcher", @"Plasma pistol", @"Plasma rifle", @"Needler", @"Flamethrower", @"Gravity rifle"] base:100]; }),
        HaloUIButton(@"Give frag grenades",0,^(UIButton *b){(void)b;[self queueCampaignAction:400];}),
        HaloUIButton(@"Give plasma grenades",0,^(UIButton *b){(void)b;[self queueCampaignAction:401];}),
        HaloUINote(@"Weapons spawn in front of you when loaded by the map. Grenades refill once to the map’s normal capacity.")])];
    NSArray<NSString *> *projectileChoices=@[@"Original",@"Pistol bullet",@"Plasma rifle bolt",@"Needler needle",@"Rocket",@"Frag grenade",@"Plasma grenade"];
    [cards addObject:HaloUICardView(@"Projectile Swapping",@[
        HaloUIButton(projectileChoices[(NSUInteger)hs_clampi(settings->cheat_projectile,0,6)],0,^(UIButton *button){
            [self presentChoices:@"Projectile Swapping" names:projectileChoices from:self pick:^(NSUInteger choice){
                [self update:^(HsSettings *s){s->cheat_projectile=(int)choice;}];[button setTitle:projectileChoices[choice] forState:UIControlStateNormal];}];}),
        HaloUINote(@"Local player weapon fire only. The chosen projectile must already be loaded by the map. Missing assets keep the original shot; weapon tags are not modified.")])];
    [cards addObject:HaloUICardView(nil,@[HaloUIButton(@"Drop Weapon Ring Around Player",0,^(UIButton *b){(void)b;[self queueCampaignAction:11];}),HaloUINote(@"Runs cheat_all_weapons using this map’s weapon collection.")])];
    [self addCheatSection:@"Weapons" summary:HaloActiveNames(@[(settings->cheat_reload)?@"Bottomless clip":@"",(settings->cheat_grenades)?@"Infinite grenades":@"",(settings->cheat_rapid)?@"Rapid fire":@"",(settings->cheat_no_recoil)?@"No recoil":@"",(settings->cheat_projectile)?@"Projectile Swapping":@""]) views:cards];

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
    [self addCheatSection:@"Power-ups" summary:HaloActiveNames(@[(settings->cheat_camo)?@"Infinite Active Camo":@"",(settings->cheat_overshield)?@"Infinite Overshield":@""]) views:cards];

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(nil, @[
        CHEAT_SWITCH(@"Jetpack", @"The game's own jetpack: hold jump to rise.", cheat_jetpack),
        CHEAT_SWITCH(@"Low Gravity", @"Uses one-quarter gravity for this campaign. Disable to restore the previous gravity.", cheat_low_gravity),
        CHEAT_SWITCH(@"Noclip", @"Fly through walls. Aim to move; jump rises and crouch descends. Disable inside clear space.", cheat_noclip)])];
    [cards addObject:HaloUICardView(@"Super jump", @[HaloUISliderRow(@"Value", 1, 10, settings->cheat_jump, @"%.1f", ^(float value) { [self update:^(HsSettings *s) { s->cheat_jump = value; }]; }), HaloUIButton(@"Enter value", 0, ^(UIButton *b) { HsSettings current = [[HaloSettingsStore shared] snapshot]; [self enterCampaignValue:@"Super jump" value:current.cheat_jump minimum:1 maximum:10 apply:^(float value) { [self update:^(HsSettings *s) { s->cheat_jump = value; }]; }]; })])];
    [cards addObject:HaloUICardView(@"Player speed", @[HaloUISliderRow(@"Value", 1, 5, settings->cheat_speed, @"%.1f", ^(float value) { [self update:^(HsSettings *s) { s->cheat_speed = value; }]; }), HaloUIButton(@"Enter value", 0, ^(UIButton *b) { HsSettings current = [[HaloSettingsStore shared] snapshot]; [self enterCampaignValue:@"Player speed" value:current.cheat_speed minimum:1 maximum:5 apply:^(float value) { [self update:^(HsSettings *s) { s->cheat_speed = value; }]; }]; })])];
    [self addCheatSection:@"Movement" summary:HaloActiveNames(@[(settings->cheat_jetpack)?@"Jetpack":@"",(settings->cheat_noclip)?@"Noclip":@"",(settings->cheat_low_gravity)?@"Low Gravity":@"",(settings->cheat_jump > 1.01f)?@"Super jump":@"",(settings->cheat_speed > 1.01f)?@"Player speed":@""]) views:cards];

    cards = [NSMutableArray array];
    [cards addObject:HaloUICardView(@"AI Alliance",@[
        HaloUISegmentRow(nil,@[@"Original",@"Human",@"Covenant",@"Flood",@"Sentinel"],settings->cheat_alliance,^(NSInteger choice){[self update:^(HsSettings *s){s->cheat_alliance=(int)choice;}];}),
        HaloUINote(@"Changes the player's faction; AI use the map's normal team relationships. Original restores the previous team. Existing battles and scripts may not change immediately."),
        CHEAT_SWITCH(@"AI ignores you", @"Hostile units no longer notice the local player. They still fight each other and react to what they already know.", cheat_ai_ignore)])];
    NSArray<NSString *> *timeChoices=@[@"Normal (100%)",@"75%",@"50%",@"25%",@"10%",@"150%",@"200%",@"300%"];
    [cards addObject:HaloUICardView(@"Time scale",@[
        HaloUIButton(timeChoices[(NSUInteger)hs_clampi(settings->cheat_slow,0,7)],0,^(UIButton *button){
            [self presentChoices:@"Time scale" names:timeChoices from:self pick:^(NSUInteger choice){
                [self update:^(HsSettings *s){s->cheat_slow=(int)choice;}];[button setTitle:timeChoices[choice] forState:UIControlStateNormal];}];}),
        HaloUINote(@"Changes the whole campaign, including AI and cutscenes. Normal restores game speed. High values increase CPU demand.")])];
    [cards addObject:HaloUICardView(nil, @[
        CHEAT_SWITCH(@"Medusa Mode", @"Uses Halo’s Medusa behavior: hostile AI that detect the player are killed.", cheat_medusa),
        CHEAT_SWITCH(@"Bumper Cars", @"Touch an AI-driven vehicle to take its driver seat. NPC bodies and other players are excluded.", cheat_hijack_vehicle),
        CHEAT_SWITCH(@"Hijack NPCs", @"Touch a living non-player biped to possess it. Vehicles are excluded. Changing bodies may affect campaign scripts.", cheat_hijack_npc)])];

    [cards addObject:HaloUICardView(nil,@[
        HaloUIButton(@"Erase All AI",2,^(UIButton *b){(void)b;
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Erase all encounter AI?" message:@"This can prevent mission scripts from progressing. Revert a checkpoint to restore the scene." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Erase AI" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){(void)a;[self queueCampaignAction:14];}]];
            [self presentViewController:alert animated:YES completion:nil];})])];
    [self addCheatSection:@"World" summary:HaloActiveNames(@[(settings->cheat_slow)?@"Time scale":@"",(settings->cheat_ai_ignore)?@"AI ignores you":@"",(settings->cheat_medusa)?@"Medusa Mode":@"",(settings->cheat_hijack_npc)?@"Hijack NPCs":@"",(settings->cheat_hijack_vehicle)?@"Bumper Cars":@"",(settings->cheat_alliance)?@"AI Alliance":@""]) views:cards];
    cards=[NSMutableArray array];
    [cards addObject:HaloUICardView(@"Vertical FOV (0 = default)", @[HaloUISliderRow(@"Value", 0, 90, settings->cheat_fov, @"%.1f", ^(float value) { [self update:^(HsSettings *s) { s->cheat_fov = value; }]; }), HaloUIButton(@"Enter value", 0, ^(UIButton *b) { HsSettings current = [[HaloSettingsStore shared] snapshot]; [self enterCampaignValue:@"Vertical FOV (0 = default)" value:current.cheat_fov minimum:0 maximum:90 apply:^(float value) { [self update:^(HsSettings *s) { s->cheat_fov = value; }]; }]; })])];
    [cards addObject:HaloUICardView(nil,@[CHEAT_SWITCH(@"Detach Camera from Player", @"On foot: fly with the sticks, R2/RT rises and L2/LT descends. Your body stays in place. Disable to return; the world continues running.", cheat_detach_camera)])];
    [cards addObject:HaloUICardView(nil,@[
        CHEAT_SWITCH(@"Third person", @"Follow the player with the existing third-person camera.", cheat_third_person)])];
    [cards addObject:HaloUICardView(nil,@[CHEAT_SWITCH(@"Wireframe Render", @"Diagnostic triangle-edge view. Can reduce performance and expose hidden geometry; campaign only.", cheat_wireframe)])];
    [self addCheatSection:@"Visuals" summary:HaloActiveNames(@[(settings->cheat_fov > 0.5f)?@"FOV":@"",(settings->cheat_wireframe)?@"Wireframe Render":@"",(settings->cheat_detach_camera)?@"Detach Camera":@"",(settings->cheat_third_person)?@"Third person":@""]) views:cards];


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
        HaloUIButton(@"Teleport To Camera",0,^(UIButton *b){(void)b;[self queueCampaignAction:13];}),
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
    [cards addObject:HaloUICardView(nil, @[
        HaloUIButton(@"Choose a vehicle", 0, ^(UIButton *b) { [self chooseCampaignAsset:@"Spawn a vehicle" names:@[@"Warthog", @"Ghost", @"Banshee", @"Scorpion"] base:200]; }),
        HaloUINote(@"The vehicle appears in front of you. Only vehicles loaded by the current map can be spawned; others report a message.")])];
    [cards addObject:HaloUICardView(nil, @[
        CHEAT_SWITCH(@"Infinite Vehicle Health", @"Restores the occupied vehicle’s body and shields while it is alive. Cannot revive destroyed vehicles.", cheat_vehicle_health)])];
    [self addCheatSection:@"Vehicle Spawner" summary:(settings->cheat_vehicle_health?@"Infinite Vehicle Health":@"Warthog, Ghost, Banshee, Scorpion") views:cards];
#undef CHEAT_SWITCH
    NSMutableArray *bindings = [NSMutableArray array];
    for (int k=1;k<4;k++) {
        int slot=k;
        NSString *action=HaloShortcutActions()[settings->shortcuts[k].action];
        [bindings addObject:HaloUIButton([NSString stringWithFormat:@"Shortcut %d · %@",k,action],0,^(UIButton *button){(void)button;[self editShortcut:slot];})];
    }
    [bindings addObject:HaloUINote(@"Three independent input sequences toggle modifiers or run one-time actions in campaign. Multiplayer disables them; active modifier states are never saved.")];
    [self add:HaloUICardView(@"Cheat shortcuts",bindings)];
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
    NSArray<NSString *> *names=@[@"God mode",@"Infinite ammo",@"Infinite grenades",@"Bottomless clip",@"One-hit kills",@"Unlimited flashlight",@"No fall damage",@"Rapid fire",@"No recoil",@"Third person",@"Noclip",@"Infinite Active Camo",@"Infinite Overshield",@"Jetpack",@"AI ignores you",@"Medusa Mode",@"Low Gravity",@"Hijack NPCs",@"Infinite Vehicle Health",@"Wireframe Render",@"Bumper Cars",@"Detach Camera from Player"];
    for (NSUInteger bit=0;bit<names.count;++bit) {
        unsigned flag=1u<<(unsigned)(bit<15?bit:bit+3);
        [rows addArrangedSubview:HaloUISwitchRow(names[bit],nil,!!(p.cheat_flags&flag),^(BOOL on) { [self update:^(HsSettings *s) { if (on) s->presets[index].cheat_flags|=flag;else s->presets[index].cheat_flags&=~flag; }]; })];
    }
    [rows addArrangedSubview:HaloUISegmentRow(@"Time scale",@[@"Normal",@"75%",@"50%",@"25%",@"10%",@"150%",@"200%",@"300%"],p.cheat_slow,^(NSInteger value) { [self update:^(HsSettings *s) { s->presets[index].cheat_slow=(int)value; }]; })];
    NSArray<NSString *> *allianceChoices=@[@"Original",@"Human",@"Covenant",@"Flood",@"Sentinel"];
    [rows addArrangedSubview:HaloUISegmentRow(@"AI Alliance",allianceChoices,p.cheat_alliance,^(NSInteger choice){[self update:^(HsSettings *s){s->presets[index].cheat_alliance=(int)choice;}];})];
    NSArray<NSString *> *projectileChoices=@[@"Original",@"Pistol bullet",@"Plasma rifle bolt",@"Needler needle",@"Rocket",@"Frag grenade",@"Plasma grenade"];
    [rows addArrangedSubview:HaloUIButton(projectileChoices[(NSUInteger)hs_clampi(p.cheat_projectile,0,6)],0,^(UIButton *button){
        [self presentChoices:@"Preset projectile" names:projectileChoices from:weakEditor pick:^(NSUInteger choice){
            [self update:^(HsSettings *s){s->presets[index].cheat_projectile=(int)choice;}];[button setTitle:projectileChoices[choice] forState:UIControlStateNormal];}];})];
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

static UIView *HaloProfileSummary(NSString *title,NSString *detail) {
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[
        HaloUILabel(title,15,UIFontWeightSemibold,nil),HaloUINote(detail)]];
    row.axis=UILayoutConstraintAxisVertical;
    row.spacing=3;
    return row;
}

/* Lists the Halo player profiles the game has and switches to the one picked (the game does the switching, within a second). */
- (void)chooseHaloProfile {
    HaloProfileEntry list[HALO_PROFILE_MAX];
    int count=halo_ios_profile_list(list,HALO_PROFILE_MAX);
    if(count<=0){halo_ios_toast("No saved Halo player profiles yet. Make one in the game's Profiles menu first.");return;}
    NSMutableArray *names=[NSMutableArray array],*indices=[NSMutableArray array];
    for(int i=0;i<count;i++){[names addObject:[NSString stringWithFormat:@"%@%s",list[i].active?@"✓  ":@"",list[i].name]];[indices addObject:@(list[i].index)];}
    [self presentChoices:@"Halo player profile" names:names from:self pick:^(NSUInteger choice){
        if(choice>=indices.count)return;
        halo_ios_profile_select([indices[choice] unsignedIntValue]);
        halo_ios_toast("Switching profile");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self renderDetail];});
    }];
}
/* Makes a new Halo player profile in the game: a name (up to 11 ASCII characters), then an armor color. */
- (void)newHaloProfile {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"New profile" message:@"Choose a name: up to 11 ASCII letters, numbers or supported punctuation. You pick the armor color next." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"Name";f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Next" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;
        NSString *name=[alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSData *ascii=[name dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];
        if(!ascii.length||ascii.length>11||[name containsString:@"|"]){halo_ios_toast("Use 1–11 ASCII characters");return;}
        [self presentChoices:@"Armor color" names:HaloArmorColorNames() from:self pick:^(NSUInteger choice){
            (void)halo_ios_profile_create_result();
            halo_ios_profile_create(name.UTF8String,(int)choice);
            __block int tries=0;
            __block void (^check)(void)=nil;
            check=^{
                int result=halo_ios_profile_create_result();
                if(result==1){halo_ios_toast("Profile made");[self renderDetail];check=nil;return;}
                if(result==2){halo_ios_toast("The game could not make that profile. The name may be taken or invalid.");check=nil;return;}
                if(++tries>12){halo_ios_toast("Start a game or open the game's menu so it can make the profile");check=nil;return;}
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),check);
            };
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),check);
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (UIView *)engineControllerCard:(const HsSettings *)settings {
    if(!settings->game_profile_ready)return HaloUICardView(@"Halo controller settings",@[HaloUIButton(@"Choose a Halo player profile",1,^(UIButton *b){(void)b;[self chooseHaloProfile];}),HaloUINote(@"Pick the Halo player profile whose controller preferences you want to edit here.")]);
    NSMutableArray *rows=[NSMutableArray array];
    [rows addObject:HaloUISliderRow(@"Look sensitivity",1,10,settings->game_controls[0],@"%.0f",^(float value){[self update:^(HsSettings *s){s->game_controls[0]=(int)lroundf(value);}];})];
    NSArray *labels=@[@"Invert look",@"Invert flight",@"Auto-center look",@"Vibration",@"In-game help"];
    const int fields[5]={1,2,3,6,7};
    for(int i=0;i<5;i++){int field=fields[i];[rows addObject:HaloUISwitchRow(labels[i],nil,settings->game_controls[field],^(BOOL on){[self update:^(HsSettings *s){s->game_controls[field]=on;}];})];}
    [rows addObject:HaloUIButton(@"Button layout",0,^(UIButton *b){(void)b;[self presentChoices:@"Halo button layout" names:@[@"Standard",@"Swap triggers",@"Swap A and left trigger",@"Swap B and left trigger",@"Swap B and right stick"] from:self pick:^(NSUInteger choice){[self update:^(HsSettings *s){s->game_controls[4]=(int)choice;}];}];})];
    [rows addObject:HaloUIButton(@"Stick layout",0,^(UIButton *b){(void)b;[self presentChoices:@"Halo stick layout" names:@[@"Standard",@"Southpaw",@"Legacy",@"Legacy Southpaw"] from:self pick:^(NSUInteger choice){[self update:^(HsSettings *s){s->game_controls[5]=(int)choice;}];}];})];
    [rows addObject:HaloUINote(@"Shared with the selected in-game player profile. In-game changes synchronize after they are saved. These layouts apply after the iOS physical-button remap; touch-look inversion remains separate. Vibration requires a controller with supported haptics.")];
    return HaloUICardView(@"Halo controller settings",rows);
}
- (void)buildProfiles:(const HsSettings *)settings
{
    HsPreset preset = settings->presets[settings->active];
    NSString *hud = preset.hud_choice == 0 ? @"Default" : [NSString stringWithUTF8String:settings->hud_presets[preset.hud_choice - 1].name];
    unsigned recipeCount = (unsigned)__builtin_popcount(preset.cheat_flags) + (preset.cheat_slow ? 1u : 0u) + (preset.cheat_alliance?1u:0u) + (preset.cheat_projectile?1u:0u);
    [self add:HaloUICardView(@"What a profile holds", @[
        HaloProfileSummary(@"App settings", @"Controls, HUD, audio, display and shortcuts."),
        HaloProfileSummary(@"Halo player profile", @"Your in-game name, armor color, controller preferences and completed levels."),
        HaloProfileSummary(@"Campaign checkpoint", @"Progress inside a campaign level."),
        HaloUINote(@"Your name and color live in the Halo player profile, not in the app settings. “Back up and restore” below puts all three in one .halobackup file. Active cheats are never saved."),
        HaloUIValueRow(@"Control scheme in use", [NSString stringWithUTF8String:preset.name], nil),
        HaloUIValueRow(@"Game HUD", hud, nil),
        HaloUIValueRow(@"Cheat recipe in this scheme", recipeCount ? [NSString stringWithFormat:@"%u items", recipeCount] : @"None", nil)])];
    [self add:HaloUICardView(@"Campaign saves", @[
        HaloUIButton(@"Edit campaign checkpoint",0,^(UIButton *b){(void)b;UIViewController *editor=HaloCheckpointEditorController();editor.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:editor animated:YES completion:nil];}),
        HaloUINote(@"Back up or restore saves under “Back up and restore” below. Checkpoint edits cover health, shields, grenades and existing weapon ammo.")])];
    [self add:HaloUICardView(@"Halo player profiles", @[
        HaloUIButton(settings->game_profile_ready?[NSString stringWithFormat:@"Active profile: %s",settings->game_name]:@"Choose a Halo player profile",1,^(UIButton *b){(void)b;[self chooseHaloProfile];}),
        HaloUIButton(@"New profile…",0,^(UIButton *b){(void)b;[self newHaloProfile];}),
        HaloUIButton(@"In-game name",0,^(UIButton *b){(void)b;HsSettings current=[HaloSettingsStore.shared snapshot];if(!current.game_profile_ready){[self chooseHaloProfile];return;}
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"In-game name" message:@"Up to 11 ASCII letters, numbers or supported punctuation. Saved to the active Halo profile; new games use the updated name." preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=[NSString stringWithUTF8String:current.game_name];f.autocorrectionType=UITextAutocorrectionTypeNo;}];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;NSString *name=alert.textFields[0].text;NSData *ascii=[name dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];if(!ascii.length || ascii.length>11){halo_ios_toast("Use 1–11 ASCII characters");return;}[self update:^(HsSettings *s){snprintf(s->game_name,24,"%s",name.UTF8String);}];}]];
            [self presentViewController:alert animated:YES completion:nil];}),
        [self choiceButton:@"Multiplayer armor color" names:HaloArmorColorNames() current:settings->game_profile_ready?settings->game_color:-1 pick:^(NSInteger choice){
            if(![HaloSettingsStore.shared snapshot].game_profile_ready){[self chooseHaloProfile];return;}
            [self update:^(HsSettings *s){s->game_color=(int)choice;}];}],
        HaloUINote(@"In-game name and armor color edit the active Halo player profile, and travel with it when you export it above. The armor color list shows a check mark on the color saved in the profile.")])];
    [self add:HaloUINote(@"Name and color edit the active Halo player profile. Rejoin a multiplayer session to publish changes to other players. Built-in default profiles are temporary; make a new profile above to keep changes after relaunch.")];
    [self add:HaloUICardView(@"Back up and restore", @[
        HaloUIButton(@"Back up or restore…", 1, ^(UIButton *b) { (void)b;
            /* app settings (2), layouts (4), campaign saves (16) and Halo player profiles (32), ticked together */
            UIViewController *c = HaloBackupsControllerForSections(2 | 4 | 16 | 32);
            c.modalPresentationStyle = UIModalPresentationFullScreen; [self presentViewController:c animated:YES completion:nil]; }),
        HaloUINote(@"One .halobackup file holds your app settings and layouts, your Halo player profiles (name, color, completed levels) and your campaign saves. Untick any of them on the next screen. Restoring applies the next time the game starts, after a recovery backup. This is also where you restore: pick the .halobackup file and tick what to bring back.")])];
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

static NSString *HaloProblemReportWithItems(NSArray *items)
{
    struct utsname system;
    uname(&system);
    NSProcessInfo *info = NSProcessInfo.processInfo;
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    NSMutableString *report = [NSMutableString stringWithFormat:@"HALO CE iOS - problem report\nCreated: %@\nApp version: %@ (%@)\n%@\nDevice: %s, iOS %@\nThermal state: %ld (0 cool .. 3 critical), Low Power Mode: %@, memory: %llu MB\n",
        [NSDate date], version, build, HaloBuildIdentityText(), system.machine, UIDevice.currentDevice.systemVersion, (long)info.thermalState, info.isLowPowerModeEnabled ? @"on" : @"off", info.physicalMemory >> 20];
    HsSettings snapshot = [[HaloSettingsStore shared] snapshot];
    char *text = malloc(32768);
    if (text && hs_serialize(&snapshot, text, 32768) > 0) [report appendFormat:@"\n--- settings (running cheats are not included) ---\n%s\n", text];
    free(text);
    for (NSArray *item in items) {
        NSString *body = HaloLogTail(item[0], [item[1] unsignedIntegerValue]);
        if (body.length) [report appendFormat:@"\n--- %@ (the end of it) ---\n%@\n", item[0], body];
    }
    return report;
}

NSString *HaloProblemReportText(BOOL compact)
{
    return HaloProblemReportWithItems(compact
        ? @[@[@"start-history.txt", @4000], @[@"ios-boot.log", @60000], @[@"debug.txt", @20000], @[@"crash.txt", @4000], @[@"last-crash.txt", @4000], @[@"launch-phase.txt", @1000]]
        : @[@[@"start-history.txt", @4000], @[@"ios-boot.log", @200000], @[@"debug.txt", @100000], @[@"crash.txt", @4000], @[@"last-crash.txt", @4000], @[@"launch-phase.txt", @1000]]);
}

/* The same report, kept under GitHub's 65,536 characters for one text box (the device and settings come first, then the ends of the logs). */
static NSString *HaloProblemReportForGitHub(void)
{
    return HaloProblemReportWithItems(@[@[@"start-history.txt", @3000], @[@"last-crash.txt", @4000], @[@"crash.txt", @4000], @[@"launch-phase.txt", @1000], @[@"ios-boot.log", @22000], @[@"debug.txt", @12000]]);
}

static NSString *HaloQueryValue(NSString *text)
{
    NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&=+#?"];
    return [text stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

/* The GitHub problem form, with the app, its version and the device filled in. */
static NSURL *HaloProblemFormURL(void)
{
    struct utsname system;
    uname(&system);
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSString *app = @"Regular (jailbroken or TrollStore)";
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
    app = @"Non-Jailbreak (Beta)";
#endif
    if ([NSBundle.mainBundle.bundleIdentifier hasSuffix:@".modtest"]) app = @"Mod Test";
    NSString *device = [NSString stringWithFormat:@"%s, iOS %@", system.machine, UIDevice.currentDevice.systemVersion];
    NSString *address = [NSString stringWithFormat:@"https://github.com/SnailBBQ/Halo-CE-IOS/issues/new?template=bug_report.yml&build=%@&app_version=%@&device=%@",
        HaloQueryValue(app), HaloQueryValue(version), HaloQueryValue(device)];
    return [NSURL URLWithString:address];
}

/* Report a problem: the report is copied, the GitHub form opens, and the report is pasted into its Logs box. The old way (a text file
 * and the share sheet) stays as the second choice. */
- (void)reportProblem:(UIView *)source
{
    NSString *copied = HaloProblemReportForGitHub();
    UIPasteboard.generalPasteboard.string = copied;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Report a problem"
        message:@"Your problem report (device, settings and the end of the logs) is copied. The form opens on GitHub: fill it in and paste the report into the Logs box. Reports are public, so look it over first."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Open the GitHub form" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        NSURL *form = HaloProblemFormURL();
        if (form) [UIApplication.sharedApplication openURL:form options:@{} completionHandler:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Share the report as a file" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [self shareProblemReport:source];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareProblemReport:(UIView *)source
{
    NSString *report = HaloProblemReportText(NO);
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
        HaloUIButton(@"Hide / show shortcut",1,^(UIButton *button){(void)button;[self editShortcut:0];}),
        HaloUINote(@"Default: Up, Up, Down, Down, Left, Right, Left, Right, B, A. Works on touch controls or a controller. Three-finger double-tap always restores the icon; relaunch also restores it."),
        HaloUISliderRow(@"Opacity",.15f,1.f,settings->gear_opacity,@"%.2f",^(float value){[self update:^(HsSettings *s){s->gear_opacity=value;}];}),
        HaloUIButton(@"Choose icon",0,^(UIButton *button){(void)button;HaloIconPicker *picker=[HaloIconPicker new];
            __weak HaloSettingsViewController *weakSelf=self;
            picker.onFiles=^{HaloSettingsViewController *strong=weakSelf;if(!strong)return;strong.pickerKind=3;UIDocumentPickerViewController *files=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];files.delegate=strong;[strong presentViewController:files animated:YES completion:nil];};
            picker.modalPresentationStyle=UIModalPresentationFormSheet;[self presentViewController:picker animated:YES completion:^{}];}),
        HaloUINote(@"Pick a built-in icon, an emoji, or a picture from Photos or Files. Tap the star to keep a favorite at the top of the list."),
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
    [self add:HaloUICardView(@"Game and startup",@[
        [self startupRow:settings->active],
        HaloUINote(@"Saved with the current control profile. A recovery start always uses the Start Halo CE iOS Title Screen."),
        HaloUIButton(@"Quit Game",2,^(UIButton *b) { (void)b; [self confirmAppQuit]; })])];
    [self add:HaloUICardView(@"Heat and battery", @[
        HaloUISwitchRow(@"Lower the frame rate when the phone is hot", @"Smooth 60 and Uncapped drop to 45 when iOS reports serious heat or Low Power Mode, and to 30 when it is critical, and return when the phone cools. The original 30 FPS mode is never changed.", settings->thermal_cap, ^(BOOL on) { [self update:^(HsSettings *s) { s->thermal_cap = on; }]; }),
        HaloUISwitchRow(@"Performance overlay", @"A small box on the game screen. Line 1: frames per second and milliseconds per frame. Line 2: memory the game is using, memory iOS says is still free, and the heat state (cool, warm, hot, critical). Position, size and opacity follow the FPS layout; free memory is not a crash threshold.", settings->perf_overlay, ^(BOOL on) { [self update:^(HsSettings *s) { s->perf_overlay = on; }]; })])];
    [self add:HaloUICardView(@"Big multiplayer games", @[
        HaloUISwitchRow(@"Original player animations", @"Off by default. The engine's extra animation work (legs keep moving while throwing, riders' hands) is skipped, which can save a little time when 20 or more players are in view. Takes effect the next time the game starts.", !HaloConfigBool("game", "enhanced_animations", YES), ^(BOOL on) {
            if (!HaloConfigSetBool("game", "enhanced_animations", !on)) halo_ios_toast("Could not save the animation setting"); }),
        HaloUINote(@"Games with 20 to 30 players are heavy for a phone: every player is simulated and drawn. Also try Player names > None above, lower resolution in Display, and keep the phone cool. If it still drops, share the log right after the match, before closing the app.")])];
    NSMutableArray<UIView *> *diag = [NSMutableArray array];
    [diag addObject:HaloUISwitchRow(@"Performance profiler", @"Samples the game thread so Diagnostics can show where the time goes. About 1% of one CPU core.", settings->profiler, ^(BOOL on) { [self update:^(HsSettings *s) { s->profiler = on; }]; })];
    [diag addObject:HaloUIButton(@"Share log files", 0, ^(UIButton *b) { if (self.onShareLogs) self.onShareLogs(b); })];
    [diag addObject:HaloUIButton(@"Copy logs as text", 0, ^(UIButton *b) { if (self.onCopyLogs) self.onCopyLogs(b); })];
    [diag addObject:HaloUIButton(@"Report a problem…", 0, ^(UIButton *b) { [self reportProblem:b]; })];
    [diag addObject:HaloUINote(@"Copies a report (your device, your settings, never active cheats, and the end of the logs) and opens the problem form on GitHub, where you paste it. Look it over before posting: reports are public.")];
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
    NSDictionary *buildInfo=NSBundle.mainBundle.infoDictionary;
    NSString *version = buildInfo[@"CFBundleShortVersionString"] ?: @"?";
    NSString *engineCommit=buildInfo[@"HaloOpenCECommit"]?:@"?";if(engineCommit.length>12)engineCommit=[engineCommit substringToIndex:12];
    NSString *engine=[NSString stringWithFormat:@"%@ (%@)",buildInfo[@"HaloOpenCERelease"]?:@"OpenCE",engineCommit];
    NSString *network=[buildInfo[@"HaloNetworkVersion"] respondsToSelector:@selector(stringValue)]?[buildInfo[@"HaloNetworkVersion"] stringValue]:@"?";
    NSString *guest=buildInfo[@"HaloGuestSHA256"]?:@"unknown";if(guest.length>16)guest=[guest substringToIndex:16];
    [self add:HaloUICardView(@"About", @[
        HaloUIValueRow(@"App version", version, nil),
        HaloUIValueRow(@"Source milestone", buildInfo[@"HaloSourceMilestone"]?:@"?", nil),
        HaloUIValueRow(@"Engine", engine, nil),
        HaloUIValueRow(@"Network version", network, nil),
        HaloUIValueRow(@"Build flavor", buildInfo[@"HaloBuildFlavor"]?:@"Development", nil),
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
        HaloUIValueRow(@"Release status", @"Beta: may have glitches, bugs and crashes", nil),
#endif
        HaloUIValueRow(@"Guest architecture", buildInfo[@"HaloGuestArchitecture"]?:@"?", nil),
        HaloUIValueRow(@"Guest adaptation", buildInfo[@"HaloGuestAdaptation"]?:@"?", nil),
        HaloUIValueRow(@"Guest SHA-256", guest, nil),
        HaloUIValueRow(@"Renderer", buildInfo[@"HaloRenderer"]?:@"?", nil),
        HaloUINote(@"Everyone in a multiplayer game must use a compatible OpenCE network version. Share logs includes this exact build identity.")])];
    [self add:HaloUICardView(@"Credits",@[
        HaloUINote(@"Halo CE Universal and the iOS port contributors."),
        HaloUIButton(@"Halo-CE-IOS on GitHub",0,^(UIButton *b) { [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/SnailBBQ/Halo-CE-IOS"] options:@{} completionHandler:nil]; })])];
}
/* Bonjour browsing invokes the system's Local Network privacy flow. This
 * diagnostic does not replace Halo's existing UDP LAN discovery transport. */
- (void)requestLocalNetworkAccess {
    [self.localNetworkProbe stop];[self.localNetworkPublisher stop];
    self.localNetworkStatus.text=@"Checking on this Wi-Fi network. Respond to the iOS prompt if it appears…";
    NSNetServiceBrowser *probe=[NSNetServiceBrowser new];self.localNetworkProbe=probe;probe.delegate=self;
    [probe searchForServicesOfType:@"_haloce-check._tcp." inDomain:@"local."];
    NSNetService *publisher=[[NSNetService alloc] initWithDomain:@"local." type:@"_haloce-check._tcp." name:[@"Halo-Access-" stringByAppendingString:NSUUID.UUID.UUIDString] port:0];
    self.localNetworkPublisher=publisher;publisher.delegate=self;
    [publisher publishWithOptions:NSNetServiceListenForConnections];
    __weak typeof(self) weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(weakSelf.localNetworkProbe==probe){
            [probe stop];[publisher stop];weakSelf.localNetworkProbe=nil;weakSelf.localNetworkPublisher=nil;
            if([weakSelf.localNetworkStatus.text hasPrefix:@"Checking"])
                weakSelf.localNetworkStatus.text=@"No permission result received. Check Wi-Fi and the signed app's privacy declarations. This is not confirmation of access.";
        }
    });
}
- (void)netServiceDidPublish:(NSNetService *)sender {
    if(sender!=self.localNetworkPublisher)return;
    self.localNetworkStatus.text=@"Bonjour publication succeeded. LAN broadcast discovery still depends on signing and your Wi-Fi network.";
    NSLog(@"[HaloIOS-LAN] Bonjour permission check published successfully");
}
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *,NSNumber *> *)errors {
    if(sender!=self.localNetworkPublisher)return;
    self.localNetworkStatus.text=[NSString stringWithFormat:@"Local Network publication failed (domain %@, code %@). Check permission and signing. Use an invite if LAN discovery is unavailable.",errors[NSNetServicesErrorDomain],errors[NSNetServicesErrorCode]];
    NSLog(@"[HaloIOS-LAN] publish failed: %@",errors);
    [sender stop];
}
- (void)netService:(NSNetService *)sender didAcceptConnectionWithInputStream:(NSInputStream *)input outputStream:(NSOutputStream *)output {
    (void)sender;[input close];[output close]; /* permission diagnostic, never a game server */
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errors {
    if(browser!=self.localNetworkProbe)return;
    [browser stop];self.localNetworkProbe=nil;[self.localNetworkPublisher stop];self.localNetworkPublisher=nil;
    self.localNetworkStatus.text=[NSString stringWithFormat:@"Local Network browsing failed (domain %@, code %@). Check Wi-Fi, permission and signing.",errors[NSNetServicesErrorDomain],errors[NSNetServicesErrorCode]];
    NSLog(@"[HaloIOS-LAN] browse failed: %@",errors);
}
- (void)confirmAppQuit {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Quit Halo" message:@"Close Halo completely? Unsaved progress will be lost." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Quit" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { halo_ios_quit_app(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
@implementation HaloSettingsSearch
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=HaloUIBackground();
    self.rows=calloc((size_t)HSS_COUNT,sizeof(int));self.query=@"";
    UILabel *title=HaloUILabel(@"Search settings",20,UIFontWeightBold,nil);title.translatesAutoresizingMaskIntoConstraints=NO;
    UIButton *close=HaloUIButton(@"Close",0,^(UIButton *b){(void)b;[self dismissViewControllerAnimated:YES completion:nil];});close.translatesAutoresizingMaskIntoConstraints=NO;
    self.bar=[UISearchBar new];self.bar.translatesAutoresizingMaskIntoConstraints=NO;self.bar.delegate=self;self.bar.placeholder=@"Search options, e.g. “mic”, “FPS”, “vehicle”";
    self.bar.searchBarStyle=UISearchBarStyleMinimal;self.bar.autocapitalizationType=UITextAutocapitalizationTypeNone;self.bar.autocorrectionType=UITextAutocorrectionTypeNo;self.bar.returnKeyType=UIReturnKeyDone;
    self.table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];self.table.translatesAutoresizingMaskIntoConstraints=NO;
    self.table.dataSource=self;self.table.delegate=self;self.table.backgroundColor=UIColor.clearColor;self.table.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:title];[self.view addSubview:close];[self.view addSubview:self.bar];[self.view addSubview:self.table];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14],[title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],[close.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],[close.heightAnchor constraintEqualToConstant:44],[close.widthAnchor constraintEqualToConstant:84],
        [self.bar.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],[self.bar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:10],[self.bar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-10],
        [self.table.topAnchor constraintEqualToAnchor:self.bar.bottomAnchor],[self.table.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[self.table.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    [self reload];
}
- (void)viewDidAppear:(BOOL)animated {[super viewDidAppear:animated];[self.bar becomeFirstResponder];}
- (void)dealloc {free(self.rows);}
- (void)reload {
    NSString *q=[self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    self.rowCount=q.length?hss_search(q.UTF8String,self.rows,HSS_COUNT):hss_suggestions(self.rows,HSS_COUNT);
    [self.table reloadData];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {(void)searchBar;self.query=searchText?:@"";[self reload];}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {[searchBar resignFirstResponder];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {(void)tableView;return 1;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {(void)tableView;(void)section;return MAX(self.rowCount,1);}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;(void)section;
    if(!self.query.length)return @"Suggested";
    return self.rowCount?[NSString stringWithFormat:@"%d result%@",self.rowCount,self.rowCount==1?@"":@"s"]:@"No results";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"hit"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"hit"];
    cell.backgroundColor=HaloUICard();cell.textLabel.textColor=UIColor.whiteColor;cell.detailTextLabel.textColor=HaloUISecondaryText();cell.tintColor=HaloUIAccent();
    if(!self.rowCount){cell.textLabel.text=@"Nothing matches";cell.detailTextLabel.text=@"Try a shorter word, like “sound”, “look” or “map”.";cell.imageView.image=nil;cell.accessoryType=UITableViewCellAccessoryNone;cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;}
    const HssEntry *entry=&hss_entries[self.rows[indexPath.row]];
    cell.textLabel.text=[NSString stringWithUTF8String:entry->title];
    cell.detailTextLabel.text=[NSString stringWithUTF8String:hss_category_names[entry->category]];
    cell.imageView.image=[[UIImage systemImageNamed:HaloCategorySymbol((HaloCategory)entry->category)] imageWithTintColor:HaloUIAccent() renderingMode:UIImageRenderingModeAlwaysOriginal];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleDefault;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(!self.rowCount)return;
    const HssEntry *entry=&hss_entries[self.rows[indexPath.row]];
    int category=entry->category;NSString *title=[NSString stringWithUTF8String:entry->title];void (^pick)(int,NSString *)=self.pick;
    [self dismissViewControllerAnimated:YES completion:^{if(pick)pick(category,title);}];
}
@end

#pragma mark - Settings button pictures

static NSString *HaloGearPhotoFolder(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Halo/icons"]; }

static UIImage *HaloEmojiImage(NSString *emoji) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (cache[emoji]) return cache[emoji];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(128, 128)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        NSDictionary *attributes = @{ NSFontAttributeName: [UIFont systemFontOfSize:92] };
        CGSize size = [emoji sizeWithAttributes:attributes];
        [emoji drawAtPoint:CGPointMake((128 - size.width) / 2, (128 - size.height) / 2) withAttributes:attributes];
    }];
    cache[emoji] = image;
    return image;
}

/* A token is "s0".."s3" (built-in), "e:<emoji>" or "p:<8 hex>" (a photo in Documents/Halo/icons). */
static UIImage *HaloTokenImage(NSString *token, BOOL large) {
    if ([token hasPrefix:@"e:"] && token.length > 2) return HaloEmojiImage([token substringFromIndex:2]);
    if ([token hasPrefix:@"p:"] && token.length == 10) {
        for (NSUInteger i = 2; i < token.length; i++) if (!isxdigit([token characterAtIndex:i])) return nil;
        return [UIImage imageWithContentsOfFile:[HaloGearPhotoFolder() stringByAppendingPathComponent:[[token substringFromIndex:2] stringByAppendingString:@".png"]]];
    }
    if (token.length == 2 && [token hasPrefix:@"s"]) {
        int n = [token characterAtIndex:1] - '0';
        NSArray *names = @[@"gearshape.fill", @"slider.horizontal.3", @"gamecontroller.fill", @"circle.grid.2x2.fill"];
        if (n >= 0 && n < 4) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:large ? 28 : 20 weight:UIImageSymbolWeightSemibold];
            return [[UIImage systemImageNamed:names[(NSUInteger)n] withConfiguration:config] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }
    return nil;
}

UIImage *HaloGearCustomImage(const void *raw) {
    const HsSettings *settings = raw;
    UIImage *image = nil;
    if (settings->gear_icon == 5) image = HaloTokenImage([NSString stringWithUTF8String:settings->gear_token], NO);
    else if (settings->gear_icon == 4) image = [UIImage imageWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Halo/settings-icon.png"]];
    return image;
}

/* Saves a 128 point picture as a photo icon and returns its token ("p:xxxxxxxx"). */
static NSString *HaloSaveGearPhoto(UIImage *image) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(128, 128)];
    UIImage *icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        CGFloat scale = MIN(128 / image.size.width, 128 / image.size.height);
        CGSize fitted = CGSizeMake(image.size.width * scale, image.size.height * scale);
        [image drawInRect:CGRectMake((128 - fitted.width) / 2, (128 - fitted.height) / 2, fitted.width, fitted.height)];
    }];
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:HaloGearPhotoFolder() withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *name = [NSString stringWithFormat:@"%08x", arc4random()];
    NSString *path = [HaloGearPhotoFolder() stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
    if (![UIImagePNGRepresentation(icon) writeToFile:path atomically:YES]) return nil;
    /* keep the folder small: the 24 newest pictures */
    NSArray *names = [files contentsOfDirectoryAtPath:HaloGearPhotoFolder() error:nil];
    if (names.count > 24) {
        NSArray *sorted = [names sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSDate *da = [files attributesOfItemAtPath:[HaloGearPhotoFolder() stringByAppendingPathComponent:a] error:nil][NSFileModificationDate] ?: NSDate.distantPast;
            NSDate *db = [files attributesOfItemAtPath:[HaloGearPhotoFolder() stringByAppendingPathComponent:b] error:nil][NSFileModificationDate] ?: NSDate.distantPast;
            return [da compare:db];
        }];
        for (NSUInteger i = 0; i + 24 < sorted.count; i++) [files removeItemAtPath:[HaloGearPhotoFolder() stringByAppendingPathComponent:sorted[i]] error:nil];
    }
    return [@"p:" stringByAppendingString:name];
}

static NSString *HaloCurrentGearToken(const HsSettings *s) {
    if (s->gear_icon == 5) return [NSString stringWithUTF8String:s->gear_token];
    if (s->gear_icon >= 0 && s->gear_icon < 4) return [NSString stringWithFormat:@"s%d", s->gear_icon];
    return @"";
}

static void HaloApplyGearToken(NSString *token) {
    [HaloSettingsStore.shared update:^(HsSettings *s) {
        if (token.length == 2 && [token hasPrefix:@"s"]) { s->gear_icon = [token characterAtIndex:1] - '0'; s->gear_token[0] = 0; }
        else { s->gear_icon = 5; strncpy(s->gear_token, token.UTF8String, sizeof(s->gear_token) - 1); s->gear_token[sizeof(s->gear_token) - 1] = 0; }
    }];
}

static NSArray<NSString *> *HaloFavoriteTokens(const HsSettings *s) {
    NSString *all = [NSString stringWithUTF8String:s->gear_favs];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *part in [all componentsSeparatedByString:@"|"]) if (part.length) [tokens addObject:part];
    return tokens;
}

static BOOL HaloToggleFavorite(NSString *token) {   /* NO when the list is full */
    __block BOOL ok = YES;
    [HaloSettingsStore.shared update:^(HsSettings *s) {
        NSMutableArray *tokens = [HaloFavoriteTokens(s) mutableCopy];
        if ([tokens containsObject:token]) [tokens removeObject:token];
        else {
            [tokens addObject:token];
            if ([tokens componentsJoinedByString:@"|"].length >= sizeof(s->gear_favs)) { ok = NO; return; }
        }
        strncpy(s->gear_favs, [tokens componentsJoinedByString:@"|"].UTF8String, sizeof(s->gear_favs) - 1);
        s->gear_favs[sizeof(s->gear_favs) - 1] = 0;
    }];
    return ok;
}

@implementation HaloIconPicker
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = HaloUIBackground();
    UILabel *title = HaloUILabel(@"Settings button icon", 20, UIFontWeightBold, nil);
    title.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton *close = HaloUIButton(@"Done", 1, ^(UIButton *b) { (void)b; [self dismissViewControllerAnimated:YES completion:nil]; });
    close.translatesAutoresizingMaskIntoConstraints = NO;
    self.field = [UITextField new];
    self.field.translatesAutoresizingMaskIntoConstraints = NO;
    self.field.placeholder = @"Type or paste an emoji";
    self.field.textColor = UIColor.whiteColor;
    self.field.backgroundColor = HaloUICard();
    self.field.layer.cornerRadius = 10;
    self.field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 10)];
    self.field.leftViewMode = UITextFieldViewModeAlways;
    self.field.delegate = self;
    self.field.returnKeyType = UIReturnKeyDone;
    self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    UIButton *use = HaloUIButton(@"Use emoji", 1, ^(UIButton *b) { (void)b; [self useTypedEmoji]; });
    use.translatesAutoresizingMaskIntoConstraints = NO;
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    for (UIView *view in @[title, close, self.field, use, self.table]) [self.view addSubview:view];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14], [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor], [close.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [close.heightAnchor constraintEqualToConstant:44], [close.widthAnchor constraintEqualToConstant:84],
        [self.field.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14], [self.field.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.field.heightAnchor constraintEqualToConstant:44],
        [use.leadingAnchor constraintEqualToAnchor:self.field.trailingAnchor constant:10], [use.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [use.centerYAnchor constraintEqualToAnchor:self.field.centerYAnchor], [use.widthAnchor constraintEqualToConstant:112], [use.heightAnchor constraintEqualToConstant:44],
        [self.table.topAnchor constraintEqualToAnchor:self.field.bottomAnchor constant:8], [self.table.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor], [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    [self reload];
}
- (void)reload {
    HsSettings s = [HaloSettingsStore.shared snapshot];
    NSMutableArray *sections = [NSMutableArray array], *titles = [NSMutableArray array];
    NSArray *favorites = HaloFavoriteTokens(&s);
    if (favorites.count) { [sections addObject:favorites]; [titles addObject:@"Favorites"]; }
    [sections addObject:@[@"s0", @"s1", @"s2", @"s3"]]; [titles addObject:@"Built-in"];
    NSMutableArray *emoji = [NSMutableArray array];
    NSString *current = HaloCurrentGearToken(&s);
    NSArray *quick = @[@"e:🎮", @"e:🪖", @"e:🛡️", @"e:🚀", @"e:⭐", @"e:💥", @"e:👾", @"e:🐗", @"e:⚙️", @"e:🔧"];
    if ([current hasPrefix:@"e:"] && ![quick containsObject:current]) [emoji addObject:current];
    [emoji addObjectsFromArray:quick];
    [sections addObject:emoji]; [titles addObject:@"Emoji"];
    NSMutableArray *photos = [NSMutableArray array];
    NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:HaloGearPhotoFolder() error:nil] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) if ([name.pathExtension isEqual:@"png"] && name.stringByDeletingPathExtension.length == 8) [photos addObject:[@"p:" stringByAppendingString:name.stringByDeletingPathExtension]];
    [sections addObject:photos]; [titles addObject:@"Your photos"];
    self.sections = sections; self.titles = titles;
    [self.table reloadData];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; [self useTypedEmoji]; return YES; }
- (void)useTypedEmoji {
    NSString *text = [self.field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    __block NSString *emoji = nil;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *piece, NSRange r, NSRange er, BOOL *stop) {
        (void)r; (void)er; emoji = piece; *stop = YES;
    }];
    if (!emoji.length || [emoji lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 30 || [emoji stringByTrimmingCharactersInSet:NSCharacterSet.alphanumericCharacterSet].length == 0) {
        halo_ios_toast("Type one emoji"); return;
    }
    emoji = [emoji stringByReplacingOccurrencesOfString:@"|" withString:@""];
    HaloApplyGearToken([@"e:" stringByAppendingString:emoji]);
    self.field.text = @""; [self.field resignFirstResponder]; [self reload];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return (NSInteger)self.sections.count + 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == (NSInteger)self.sections.count) return 2;   /* Photos, Files */
    return (NSInteger)self.sections[(NSUInteger)section].count + (self.sections[(NSUInteger)section].count == 0 && [self.titles[(NSUInteger)section] isEqual:@"Your photos"] ? 1 : 0);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == (NSInteger)self.sections.count ? @"Add a picture" : self.titles[(NSUInteger)section];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = HaloUICard(); cell.textLabel.textColor = UIColor.whiteColor; cell.tintColor = HaloUIAccent();
    if (indexPath.section == (NSInteger)self.sections.count) {
        cell.textLabel.text = indexPath.row == 0 ? @"Choose from Photos…" : @"Choose from Files…";
        cell.imageView.image = [[UIImage systemImageNamed:indexPath.row == 0 ? @"photo.on.rectangle" : @"folder"] imageWithTintColor:HaloUIAccent() renderingMode:UIImageRenderingModeAlwaysOriginal];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    NSArray *tokens = self.sections[(NSUInteger)indexPath.section];
    if (!tokens.count) { cell.textLabel.text = @"Photos you pick appear here"; cell.textLabel.textColor = HaloUISecondaryText(); cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell; }
    NSString *token = tokens[(NSUInteger)indexPath.row];
    HsSettings s = [HaloSettingsStore.shared snapshot];
    BOOL selected = [HaloCurrentGearToken(&s) isEqualToString:token];
    BOOL favorite = [HaloFavoriteTokens(&s) containsObject:token];
    if ([token hasPrefix:@"e:"]) { cell.textLabel.text = [token substringFromIndex:2]; cell.textLabel.font = [UIFont systemFontOfSize:30]; }
    else if ([token hasPrefix:@"p:"]) cell.textLabel.text = @"Photo";
    else cell.textLabel.text = @[@"Default gear", @"Sliders", @"Controller", @"Grid"][(NSUInteger)MAX(0, MIN(3, [token characterAtIndex:1] - '0'))];
    if (![token hasPrefix:@"e:"]) {
        UIImage *picture = HaloTokenImage(token, YES);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(36, 36)];
        cell.imageView.image = picture ? [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) { (void)context; [picture drawInRect:CGRectMake(0, 0, 36, 36)]; }] : nil;
    }
    cell.backgroundColor = selected ? [HaloUIAccent() colorWithAlphaComponent:0.35] : HaloUICard();
    UIButton *star = [UIButton buttonWithType:UIButtonTypeSystem];
    star.frame = CGRectMake(0, 0, 44, 44);
    [star setImage:[UIImage systemImageNamed:favorite ? @"star.fill" : @"star"] forState:UIControlStateNormal];
    star.tintColor = favorite ? [UIColor colorWithRed:1 green:0.8 blue:0.2 alpha:1] : HaloUISecondaryText();
    star.accessibilityLabel = favorite ? @"Remove from favorites" : @"Add to favorites";
    __weak HaloIconPicker *weakSelf = self;
    [star addAction:[UIAction actionWithHandler:^(UIAction *action) {
        (void)action;
        if (!HaloToggleFavorite(token)) halo_ios_toast("Favorites are full. Remove one first.");
        [weakSelf reload];
    }] forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView = star;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == (NSInteger)self.sections.count) {
        if (indexPath.row == 0) {
            if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) { halo_ios_toast("Photos are not available"); return; }
            UIImagePickerController *picker = [UIImagePickerController new];
            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.allowsEditing = YES;   /* a square crop */
            picker.delegate = self;
            [self presentViewController:picker animated:YES completion:nil];
        } else {
            void (^files)(void) = self.onFiles;
            [self dismissViewControllerAnimated:YES completion:^{ if (files) files(); }];
        }
        return;
    }
    NSArray *tokens = self.sections[(NSUInteger)indexPath.section];
    if (indexPath.row >= (NSInteger)tokens.count) return;
    HaloApplyGearToken(tokens[(NSUInteger)indexPath.row]);
    [self reload];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!image || !image.CGImage) { halo_ios_toast("Could not read that picture"); return; }
    NSString *token = HaloSaveGearPhoto(image);
    if (!token) { halo_ios_toast("Could not save the icon"); return; }
    HaloApplyGearToken(token);
    [self reload];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
@end
