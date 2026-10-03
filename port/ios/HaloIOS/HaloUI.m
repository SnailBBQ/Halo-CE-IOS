#import "HaloUI.h"
#import "HaloSettingsStore.h"
#import "halo_color.h"

UIColor *HaloUIBackground(void) { return [UIColor colorWithRed:0.055 green:0.063 blue:0.078 alpha:1]; }
UIColor *HaloUICard(void) { return [UIColor colorWithRed:0.105 green:0.118 blue:0.145 alpha:1]; }
static UIColor *HaloUIColorFromRGB(unsigned rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}
UIColor *HaloUIAccent(void) {
    HsSettings settings=[HaloSettingsStore.shared snapshot];
    if(settings.accent_mode==1)return HaloUIColorFromRGB(hx_clamp_accent(settings.accent_rgb));
    if(settings.accent_mode==2)return HaloUIColorFromRGB(hx_chroma(CACurrentMediaTime(),settings.chroma_seconds));
    switch(settings.ui_theme){
        case 1:return [UIColor colorWithRed:.08 green:.48 blue:.26 alpha:1];
        case 2:return [UIColor colorWithRed:.48 green:.27 blue:.78 alpha:1];
        case 3:return [UIColor colorWithRed:.70 green:.34 blue:.02 alpha:1];
        case 4:return [UIColor colorWithRed:.72 green:.19 blue:.34 alpha:1];
        default:return [UIColor colorWithRed:.20 green:.52 blue:.98 alpha:1];
    }
}
/* Sidebar rows keep their white icon and text: the selected row's background is the accent colour, so an accent-tinted icon
 * would vanish into it. Everything else follows the accent. */
static void HaloUIApplyAccentWith(UIView *root,UIColor *accent) {
    if([root.accessibilityIdentifier isEqual:@"HaloSidebarRow"])return;
    root.tintColor=accent;
    if([root isKindOfClass:UISwitch.class])((UISwitch *)root).onTintColor=accent;
    else if([root isKindOfClass:UISlider.class])((UISlider *)root).minimumTrackTintColor=accent;
    else if([root isKindOfClass:UISegmentedControl.class])((UISegmentedControl *)root).selectedSegmentTintColor=accent;
    if([root.accessibilityIdentifier isEqual:@"HaloAccentButton"])root.backgroundColor=accent;
    for(UIView *child in root.subviews)HaloUIApplyAccentWith(child,accent);
}
void HaloUIApplyAccent(UIView *root) { HaloUIApplyAccentWith(root,HaloUIAccent()); }
UIColor *HaloUIGreen(void) { return [UIColor colorWithRed:0.30 green:0.82 blue:0.45 alpha:1]; }
UIColor *HaloUIAmber(void) { return [UIColor colorWithRed:1.00 green:0.74 blue:0.28 alpha:1]; }
UIColor *HaloUIRed(void) { return [UIColor colorWithRed:1.00 green:0.40 blue:0.40 alpha:1]; }
UIColor *HaloUISecondaryText(void) { return [UIColor colorWithWhite:0.62 alpha:1]; }

UILabel *HaloUILabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color)
{
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.numberOfLines = 0;
    label.textColor = color ?: UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    return label;
}

UILabel *HaloUINote(NSString *text)
{
    return HaloUILabel(text, 12.5, UIFontWeightRegular, HaloUISecondaryText());
}

UIView *HaloUICardView(NSString *title, NSArray<UIView *> *rows)
{
    NSMutableArray<UIView *> *all = [NSMutableArray array];
    if (title.length)
        [all addObject:HaloUILabel(title.uppercaseString, 12, UIFontWeightBold, HaloUISecondaryText())];
    [all addObjectsFromArray:rows];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:all];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.layoutMargins = UIEdgeInsetsMake(14, 16, 14, 16);
    stack.layoutMarginsRelativeArrangement = YES;
    stack.backgroundColor = HaloUICard();
    stack.layer.cornerRadius = 14;
    stack.clipsToBounds = YES;
    return stack;
}

UIView *HaloUIValueRow(NSString *name, NSString *value, UIColor *valueColor)
{
    UILabel *left = HaloUILabel(name, 15, UIFontWeightRegular, nil);
    UILabel *right = HaloUILabel(value, 15, UIFontWeightSemibold, valueColor ?: UIColor.whiteColor);
    right.textAlignment = NSTextAlignmentRight;
    [right setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [left setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[left, right]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentFirstBaseline;
    return row;
}

UIView *HaloUISwitchRow(NSString *title, NSString *subtitle, BOOL on, void (^change)(BOOL on))
{
    UILabel *name = HaloUILabel(title, 15.5, UIFontWeightRegular, nil);
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[name]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 3;
    if (subtitle.length) [text addArrangedSubview:HaloUINote(subtitle)];
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = on;
    toggle.onTintColor = HaloUIAccent();
    [toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [toggle addAction:[UIAction actionWithHandler:^(UIAction *action) { if (change) change(toggle.on); }]
     forControlEvents:UIControlEventValueChanged];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[text, toggle]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

UIView *HaloUISliderRow(NSString *title, float min, float max, float value, NSString *format, void (^change)(float value))
{
    UILabel *name = HaloUILabel(title, 15.5, UIFontWeightRegular, nil);
    UILabel *shown = HaloUILabel([NSString stringWithFormat:format, value], 15, UIFontWeightSemibold, HaloUISecondaryText());
    shown.textAlignment = NSTextAlignmentRight;
    UISlider *slider = [[UISlider alloc] init];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    slider.minimumTrackTintColor = HaloUIAccent();
    __weak UILabel *weakShown = shown;
    [slider addAction:[UIAction actionWithHandler:^(UIAction *action) {
        weakShown.text = [NSString stringWithFormat:format, slider.value];
        if (change) change(slider.value);
    }] forControlEvents:UIControlEventValueChanged];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[name, shown]];
    top.axis = UILayoutConstraintAxisHorizontal;
    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[top, slider]];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 6;
    return column;
}

UIButton *HaloUIButton(NSString *title, NSInteger style, void (^tap)(UIButton *button))
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];
    if(style==1)button.accessibilityIdentifier=@"HaloAccentButton";
    UIColor *background = style == 1 ? HaloUIAccent() : [UIColor colorWithWhite:0.20 alpha:1];
    UIColor *text = style == 2 ? HaloUIRed() : UIColor.whiteColor;
    [button setTitleColor:text forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:0.45 alpha:1] forState:UIControlStateDisabled];
    button.backgroundColor = background;
    button.layer.cornerRadius = 10;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:42].active = YES;
    __weak UIButton *weak = button;
    [button addAction:[UIAction actionWithHandler:^(UIAction *action) { if (weak && tap) tap(weak); }]
     forControlEvents:UIControlEventTouchUpInside];
    return button;
}

UIView *HaloUISegmentRow(NSString *title, NSArray<NSString *> *options, NSInteger selected, void (^change)(NSInteger index))
{
    UISegmentedControl *segments = [[UISegmentedControl alloc] initWithItems:options];
    segments.selectedSegmentIndex = selected;
    segments.selectedSegmentTintColor = HaloUIAccent();
    [segments setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor } forState:UIControlStateNormal];
    [segments setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor } forState:UIControlStateSelected];
    [segments addAction:[UIAction actionWithHandler:^(UIAction *action) { if (change) change(segments.selectedSegmentIndex); }]
       forControlEvents:UIControlEventValueChanged];
    if (!title.length) return segments;
    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[HaloUILabel(title, 15.5, UIFontWeightRegular, nil), segments]];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 8;
    return column;
}

UIView *HaloUIPill(NSString *text, UIColor *color)
{
    UILabel *label = HaloUILabel(text.uppercaseString, 12, UIFontWeightBold, UIColor.blackColor);
    label.textAlignment = NSTextAlignmentCenter;
    UIView *pill = [[UIView alloc] init];
    pill.backgroundColor = color;
    pill.layer.cornerRadius = 11;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [pill addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-10],
        [label.topAnchor constraintEqualToAnchor:pill.topAnchor constant:4],
        [label.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-4]]];
    return pill;
}

UIStackView *HaloUIScrollingStack(UIView *container, CGFloat spacing)
{
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [container addSubview:scroll];
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:4],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-40],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:4],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-4]]];
    return stack;
}

UIButton *HaloUIDisclosureHeader(NSString *title, NSString *summary, BOOL expanded, void (^toggle)(void)) {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor=HaloUICard();button.layer.cornerRadius=14;
    UILabel *name=HaloUILabel(title,17,UIFontWeightSemibold,nil);
    UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[name]];text.axis=UILayoutConstraintAxisVertical;text.spacing=2;
    if(summary.length)[text addArrangedSubview:HaloUINote(summary)];
    UIImageView *chevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:expanded?@"chevron.down":@"chevron.right"]];
    chevron.tintColor=HaloUISecondaryText();chevron.contentMode=UIViewContentModeScaleAspectFit;
    [chevron setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [chevron.widthAnchor constraintEqualToConstant:18].active=YES;
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[text,chevron]];
    row.axis=UILayoutConstraintAxisHorizontal;row.spacing=10;row.alignment=UIStackViewAlignmentCenter;row.userInteractionEnabled=NO;row.translatesAutoresizingMaskIntoConstraints=NO;
    [button addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:button.topAnchor constant:14],[row.bottomAnchor constraintEqualToAnchor:button.bottomAnchor constant:-14],
        [row.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:16],[row.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-16]]];
    [button addAction:[UIAction actionWithHandler:^(UIAction *action){(void)action;if(toggle)toggle();}] forControlEvents:UIControlEventTouchUpInside];
    return button;
}
