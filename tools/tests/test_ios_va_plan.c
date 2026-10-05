/* The Non-Jailbreak Version's address-space planner (halo_va_plan.h) against simulated address spaces: how much can be
   reserved, which fixed 4 GiB-aligned window is used, that nothing is ever leaked or misplaced, and the JIT verdicts. */
#include <stdlib.h>
#include "halo_va_plan.h"

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

typedef struct { uint64_t base, size; } Range;
typedef struct {
    uint64_t limit, used, cursor;      /* total address space the process may hold; where "anywhere" goes next */
    Range held[64]; unsigned count;
    Range blocked[8]; unsigned blocked_count;   /* addresses something else already occupies */
    int lie;                            /* answer a fixed request with a different address */
    unsigned bad_releases;
    int aligned_error;                  /* the system refuses its own aligned search with this code */
    int aligned_misplaced;              /* the system answers its own aligned search with an unaligned address */
    unsigned aligned_calls;
} Space;

static int overlaps(Range a, uint64_t base, uint64_t size) { return base < a.base + a.size && a.base < base + size; }

static int space_reserve(void *context, uint64_t hint, uint64_t size, uint64_t *base, int *error) {
    Space *s = context;
    if (s->used + size > s->limit) { *error = 12; return 0; }
    if (hint) {
        for (unsigned i = 0; i < s->blocked_count; i++) if (overlaps(s->blocked[i], hint, size)) { *error = 12; return 0; }
        for (unsigned i = 0; i < s->count; i++) if (overlaps(s->held[i], hint, size)) { *error = 12; return 0; }
        *base = s->lie ? hint + 4096 : hint;
    } else {
        *base = s->cursor;
        s->cursor += (size + HALO_VA_GIB - 1) / HALO_VA_GIB * HALO_VA_GIB;
    }
    s->held[s->count].base = *base; s->held[s->count].size = size; s->count++; s->used += size;
    return 1;
}
static void space_release(void *context, uint64_t base, uint64_t size) {
    Space *s = context;
    for (unsigned i = 0; i < s->count; i++)
        if (s->held[i].base == base && s->held[i].size == size) { s->held[i] = s->held[--s->count]; s->used -= size; return; }
    s->bad_releases++;
}
/* the system's own search: the first 4 GiB-aligned address above where "anywhere" goes next, if the process may hold that much more */
static int space_reserve_aligned(void *context, uint64_t size, uint64_t *base, int *error) {
    Space *s = context;
    uint64_t at;
    s->aligned_calls++;
    if (s->aligned_error) { *error = s->aligned_error; return 0; }
    if (s->used + size > s->limit) { *error = 3; return 0; }
    at = (s->cursor + size - 1) & ~(size - 1);
    *base = s->aligned_misplaced ? at + 4096 : at;
    s->held[s->count].base = *base; s->held[s->count].size = size; s->count++; s->used += size;
    s->cursor = at + size;
    return 1;
}
static Space make_space(uint64_t limit_gib) { Space s; memset(&s, 0, sizeof(s)); s.limit = limit_gib * HALO_VA_GIB; s.cursor = UINT64_C(0x4000000000); return s; }
static HaloVaReserver reserver(Space *s) { HaloVaReserver r = { .context = s, .reserve = space_reserve, .release = space_release }; return r; }
static HaloVaReserver reserver_with_search(Space *s) { HaloVaReserver r = reserver(s); r.reserve_aligned = space_reserve_aligned; return r; }

static void test_candidates(void) {
    CHECK(halo_va_candidate(0) == UINT64_C(0x100000000), "the first window is at 4 GiB");
    for (unsigned i = 0; i < HALO_VA_CANDIDATES; i++) {
        CHECK((halo_va_candidate(i) & (HALO_VA_ARENA - 1)) == 0, "candidate %u is 4 GiB aligned", i);
        if (i) CHECK(halo_va_candidate(i) == halo_va_candidate(i - 1) + HALO_VA_ARENA, "candidate %u follows the previous one", i);
    }
}

static void test_ceilings(void) {
    HaloVaProbe p; unsigned expected_ok[HALO_VA_LADDER];
    static const unsigned limits[] = { 3, 6, 100 };
    static const unsigned ladder[HALO_VA_LADDER] = { 1, 2, 3, 4, 6, 8, 12, 16 };
    for (unsigned t = 0; t < 3; t++) {
        Space s = make_space(limits[t]); HaloVaReserver r = reserver(&s);
        halo_va_probe_run(&r, &p);
        for (unsigned i = 0; i < HALO_VA_LADDER; i++) {
            expected_ok[i] = ladder[i] <= limits[t];
            CHECK((unsigned)p.ladder_ok[i] == expected_ok[i] && p.ladder_gib[i] == ladder[i], "limit %u GiB: %u GiB ok=%d (expected %u)", limits[t], ladder[i], p.ladder_ok[i], expected_ok[i]);
            CHECK(p.ladder_ok[i] || p.ladder_error[i] == 12, "a refusal carries its error code");
        }
        CHECK(p.chain_gib == (limits[t] < HALO_VA_CHAIN_MAX ? limits[t] : HALO_VA_CHAIN_MAX), "limit %u GiB: %u GiB held at once", limits[t], p.chain_gib);
        CHECK((limits[t] < HALO_VA_CHAIN_MAX) == (p.chain_error != 0), "limit %u GiB: chain error %d", limits[t], p.chain_error);
        CHECK(p.aligned_tried == HALO_VA_CANDIDATES, "all windows asked about");
        if (limits[t] < 4) CHECK(p.aligned_ok == 0 && p.first_aligned == 0 && p.aligned_error == 12, "limit %u GiB: no 4 GiB window fits", limits[t]);
        else CHECK(p.aligned_ok == HALO_VA_CANDIDATES && p.first_aligned == halo_va_candidate(0), "limit %u GiB: every free window works, first at 0x%llx", limits[t], (unsigned long long)p.first_aligned);
        CHECK(s.count == 0 && s.used == 0 && s.bad_releases == 0, "limit %u GiB: the probe left %u reservations (%llu bytes) and %u bad releases", limits[t], s.count, (unsigned long long)s.used, s.bad_releases);
    }
}

static void test_fixed_arena(void) {
    uint64_t base = 0; int error = 0; unsigned tried = 0;
    Space s = make_space(6); HaloVaReserver r = reserver(&s);
    CHECK(halo_va_try_fixed_arena(&r, &base, &error, &tried) && base == halo_va_candidate(0) && tried == 1 && error == 0, "6 GiB: the first window is taken at once");
    CHECK(s.count == 1 && s.held[0].base == base && s.held[0].size == HALO_VA_ARENA, "exactly the 4 GiB window stays reserved for the caller");

    s = make_space(100);
    for (unsigned i = 0; i < 5; i++) { s.blocked[i].base = halo_va_candidate(i); s.blocked[i].size = HALO_VA_ARENA; }
    s.blocked_count = 5;
    r = reserver(&s);
    CHECK(halo_va_try_fixed_arena(&r, &base, &error, &tried) && base == halo_va_candidate(5) && tried == 6 && error == 12, "five occupied windows are skipped (tried %u, error %d)", tried, error);
    CHECK(s.count == 1 && s.bad_releases == 0, "nothing else is left reserved");

    s = make_space(3); r = reserver(&s);
    CHECK(!halo_va_try_fixed_arena(&r, &base, &error, &tried) && tried == HALO_VA_CANDIDATES && error == 12 && s.count == 0, "3 GiB: no window can be had and nothing stays reserved");

    s = make_space(100); s.lie = 1; r = reserver(&s);
    CHECK(!halo_va_try_fixed_arena(&r, &base, &error, &tried) && s.count == 0 && s.bad_releases == 0 && error == -1, "an answer at the wrong address is refused and released (error %d)", error);
    halo_va_probe_run(&r, &(HaloVaProbe){ 0 });
    CHECK(s.count == 0 && s.bad_releases == 0, "the probe also releases a wrongly placed answer");
}

static void test_aligned_arena(void) {
    uint64_t base = 0; int error = 0, fixed_error = 0; unsigned tried = 0; HaloVaProbe p; char text[1536];
    Space s = make_space(6); HaloVaReserver r = reserver_with_search(&s);
    CHECK(halo_va_try_aligned_arena(&r, &base, &error) && error == 0 && base % HALO_VA_ARENA == 0 && base != 0, "6 GiB: the system finds an aligned window (0x%llx)", (unsigned long long)base);
    CHECK(s.count == 1 && s.held[0].base == base && s.held[0].size == HALO_VA_ARENA && s.aligned_calls == 1, "exactly that 4 GiB window stays reserved for the caller");

    s = make_space(3); r = reserver_with_search(&s);
    CHECK(!halo_va_try_aligned_arena(&r, &base, &error) && error == 3 && s.count == 0, "3 GiB: the system has no aligned 4 GiB range (error %d) and nothing stays reserved", error);

    s = make_space(100); s.aligned_error = 4; r = reserver_with_search(&s);
    CHECK(!halo_va_try_aligned_arena(&r, &base, &error) && error == 4 && s.count == 0, "a refusal's code is passed on");
    CHECK(halo_va_try_fixed_arena(&r, &base, &fixed_error, &tried) && base == halo_va_candidate(0), "when the system's own search is refused the fixed windows are still tried");

    s = make_space(100); s.aligned_misplaced = 1; r = reserver_with_search(&s);
    CHECK(!halo_va_try_aligned_arena(&r, &base, &error) && error == HALO_VA_ERR_UNALIGNED && s.count == 0 && s.bad_releases == 0, "an unaligned answer is refused and released (error %d)", error);

    s = make_space(100); r = reserver(&s);
    CHECK(!halo_va_try_aligned_arena(&r, &base, &error) && error == HALO_VA_ERR_NOT_ATTEMPTED && s.count == 0 && s.aligned_calls == 0, "a platform without the search is told so, and nothing is asked");

    s = make_space(6); r = reserver_with_search(&s); halo_va_probe_run(&r, &p); halo_va_probe_format(&p, text, sizeof(text));
    CHECK(p.aligned_vm_tried && p.aligned_vm_ok && p.aligned_vm_base % HALO_VA_ARENA == 0 && s.count == 0 && s.bad_releases == 0, "the probe tries the system's search once and releases what it got");
    CHECK(strstr(text, "found by the system itself (vm_map): ok at 0x"), "report with a window:\n%s", text);
    s = make_space(3); r = reserver_with_search(&s); halo_va_probe_run(&r, &p); halo_va_probe_format(&p, text, sizeof(text));
    CHECK(p.aligned_vm_tried && !p.aligned_vm_ok && p.aligned_vm_error == 3 && strstr(text, "(vm_map): refused (no free aligned 4 GiB range (KERN_NO_SPACE, 3))"), "report when refused:\n%s", text);
    s = make_space(100); s.aligned_misplaced = 1; r = reserver_with_search(&s); halo_va_probe_run(&r, &p); halo_va_probe_format(&p, text, sizeof(text));
    CHECK(strstr(text, "refused (the system returned a window that is not 4 GiB-aligned)") && s.count == 0, "report for an unaligned answer:\n%s", text);
    s = make_space(100); r = reserver(&s); halo_va_probe_run(&r, &p); halo_va_probe_format(&p, text, sizeof(text));
    CHECK(!p.aligned_vm_tried && strstr(text, "(vm_map): not attempted on this platform"), "report without the search:\n%s", text);
    for (size_t size = 0; size <= 400; size += (size < 8 ? 1 : 41)) {
        unsigned char guarded[460];
        memset(guarded, 0xA5, sizeof(guarded));
        halo_va_probe_format(&p, (char *)guarded, size);
        for (size_t i = size; i < sizeof(guarded); i++) if (guarded[i] != 0xA5) { CHECK(0, "buffer of %zu bytes was overrun at %zu", size, i); break; }
        if (size) CHECK(memchr(guarded, 0, size) != NULL, "buffer of %zu bytes is not terminated", size);
    }
}

static void test_format(void) {
    HaloVaProbe p; char text[1024];
    Space s = make_space(6); HaloVaReserver r = reserver(&s);
    halo_va_probe_run(&r, &p);
    halo_va_probe_format(&p, text, sizeof(text));
    CHECK(strstr(text, "6 GiB ok") && strstr(text, "8 GiB FAILED (error 12)") && strstr(text, "held at once in 1 GiB steps: 6 GiB (stopped by error 12)") && strstr(text, "24 of 24 usable (first at 0x100000000)"), "report text:\n%s", text);
    s = make_space(3); r = reserver(&s); halo_va_probe_run(&r, &p); halo_va_probe_format(&p, text, sizeof(text));
    CHECK(strstr(text, "0 of 24 usable (first refusal: error 12)") && strstr(text, "4 GiB FAILED"), "report text for 3 GiB:\n%s", text);
    s = make_space(100); r = reserver(&s); halo_va_probe_run(&r, &p); halo_va_probe_format(&p, text, sizeof(text));
    CHECK(strstr(text, "(reached the 16 GiB test limit)"), "report text for 100 GiB:\n%s", text);
    /* a fixed request that the system places elsewhere is described in words, not as an error number */
    s = make_space(100); s.lie = 1; r = reserver(&s); halo_va_probe_run(&r, &p); halo_va_probe_format(&p, text, sizeof(text));
    CHECK(strstr(text, "0 of 24 usable (first refusal: the system placed it elsewhere)") && !strstr(text, "error -1"), "report text when fixed requests are placed elsewhere:\n%s", text);
    /* a small buffer is never overrun and is always terminated */
    for (size_t size = 0; size <= 120; size += (size < 8 ? 1 : 37)) {
        unsigned char guarded[160];
        memset(guarded, 0xA5, sizeof(guarded));
        halo_va_probe_format(&p, (char *)guarded, size);
        for (size_t i = size; i < sizeof(guarded); i++) if (guarded[i] != 0xA5) { CHECK(0, "buffer of %zu bytes was overrun at %zu", size, i); break; }
        if (size) CHECK(memchr(guarded, 0, size) != NULL, "buffer of %zu bytes is not terminated", size);
    }
}

static void test_jit(void) {
    HaloJitProbe p; char text[400];
    p = (HaloJitProbe){ 1, 1, 0, 0, 0 };    CHECK(halo_jit_verdict(&p) == HALO_JIT_AVAILABLE, "a debugger-enabled process allows it");
    p = (HaloJitProbe){ 1, 0, 0, 1, -1 };   CHECK(halo_jit_verdict(&p) == HALO_JIT_AVAILABLE, "one working route is enough");
    p = (HaloJitProbe){ 1, 0, 1, 1, 1 };    CHECK(halo_jit_verdict(&p) == HALO_JIT_NEEDS_ENABLER, "refused with no debugger: an enabler is needed");
    halo_jit_describe(&p, text, sizeof(text));
    CHECK(strstr(text, "no debugger is attached") && strstr(text, "enables JIT") && strstr(text, "error 1"), "text: %s", text);
    p = (HaloJitProbe){ 1, 1, 1, 1, 1 };    CHECK(halo_jit_verdict(&p) == HALO_JIT_UNKNOWN, "refused even with a debugger: cause unknown");
    halo_jit_describe(&p, text, sizeof(text)); CHECK(strstr(text, "debugger attached: yes") && strstr(text, "not established"), "text: %s", text);
    p = (HaloJitProbe){ 0, 0, 1, 1, 1 };    CHECK(halo_jit_verdict(&p) == HALO_JIT_UNKNOWN, "unreadable status is not guessed");
    halo_jit_describe(&p, text, sizeof(text)); CHECK(strstr(text, "debugger attached: unknown"), "text: %s", text);
    halo_jit_describe(&p, text, 5); CHECK(strlen(text) == 4, "a tiny buffer is terminated");
}

int main(void) {
    test_candidates(); test_ceilings(); test_fixed_arena(); test_aligned_arena(); test_format(); test_jit();
    if (!failures) printf("PASS: the address-space planner reports exact ceilings, takes the first free fixed 4 GiB-aligned window, never leaks or accepts a misplaced answer, formats safely, and classifies JIT availability\n");
    return failures ? 1 : 0;
}
