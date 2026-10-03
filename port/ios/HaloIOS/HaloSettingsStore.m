#import "HaloSettingsStore.h"
#import "halo_ios_audio.h"
#import "halo_guest_runner.h"
#import "halo_ios_gl_host.h"

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
        halo_ios_gl_set_frame_cap(hs_frame_cap(&_settings));
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
- (void)setCampaignActive:(BOOL)active {
    [_lock lock];_campaignActive=active;if (!active) hs_clear_cheats(&_settings);[_lock unlock];
    if (!active) halo_ios_set_cheat_flags(0);
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:HaloCampaignStateChangedNotification object:nil]; });
}

- (void)update:(void (^)(HsSettings *settings))block
{
    [_lock lock];
    HsSettings next = _settings;
    block(&next);
    hs_sanitize(&next);
    if (!_campaignActive) hs_clear_cheats(&next);
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

    halo_ios_set_channel_gains(next.music_volume,next.dialogue_volume,next.effects_volume);
    halo_ios_audio_set_volume(next.audio_enabled ? next.volume : 0.0f);
    halo_ios_set_profiler_enabled(next.profiler);
    halo_ios_gl_set_frame_cap(hs_frame_cap(&next));
    halo_ios_set_cheat_flags(hs_cheat_mask(&next));
    halo_ios_set_viewmodel_flags(hs_viewmodel_mask(&next));
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:HaloSettingsChangedNotification object:nil];
    });
}

@end
