#import "halo_ios_controls.h"
#import "halo_guest_runner.h"
#import "halo_controls_layout.h"

#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>

static UIColor *HaloColor(int color, CGFloat alpha)
{
    UIColor *c;
    switch (color) {
        case HC_COLOR_GREEN:  c = [UIColor colorWithRed:0.10 green:0.68 blue:0.24 alpha:alpha]; break;
        case HC_COLOR_RED:    c = [UIColor colorWithRed:0.86 green:0.13 blue:0.16 alpha:alpha]; break;
        case HC_COLOR_BLUE:   c = [UIColor colorWithRed:0.12 green:0.40 blue:0.92 alpha:alpha]; break;
        case HC_COLOR_YELLOW: c = [UIColor colorWithRed:0.98 green:0.80 blue:0.10 alpha:alpha]; break;
        case HC_COLOR_BLACK:  c = [UIColor colorWithWhite:0.05 alpha:alpha]; break;
        case HC_COLOR_WHITE:  c = [UIColor colorWithWhite:0.96 alpha:alpha]; break;
        default:              c = [UIColor colorWithWhite:0.45 alpha:alpha]; break;
    }
    return c;
}

@interface HaloControlsView ()
@property(nonatomic, strong) NSMutableArray<CAShapeLayer *> *shapes;     /* one per control */
@property(nonatomic, strong) NSMutableArray<CATextLayer *> *labels;
@property(nonatomic, strong) NSMutableArray<CATextLayer *> *subLabels;
@property(nonatomic, strong) NSMutableArray<CAShapeLayer *> *dpadArms;   /* up, down, left, right */
@property(nonatomic, strong) NSMutableArray<CAShapeLayer *> *knobs;      /* left, right */
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *owners; /* touch -> control */
@property(nonatomic, strong) UIImpactFeedbackGenerator *haptic;
@end

@implementation HaloControlsView {
    HcControl _controls[HC_COUNT];
    int _holds[HC_COUNT];        /* fingers currently on a button or trigger */
    unsigned _dpadMask;
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
        self.haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        _scale = 1.0f;
    }
    return self;
}

#pragma mark - building and laying out the layers

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
    _scale = hc_layout((float)insets.left, (float)insets.top, (float)(self.bounds.size.width - insets.right),
                       (float)(self.bounds.size.height - insets.bottom), _controls);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 0; i < HC_COUNT; i++) [self styleControl:i];
    [CATransaction commit];
    [self refresh];
}

- (void)styleControl:(int)i
{
    const HcControl *c = &_controls[i];
    CGRect r = CGRectMake(c->r.x, c->r.y, c->r.w, c->r.h);
    CAShapeLayer *shape = self.shapes[i];
    CGFloat s = _scale;
    shape.frame = CGRectZero;
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
            /* four arm overlays that light up with the pressed direction */
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
    }

    CATextLayer *label = self.labels[i];
    CATextLayer *sub = self.subLabels[i];
    NSString *text = [NSString stringWithUTF8String:c->label];
    NSString *subText = [NSString stringWithUTF8String:c->sub];
    BOOL darkText = (c->color == HC_COLOR_YELLOW || c->color == HC_COLOR_WHITE);
    label.foregroundColor = (darkText ? UIColor.blackColor : UIColor.whiteColor).CGColor;
    sub.foregroundColor = (darkText ? UIColor.blackColor : UIColor.whiteColor).CGColor;
    label.string = text;
    sub.string = subText;
    CGFloat lf, sf = 0;
    if (c->kind == HC_KIND_CIRCLE) lf = (text.length > 1 ? 10.5 : 26) * s;
    else if (c->kind == HC_KIND_PILL) lf = (subText.length ? 15 : 13) * s;
    else lf = 12 * s;
    if (subText.length) sf = 10 * s;
    label.fontSize = lf;
    sub.fontSize = sf;
    if (subText.length) {
        CGFloat total = lf * 1.2 + sf * 1.2;
        CGFloat top = CGRectGetMidY(r) - total / 2;
        label.frame = CGRectMake(r.origin.x, top, r.size.width, lf * 1.25);
        sub.frame = CGRectMake(r.origin.x, top + lf * 1.15, r.size.width, sf * 1.3);
        sub.hidden = NO;
    } else {
        label.frame = CGRectMake(r.origin.x, CGRectGetMidY(r) - lf * 0.62, r.size.width, lf * 1.3);
        sub.hidden = YES;
    }
    label.hidden = (text.length == 0);
}

/* Redraws pressed/idle state; cheap enough to run after every touch event. */
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

- (void)moveKnob:(int)index toDx:(float)dx dy:(float)dy
{
    const HcControl *c = &_controls[index == 0 ? HC_LSTICK : HC_RSTICK];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.knobs[index].position = CGPointMake(hc_cx(c->r) + dx, hc_cy(c->r) + dy);
    self.knobs[index].fillColor = [UIColor colorWithWhite:0.7 alpha:(dx != 0 || dy != 0) ? 0.75 : 0.5].CGColor;
    [CATransaction commit];
}

#pragma mark - touch handling

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    /* Empty space passes through, so views underneath (the Show log button) stay usable. */
    if (_built && hc_hit(_controls, (float)point.x, (float)point.y, _scale) >= 0) return self;
    return nil;
}

static NSNumber *HaloTouchKey(UITouch *touch)
{
    return @((unsigned long long)(uintptr_t)(__bridge void *)touch);
}

- (BOOL)ownerHoldsControl:(int)index
{
    for (NSNumber *value in self.owners.allValues)
        if (value.intValue == index) return YES;
    return NO;
}

- (void)press:(int)index
{
    const HcControl *c = &_controls[index];
    if (_holds[index]++ > 0) return;
    if (c->axis >= 0 && c->kind == HC_KIND_PILL) halo_ios_pad_axis(c->axis, 32767);
    else if (c->button >= 0) halo_ios_menu_button(c->button, 1);
    [self.haptic impactOccurred];
    [self.haptic prepare];
}

- (void)lift:(int)index
{
    const HcControl *c = &_controls[index];
    if (_holds[index] <= 0) return;
    if (--_holds[index] > 0) return;
    if (c->axis >= 0 && c->kind == HC_KIND_PILL) halo_ios_pad_axis(c->axis, 0);
    else if (c->button >= 0) halo_ios_menu_button(c->button, 0);
}

- (void)updateStick:(int)index at:(CGPoint)p
{
    const HcControl *c = &_controls[index];
    float dx, dy; int ax, ay;
    hc_stick(c->r, (float)p.x, (float)p.y, &dx, &dy, &ax, &ay);
    halo_ios_pad_axis(c->axis, ax);
    halo_ios_pad_axis(c->axis + 1, ay);
    [self moveKnob:(index == HC_LSTICK ? 0 : 1) toDx:dx dy:dy];
}

- (void)updateDpadAt:(CGPoint)p
{
    unsigned mask = hc_dpad_mask(_controls[HC_DPAD].r, (float)p.x, (float)p.y);
    unsigned changed = mask ^ _dpadMask;
    for (int bit = 0; bit < 4; bit++) {
        if (!((changed >> bit) & 1u)) continue;
        halo_ios_menu_button(HC_BTN_DPAD_UP + bit, (mask >> bit) & 1u);
        if ((mask >> bit) & 1u) { [self.haptic impactOccurred]; [self.haptic prepare]; }
    }
    _dpadMask = mask;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        CGPoint p = [touch locationInView:self];
        int index = hc_hit(_controls, (float)p.x, (float)p.y, _scale);
        if (index < 0) continue;
        const HcControl *c = &_controls[index];
        if ((c->kind == HC_KIND_STICK || c->kind == HC_KIND_DPAD) && [self ownerHoldsControl:index]) continue;
        self.owners[HaloTouchKey(touch)] = @(index);
        if (c->kind == HC_KIND_STICK) [self updateStick:index at:p];
        else if (c->kind == HC_KIND_DPAD) [self updateDpadAt:p];
        else [self press:index];
    }
    [self refresh];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        NSNumber *owner = self.owners[HaloTouchKey(touch)];
        if (!owner) continue;
        int index = owner.intValue;
        CGPoint p = [touch locationInView:self];
        if (_controls[index].kind == HC_KIND_STICK) [self updateStick:index at:p];
        else if (_controls[index].kind == HC_KIND_DPAD) [self updateDpadAt:p];
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
        int index = owner.intValue;
        const HcControl *c = &_controls[index];
        if (c->kind == HC_KIND_STICK) {
            halo_ios_pad_axis(c->axis, 0);
            halo_ios_pad_axis(c->axis + 1, 0);
            [self moveKnob:(index == HC_LSTICK ? 0 : 1) toDx:0 dy:0];
        } else if (c->kind == HC_KIND_DPAD) {
            [self updateDpadAt:CGPointMake(hc_cx(c->r), hc_cy(c->r))]; /* centre: releases all */
        } else {
            [self lift:index];
        }
    }
    [self refresh];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self finishTouches:touches]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self finishTouches:touches]; }

- (void)releaseAll
{
    [self.owners removeAllObjects];
    for (int i = 0; i < HC_COUNT; i++) _holds[i] = 0;
    _dpadMask = 0;
    halo_ios_menu_reset();
    if (_built) {
        [self moveKnob:0 toDx:0 dy:0];
        [self moveKnob:1 toDx:0 dy:0];
        [self refresh];
    }
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
