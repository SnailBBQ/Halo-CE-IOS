#import "halo_ios_controls.h"
#import "halo_guest_runner.h"
#import "halo_controls_layout.h"
#import "HaloSettingsStore.h"

#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>

static UIColor *HaloColor(int color, CGFloat alpha)
{
    switch (color) {
        case HC_COLOR_GREEN:  return [UIColor colorWithRed:0.10 green:0.68 blue:0.24 alpha:alpha];
        case HC_COLOR_RED:    return [UIColor colorWithRed:0.86 green:0.13 blue:0.16 alpha:alpha];
        case HC_COLOR_BLUE:   return [UIColor colorWithRed:0.12 green:0.40 blue:0.92 alpha:alpha];
        case HC_COLOR_YELLOW: return [UIColor colorWithRed:0.98 green:0.80 blue:0.10 alpha:alpha];
        case HC_COLOR_BLACK:  return [UIColor colorWithWhite:0.05 alpha:alpha];
        case HC_COLOR_WHITE:  return [UIColor colorWithWhite:0.96 alpha:alpha];
        default:              return [UIColor colorWithWhite:0.45 alpha:alpha];
    }
}

/* what a finger is doing */
enum { kRoleLeftZone = -2, kRoleLook = -3, kRoleEditDrag = 1000 /* + control */ };

static const char *const kControlNames[HC_COUNT] = {
    "Left trigger", "Right trigger", "Back", "Start", "Left stick click", "Right stick click",
    "A", "B", "X", "Y", "White", "Black", "D-pad", "Left stick", "Right stick"
};

@interface HaloControlsView ()
@property(nonatomic, strong) NSMutableArray<CAShapeLayer *> *shapes;
@property(nonatomic, strong) NSMutableArray<CATextLayer *> *labels;
@property(nonatomic, strong) NSMutableArray<CATextLayer *> *subLabels;
@property(nonatomic, strong) NSMutableArray<CAShapeLayer *> *dpadArms;
@property(nonatomic, strong) NSMutableArray<CAShapeLayer *> *knobs;
@property(nonatomic, strong) CAShapeLayer *selection;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *owners;     /* touch -> role */
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *lastPoints;  /* touch -> CGPoint */
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *lastTimes;  /* touch -> timestamp */
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *dragOffsets; /* touch -> CGPoint */
@property(nonatomic, strong) UIImpactFeedbackGenerator *haptic;
@property(nonatomic, strong) UIView *toolbar;
@property(nonatomic, strong) UILabel *toolbarTitle;
@property(nonatomic) BOOL editing;
@end

@implementation HaloControlsView {
    HcControl _controls[HC_COUNT];
    int _holds[HC_COUNT];
    unsigned _dpadMask;
    HsSettings _settings;
    HsPreset _work;              /* the scheme being edited */
    int _selected;
    HcRect _stickBase[2];        /* where each stick's ring is right now (floating sticks move it) */
    BOOL _stickActive[2];
    HcRect _stickHome[2];
    CGSize _laidOutSize;
    UIEdgeInsets _laidOutInsets;
    float _scale;
    BOOL _built;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.multipleTouchEnabled = YES;
        self.backgroundColor = UIColor.clearColor;
        self.shapes = [NSMutableArray array];
        self.labels = [NSMutableArray array];
        self.subLabels = [NSMutableArray array];
        self.dpadArms = [NSMutableArray array];
        self.knobs = [NSMutableArray array];
        self.owners = [NSMutableDictionary dictionary];
        self.lastPoints = [NSMutableDictionary dictionary];
        self.lastTimes = [NSMutableDictionary dictionary];
        self.dragOffsets = [NSMutableDictionary dictionary];
        self.haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        _scale = 1.0f;
        _selected = -1;
        _settings = [[HaloSettingsStore shared] snapshot];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged:)
                                                     name:HaloSettingsChangedNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (const HsPreset *)preset
{
    return self.editing ? &_work : &_settings.presets[_settings.active];
}

- (void)settingsChanged:(NSNotification *)note
{
    (void)note;
    if (self.editing) return; /* the editor owns the layout until Done */
    _settings = [[HaloSettingsStore shared] snapshot];
    [self releaseAll];
    _laidOutSize = CGSizeZero; /* force a relayout */
    [self setNeedsLayout];
}

#pragma mark - layers

- (CATextLayer *)textLayer
{
    CATextLayer *t = [CATextLayer layer];
    t.alignmentMode = kCAAlignmentCenter;
    t.contentsScale = UIScreen.mainScreen.scale;
    t.font = (__bridge CFTypeRef)@"Helvetica-Bold";
    t.foregroundColor = UIColor.whiteColor.CGColor;
    return t;
}

- (void)buildLayers
{
    if (_built) return;
    _built = YES;
    for (int i = 0; i < HC_COUNT; i++) {
        CAShapeLayer *shape = [CAShapeLayer layer];
        [self.layer addSublayer:shape];
        [self.shapes addObject:shape];
        CATextLayer *label = [self textLayer];
        CATextLayer *sub = [self textLayer];
        [self.layer addSublayer:label];
        [self.layer addSublayer:sub];
        [self.labels addObject:label];
        [self.subLabels addObject:sub];
    }
    for (int i = 0; i < 4; i++) {
        CAShapeLayer *arm = [CAShapeLayer layer];
        [self.layer addSublayer:arm];
        [self.dpadArms addObject:arm];
    }
    for (int i = 0; i < 2; i++) {
        CAShapeLayer *knob = [CAShapeLayer layer];
        [self.layer addSublayer:knob];
        [self.knobs addObject:knob];
    }
    self.selection = [CAShapeLayer layer];
    self.selection.fillColor = nil;
    self.selection.strokeColor = UIColor.systemYellowColor.CGColor;
    self.selection.lineWidth = 2;
    self.selection.lineDashPattern = @[@6, @4];
    self.selection.hidden = YES;
    [self.layer addSublayer:self.selection];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    UIEdgeInsets insets = self.safeAreaInsets;
    if (self.bounds.size.width < 10 || self.bounds.size.height < 10) return;
    if (_built && CGSizeEqualToSize(_laidOutSize, self.bounds.size) && UIEdgeInsetsEqualToEdgeInsets(_laidOutInsets, insets))
        return;
    [self buildLayers];
    _laidOutSize = self.bounds.size;
    _laidOutInsets = insets;
    [self relayout];
}

/* Standard layout for this screen, then the active scheme's moves, sizes and hidden controls. */
- (void)relayout
{
    if (!_built || _laidOutSize.width < 10) return;
    float left = (float)_laidOutInsets.left, top = (float)_laidOutInsets.top;
    float right = (float)(_laidOutSize.width - _laidOutInsets.right), bottom = (float)(_laidOutSize.height - _laidOutInsets.bottom);
    _scale = hc_layout(left, top, right, bottom, _controls);
    hs_apply_preset([self preset], left, top, right, bottom, _controls);
    _stickHome[0] = _controls[HC_LSTICK].r;
    _stickHome[1] = _controls[HC_RSTICK].r;
    _stickBase[0] = _stickHome[0];
    _stickBase[1] = _stickHome[1];
    _stickActive[0] = _stickActive[1] = NO;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 0; i < HC_COUNT; i++) [self styleControl:i];
    self.alpha = self.editing ? 1.0 : [self preset]->opacity;
    [CATransaction commit];
    [self updateSelection];
    [self refresh];
}

- (void)styleControl:(int)i
{
    const HcControl *c = &_controls[i];
    CGRect r = CGRectMake(c->r.x, c->r.y, c->r.w, c->r.h);
    CAShapeLayer *shape = self.shapes[i];
    CGFloat s = _scale;
    shape.frame = CGRectZero;
    shape.position = CGPointZero;
    shape.lineWidth = 1.5;
    shape.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.75].CGColor;
    CGMutablePathRef path = CGPathCreateMutable();
    switch (c->kind) {
        case HC_KIND_CIRCLE:
            CGPathAddEllipseInRect(path, NULL, r);
            break;
        case HC_KIND_PILL:
            CGPathAddRoundedRect(path, NULL, r, r.size.height * 0.5, r.size.height * 0.5);
            break;
        case HC_KIND_STICK:
            CGPathAddEllipseInRect(path, NULL, r);
            shape.lineWidth = 3;
            break;
        case HC_KIND_DPAD: {
            CGFloat t = r.size.width / 3.0;
            CGPathAddRoundedRect(path, NULL, CGRectMake(r.origin.x + t, r.origin.y, t, r.size.height), 8 * s, 8 * s);
            CGPathAddRoundedRect(path, NULL, CGRectMake(r.origin.x, r.origin.y + t, r.size.width, t), 8 * s, 8 * s);
            CGRect arms[4] = {
                CGRectMake(r.origin.x + t, r.origin.y, t, t),
                CGRectMake(r.origin.x + t, r.origin.y + 2 * t, t, t),
                CGRectMake(r.origin.x, r.origin.y + t, t, t),
                CGRectMake(r.origin.x + 2 * t, r.origin.y + t, t, t)
            };
            for (int a = 0; a < 4; a++) {
                CGMutablePathRef p = CGPathCreateMutable();
                CGPathAddRoundedRect(p, NULL, arms[a], 8 * s, 8 * s);
                self.dpadArms[a].path = p;
                CGPathRelease(p);
                self.dpadArms[a].strokeColor = nil;
                self.dpadArms[a].fillColor = UIColor.whiteColor.CGColor;
                self.dpadArms[a].hidden = c->hidden && !self.editing;
            }
            break;
        }
    }
    shape.path = path;
    CGPathRelease(path);

    if (c->kind == HC_KIND_STICK) {
        int index = (c->axis == HC_AXIS_LX) ? 0 : 1;
        CAShapeLayer *knob = self.knobs[index];
        CGFloat d = r.size.width * 0.56;
        CGMutablePathRef p = CGPathCreateMutable();
        CGPathAddEllipseInRect(p, NULL, CGRectMake(-d / 2, -d / 2, d, d));
        knob.path = p;
        CGPathRelease(p);
        knob.position = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
        knob.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
        knob.lineWidth = 1.5;
        knob.hidden = c->hidden && !self.editing;
    }

    BOOL dim = c->hidden;  /* hidden controls show faintly while editing, not at all in play */
    BOOL show = !c->hidden || self.editing;
    shape.hidden = !show;
    shape.opacity = dim ? 0.3f : 1.0f;

    CATextLayer *label = self.labels[i];
    CATextLayer *sub = self.subLabels[i];
    NSString *text = [NSString stringWithUTF8String:c->label];
    NSString *subText = [NSString stringWithUTF8String:c->sub];
    BOOL darkText = (c->color == HC_COLOR_YELLOW || c->color == HC_COLOR_WHITE);
    label.foregroundColor = (darkText ? UIColor.blackColor : UIColor.whiteColor).CGColor;
    sub.foregroundColor = (darkText ? UIColor.blackColor : UIColor.whiteColor).CGColor;
    label.string = text;
    sub.string = subText;
    /* text scales with the control, so a resized button keeps readable letters */
    CGFloat unit = _scale * (r.size.height / (c->kind == HC_KIND_CIRCLE ? 56.0 * _scale : 44.0 * _scale));
    CGFloat lf, sf = 0;
    if (c->kind == HC_KIND_CIRCLE) lf = (text.length > 1 ? 10.5 : 26) * unit;
    else if (c->kind == HC_KIND_PILL) lf = (subText.length ? 15 : 13) * unit;
    else lf = 12 * s;
    if (subText.length) sf = 10 * unit;
    label.fontSize = lf;
    sub.fontSize = sf;
    if (subText.length) {
        CGFloat total = lf * 1.2 + sf * 1.2;
        CGFloat top = CGRectGetMidY(r) - total / 2;
        label.frame = CGRectMake(r.origin.x, top, r.size.width, lf * 1.25);
        sub.frame = CGRectMake(r.origin.x, top + lf * 1.15, r.size.width, sf * 1.3);
        sub.hidden = !show;
    } else {
        label.frame = CGRectMake(r.origin.x, CGRectGetMidY(r) - lf * 0.62, r.size.width, lf * 1.3);
        sub.hidden = YES;
    }
    label.hidden = (text.length == 0) || !show;
    label.opacity = sub.opacity = dim ? 0.3f : 1.0f;
}

- (void)refresh
{
    if (!_built) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 0; i < HC_COUNT; i++) {
        const HcControl *c = &_controls[i];
        BOOL down = _holds[i] > 0;
        CAShapeLayer *shape = self.shapes[i];
        if (c->kind == HC_KIND_STICK) {
            shape.fillColor = [UIColor colorWithWhite:0.0 alpha:0.18].CGColor;
        } else if (c->kind == HC_KIND_DPAD) {
            shape.fillColor = [UIColor colorWithWhite:0.45 alpha:0.50].CGColor;
        } else {
            shape.fillColor = HaloColor(c->color, down ? 0.92 : 0.52).CGColor;
        }
    }
    for (int a = 0; a < 4; a++)
        self.dpadArms[a].opacity = (_dpadMask >> a) & 1u ? 0.55f : 0.0f;
    [CATransaction commit];
}

/* The stick's ring and knob follow the thumb when the stick floats. */
- (void)moveStick:(int)index knobDx:(float)dx dy:(float)dy
{
    const HcControl *c = &_controls[index == 0 ? HC_LSTICK : HC_RSTICK];
    HcRect base = _stickBase[index];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shapes[index == 0 ? HC_LSTICK : HC_RSTICK].position = CGPointMake(hc_cx(base) - hc_cx(c->r), hc_cy(base) - hc_cy(c->r));
    self.knobs[index].position = CGPointMake(hc_cx(base) + dx, hc_cy(base) + dy);
    self.knobs[index].fillColor = [UIColor colorWithWhite:0.7 alpha:(dx != 0 || dy != 0) ? 0.75 : 0.5].CGColor;
    [CATransaction commit];
}

- (void)updateSelection
{
    if (!_built) return;
    if (!self.editing || _selected < 0) { self.selection.hidden = YES; return; }
    HcRect r = _controls[_selected].r;
    CGRect box = CGRectInset(CGRectMake(r.x, r.y, r.w, r.h), -6, -6);
    self.selection.path = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:10].CGPath;
    self.selection.hidden = NO;
}

#pragma mark - touch handling

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    if (self.editing) {
        UIView *inner = [super hitTest:point withEvent:event]; /* the editor's toolbar buttons */
        return inner ?: self;
    }
    if (!_built) return nil;
    /* Touch-look and the floating-stick zone use the empty screen; only the corner where the
     * Show log / settings buttons live is left to them. */
    CGRect topCentre = CGRectMake(self.bounds.size.width / 2 - 90, 0, 180, 52);
    if (CGRectContainsPoint(topCentre, point)) return nil;
    return self;
}

static NSNumber *HaloTouchKey(UITouch *touch)
{
    return @((unsigned long long)(uintptr_t)(__bridge void *)touch);
}

- (BOOL)someTouchHasRole:(int)role
{
    for (NSNumber *value in self.owners.allValues)
        if (value.intValue == role) return YES;
    return NO;
}

- (void)buzz
{
    if ([self preset]->haptics) { [self.haptic impactOccurred]; [self.haptic prepare]; }
}

- (void)press:(int)index
{
    const HcControl *c = &_controls[index];
    if (_holds[index]++ > 0) return;
    if (c->axis >= 0 && c->kind == HC_KIND_PILL) halo_ios_pad_axis(c->axis, 32767);
    else if (c->button >= 0) halo_ios_menu_button(c->button, 1);
    [self buzz];
}

- (void)lift:(int)index
{
    const HcControl *c = &_controls[index];
    if (_holds[index] <= 0) return;
    if (--_holds[index] > 0) return;
    if (c->axis >= 0 && c->kind == HC_KIND_PILL) halo_ios_pad_axis(c->axis, 0);
    else if (c->button >= 0) halo_ios_menu_button(c->button, 0);
}

- (void)startStick:(int)index at:(CGPoint)p
{
    const HsPreset *preset = [self preset];
    HcRect home = _stickHome[index];
    float left = (float)_laidOutInsets.left, top = (float)_laidOutInsets.top;
    float right = (float)(_laidOutSize.width - _laidOutInsets.right), bottom = (float)(_laidOutSize.height - _laidOutInsets.bottom);
    _stickBase[index] = preset->floating_sticks ? hc_floating_base(home, (float)p.x, (float)p.y, left, top, right, bottom) : home;
    _stickActive[index] = YES;
    [self updateStick:index at:p];
}

- (void)updateStick:(int)index at:(CGPoint)p
{
    const HsPreset *preset = [self preset];
    const HcControl *c = &_controls[index == 0 ? HC_LSTICK : HC_RSTICK];
    float dx, dy; int ax, ay;
    hc_stick_ex(_stickBase[index], (float)p.x, (float)p.y, preset->stick_dead_zone,
                index == 0 ? preset->move_curve : preset->look_curve, &dx, &dy, &ax, &ay);
    halo_ios_pad_axis(c->axis, ax);
    halo_ios_pad_axis(c->axis + 1, ay);
    [self moveStick:index knobDx:dx dy:dy];
}

- (void)endStick:(int)index
{
    const HcControl *c = &_controls[index == 0 ? HC_LSTICK : HC_RSTICK];
    halo_ios_pad_axis(c->axis, 0);
    halo_ios_pad_axis(c->axis + 1, 0);
    _stickBase[index] = _stickHome[index];
    _stickActive[index] = NO;
    [self moveStick:index knobDx:0 dy:0];
}

- (void)updateDpadAt:(CGPoint)p
{
    unsigned mask = hc_dpad_mask(_controls[HC_DPAD].r, (float)p.x, (float)p.y);
    unsigned changed = mask ^ _dpadMask;
    for (int bit = 0; bit < 4; bit++) {
        if (!((changed >> bit) & 1u)) continue;
        halo_ios_menu_button(HC_BTN_DPAD_UP + bit, (mask >> bit) & 1u);
        if ((mask >> bit) & 1u) [self buzz];
    }
    _dpadMask = mask;
}

/* Where a new finger on empty screen belongs: the left side steers, the rest looks. */
- (BOOL)inLeftStickZone:(CGPoint)p
{
    float left = (float)_laidOutInsets.left, top = (float)_laidOutInsets.top;
    float right = (float)(_laidOutSize.width - _laidOutInsets.right), bottom = (float)(_laidOutSize.height - _laidOutInsets.bottom);
    float w = right - left, h = bottom - top;
    return p.x < left + 0.42f * w && p.y > top + 0.28f * h;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        CGPoint p = [touch locationInView:self];
        NSNumber *key = HaloTouchKey(touch);
        if (self.editing) { [self editBegan:touch at:p]; continue; }
        const HsPreset *preset = [self preset];
        int index = hc_hit(_controls, (float)p.x, (float)p.y, _scale);
        if (index >= 0) {
            const HcControl *c = &_controls[index];
            if ((c->kind == HC_KIND_STICK || c->kind == HC_KIND_DPAD) && [self someTouchHasRole:index]) continue;
            self.owners[key] = @(index);
            if (c->kind == HC_KIND_STICK) [self startStick:(index == HC_LSTICK ? 0 : 1) at:p];
            else if (c->kind == HC_KIND_DPAD) [self updateDpadAt:p];
            else [self press:index];
            continue;
        }
        if (preset->floating_sticks && !_controls[HC_LSTICK].hidden && [self inLeftStickZone:p] && ![self someTouchHasRole:HC_LSTICK]) {
            self.owners[key] = @(HC_LSTICK);
            [self startStick:0 at:p];
            continue;
        }
        if (preset->touch_look && ![self inLeftStickZone:p]) {
            self.owners[key] = @(kRoleLook);
            self.lastPoints[key] = [NSValue valueWithCGPoint:p];
            self.lastTimes[key] = @(touch.timestamp);
        }
    }
    [self refresh];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        NSNumber *key = HaloTouchKey(touch);
        NSNumber *owner = self.owners[key];
        if (!owner) continue;
        CGPoint p = [touch locationInView:self];
        int role = owner.intValue;
        if (role >= kRoleEditDrag) { [self editMoved:role - kRoleEditDrag touch:touch at:p]; continue; }
        if (role == kRoleLook) {
            CGPoint last = self.lastPoints[key].CGPointValue;
            double dt = touch.timestamp - self.lastTimes[key].doubleValue;
            const HsPreset *preset = [self preset];
            double dx = p.x - last.x, dy = p.y - last.y;
            double speed = dt > 0.0005 ? sqrt(dx * dx + dy * dy) / dt : 0.0;
            /* a look curve above 1 turns fast swipes further than slow drags */
            double gain = pow(fmin(fmax(speed / 700.0, 0.35), 3.0), (preset->look_curve - 1.0) * 0.6);
            double k = 1.6 * preset->look_sensitivity * gain;
            halo_ios_touch_look((float)(dx * k), (float)(dy * k * (preset->invert_look_y ? -1.0 : 1.0)));
            self.lastPoints[key] = [NSValue valueWithCGPoint:p];
            self.lastTimes[key] = @(touch.timestamp);
            continue;
        }
        if (_controls[role].kind == HC_KIND_STICK) [self updateStick:(role == HC_LSTICK ? 0 : 1) at:p];
        else if (_controls[role].kind == HC_KIND_DPAD) [self updateDpadAt:p];
    }
    [self refresh];
}

- (void)finishTouches:(NSSet<UITouch *> *)touches
{
    for (UITouch *touch in touches) {
        NSNumber *key = HaloTouchKey(touch);
        NSNumber *owner = self.owners[key];
        if (!owner) continue;
        [self.owners removeObjectForKey:key];
        [self.lastPoints removeObjectForKey:key];
        [self.lastTimes removeObjectForKey:key];
        int role = owner.intValue;
        if (role >= kRoleEditDrag) { [self editEnded:role - kRoleEditDrag touch:touch]; continue; }
        if (role == kRoleLook) continue;
        const HcControl *c = &_controls[role];
        if (c->kind == HC_KIND_STICK) [self endStick:(role == HC_LSTICK ? 0 : 1)];
        else if (c->kind == HC_KIND_DPAD) [self updateDpadAt:CGPointMake(hc_cx(c->r), hc_cy(c->r))]; /* centre: releases all */
        else [self lift:role];
    }
    [self refresh];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self finishTouches:touches]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self finishTouches:touches]; }

- (void)releaseAll
{
    [self.owners removeAllObjects];
    [self.lastPoints removeAllObjects];
    [self.lastTimes removeAllObjects];
    for (int i = 0; i < HC_COUNT; i++) _holds[i] = 0;
    _dpadMask = 0;
    halo_ios_menu_reset();
    if (_built) {
        _stickBase[0] = _stickHome[0];
        _stickBase[1] = _stickHome[1];
        _stickActive[0] = _stickActive[1] = NO;
        [self moveStick:0 knobDx:0 dy:0];
        [self moveStick:1 knobDx:0 dy:0];
        [self refresh];
    }
}

#pragma mark - layout editor

- (UIButton *)toolbarButton:(NSString *)title action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    button.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.95];
    button.layer.cornerRadius = 8;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:34].active = YES;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:56].active = YES;
    return button;
}

- (void)beginEditing
{
    if (self.editing) return;
    [self releaseAll];
    _settings = [[HaloSettingsStore shared] snapshot];
    _work = _settings.presets[_settings.active];
    self.editing = YES;
    _selected = -1;

    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.9];
    bar.layer.cornerRadius = 12;
    UILabel *title = [[UILabel alloc] init];
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 2;
    self.toolbarTitle = title;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self toolbarButton:@"−" action:@selector(smaller)],
        [self toolbarButton:@"+" action:@selector(larger)],
        [self toolbarButton:@"Hide / Show" action:@selector(toggleHidden)],
        [self toolbarButton:@"Reset all" action:@selector(resetAll)],
        [self toolbarButton:@"Done" action:@selector(finishEditing)]]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[title, row]];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 6;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:column];
    [self addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:10],
        [column.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-10],
        [column.topAnchor constraintEqualToAnchor:bar.topAnchor constant:8],
        [column.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-8],
        [bar.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:6]]];
    self.toolbar = bar;
    [self updateToolbarTitle];
    [self relayout];
}

- (void)updateToolbarTitle
{
    if (_selected < 0) {
        self.toolbarTitle.text = [NSString stringWithFormat:@"Editing “%s” — drag a control to move it", _work.name];
    } else {
        const HsPlacement *p = &_work.place[_selected];
        self.toolbarTitle.text = [NSString stringWithFormat:@"%s · size %d%%%s", kControlNames[_selected],
                                  (int)lroundf(p->scale * 100), p->hidden ? " · hidden" : ""];
    }
}

- (void)smaller { [self scaleSelectedBy:-0.1f]; }
- (void)larger { [self scaleSelectedBy:0.1f]; }

- (void)scaleSelectedBy:(float)delta
{
    if (_selected < 0) return;
    HsPlacement *p = &_work.place[_selected];
    p->scale = hs_clampf(p->scale + delta, 0.6f, 1.8f);
    [self updateToolbarTitle];
    [self relayout];
}

- (void)toggleHidden
{
    if (_selected < 0) return;
    _work.place[_selected].hidden = !_work.place[_selected].hidden;
    [self updateToolbarTitle];
    [self relayout];
}

- (void)resetAll
{
    hs_reset_layout(&_work);
    _selected = -1;
    [self updateToolbarTitle];
    [self relayout];
}

- (void)finishEditing
{
    HsPreset result = _work;
    self.editing = NO;
    [self.toolbar removeFromSuperview];
    self.toolbar = nil;
    _selected = -1;
    [self.owners removeAllObjects];
    [[HaloSettingsStore shared] update:^(HsSettings *s) { s->presets[s->active] = result; }];
    _settings = [[HaloSettingsStore shared] snapshot];
    [self relayout];
    if (self.onEditFinished) self.onEditFinished();
}

/* Controls hidden by the scheme can still be picked while editing. */
- (int)editHitAt:(CGPoint)p
{
    HcControl all[HC_COUNT];
    memcpy(all, _controls, sizeof(all));
    for (int i = 0; i < HC_COUNT; i++) all[i].hidden = 0;
    return hc_hit(all, (float)p.x, (float)p.y, _scale);
}

- (void)editBegan:(UITouch *)touch at:(CGPoint)p
{
    int index = [self editHitAt:p];
    if (index < 0) { _selected = -1; [self updateToolbarTitle]; [self updateSelection]; return; }
    _selected = index;
    self.owners[HaloTouchKey(touch)] = @(kRoleEditDrag + index);
    HcRect r = _controls[index].r;
    self.dragOffsets[HaloTouchKey(touch)] = [NSValue valueWithCGPoint:CGPointMake(p.x - hc_cx(r), p.y - hc_cy(r))];
    [self updateToolbarTitle];
    [self updateSelection];
}

- (void)editMoved:(int)index touch:(UITouch *)touch at:(CGPoint)p
{
    CGPoint offset = self.dragOffsets[HaloTouchKey(touch)].CGPointValue;
    float left = (float)_laidOutInsets.left, top = (float)_laidOutInsets.top;
    float right = (float)(_laidOutSize.width - _laidOutInsets.right), bottom = (float)(_laidOutSize.height - _laidOutInsets.bottom);
    hs_place_control(&_work, index, (float)(p.x - offset.x), (float)(p.y - offset.y), left, top, right, bottom);
    [self relayout];
}

- (void)editEnded:(int)index touch:(UITouch *)touch
{
    (void)index;
    [self.dragOffsets removeObjectForKey:HaloTouchKey(touch)];
}

@end

#pragma mark - physical controllers

static void (^g_controllers_changed)(BOOL connected);

static int32_t HaloAxisValue(float value, BOOL invert)
{
    float v = invert ? -value : value;
    if (v > 1.0f) v = 1.0f;
    if (v < -1.0f) v = -1.0f;
    return (int32_t)lroundf(v * 32767.0f);
}

/* Maps an extended gamepad onto the original Xbox layout the guest expects. */
static void HaloPushGamepad(GCExtendedGamepad *pad)
{
    uint32_t b = 0;
    if (pad.buttonA.isPressed) b |= 1u << HC_BTN_A;
    if (pad.buttonB.isPressed) b |= 1u << HC_BTN_B;
    if (pad.buttonX.isPressed) b |= 1u << HC_BTN_X;
    if (pad.buttonY.isPressed) b |= 1u << HC_BTN_Y;
    if (pad.leftShoulder.isPressed) b |= 1u << HC_BTN_WHITE;
    if (pad.rightShoulder.isPressed) b |= 1u << HC_BTN_BLACK;
    if (pad.buttonMenu.isPressed) b |= 1u << HC_BTN_START;
    if (pad.buttonOptions.isPressed) b |= 1u << HC_BTN_BACK;
    if (pad.leftThumbstickButton.isPressed) b |= 1u << HC_BTN_LSTICK;
    if (pad.rightThumbstickButton.isPressed) b |= 1u << HC_BTN_RSTICK;
    if (pad.dpad.up.isPressed) b |= 1u << HC_BTN_DPAD_UP;
    if (pad.dpad.down.isPressed) b |= 1u << HC_BTN_DPAD_DOWN;
    if (pad.dpad.left.isPressed) b |= 1u << HC_BTN_DPAD_LEFT;
    if (pad.dpad.right.isPressed) b |= 1u << HC_BTN_DPAD_RIGHT;
    int32_t axes[6];
    /* GameController's Y axes grow upwards; SDL's grow downwards. */
    axes[HC_AXIS_LX] = HaloAxisValue(pad.leftThumbstick.xAxis.value, NO);
    axes[HC_AXIS_LY] = HaloAxisValue(pad.leftThumbstick.yAxis.value, YES);
    axes[HC_AXIS_RX] = HaloAxisValue(pad.rightThumbstick.xAxis.value, NO);
    axes[HC_AXIS_RY] = HaloAxisValue(pad.rightThumbstick.yAxis.value, YES);
    axes[HC_AXIS_LT] = HaloAxisValue(pad.leftTrigger.value, NO);
    axes[HC_AXIS_RT] = HaloAxisValue(pad.rightTrigger.value, NO);
    halo_ios_physical_pad_state(b, axes);
}

static void HaloAttachController(GCController *controller)
{
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (!pad) return;
    pad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
        (void)element;
        HaloPushGamepad(gamepad);
    };
    HaloPushGamepad(pad);
}

static void HaloReportControllers(void)
{
    BOOL connected = NO;
    for (GCController *controller in GCController.controllers)
        if (controller.extendedGamepad) connected = YES;
    if (!connected) {
        int32_t zero[6] = { 0, 0, 0, 0, 0, 0 };
        halo_ios_physical_pad_state(0, zero);
    }
    if (g_controllers_changed) g_controllers_changed(connected);
}

void halo_ios_controllers_start(void (^changed)(BOOL connected))
{
    g_controllers_changed = [changed copy];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:GCControllerDidConnectNotification object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:GCController.class]) HaloAttachController((GCController *)note.object);
        HaloReportControllers();
    }];
    [center addObserverForName:GCControllerDidDisconnectNotification object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) {
        (void)note;
        HaloReportControllers();
    }];
    for (GCController *controller in GCController.controllers) HaloAttachController(controller);
    HaloReportControllers();
}
