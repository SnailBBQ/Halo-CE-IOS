#include "halo_audio_ring.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

static HaloAudioRing ring;
static const uint32_t total = 3000000;

static void *producer(void *arg)
{
    (void)arg;
    float chunk[480 * 2];
    uint32_t sent = 0;
    while (sent < total) {
        uint32_t n = total - sent < 480 ? total - sent : 480;
        for (uint32_t i = 0; i < n; i++) { chunk[i * 2] = (float)(sent + i); chunk[i * 2 + 1] = -(float)(sent + i); }
        uint32_t pushed = halo_ring_push(&ring, chunk, n);
        /* a partial push must be retried from where it stopped */
        sent += pushed;
        if (pushed < n) sched_yield();
    }
    return NULL;
}

int main(void)
{
    /* single-threaded edge cases */
    float in[10 * 2], l[10], r[10];
    for (int i = 0; i < 10; i++) { in[i * 2] = (float)i; in[i * 2 + 1] = (float)-i; }
    if (halo_ring_push(&ring, in, 10) != 10 || halo_ring_fill(&ring) != 10) { printf("FAIL: push\n"); return 1; }
    halo_ring_pull(&ring, l, r, 4, 0.5f);
    if (l[3] != 1.5f || r[3] != -1.5f || halo_ring_fill(&ring) != 6) { printf("FAIL: pull and volume\n"); return 1; }
    halo_ring_pull(&ring, l, r, 10, 1.0f);   /* 6 real frames then silence */
    if (l[5] != 9.0f || l[6] != 0.0f || r[9] != 0.0f || atomic_load(&ring.underruns) != 1) { printf("FAIL: underrun gives silence\n"); return 1; }
    static float big[(HALO_RING_FRAMES + 100) * 2];
    if (halo_ring_push(&ring, big, HALO_RING_FRAMES + 100) != HALO_RING_FRAMES) { printf("FAIL: capacity limit\n"); return 1; }
    halo_ring_pull(&ring, l, r, 10, 1.0f);
    memset(&ring, 0, sizeof(ring));

    /* producer and consumer on separate threads: every frame arrives, in order, exactly once */
    pthread_t t;
    pthread_create(&t, NULL, producer, NULL);
    uint32_t received = 0, bad = 0;
    float left[256], right[256];
    while (received < total) {
        uint32_t want = 256;
        uint32_t fill = halo_ring_fill(&ring);
        if (fill == 0) { sched_yield(); continue; }
        if (want > fill) want = fill;
        halo_ring_pull(&ring, left, right, want, 1.0f);
        for (uint32_t i = 0; i < want; i++) if (left[i] != (float)(received + i) || right[i] != -(float)(received + i)) bad++;
        received += want;
    }
    pthread_join(t, NULL);
    if (bad || received != total || atomic_load(&ring.underruns) != 0) { printf("FAIL: threaded transfer, %u bad, %u received\n", bad, received); return 1; }
    printf("PASS: audio ring: ordering, volume, underrun silence, capacity, %u frames across two threads\n", total);
    return 0;
}
