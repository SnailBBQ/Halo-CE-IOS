#ifndef HALO_GL_WAIT_STATS_H
#define HALO_GL_WAIT_STATS_H
#include <stdatomic.h>
#include <stdint.h>
#include "halo_timing_sample.h"

/* Host-only telemetry: where the game thread's wall time goes inside OpenGL calls, so a slow or blocked call can be named.
 * It never changes what is drawn, uploaded or waited for. Calls are always counted exactly. Rare or potentially blocking
 * categories are timed on every call; the very frequent ones (draws, buffer data) on about 1 call in 64, like the other
 * sampled clocks. Sampled totals are estimates and say how many samples back them. No guest pointers are kept. */
typedef enum {
    HALO_GLW_DRAW, HALO_GLW_BUFFER, HALO_GLW_TEXTURE, HALO_GLW_PROGRAM, HALO_GLW_FLUSH,
    HALO_GLW_READBACK, HALO_GLW_QUERY, HALO_GLW_CLEAR, HALO_GLW_FENCE, HALO_GLW_COUNT
} HaloGlWaitCategory;

#define HALO_GLW_LONG_CALL_NS UINT64_C(2000000)   /* a call this slow is counted separately */
#define HALO_GLW_SAMPLE_SHIFT 6                    /* sampled categories: about 1 call in 64 */

static inline const char *halo_glw_name(int category) {
    static const char *const names[HALO_GLW_COUNT] = {
        "draws", "buffer data", "texture upload", "shader compile/link", "flush/finish",
        "readback", "query result", "clear", "frame fence wait" };
    return (unsigned)category < HALO_GLW_COUNT ? names[category] : "unknown";
}
/* every category except the two that run thousands of times per second is timed on every call */
static inline int halo_glw_exact(int category) { return category != HALO_GLW_DRAW && category != HALO_GLW_BUFFER; }

typedef struct {
    _Atomic uint64_t calls[HALO_GLW_COUNT], samples[HALO_GLW_COUNT], ns[HALO_GLW_COUNT],
                     long_calls[HALO_GLW_COUNT], max_ns[HALO_GLW_COUNT];
} HaloGlWaitStats;
typedef struct {
    uint64_t calls[HALO_GLW_COUNT], samples[HALO_GLW_COUNT], ns[HALO_GLW_COUNT],
             long_calls[HALO_GLW_COUNT], max_ns[HALO_GLW_COUNT];
} HaloGlWaitSnapshot;
typedef struct { int category; HaloTimedSample timing; } HaloGlWaitTimer;

static inline HaloGlWaitTimer halo_gl_wait_begin(HaloGlWaitStats *stats, HaloTimingSampler *sampler, int category, double (*clock)(void)) {
    HaloGlWaitTimer timer = { category, { 0, 0 } };
    if ((unsigned)category >= HALO_GLW_COUNT) { timer.category = -1; return timer; }
    atomic_fetch_add_explicit(&stats->calls[category], 1, memory_order_relaxed);
    if (halo_glw_exact(category)) { timer.timing.selected = 1; timer.timing.started = clock(); }
    else timer.timing = halo_timing_begin(sampler, HALO_GLW_SAMPLE_SHIFT, clock);
    return timer;
}
static inline void halo_gl_wait_end(HaloGlWaitStats *stats, HaloGlWaitTimer timer, double (*clock)(void)) {
    if (timer.category < 0 || !timer.timing.selected) return;
    uint64_t ns = halo_timing_finish(timer.timing, clock), seen = atomic_load_explicit(&stats->max_ns[timer.category], memory_order_relaxed);
    atomic_fetch_add_explicit(&stats->samples[timer.category], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&stats->ns[timer.category], ns, memory_order_relaxed);
    if (ns >= HALO_GLW_LONG_CALL_NS) atomic_fetch_add_explicit(&stats->long_calls[timer.category], 1, memory_order_relaxed);
    while (ns > seen && !atomic_compare_exchange_weak_explicit(&stats->max_ns[timer.category], &seen, ns, memory_order_relaxed, memory_order_relaxed)) {}
}
/* the window's numbers, then back to zero for the next window */
static inline void halo_gl_wait_take(HaloGlWaitStats *stats, HaloGlWaitSnapshot *out) {
    for (int c = 0; c < HALO_GLW_COUNT; c++) {
        out->calls[c] = atomic_exchange_explicit(&stats->calls[c], 0, memory_order_relaxed);
        out->samples[c] = atomic_exchange_explicit(&stats->samples[c], 0, memory_order_relaxed);
        out->ns[c] = atomic_exchange_explicit(&stats->ns[c], 0, memory_order_relaxed);
        out->long_calls[c] = atomic_exchange_explicit(&stats->long_calls[c], 0, memory_order_relaxed);
        out->max_ns[c] = atomic_exchange_explicit(&stats->max_ns[c], 0, memory_order_relaxed);
    }
}
/* total wall time in ms: measured for exact categories, an estimate (average sample times all calls) for sampled ones */
static inline double halo_gl_wait_total_ms(const HaloGlWaitSnapshot *s, int category) {
    if ((unsigned)category >= HALO_GLW_COUNT) return 0;
    return halo_glw_exact(category) ? (double)s->ns[category] / 1e6 : halo_timing_estimated_ms(s->calls[category], s->samples[category], s->ns[category]);
}
#endif
