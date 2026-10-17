#import "halo_ios_audio.h"
#import "halo_audio_ring.h"

#import <AVFoundation/AVFoundation.h>

static HaloAudioRing g_ring;
static _Atomic float g_volume = 1.0f;
static AVAudioEngine *g_engine;
static AVAudioSourceNode *g_source;
static BOOL g_opened;
static dispatch_once_t g_observers_once;
static char g_status[200] = "the game has not asked for sound yet";

static void HaloSetStatus(NSString *text, NSError *error)
{
    NSString *full = error ? [NSString stringWithFormat:@"%@: %@ (code %ld)", text, error.localizedDescription, (long)error.code] : text;
    snprintf(g_status, sizeof(g_status), "%s", full.UTF8String);
}

static void HaloStartEngine(void)
{
    if (!g_engine || g_engine.isRunning)
        return;
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (![g_engine startAndReturnError:&error])
        NSLog(@"[HaloIOS-Audio] engine start failed: %@", error);
}

int halo_ios_audio_open(uint32_t sample_rate, uint32_t channels)
{
    if (channels != 2 || sample_rate < 8000 || sample_rate > 192000)
        return 0;
    if (g_opened)
        return 1;
    __block int ok = 0;
    void (^open)(void) = ^{
        NSError *error = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        /* A game: plays with the ring/silent switch on, like the original console. */
        if (![session setCategory:AVAudioSessionCategoryPlayback error:&error]) {
            HaloSetStatus(@"audio session category failed", error);
            return;
        }
        [session setPreferredIOBufferDuration:0.010 error:nil];
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sample_rate channels:2];
        g_engine = [[AVAudioEngine alloc] init];
        g_source = [[AVAudioSourceNode alloc] initWithFormat:format
            renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp,
                                  AVAudioFrameCount frameCount, AudioBufferList *output) {
                (void)timestamp;
                float volume = atomic_load_explicit(&g_volume, memory_order_relaxed);
                if (output->mNumberBuffers >= 2) {
                    halo_ring_pull(&g_ring, (float *)output->mBuffers[0].mData,
                                   (float *)output->mBuffers[1].mData, frameCount, volume);
                } else if (output->mNumberBuffers == 1) {
                    /* interleaved: pull to the stack in chunks, then interleave */
                    float left[512], right[512];
                    float *destination = (float *)output->mBuffers[0].mData;
                    AVAudioFrameCount done = 0;
                    while (done < frameCount) {
                        uint32_t n = frameCount - done < 512 ? frameCount - done : 512;
                        halo_ring_pull(&g_ring, left, right, n, volume);
                        for (uint32_t i = 0; i < n; i++) {
                            destination[(done + i) * 2] = left[i];
                            destination[(done + i) * 2 + 1] = right[i];
                        }
                        done += n;
                    }
                }
                *isSilence = NO;
                return noErr;
            }];
        [g_engine attachNode:g_source];
        [g_engine connect:g_source to:g_engine.mainMixerNode format:format];
        [session setActive:YES error:&error];
        if (error) HaloSetStatus(@"audio session would not activate", error);
        error = nil;
        if (![g_engine startAndReturnError:&error]) {
            HaloSetStatus(@"audio engine would not start", error);
            g_engine = nil;
            g_source = nil;
            return;
        }
        dispatch_once(&g_observers_once, ^{
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            [center addObserverForName:AVAudioSessionInterruptionNotification object:nil
                                 queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
                if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded) HaloStartEngine();
            }];
            [center addObserverForName:AVAudioEngineConfigurationChangeNotification object:nil
                                 queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                (void)note;
                HaloStartEngine();
            }];
        });
        HaloSetStatus(@"playing through the speaker", nil);
        ok = 1;
    };
    /* AVAudioEngine setup is happiest on the main thread; the guest thread waits briefly. */
    if (NSThread.isMainThread) open();
    else dispatch_sync(dispatch_get_main_queue(), open);
    g_opened = ok ? YES : NO;
    return ok;
}

uint32_t halo_ios_audio_fill(void)
{
    return halo_ring_fill(&g_ring);
}

uint32_t halo_ios_audio_push(const float *frames, uint32_t count)
{
    return halo_ring_push(&g_ring, frames, count);
}

void halo_ios_audio_set_volume(float volume)
{
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    atomic_store_explicit(&g_volume, volume, memory_order_relaxed);
}

/* Stops and starts the phone's audio engine again (the guest and its sound buffers are not touched). */
void halo_ios_audio_restart(void)
{
    if (!g_opened)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_engine.isRunning)
            [g_engine stop];
        HaloStartEngine();
    });
}

void halo_ios_audio_resume(void)
{
    if (!g_opened)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{ HaloStartEngine(); });
}

uint32_t halo_ios_audio_underruns(void)
{
    return atomic_load_explicit(&g_ring.underruns, memory_order_relaxed);
}

int halo_ios_audio_is_open(void)
{
    return g_opened ? 1 : 0;
}

const char *halo_ios_audio_status(void)
{
    return g_status;
}


/* ---------- voice chat microphone ---------- */

#define HALO_MIC_RING 96000u /* two seconds at 48 kHz */
static float g_mic_ring[HALO_MIC_RING];
static _Atomic uint64_t g_mic_write, g_mic_read;
static _Atomic int g_mic_muted, g_ptt_held;
static AVAudioEngine *g_mic_engine;
static BOOL g_mic_open;
static uint32_t g_mic_rate = 48000;
static dispatch_once_t g_mic_observer_once;
static char g_mic_status[200] = "voice chat has not asked for the microphone yet";

static void HaloMicStatus(NSString *text, NSError *error)
{
    NSString *full = error ? [NSString stringWithFormat:@"%@: %@ (code %ld)", text, error.localizedDescription, (long)error.code] : text;
    snprintf(g_mic_status, sizeof(g_mic_status), "%s", full.UTF8String);
}

static void HaloMicPush(const float *samples, uint32_t count)
{
    uint64_t write = atomic_load_explicit(&g_mic_write, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&g_mic_read, memory_order_acquire);
    uint64_t room = HALO_MIC_RING - (write - read);
    if (count > room) count = (uint32_t)room;
    for (uint32_t i = 0; i < count; i++) g_mic_ring[(write + i) % HALO_MIC_RING] = samples[i];
    atomic_store_explicit(&g_mic_write, write + count, memory_order_release);
}

/* (main thread) the tap that converts whatever the current input is (built-in microphone, AirPods, a wired headset)
 * to 48 kHz mono float. Called again when the route changes. */
static BOOL HaloMicInstallTap(NSError **error)
{
    AVAudioInputNode *input = g_mic_engine.inputNode;
    AVAudioFormat *inFormat = [input outputFormatForBus:0];
    if (inFormat.sampleRate < 8000 || inFormat.channelCount < 1) {
        HaloMicStatus(@"no usable microphone input is available", nil);
        return NO;
    }
    AVAudioFormat *outFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                sampleRate:g_mic_rate channels:1 interleaved:NO];
    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inFormat toFormat:outFormat];
    if (!converter) {
        HaloMicStatus(@"cannot convert the microphone's format", nil);
        return NO;
    }
    [input removeTapOnBus:0];
    [input installTapOnBus:0 bufferSize:1024 format:inFormat
                     block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        (void)when;
        AVAudioFrameCount capacity = (AVAudioFrameCount)(buffer.frameLength * (g_mic_rate / inFormat.sampleRate)) + 64;
        AVAudioPCMBuffer *out = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outFormat frameCapacity:capacity];
        __block BOOL supplied = NO;
        NSError *convertError = nil;
        [converter convertToBuffer:out error:&convertError
                withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount count, AVAudioConverterInputStatus *status) {
            (void)count;
            if (supplied) { *status = AVAudioConverterInputStatus_NoDataNow; return nil; }
            supplied = YES;
            *status = AVAudioConverterInputStatus_HaveData;
            return buffer;
        }];
        if (!convertError && out.frameLength > 0 && out.floatChannelData)
            HaloMicPush(out.floatChannelData[0], out.frameLength);
    }];
    return YES;
}

static BOOL HaloMicStart(void)
{
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    /* Play and record, so the game keeps playing; Bluetooth headsets (AirPods and others with a microphone) are
     * allowed as the input, and the loudspeaker stays the output when nothing else is connected. */
    AVAudioSessionCategoryOptions options = AVAudioSessionCategoryOptionDefaultToSpeaker |
        AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionAllowBluetoothA2DP;
    if (![session setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeDefault options:options error:&error]) {
        HaloMicStatus(@"audio session would not switch to recording", error);
        return NO;
    }
    [session setActive:YES error:nil];
    g_mic_engine = [[AVAudioEngine alloc] init];
    if (!HaloMicInstallTap(&error)) {
        g_mic_engine = nil;
        return NO;
    }
    [g_mic_engine prepare];
    if (![g_mic_engine startAndReturnError:&error]) {
        HaloMicStatus(@"the microphone would not start", error);
        [g_mic_engine.inputNode removeTapOnBus:0];
        g_mic_engine = nil;
        return NO;
    }
    dispatch_once(&g_mic_observer_once, ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        /* a headset connected or removed, a call, another app: the input changed under the engine */
        [center addObserverForName:AVAudioEngineConfigurationChangeNotification object:nil
                             queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (!g_mic_open || note.object != g_mic_engine) return;
            NSError *again = nil;
            if (HaloMicInstallTap(&again) && !g_mic_engine.isRunning) [g_mic_engine startAndReturnError:&again];
        }];
        [center addObserverForName:AVAudioSessionInterruptionNotification object:nil
                             queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
            if (g_mic_open && g_mic_engine && type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded) {
                NSError *again = nil;
                [[AVAudioSession sharedInstance] setActive:YES error:nil];
                if (!g_mic_engine.isRunning) [g_mic_engine startAndReturnError:&again];
            }
        }];
    });
    AVAudioSessionPortDescription *route = session.currentRoute.inputs.firstObject;
    HaloMicStatus([NSString stringWithFormat:@"microphone open (%@)", route.portName ?: @"unknown input"], nil);
    return YES;
}

int halo_ios_mic_open(uint32_t sample_rate)
{
    if (sample_rate < 8000 || sample_rate > 96000) return 0;
    if (g_mic_open) return 1;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionRecordPermission permission = session.recordPermission;
    if (permission == AVAudioSessionRecordPermissionDenied) {
        HaloMicStatus(@"microphone access is off for Halo (iOS Settings > Halo > Microphone)", nil);
        return 0;
    }
    if (permission == AVAudioSessionRecordPermissionUndetermined) {
        dispatch_semaphore_t answered = dispatch_semaphore_create(0);
        __block BOOL granted = NO;
        [session requestRecordPermission:^(BOOL allowed) { granted = allowed; dispatch_semaphore_signal(answered); }];
        /* (this is the voice chat's own microphone thread: it may wait for the person to answer) */
        if (dispatch_semaphore_wait(answered, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)) != 0 || !granted) {
            HaloMicStatus(@"microphone permission was not given", nil);
            return 0;
        }
    }
#pragma clang diagnostic pop
    g_mic_rate = sample_rate;
    atomic_store(&g_mic_write, 0);
    atomic_store(&g_mic_read, 0);
    __block int ok = 0;
    void (^start)(void) = ^{ ok = HaloMicStart() ? 1 : 0; };
    if (NSThread.isMainThread) start();
    else dispatch_sync(dispatch_get_main_queue(), start);
    g_mic_open = ok ? YES : NO;
    return ok;
}

uint32_t halo_ios_mic_available(void)
{
    uint64_t write = atomic_load_explicit(&g_mic_write, memory_order_acquire);
    uint64_t read = atomic_load_explicit(&g_mic_read, memory_order_relaxed);
    return (uint32_t)(write - read);
}

uint32_t halo_ios_mic_read(float *out, uint32_t max_frames)
{
    uint64_t read = atomic_load_explicit(&g_mic_read, memory_order_relaxed);
    uint32_t count = halo_ios_mic_available();
    if (count > max_frames) count = max_frames;
    if (atomic_load_explicit(&g_mic_muted, memory_order_relaxed))
        for (uint32_t i = 0; i < count; i++) out[i] = 0.0f;
    else
        for (uint32_t i = 0; i < count; i++) out[i] = g_mic_ring[(read + i) % HALO_MIC_RING];
    atomic_store_explicit(&g_mic_read, read + count, memory_order_release);
    return count;
}

void halo_ios_mic_close(void)
{
    if (!g_mic_open) return;
    g_mic_open = NO;
    void (^stop)(void) = ^{
        [g_mic_engine.inputNode removeTapOnBus:0];
        [g_mic_engine stop];
        g_mic_engine = nil;
        NSError *error = nil;
        /* back to playback only: the game's sound keeps its usual route and quality */
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        HaloMicStatus(@"microphone closed", nil);
        HaloStartEngine();
    };
    if (NSThread.isMainThread) stop();
    else dispatch_async(dispatch_get_main_queue(), stop);
}

void halo_ios_mic_set_muted(int muted) { atomic_store(&g_mic_muted, muted ? 1 : 0); }
int halo_ios_mic_is_muted(void) { return atomic_load(&g_mic_muted); }
void halo_ios_ptt_set_held(int held) { atomic_store(&g_ptt_held, held ? 1 : 0); }
int halo_ios_ptt_held(void) { return atomic_load(&g_ptt_held); }

int halo_ios_mic_is_open(void)
{
    return g_mic_open ? 1 : 0;
}

const char *halo_ios_mic_status(void)
{
    return g_mic_status;
}
