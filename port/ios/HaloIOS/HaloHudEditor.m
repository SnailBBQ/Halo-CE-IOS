#import "HaloHudEditor.h"
#import "HaloSettingsStore.h"
#import "HaloUI.h"
@interface HaloHudEditor ()
@property NSInteger selected;
@property(nonatomic,strong) UIStackView *rows;
@end
@implementation HaloHudEditor
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.clearColor;
    UIView *panel=[UIView new];panel.translatesAutoresizingMaskIntoConstraints=NO;panel.backgroundColor=[UIColor colorWithWhite:.06 alpha:.94];panel.layer.cornerRadius=14;[self.view addSubview:panel];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[panel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],[panel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],[panel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],[panel.widthAnchor constraintEqualToConstant:300]]];
    self.rows=HaloUIScrollingStack(panel,10);self.selected=0;[self render];
}
- (void)change:(void(^)(HsHud *))block {
    NSInteger selected=self.selected;[[HaloSettingsStore shared] update:^(HsSettings *s){for(int i=0;i<HS_HUD_COUNT;i++)if(selected==5||selected==i)block(&s->hud[i]);}];
}
- (void)render {
    for(UIView *v in self.rows.arrangedSubviews){[self.rows removeArrangedSubview:v];[v removeFromSuperview];}
    HsSettings s=[[HaloSettingsStore shared] snapshot];HsHud h=s.hud[self.selected==5?0:self.selected];
    NSArray *names=@[@"FPS",@"Weapon HUD",@"Health / shields / radar",@"Navigation",@"Damage indicators",@"All elements"];
    [self.rows addArrangedSubview:HaloUILabel(@"HUD Editor",20,UIFontWeightBold,nil)];
    [self.rows addArrangedSubview:HaloUIButton(@"Done",1,^(UIButton *b){(void)b;[self dismissViewControllerAnimated:YES completion:nil];})];
    [self.rows addArrangedSubview:HaloUINote(@"Live preview over the game. Elements follow the engine’s draw groups; text and some special overlays retain their original placement.")];
    [self.rows addArrangedSubview:HaloUIButton(names[(NSUInteger)self.selected],0,^(UIButton *b){(void)b;
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Choose element" message:nil preferredStyle:UIAlertControllerStyleAlert];
        for(NSUInteger i=0;i<names.count;i++)[a addAction:[UIAlertAction actionWithTitle:names[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;self.selected=(NSInteger)i;[self render];}]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
    })];
    if(self.selected==0)[self.rows addArrangedSubview:HaloUISwitchRow(@"Show FPS counter",nil,s.show_fps,^(BOOL on){[[HaloSettingsStore shared] update:^(HsSettings *next){next->show_fps=on;}];})];
    if(self.selected==5)[self.rows addArrangedSubview:HaloUINote(@"All Elements sets the same value for every group. Sliders initially show the FPS values.")];
    [self.rows addArrangedSubview:HaloUISliderRow(@"Horizontal position",-.45,.45,h.x,@"%.2f",^(float v){[self change:^(HsHud *q){q->x=v;}];})];
    [self.rows addArrangedSubview:HaloUISliderRow(@"Vertical position",-.45,.45,h.y,@"%.2f",^(float v){[self change:^(HsHud *q){q->y=v;}];})];
    [self.rows addArrangedSubview:HaloUISliderRow(@"Scale",.5,1.5,h.scale,@"%.2f",^(float v){[self change:^(HsHud *q){q->scale=v;}];})];
    [self.rows addArrangedSubview:HaloUISliderRow(@"Opacity",0,1,h.opacity,@"%.2f",^(float v){[self change:^(HsHud *q){q->opacity=v;}];})];
    [self.rows addArrangedSubview:HaloUISwitchRow(@"Hidden",nil,h.hidden,^(BOOL v){[self change:^(HsHud *q){q->hidden=v;}];})];
    [self.rows addArrangedSubview:HaloUIButton(@"Reset selected",0,^(UIButton *b){(void)b;[self change:^(HsHud *q){HsHud original={0};original.scale=original.opacity=1;*q=original;}];[self render];})];
    [self.rows addArrangedSubview:HaloUIButton(@"Reset all",0,^(UIButton *b){(void)b;[[HaloSettingsStore shared] update:^(HsSettings *next){for(int i=0;i<HS_HUD_COUNT;i++){HsHud original={0};original.scale=original.opacity=1;next->hud[i]=original;}}];[self render];})];
    for(int i=0;i<3;i++) {
        int slot=i;NSString *name=[NSString stringWithUTF8String:s.hud_presets[i].name];
        [self.rows addArrangedSubview:HaloUICardView(name,@[
            HaloUIButton(@"Load",0,^(UIButton *b){(void)b;[[HaloSettingsStore shared] update:^(HsSettings *next){memcpy(next->hud,next->hud_presets[slot].elements,sizeof(next->hud));}];[self render];}),
            HaloUIButton(@"Save / rename",0,^(UIButton *b){(void)b;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Save HUD preset" message:@"Store the current HUD layout in this slot." preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=name;f.placeholder=@"Preset name";}];[a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;[[HaloSettingsStore shared] update:^(HsSettings *next){hs_set_name(next->hud_presets[slot].name,a.textFields.firstObject.text.UTF8String);memcpy(next->hud_presets[slot].elements,next->hud,sizeof(next->hud));}];[self render];}]];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];})])];
    }
}
@end
