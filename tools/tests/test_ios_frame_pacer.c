#include "halo_frame_pacer.h"
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

/* simulates frames that take `work_ns` of their own, presented through the pacer, for `frames` frames;
 * returns the average presented rate */
static double simulate(int cap, uint64_t work_ns, int frames, uint64_t start)
{
    HaloFramePacer pacer = {0};
    uint64_t now = start, first = 0, last = 0;

    for (int i = 0; i < frames; i++)
    {
        now += work_ns;
        now += halo_pacer_wait(&pacer, now, cap);
        if (i == 0) first = now;
        last = now;
    }
    return frames > 1 ? (frames - 1) * 1e9 / (double)(last - first) : 0;
}

int main(void)
{
    /* a fast renderer is held to the cap */
    double r = simulate(60, 2000000, 600, 1000000000ull);
    CHECK(r > 59.9 && r < 60.1, "60 cap with 2 ms frames gives %.2f", r);
    r = simulate(30, 1000000, 300, 5);
    CHECK(r > 29.9 && r < 30.1, "30 cap gives %.2f", r);
    r = simulate(120, 3000000, 1200, 99);
    CHECK(r > 119.8 && r < 120.2, "120 cap gives %.2f", r);

    /* a renderer slower than the cap is not slowed further */
    r = simulate(60, 25000000, 200, 7);
    CHECK(r > 39.9 && r < 40.1, "25 ms frames under a 60 cap stay at 40 FPS, got %.2f", r);

    /* uncapped never waits and forgets its schedule */
    HaloFramePacer p = {0};
    CHECK(halo_pacer_wait(&p, 100, 0) == 0 && p.next_ns == 0, "uncapped does not wait");
    CHECK(halo_pacer_wait(&p, 200, 60) == 0 && p.next_ns == 200 + 16666666ull, "first capped frame is never delayed");
    CHECK(halo_pacer_wait(&p, 200 + 1000000ull, 60) == 15666666ull, "second waits out the interval");
    CHECK(halo_pacer_wait(&p, 5, 0) == 0 && p.next_ns == 0, "switching to uncapped resets");

    /* a long stall (a loading screen) restarts the count instead of firing a burst of frames */
    HaloFramePacer q = {0};
    uint64_t now = 1000;
    halo_pacer_wait(&q, now, 60);
    now += 3000000000ull;   /* 3 s stall */
    CHECK(halo_pacer_wait(&q, now, 60) == 0, "the late frame goes at once");
    int burst = 0;
    for (int i = 0; i < 5; i++) if (halo_pacer_wait(&q, now, 60) == 0) burst++;
    CHECK(burst == 0, "no burst of catch-up frames after a stall (%d)", burst);

    /* changing the cap mid-run takes effect on the next frame */
    HaloFramePacer c = {0};
    uint64_t t = 0;
    for (int i = 0; i < 10; i++) { t += halo_pacer_wait(&c, t, 60); t += 1000000; }
    uint64_t before = t;
    for (int i = 0; i < 10; i++) { t += halo_pacer_wait(&c, t, 30); t += 1000000; }
    double span = (t - before) / 1e9;
    CHECK(span > 0.30 && span < 0.38, "ten frames at a 30 cap take about 0.33 s, got %.3f", span);

    if (!failures) printf("PASS: frame pacer holds 30/60/120 caps, never slows a slow renderer, resets on uncapped and after stalls\n");
    return failures ? 1 : 0;
}
