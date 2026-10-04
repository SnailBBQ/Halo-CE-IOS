#ifndef HALO_TIMING_SAMPLE_H
#define HALO_TIMING_SAMPLE_H
#include <stdint.h>
/* Host-only telemetry. Sampling never changes work, validation or fault accounting.
 * Use high LCG bits rather than every Nth call to reduce periodic-loop bias.
 * State is owned by the invoking thread, with no shared cache or guest addresses. */
typedef struct { uint32_t state; } HaloTimingSampler;
typedef struct { int selected; double started; } HaloTimedSample;
static inline int halo_timing_select(HaloTimingSampler *sampler, unsigned shift) {
    sampler->state = sampler->state * UINT32_C(1664525) + UINT32_C(1013904223);
    return shift > 0 && shift < 32 && (sampler->state >> (32-shift)) == 0;
}
static inline HaloTimedSample halo_timing_begin(HaloTimingSampler *sampler,unsigned shift,double (*clock)(void)) {
    HaloTimedSample sample={halo_timing_select(sampler,shift),0};
    if(sample.selected)sample.started=clock();
    return sample;
}
static inline uint64_t halo_timing_finish(HaloTimedSample sample,double (*clock)(void)) {
    if(!sample.selected)return 0;
    double elapsed=clock()-sample.started;
    /* Reject backwards/nonfinite clocks and durations that cannot fit in ns. */
    return elapsed>=0 && elapsed<18446744073.0 ? (uint64_t)(elapsed*1e9) : 0;
}
static inline double halo_timing_estimated_ms(uint64_t calls,uint64_t samples,uint64_t sampled_ns) {
    return samples ? ((double)sampled_ns/(double)samples)*(double)calls/1e6 : 0;
}
#endif
