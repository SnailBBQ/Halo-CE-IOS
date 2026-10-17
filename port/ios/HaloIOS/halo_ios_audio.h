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
/* Stops and starts the audio engine again; for a player whose sound cut out or crackles. */
void halo_ios_audio_restart(void);
uint32_t halo_ios_audio_underruns(void);
int halo_ios_audio_is_open(void);
/* Plain-language state for the log: why sound is or is not playing. */
const char *halo_ios_audio_status(void);

/* Voice chat's microphone. Open asks for the microphone permission the first time (and waits for the answer),
 * switches the audio session to play-and-record with Bluetooth headsets allowed (AirPods and other headphones with a
 * microphone are used when connected), and captures 48 kHz mono float. Returns 1 when samples will arrive. */
int halo_ios_mic_open(uint32_t sample_rate);
/* Takes up to max_frames captured samples; returns how many. */
uint32_t halo_ios_mic_read(float *out, uint32_t max_frames);
uint32_t halo_ios_mic_available(void);
/* Stops capture and puts the audio session back to playback only. */
void halo_ios_mic_close(void);
int halo_ios_mic_is_open(void);
/* Open mic's Mute button: while muted the game hears silence. Not saved; every launch starts unmuted. */
void halo_ios_mic_set_muted(int muted);
int halo_ios_mic_is_muted(void);
/* Push to talk's on-screen button: the game's own push-to-talk check reads this (with the keyboard key). */
void halo_ios_ptt_set_held(int held);
int halo_ios_ptt_held(void);
/* Plain-language state for the log: why the microphone is or is not working. */
const char *halo_ios_mic_status(void);

#ifdef __cplusplus
}
#endif

#endif
