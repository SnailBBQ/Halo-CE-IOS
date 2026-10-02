#ifndef HALO_IOS_AUDIO_H
#define HALO_IOS_AUDIO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opens stereo float output. Returns 1 if the host will play what is pushed. */
int halo_ios_audio_open(uint32_t sample_rate, uint32_t channels);
/* Frames queued but not yet played. */
uint32_t halo_ios_audio_fill(void);
/* Queues interleaved stereo float frames; returns how many were taken. */
uint32_t halo_ios_audio_push(const float *frames, uint32_t count);

/* Master volume 0...1 from the settings screen. */
void halo_ios_audio_set_volume(float volume);
/* Restarts output after an interruption or when the app returns to the front. */
void halo_ios_audio_resume(void);
uint32_t halo_ios_audio_underruns(void);
int halo_ios_audio_is_open(void);

#ifdef __cplusplus
}
#endif

#endif
