/* The guest image loader's memory plan, run against the real guest memory manager (halo_guest_runtime.c).
 *
 * guest.ld aligns .data to 64 KiB, so a gap of unmapped 16 KiB pages can sit between segments. M2.6.34/35
 * mapped each segment on its own and then swept [first byte, last byte) for the instruction cache; that sweep
 * took a bus error on the first gap page (signal 10 at 0x88848000 on the device). This test lays out segments
 * the same way, runs the old plan (must fault) and the new plan (must not), and checks the final protections.
 * It models the loader's mapping steps; it does not run the Objective-C loader itself. */
#define _GNU_SOURCE
#include "../../port/ios/HaloIOS/halo_guest_runtime.c"
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

typedef struct { uint32_t va, mem, flags; } Seg; /* flags: 1 = x, 2 = w, 4 = r */

static sigjmp_buf jump;
static void on_fault(int sig) { (void)sig; siglongjmp(jump, 1); }

/* reads one byte per page, as cache maintenance over a range does; returns the first page that faults, or 0 */
static uint32_t sweep(uint32_t va, uint32_t size, size_t page)
{
    struct sigaction action, old_segv, old_bus;
    uint32_t faulted = 0;

    memset(&action, 0, sizeof(action));
    action.sa_handler = on_fault;
    sigemptyset(&action.sa_mask);
    sigaction(SIGSEGV, &action, &old_segv);
    sigaction(SIGBUS, &action, &old_bus);
    for (uint64_t p = va & ~(uint64_t)(page - 1); p < (uint64_t)va + size; p += page)
    {
        uint32_t at = p < va ? va : (uint32_t)p;
        if (sigsetjmp(jump, 1) == 0)
            *(volatile uint8_t *)halo_guest_ptr(at, 1);
        else
        {
            faulted = (uint32_t)p;
            break;
        }
    }
    sigaction(SIGSEGV, &old_segv, NULL);
    sigaction(SIGBUS, &old_bus, NULL);
    return faulted;
}

/* the old plan: map each segment alone, then sweep the whole image */
static uint32_t old_plan(const Seg *segs, int n, size_t page)
{
    uint32_t low = UINT32_MAX, high = 0;
    for (int i = 0; i < n; i++)
    {
        halo_guest_commit(segs[i].va, segs[i].mem);
        if (segs[i].va < low) low = segs[i].va;
        if (segs[i].va + segs[i].mem > high) high = segs[i].va + segs[i].mem;
    }
    return sweep(low, high - low, page);
}

/* the new plan: map the whole span, then sweep only the executable segments, each over its own bytes */
static uint32_t new_plan(const Seg *segs, int n, size_t page)
{
    uint32_t low = UINT32_MAX, high = 0;
    for (int i = 0; i < n; i++)
    {
        if (segs[i].va < low) low = segs[i].va;
        if (segs[i].va + segs[i].mem > high) high = segs[i].va + segs[i].mem;
    }
    halo_guest_commit(low, high - low);
    for (int i = 0; i < n; i++)
        if (segs[i].flags & 1)
        {
            uint32_t f = sweep(segs[i].va, segs[i].mem, page);
            if (f) return f;
        }
    /* and even the whole-image sweep is safe now */
    return sweep(low, high - low, page);
}

int main(void)
{
    if (!halo_guest_runtime_init())
    {
        printf("SKIP: cannot reserve the 8 GiB guest arena here\n");
        return 0;
    }
    size_t page = 16384;
    long real = sysconf(_SC_PAGESIZE);
    if (real > 16384) page = (size_t)real;
    if ((size_t)real != page) { printf("note: host page size is %ld, test uses it\n", real); page = (size_t)real; }

    /* text+rodata end 0x88848000 on a 16 KiB boundary (the device's fault address), .data aligned to 64 KiB */
    const Seg gap[] = { { 0x88000000u, 0x00844000u, 1 | 4 }, { 0x88850000u, 0x00200000u, 2 | 4 } };
    /* no gap: a segment that ends right at the next one */
    const Seg flush[] = { { 0x88000000u, 0x00850000u, 1 | 4 }, { 0x88850000u, 0x00100000u, 2 | 4 } };

    uint32_t fault = old_plan(gap, 2, page);
    CHECK(fault != 0, "the old plan should fault on a layout with a gap");
    CHECK(fault == 0x88844000u, "the old plan faults on the first page after the last mapped byte (got 0x%08x)", fault);
    halo_guest_decommit(0x88000000u, 0x00a50000u);

    CHECK(new_plan(gap, 2, page) == 0, "the new plan must not fault on a layout with a gap");
    CHECK(sweep(0x88844000u, 0x10000u, page) == 0, "the gap pages are mapped (readable)");
    halo_guest_decommit(0x88000000u, 0x00a50000u);

    CHECK(old_plan(flush, 2, page) == 0, "a layout without a gap worked before (this is why the old image loaded)");
    halo_guest_decommit(0x88000000u, 0x00a50000u);
    CHECK(new_plan(flush, 2, page) == 0, "and still works");
    halo_guest_decommit(0x88000000u, 0x00a50000u);

    /* sizes that are not page multiples, and a one-page gap */
    const Seg ragged[] = { { 0x88000000u, 0x0083f123u, 1 | 4 }, { 0x88840000u, 0x00001000u, 2 | 4 }, { 0x88860000u, 0x00300000u, 2 | 4 } };
    CHECK(new_plan(ragged, 3, page) == 0, "ragged sizes and several gaps");
    halo_guest_decommit(0x88000000u, 0x00b60000u);

    /* the bounds the loader checks before mapping anything */
    CHECK(halo_guest_commit(0xfffff000u, 0x2000u) == 0, "a range that runs past 4 GiB is refused");
    CHECK(halo_guest_commit(0x88000000u, 0) == 0, "an empty range is refused");

    if (!failures) printf("PASS: image loading plan: a gap between segments faults the old plan at the gap's first page and not the new one; layouts without a gap, ragged sizes and bad ranges\n");
    return failures ? 1 : 0;
}
