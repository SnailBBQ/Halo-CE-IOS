#import "HaloSettingsStore.h"
#ifdef HALO_SETTINGS_TEST
/* Exercise this actual store on CI's Foundation host, without audio/GL devices. */
extern void halo_ios_set_channel_gains(float,float,float);
extern void halo_ios_audio_set_volume(float);
extern void halo_ios_set_profiler_enabled(int);
extern void halo_ios_gl_set_frame_cap(int);
extern void halo_ios_set_ambient_gain(float);
extern void halo_ios_set_cheat_flags(uint32_t);
extern void halo_ios_set_viewmodel_flags(uint32_t);
extern int halo_ios_queue_campaign_action(uint32_t);
#else
#import "halo_ios_audio.h"
#import "halo_guest_runner.h"
#import "halo_ios_gl_host.h"

static int HaloEffectiveCap(const HsSettings *settings)
{
    NSProcessInfo *info = NSProcessInfo.processInfo;
    return hs_effective_cap(settings, (int)info.thermalState, info.isLowPowerModeEnabled ? 1 : 0);
}
#endif

NSString *const HaloSettingsChangedNotification = @"HaloSettingsChanged";
NSString *const HaloCampaignStateChangedNotification = @"HaloCampaignStateChanged";
static NSString *const kSettingsKey = @"HaloSettingsV1";

@implementation HaloSettingsStore {
    HsSettings _settings;
    NSLock *_lock;
    BOOL _campaignActive;
}

+ (instancetype)shared
{
    static HaloSettingsStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [[HaloSettingsStore alloc] init]; });
    return store;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        NSString *text = [[NSUserDefaults standardUserDefaults] stringForKey:kSettingsKey];
        hs_parse(&_settings, text.UTF8String); /* defaults when nothing or garbage is saved */
        halo_ios_set_channel_gains(_settings.music_volume,_settings.dialogue_volume,_settings.effects_volume);
        halo_ios_audio_set_volume(_settings.audio_enabled ? _settings.volume : 0.0f);
        halo_ios_set_profiler_enabled(_settings.profiler);
        halo_ios_gl_set_frame_cap(HaloEffectiveCap(&_settings));
        halo_ios_set_ambient_gain(_settings.ambient_volume);
        __weak HaloSettingsStore *weakSelf = self;
        void (^reapply)(NSNotification *) = ^(NSNotification *note) {
            (void)note;
            HaloSettingsStore *strong = weakSelf;
            if (!strong) return;
            HsSettings now = [strong snapshot];
            halo_ios_gl_set_frame_cap(HaloEffectiveCap(&now));   /* the phone got hotter or cooler, or Low Power Mode changed */
        };
        [[NSNotificationCenter defaultCenter] addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:nil usingBlock:reapply];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:nil usingBlock:reapply];
        halo_ios_set_cheat_flags(hs_cheat_mask(&_settings));
        halo_ios_set_viewmodel_flags(hs_viewmodel_mask(&_settings));
    }
    return self;
}

- (HsSettings)snapshot
{
    [_lock lock];
    HsSettings copy = _settings;
    [_lock unlock];
    return copy;
}

- (BOOL)campaignActive { [_lock lock];BOOL active=_campaignActive;[_lock unlock];return active; }
/* Runtime recipes are never serialized as active cheats. Activation is edge
 * triggered, so slider changes and repeated engine state reports cannot spawn
 * items every frame. The engine independently enforces the campaign gate. */
- (void)activatePresetRecipe {
    if(![self campaignActive])return;
    HsSettings current=[self snapshot];HsPreset recipe=current.presets[current.active];
    [self update:^(HsSettings *s){hs_apply_preset_cheats(s,s->active);}];
    if(recipe.cheat_actions&1u)halo_ios_queue_campaign_action(3);
    if(recipe.cheat_actions&2u)halo_ios_queue_campaign_action(2);
    if(recipe.cheat_actions&4u)halo_ios_queue_campaign_action(1);
    if(recipe.cheat_actions&8u)halo_ios_queue_campaign_action(4);
    if(recipe.cheat_weapon)halo_ios_queue_campaign_action(99u+(uint32_t)recipe.cheat_weapon);
}
- (void)setCampaignActive:(BOOL)active {
    [_lock lock];BOOL entered=active && !_campaignActive;_campaignActive=active;if(!active)hs_clear_cheats(&_settings);[_lock unlock];
    if(!active)halo_ios_set_cheat_flags(0);
    if(entered)[self activatePresetRecipe];
    dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:HaloCampaignStateChangedNotification object:nil];});
}

- (void)update:(void (^)(HsSettings *settings))block
{
    [_lock lock];
    int previousPreset=_settings.active;
    HsSettings next = _settings;
    block(&next);
    hs_sanitize(&next);
    if (!_campaignActive) hs_clear_cheats(&next);
    /* Resolve a profile link only when selecting a profile or changing its link.
       Touch editing cannot modify a saved Game HUD recipe. */
    if(next.active!=previousPreset || next.presets[next.active].hud_choice!=_settings.presets[previousPreset].hud_choice) {
        int choice=next.presets[next.active].hud_choice;
        if(choice)memcpy(next.hud,next.hud_presets[choice-1].elements,sizeof(next.hud));
        else { for(int h=0;h<HS_HUD_COUNT;h++)next.hud[h]=(HsHud){0,0,1,1,0}; }
    }
    BOOL activate=_campaignActive && next.active!=previousPreset;
    if(activate)hs_apply_preset_cheats(&next,next.active);
    _settings = next;
    [_lock unlock];

    static char text[16384];
    static NSLock *textLock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ textLock = [[NSLock alloc] init]; });
    [textLock lock];
    if (hs_serialize(&next, text, sizeof(text)) > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithUTF8String:text] forKey:kSettingsKey];
    }
    [textLock unlock];

    if(activate)[self activatePresetRecipe];
    halo_ios_set_channel_gains(next.music_volume,next.dialogue_volume,next.effects_volume);
    halo_ios_audio_set_volume(next.audio_enabled ? next.volume : 0.0f);
    halo_ios_set_profiler_enabled(next.profiler);
    halo_ios_gl_set_frame_cap(HaloEffectiveCap(&next));
    halo_ios_set_ambient_gain(next.ambient_volume);
    halo_ios_set_cheat_flags(hs_cheat_mask(&next));
    halo_ios_set_viewmodel_flags(hs_viewmodel_mask(&next));
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:HaloSettingsChangedNotification object:nil];
    });
}

@end
