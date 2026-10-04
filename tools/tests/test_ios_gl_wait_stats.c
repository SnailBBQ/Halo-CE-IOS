#define _POSIX_C_SOURCE 200809L
/* GL call wall-time accounting (halo_gl_wait_stats.h): exact counts, exact timing for rare calls, bounded sampling for the hot
   ones, long-call and worst-call tracking, resettable windows, and no lost updates across threads. */
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include "halo_gl_wait_stats.h"

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

static double now_s, step_s;
static unsigned reads;
static double fake_clock(void) { reads++; now_s += step_s; return now_s; }
static double backwards_clock(void) { reads++; now_s -= 1.0; return now_s; }

static HaloGlWaitStats stats;
static HaloTimingSampler sampler;

static void reset(double step) { HaloGlWaitSnapshot discard; halo_gl_wait_take(&stats, &discard); now_s = 100; step_s = step; reads = 0; }

static void test_exact_categories(void) {
    HaloGlWaitSnapshot s;
    for (int c = 0; c < HALO_GLW_COUNT; c++) {
        if (!halo_glw_exact(c)) continue;
        reset(0.0005);
        for (int i = 0; i < 1000; i++) { HaloGlWaitTimer t = halo_gl_wait_begin(&stats, &sampler, c, fake_clock); halo_gl_wait_end(&stats, t, fake_clock); }
        halo_gl_wait_take(&stats, &s);
        CHECK(s.calls[c] == 1000 && s.samples[c] == 1000 && reads == 2000, "%s: %llu calls, %llu samples, %u clock reads", halo_glw_name(c), (unsigned long long)s.calls[c], (unsigned long long)s.samples[c], reads);
        CHECK(llabs((long long)s.ns[c] - 1000LL * 500000) < 1000 && s.long_calls[c] == 0 && llabs((long long)s.max_ns[c] - 500000) < 1000, "%s: %llu ns total, worst %llu", halo_glw_name(c), (unsigned long long)s.ns[c], (unsigned long long)s.max_ns[c]);
        CHECK(fabs(halo_gl_wait_total_ms(&s, c) - 500.0) < 1.0, "%s total %.3f ms", halo_glw_name(c), halo_gl_wait_total_ms(&s, c));
    }
}

static void test_long_calls_and_worst(void) {
    HaloGlWaitSnapshot s;
    const double steps[] = { 0.0001, 0.003, 0.0001, 0.0021, 0.0019, 0.0125, 0.0001 };
    reset(0);
    for (unsigned i = 0; i < sizeof(steps) / sizeof(steps[0]); i++) {
        HaloGlWaitTimer t; step_s = 0;
        t = halo_gl_wait_begin(&stats, &sampler, HALO_GLW_FENCE, fake_clock);
        step_s = steps[i];
        halo_gl_wait_end(&stats, t, fake_clock);
    }
    halo_gl_wait_take(&stats, &s);
    CHECK(s.calls[HALO_GLW_FENCE] == 7 && s.long_calls[HALO_GLW_FENCE] == 3, "fence: %llu calls, %llu long (expected 3: 3.0, 2.1 and 12.5 ms)", (unsigned long long)s.calls[HALO_GLW_FENCE], (unsigned long long)s.long_calls[HALO_GLW_FENCE]);
    CHECK(llabs((long long)s.max_ns[HALO_GLW_FENCE] - 12500000) < 2000, "worst %.3f ms", s.max_ns[HALO_GLW_FENCE] / 1e6);
}

static void test_sampled_categories(void) {
    HaloGlWaitSnapshot s;
    const unsigned long long calls = 1ull << 20;
    for (int c = 0; c < HALO_GLW_COUNT; c++) {
        if (halo_glw_exact(c)) continue;
        reset(0.0001);
        for (unsigned long long i = 0; i < calls; i++) { HaloGlWaitTimer t = halo_gl_wait_begin(&stats, &sampler, c, fake_clock); halo_gl_wait_end(&stats, t, fake_clock); }
        halo_gl_wait_take(&stats, &s);
        double expected = (double)calls / 64.0;
        CHECK(s.calls[c] == calls, "%s: calls must stay exact, got %llu", halo_glw_name(c), (unsigned long long)s.calls[c]);
        CHECK((double)s.samples[c] > 0.8 * expected && (double)s.samples[c] < 1.2 * expected, "%s: %llu samples of %llu calls (expected about %.0f)", halo_glw_name(c), (unsigned long long)s.samples[c], calls, expected);
        CHECK(reads == 2 * s.samples[c], "%s: %u clock reads for %llu samples (unsampled calls must not read the clock)", halo_glw_name(c), reads, (unsigned long long)s.samples[c]);
        CHECK(fabs(halo_gl_wait_total_ms(&s, c) - 0.0001 * 1000.0 * (double)calls) < 0.5, "%s estimated %.1f ms (expected %.1f)", halo_glw_name(c), halo_gl_wait_total_ms(&s, c), 0.0001 * 1000.0 * (double)calls);
    }
    CHECK(!halo_glw_exact(HALO_GLW_DRAW) && !halo_glw_exact(HALO_GLW_BUFFER) && halo_glw_exact(HALO_GLW_FLUSH) && halo_glw_exact(HALO_GLW_FENCE) && halo_glw_exact(HALO_GLW_PROGRAM) && halo_glw_exact(HALO_GLW_READBACK) && halo_glw_exact(HALO_GLW_QUERY) && halo_glw_exact(HALO_GLW_TEXTURE) && halo_glw_exact(HALO_GLW_CLEAR), "only draws and buffer data are sampled");
}

static void test_windows_and_bad_input(void) {
    HaloGlWaitSnapshot first, second;
    reset(0.001);
    for (int i = 0; i < 10; i++) { HaloGlWaitTimer t = halo_gl_wait_begin(&stats, &sampler, HALO_GLW_FLUSH, fake_clock); halo_gl_wait_end(&stats, t, fake_clock); }
    halo_gl_wait_take(&stats, &first);
    halo_gl_wait_take(&stats, &second);
    CHECK(first.calls[HALO_GLW_FLUSH] == 10 && second.calls[HALO_GLW_FLUSH] == 0 && second.ns[HALO_GLW_FLUSH] == 0 && second.max_ns[HALO_GLW_FLUSH] == 0 && second.long_calls[HALO_GLW_FLUSH] == 0, "a window starts from zero");
    reads = 0;
    HaloGlWaitTimer bad = halo_gl_wait_begin(&stats, &sampler, -1, fake_clock);
    halo_gl_wait_end(&stats, bad, fake_clock);
    bad = halo_gl_wait_begin(&stats, &sampler, HALO_GLW_COUNT, fake_clock);
    halo_gl_wait_end(&stats, bad, fake_clock);
    halo_gl_wait_take(&stats, &first);
    { unsigned long long total = 0; for (int c = 0; c < HALO_GLW_COUNT; c++) total += first.calls[c]; CHECK(reads == 0 && total == 0, "an invalid category is ignored (%u reads, %llu calls)", reads, total); }
    /* a clock that goes backwards must not produce a huge duration */
    reset(0);
    { HaloGlWaitTimer t = halo_gl_wait_begin(&stats, &sampler, HALO_GLW_READBACK, backwards_clock); halo_gl_wait_end(&stats, t, backwards_clock); }
    halo_gl_wait_take(&stats, &first);
    CHECK(first.calls[HALO_GLW_READBACK] == 1 && first.ns[HALO_GLW_READBACK] == 0 && first.long_calls[HALO_GLW_READBACK] == 0, "a backwards clock records zero, not garbage (%llu ns)", (unsigned long long)first.ns[HALO_GLW_READBACK]);
    /* names */
    for (int c = 0; c < HALO_GLW_COUNT; c++) {
        CHECK(halo_glw_name(c)[0] && strcmp(halo_glw_name(c), "unknown"), "category %d has a name", c);
        for (int d = c + 1; d < HALO_GLW_COUNT; d++) CHECK(strcmp(halo_glw_name(c), halo_glw_name(d)), "names %d and %d differ", c, d);
    }
    CHECK(!strcmp(halo_glw_name(99), "unknown") && !strcmp(halo_glw_name(-1), "unknown"), "out-of-range names");
}

static double real_clock(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (double)t.tv_sec + (double)t.tv_nsec / 1e9; }
static void *worker(void *unused) {
    HaloTimingSampler mine = { 12345 };
    (void)unused;
    for (int i = 0; i < 20000; i++) {
        HaloGlWaitTimer t = halo_gl_wait_begin(&stats, &mine, HALO_GLW_QUERY, real_clock); halo_gl_wait_end(&stats, t, real_clock);
        t = halo_gl_wait_begin(&stats, &mine, HALO_GLW_DRAW, real_clock); halo_gl_wait_end(&stats, t, real_clock);
    }
    return NULL;
}
static void test_threads(void) {
    pthread_t threads[4]; HaloGlWaitSnapshot s;
    reset(0);
    for (int i = 0; i < 4; i++) pthread_create(&threads[i], NULL, worker, NULL);
    for (int i = 0; i < 4; i++) pthread_join(threads[i], NULL);
    halo_gl_wait_take(&stats, &s);
    CHECK(s.calls[HALO_GLW_QUERY] == 80000 && s.samples[HALO_GLW_QUERY] == 80000 && s.calls[HALO_GLW_DRAW] == 80000, "no update lost across threads: %llu query calls, %llu timed, %llu draws", (unsigned long long)s.calls[HALO_GLW_QUERY], (unsigned long long)s.samples[HALO_GLW_QUERY], (unsigned long long)s.calls[HALO_GLW_DRAW]);
    CHECK(s.samples[HALO_GLW_DRAW] > 600 && s.samples[HALO_GLW_DRAW] < 2000, "about 1 draw in 64 timed: %llu of 80000", (unsigned long long)s.samples[HALO_GLW_DRAW]);
}

int main(void) {
    test_exact_categories(); test_long_calls_and_worst(); test_sampled_categories(); test_windows_and_bad_input(); test_threads();
    if (!failures) printf("PASS: GL wall-time accounting: exact counts, every rare call timed, hot calls sampled 1/64 with zero clock reads when unsampled, long and worst calls, resettable windows, bad input and threads\n");
    return failures ? 1 : 0;
}
