#ifndef HALO_VA_PLAN_H
#define HALO_VA_PLAN_H
/*
 * Non-Jailbreak Version (HALO_NON_JAILBREAK builds only): what address space and executable memory a sideloaded install
 * really gets, and a way to boot with less than the production 8 GiB reservation. Plain C with no system calls of its own, so
 * tools/tests/test_ios_va_plan.c runs it against simulated address spaces. Nothing here changes how the guest is addressed:
 * the runtime still needs low32(host_pointer) == guest_virtual_address, i.e. a 4 GiB-aligned 4 GiB window.
 */
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define HALO_VA_GIB (UINT64_C(1) << 30)
#define HALO_VA_ARENA (UINT64_C(1) << 32)
#define HALO_VA_LADDER 8
#define HALO_VA_CHAIN_MAX 16
#define HALO_VA_CANDIDATES 24

typedef struct HaloVaReserver {
    void *context;
    /* Reserve size bytes of address space with no access. hint 0: anywhere. A non-zero hint asks for exactly that address and
       must not move or overwrite anything. Returns 1 and the base, or 0 and the system's error code. */
    int (*reserve)(void *context, uint64_t hint, uint64_t size, uint64_t *base, int *error);
    void (*release)(void *context, uint64_t base, uint64_t size);
} HaloVaReserver;

typedef struct HaloVaProbe {
    unsigned ladder_gib[HALO_VA_LADDER];
    int ladder_ok[HALO_VA_LADDER], ladder_error[HALO_VA_LADDER];
    unsigned chain_gib;            /* 1 GiB reservations held at once, up to HALO_VA_CHAIN_MAX */
    int chain_error;               /* what stopped the chain (0: it reached the maximum) */
    unsigned aligned_tried, aligned_ok;
    uint64_t first_aligned;        /* the first 4 GiB-aligned window that could be reserved (0: none) */
    int aligned_error;             /* the error of the first window that failed */
} HaloVaProbe;

/* the fixed 4 GiB-aligned windows tried, from 8 GiB upward (the first 4 GiB belong to the executable's page zero) */
static inline uint64_t halo_va_candidate(unsigned index) { return ((uint64_t)index + 2u) << 32; }

/* Reserve exactly `hint` (or anywhere when 0). A reserver that answers with a different address is refused and released. */
static inline int halo_va_reserve_at(const HaloVaReserver *r, uint64_t hint, uint64_t size, uint64_t *placed, int *error) {
    uint64_t base = 0;
    int code = 0;
    if (!r->reserve(r->context, hint, size, &base, &code)) { if (error) *error = code ? code : -1; return 0; }
    if (hint && base != hint) { r->release(r->context, base, size); if (error) *error = -1; return 0; }
    if (placed) *placed = base;
    return 1;
}

/* The fallback when the production reservation is refused: one 4 GiB window at the first aligned address that is free. On
   success that window stays reserved for the caller. *first_error is the first refusal's error; *tried how many were asked. */
static inline int halo_va_try_fixed_arena(const HaloVaReserver *r, uint64_t *base, int *first_error, unsigned *tried) {
    int saved = 0;
    for (unsigned i = 0; i < HALO_VA_CANDIDATES; i++) {
        int code = 0;
        uint64_t candidate = halo_va_candidate(i);
        if (tried) *tried = i + 1;
        if (halo_va_reserve_at(r, candidate, HALO_VA_ARENA, NULL, &code)) { *base = candidate; if (first_error) *first_error = saved; return 1; }
        if (!saved) saved = code;
    }
    if (first_error) *first_error = saved;
    return 0;
}

/* Log-only survey. Everything it reserves is released again before it returns. */
static inline void halo_va_probe_run(const HaloVaReserver *r, HaloVaProbe *p) {
    static const unsigned ladder[HALO_VA_LADDER] = { 1, 2, 3, 4, 6, 8, 12, 16 };
    uint64_t held[HALO_VA_CHAIN_MAX];
    unsigned n;
    memset(p, 0, sizeof(*p));
    for (unsigned i = 0; i < HALO_VA_LADDER; i++) {
        uint64_t base = 0, size = (uint64_t)ladder[i] * HALO_VA_GIB;
        int code = 0;
        p->ladder_gib[i] = ladder[i];
        if (halo_va_reserve_at(r, 0, size, &base, &code)) { p->ladder_ok[i] = 1; r->release(r->context, base, size); }
        else p->ladder_error[i] = code;
    }
    for (n = 0; n < HALO_VA_CHAIN_MAX; n++) {
        int code = 0;
        if (!halo_va_reserve_at(r, 0, HALO_VA_GIB, &held[n], &code)) { p->chain_error = code; break; }
    }
    p->chain_gib = n;
    for (unsigned i = 0; i < n; i++) r->release(r->context, held[i], HALO_VA_GIB);
    for (unsigned i = 0; i < HALO_VA_CANDIDATES; i++) {
        int code = 0;
        uint64_t candidate = halo_va_candidate(i);
        p->aligned_tried++;
        if (halo_va_reserve_at(r, candidate, HALO_VA_ARENA, NULL, &code)) {
            if (!p->aligned_ok) p->first_aligned = candidate;
            p->aligned_ok++;
            r->release(r->context, candidate, HALO_VA_ARENA);
        } else if (!p->aligned_error) p->aligned_error = code;
    }
}

static inline void halo_va_text(char *out, size_t size, size_t *used, const char *fmt, ...) {
    va_list ap;
    int n;
    if (!size || *used >= size - 1) return;
    va_start(ap, fmt);
    n = vsnprintf(out + *used, size - *used, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    *used += ((size_t)n < size - *used) ? (size_t)n : size - *used - 1;
}

static inline void halo_va_probe_format(const HaloVaProbe *p, char *out, size_t size) {
    size_t used = 0;
    if (!size) return;
    out[0] = 0;
    halo_va_text(out, size, &used, "Address-space probe (nothing stays reserved):\n  one reservation, any address:");
    for (unsigned i = 0; i < HALO_VA_LADDER; i++) {
        if (p->ladder_ok[i]) halo_va_text(out, size, &used, "%s %u GiB ok", i ? ";" : "", p->ladder_gib[i]);
        else halo_va_text(out, size, &used, "%s %u GiB FAILED (error %d)", i ? ";" : "", p->ladder_gib[i], p->ladder_error[i]);
    }
    halo_va_text(out, size, &used, "\n  held at once in 1 GiB steps: %u GiB", p->chain_gib);
    if (p->chain_error) halo_va_text(out, size, &used, " (stopped by error %d)", p->chain_error);
    else halo_va_text(out, size, &used, " (reached the %u GiB test limit)", (unsigned)HALO_VA_CHAIN_MAX);
    halo_va_text(out, size, &used, "\n  fixed 4 GiB-aligned windows: %u of %u usable", p->aligned_ok, p->aligned_tried);
    if (p->aligned_ok) halo_va_text(out, size, &used, " (first at 0x%llx)", (unsigned long long)p->first_aligned);
    else halo_va_text(out, size, &used, " (first refusal: error %d)", p->aligned_error);
    halo_va_text(out, size, &used, "\n");
}

/* ---- executable memory ---- */

typedef struct HaloJitProbe {
    int csops_ok;          /* the code-signing status could be read */
    int debugged;          /* a debugger has enabled JIT for this process (CS_DEBUGGED) */
    int mprotect_error;    /* writable page made executable; 0 means it worked */
    int direct_error;      /* executable anonymous mapping; 0 means it worked */
    int map_jit_error;     /* MAP_JIT mapping; 0 worked, -1 not available on this build */
} HaloJitProbe;

typedef enum { HALO_JIT_UNKNOWN, HALO_JIT_AVAILABLE, HALO_JIT_NEEDS_ENABLER } HaloJitVerdict;

static inline HaloJitVerdict halo_jit_verdict(const HaloJitProbe *p) {
    if (p->mprotect_error == 0 || p->direct_error == 0) return HALO_JIT_AVAILABLE;
    if (p->csops_ok && !p->debugged) return HALO_JIT_NEEDS_ENABLER;
    return HALO_JIT_UNKNOWN;
}

static inline void halo_jit_describe(const HaloJitProbe *p, char *out, size_t size) {
    switch (halo_jit_verdict(p)) {
    case HALO_JIT_AVAILABLE:
        snprintf(out, size, "Executable memory: the system allowed a writable page to become executable (mprotect error %d, direct mapping error %d, MAP_JIT error %d). That does not by itself prove the game's code will run.", p->mprotect_error, p->direct_error, p->map_jit_error);
        break;
    case HALO_JIT_NEEDS_ENABLER:
        snprintf(out, size, "Executable memory: refused (making a page executable: error %d; executable mapping: error %d; MAP_JIT: error %d) and no debugger is attached. A stock install needs a tool that enables JIT for sideloaded apps before the game's code can run.", p->mprotect_error, p->direct_error, p->map_jit_error);
        break;
    default:
        snprintf(out, size, "Executable memory: refused (making a page executable: error %d; executable mapping: error %d; MAP_JIT: error %d); debugger attached: %s. The cause is not established.", p->mprotect_error, p->direct_error, p->map_jit_error, p->csops_ok ? (p->debugged ? "yes" : "no") : "unknown");
        break;
    }
}
#endif
