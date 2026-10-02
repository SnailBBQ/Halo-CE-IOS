#ifndef HALO_AUDIO_RING_H
#define HALO_AUDIO_RING_H

/*
 * Lock-free single-producer / single-consumer ring of stereo float frames.
 * The producer is the guest's audio thread (which mixes the game's voices in
 * guest code); the consumer is Core Audio's real-time render callback, which
 * must never block or take a lock. Capacity is a power of two.
 */

#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

#define HALO_RING_FRAMES 16384u /* about 340 ms at 48 kHz */

typedef struct
{
    float samples[HALO_RING_FRAMES * 2];
    _Atomic uint32_t write; /* total frames pushed */
    _Atomic uint32_t read;  /* total frames pulled */
    _Atomic uint32_t underruns;
} HaloAudioRing;

static inline uint32_t halo_ring_fill(HaloAudioRing *ring)
{
    return atomic_load_explicit(&ring->write, memory_order_acquire) -
           atomic_load_explicit(&ring->read, memory_order_acquire);
}

/* producer: copies as many whole frames as fit; returns how many */
static inline uint32_t halo_ring_push(HaloAudioRing *ring, const float *frames, uint32_t count)
{
    uint32_t write = atomic_load_explicit(&ring->write, memory_order_relaxed);
    uint32_t read = atomic_load_explicit(&ring->read, memory_order_acquire);
    uint32_t space = HALO_RING_FRAMES - (write - read);

    if (count > space)
        count = space;
    for (uint32_t i = 0; i < count; i++)
    {
        uint32_t slot = (write + i) & (HALO_RING_FRAMES - 1);

        ring->samples[slot * 2] = frames[i * 2];
        ring->samples[slot * 2 + 1] = frames[i * 2 + 1];
    }
    atomic_store_explicit(&ring->write, write + count, memory_order_release);
    return count;
}

/* consumer (real-time safe): fills left/right with volume applied, silence on underrun */
static inline void halo_ring_pull(HaloAudioRing *ring, float *left, float *right, uint32_t count, float volume)
{
    uint32_t read = atomic_load_explicit(&ring->read, memory_order_relaxed);
    uint32_t available = atomic_load_explicit(&ring->write, memory_order_acquire) - read;
    uint32_t take = count < available ? count : available;

    for (uint32_t i = 0; i < take; i++)
    {
        uint32_t slot = (read + i) & (HALO_RING_FRAMES - 1);

        left[i] = ring->samples[slot * 2] * volume;
        right[i] = ring->samples[slot * 2 + 1] * volume;
    }
    if (take < count)
    {
        memset(left + take, 0, (count - take) * sizeof(float));
        memset(right + take, 0, (count - take) * sizeof(float));
        atomic_fetch_add_explicit(&ring->underruns, 1, memory_order_relaxed);
    }
    atomic_store_explicit(&ring->read, read + take, memory_order_release);
}

#endif
