#import "HaloSettingsStore.h"
#import "halo_ios_audio.h"
#import "halo_guest_runner.h"

NSString *const HaloSettingsChangedNotification = @"HaloSettingsChanged";
static NSString *const kSettingsKey = @"HaloSettingsV1";

@implementation HaloSettingsStore {
    HsSettings _settings;
    NSLock *_lock;
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
        halo_ios_audio_set_volume(_settings.audio_enabled ? _settings.volume : 0.0f);
        halo_ios_set_profiler_enabled(_settings.profiler);
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

- (void)update:(void (^)(HsSettings *settings))block
{
    [_lock lock];
    HsSettings next = _settings;
    block(&next);
    hs_sanitize(&next);
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

    halo_ios_audio_set_volume(next.audio_enabled ? next.volume : 0.0f);
    halo_ios_set_profiler_enabled(next.profiler);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:HaloSettingsChangedNotification object:nil];
    });
}

@end
