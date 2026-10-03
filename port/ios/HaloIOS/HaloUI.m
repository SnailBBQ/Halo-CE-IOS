#import "HaloUI.h"
#import "HaloSettingsStore.h"

UIColor *HaloUIBackground(void) { return [UIColor colorWithRed:0.055 green:0.063 blue:0.078 alpha:1]; }
UIColor *HaloUICard(void) { return [UIColor colorWithRed:0.105 green:0.118 blue:0.145 alpha:1]; }
UIColor *HaloUIAccent(void) {
    switch([HaloSettingsStore.shared snapshot].ui_theme){
        case 1:return [UIColor colorWithRed:.08 green:.48 blue:.26 alpha:1];
        case 2:return [UIColor colorWithRed:.48 green:.27 blue:.78 alpha:1];
        case 3:return [UIColor colorWithRed:.70 green:.34 blue:.02 alpha:1];
        case 4:return [UIColor colorWithRed:.72 green:.19 blue:.34 alpha:1];
        default:return [UIColor colorWithRed:.20 green:.52 blue:.98 alpha:1];
    }
}
void HaloUIApplyAccent(UIView *root) {
    UIColor *accent=HaloUIAccent();root.tintColor=accent;
    if([root.accessibilityIdentifier isEqual:@"HaloAccentButton"])root.backgroundColor=accent;
    for(UIView *child in root.subviews)HaloUIApplyAccent(child);
}
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
