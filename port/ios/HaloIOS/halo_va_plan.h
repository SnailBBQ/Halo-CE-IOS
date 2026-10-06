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

/* recorded in place of a system error code */
#define HALO_VA_ERR_PLACED_ELSEWHERE (-1)   /* a fixed request that the system answered at another address */
#define HALO_VA_ERR_UNALIGNED (-2)          /* the system returned a window that is not aligned to its size */
#define HALO_VA_ERR_NOT_ATTEMPTED (-3)      /* this platform cannot ask the system to find an aligned window */
#define HALO_VA_ERR_NO_REASON (-4)          /* the request failed and gave no reason */

typedef struct HaloVaReserver {
    void *context;
    /* Reserve size bytes of address space with no access. hint 0: anywhere. A non-zero hint asks for exactly that address and
       must not move or overwrite anything. Returns 1 and the base, or 0 and the system's error code. */
    int (*reserve)(void *context, uint64_t hint, uint64_t size, uint64_t *base, int *error);
    void (*release)(void *context, uint64_t base, uint64_t size);
    /* Optional (NULL when the platform cannot): ask the system itself for a window of `size` bytes aligned to `size`, at whatever address
       it finds free. Returns 1 and the base, or 0 and the system's error code. */
    int (*reserve_aligned)(void *context, uint64_t size, uint64_t *base, int *error);
} HaloVaReserver;

typedef struct HaloVaProbe {
    unsigned ladder_gib[HALO_VA_LADDER];
    int ladder_ok[HALO_VA_LADDER], ladder_error[HALO_VA_LADDER];
    unsigned chain_gib;            /* 1 GiB reservations held at once, up to HALO_VA_CHAIN_MAX */
    int chain_error;               /* what stopped the chain (0: it reached the maximum) */
    unsigned flexible_tried, flexible_ok; /* one exact 4 GiB reservation at any address; diagnostic only */
    uint64_t flexible_base;
    int flexible_error;
    unsigned aligned_tried, aligned_ok;
    uint64_t first_aligned;        /* the first 4 GiB-aligned window that could be reserved (0: none) */
    int aligned_error;             /* the error of the first window that failed */
    unsigned aligned_vm_tried, aligned_vm_ok;   /* the system's own search for an aligned 4 GiB window (one try) */
    uint64_t aligned_vm_base;
    int aligned_vm_error;
} HaloVaProbe;

/* the fixed 4 GiB-aligned windows tried, from 4 GiB upward (the first 4 GiB belong to the executable's page zero) */
static inline uint64_t halo_va_candidate(unsigned index) { return ((uint64_t)index + 1u) << 32; }

/* Reserve exactly `hint` (or anywhere when 0). A reserver that answers with a different address is refused and released. */
static inline int halo_va_reserve_at(const HaloVaReserver *r, uint64_t hint, uint64_t size, uint64_t *placed, int *error) {
    uint64_t base = 0;
    int code = 0;
    if (!r->reserve(r->context, hint, size, &base, &code)) { if (error) *error = code ? code : -1; return 0; }
    if (hint && base != hint) { r->release(r->context, base, size); if (error) *error = -1; return 0; }
    if (placed) *placed = base;
    return 1;
}

/* Ask the system to find a 4 GiB window aligned to 4 GiB itself. This needs only 4 GiB of address space, where the production path
   needs 8, and it is the only request a system with a small address space may grant. On success the window stays reserved for the
   caller. A window that is not aligned is released and refused. */
static inline int halo_va_try_aligned_arena(const HaloVaReserver *r, uint64_t *base, int *error) {
    uint64_t placed = 0;
    int code = 0;
    if (!r->reserve_aligned) { if (error) *error = HALO_VA_ERR_NOT_ATTEMPTED; return 0; }
    if (!r->reserve_aligned(r->context, HALO_VA_ARENA, &placed, &code)) { if (error) *error = code ? code : HALO_VA_ERR_NO_REASON; return 0; }
    if (placed & (HALO_VA_ARENA - 1)) { r->release(r->context, placed, HALO_VA_ARENA); if (error) *error = HALO_VA_ERR_UNALIGNED; return 0; }
    *base = placed;
    if (error) *error = 0;
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
    {
        uint64_t base = 0;
        int code = 0;
        p->flexible_tried = 1;
        if (halo_va_reserve_at(r, 0, HALO_VA_ARENA, &base, &code)) {
            p->flexible_ok = 1;
            p->flexible_base = base;
            r->release(r->context, base, HALO_VA_ARENA);
        } else p->flexible_error = code;
    }
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
    p->aligned_vm_tried = r->reserve_aligned != NULL;
    if (p->aligned_vm_tried) {
        uint64_t base = 0;
        int code = 0;
        if (halo_va_try_aligned_arena(r, &base, &code)) { p->aligned_vm_ok = 1; p->aligned_vm_base = base; r->release(r->context, base, HALO_VA_ARENA); }
        else p->aligned_vm_error = code;
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

/* an error code in words: the negative codes are this planner's own (see above), the others the system's */
static inline void halo_va_error_text(int code, char *out, size_t size) {
    if (code == HALO_VA_ERR_PLACED_ELSEWHERE) snprintf(out, size, "the system placed it elsewhere");
    else if (code == HALO_VA_ERR_UNALIGNED) snprintf(out, size, "the system returned a window that is not 4 GiB-aligned");
    else if (code == HALO_VA_ERR_NOT_ATTEMPTED) snprintf(out, size, "not attempted on this platform");
    else if (code == HALO_VA_ERR_NO_REASON) snprintf(out, size, "the system gave no reason");
    else snprintf(out, size, "error %d", code);
}

/* the same for the system's own search, whose positive codes are Mach kernel return codes */
static inline void halo_va_aligned_error_text(int code, char *out, size_t size) {
    if (code == 3) snprintf(out, size, "no free aligned 4 GiB range (KERN_NO_SPACE, 3)");
    else if (code == 4) snprintf(out, size, "invalid argument (KERN_INVALID_ARGUMENT, 4)");
    else if (code > 0) snprintf(out, size, "kernel error %d", code);
    else halo_va_error_text(code, out, size);
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
    halo_va_text(out, size, &used, "\n  Flexible 4 GiB ANYWHERE: ");
    if (p->flexible_ok) halo_va_text(out, size, &used, "SUCCESS at 0x%llx (4 GiB-aligned: %s; offset in 4 GiB block: 0x%llx)",
        (unsigned long long)p->flexible_base, (p->flexible_base & (HALO_VA_ARENA - 1)) ? "NO" : "YES",
        (unsigned long long)(p->flexible_base & (HALO_VA_ARENA - 1)));
    else halo_va_text(out, size, &used, "FAILED (error %d)", p->flexible_error);
    halo_va_text(out, size, &used, "\n  fixed 4 GiB-aligned windows: %u of %u usable", p->aligned_ok, p->aligned_tried);
    if (p->aligned_ok) halo_va_text(out, size, &used, " (first at 0x%llx)", (unsigned long long)p->first_aligned);
    else {
        char why[96];
        halo_va_error_text(p->aligned_error, why, sizeof(why));
        halo_va_text(out, size, &used, " (first refusal: %s)", why);
    }
    halo_va_text(out, size, &used, "\n  4 GiB window aligned and found by the system itself (vm_map): ");
    if (!p->aligned_vm_tried) halo_va_text(out, size, &used, "not attempted on this platform");
    else if (p->aligned_vm_ok) halo_va_text(out, size, &used, "ok at 0x%llx", (unsigned long long)p->aligned_vm_base);
    else {
        char why[96];
        halo_va_aligned_error_text(p->aligned_vm_error, why, sizeof(why));
        halo_va_text(out, size, &used, "refused (%s)", why);
    }
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
