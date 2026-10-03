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
