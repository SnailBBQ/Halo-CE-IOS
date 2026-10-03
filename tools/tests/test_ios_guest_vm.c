/* Stress test for the guest address-space allocator (halo_guest_vm.h) against a page-by-page reference model, and for
 * the real guest memory manager's release of freed memory. Run from the repository root:
 *   cc -std=gnu11 -Iport/ios/HaloIOS tools/tests/test_ios_guest_vm.c -o t && ./t */
#define _GNU_SOURCE
#include "../../port/ios/HaloIOS/halo_guest_runtime.c"
#include "halo_guest_vm.h"
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

#define PAGE 0x4000u
#define BASE 0xA0000000u
#define LIMIT 0xD0000000u
#define PAGES ((LIMIT - BASE) / PAGE)

static unsigned char live[PAGES];   /* the model: 1 where a page is handed out */

typedef struct { uint32_t va, size; } Block;

/* invariants that must hold after every operation */
static void invariants(const HaloVm *vm, uint64_t model_used, const char *where)
{
    uint64_t holes = 0;
    for (unsigned i = 0; i < vm->holes; i++)
    {
        CHECK(vm->hole[i].start < vm->hole[i].end, "%s: empty hole", where);
        CHECK(vm->hole[i].start % PAGE == 0 && vm->hole[i].end % PAGE == 0, "%s: hole not page aligned", where);
        CHECK(vm->hole[i].start >= vm->base && vm->hole[i].end <= vm->next, "%s: hole outside the used area", where);
        if (i) CHECK(vm->hole[i - 1].end < vm->hole[i].start, "%s: holes touch or overlap or are unsorted", where);
        holes += vm->hole[i].end - vm->hole[i].start;
        for (uint32_t p = vm->hole[i].start; p < vm->hole[i].end; p += PAGE)
            if (live[(p - BASE) / PAGE]) { CHECK(0, "%s: a hole covers a live page 0x%x", where, p); return; }
    }
    CHECK(vm->used == model_used, "%s: used %llu but the model has %llu", where, (unsigned long long)vm->used, (unsigned long long)model_used);
    CHECK(vm->next >= vm->base && vm->next <= vm->limit, "%s: next out of range", where);
    CHECK(vm->used + holes + vm->lost == (uint64_t)(vm->next - vm->base), "%s: used %llu + holes %llu + lost %llu != span %llu", where,
          (unsigned long long)vm->used, (unsigned long long)holes, (unsigned long long)vm->lost, (unsigned long long)(vm->next - vm->base));
    if (vm->holes) CHECK(vm->hole[vm->holes - 1].end < vm->next, "%s: a hole at the very end should have shrunk the area", where);
}

int main(void)
{
    static HaloVm vm;
    halo_vm_init(&vm, BASE, LIMIT, PAGE);

    /* basics */
    CHECK(halo_vm_alloc(&vm, 0, PAGE) == 0, "zero size");
    uint32_t a = halo_vm_alloc(&vm, 1, PAGE);
    uint32_t b = halo_vm_alloc(&vm, PAGE + 1, PAGE);
    uint32_t c = halo_vm_alloc(&vm, 3 * PAGE, 0x10000);
    CHECK(a == BASE && b == BASE + PAGE && c % 0x10000 == 0 && c >= b + 2 * PAGE, "sequential, page rounded and 64K aligned: %x %x %x", a, b, c);
    CHECK(vm.used == (uint64_t)(PAGE + 2 * PAGE + 3 * PAGE), "used %llu", (unsigned long long)vm.used);
    memset(live, 0, sizeof live);
    for (uint32_t p = a; p < a + PAGE; p += PAGE) live[(p - BASE) / PAGE] = 1;
    for (uint32_t p = b; p < b + 2 * PAGE; p += PAGE) live[(p - BASE) / PAGE] = 1;
    for (uint32_t p = c; p < c + 3 * PAGE; p += PAGE) live[(p - BASE) / PAGE] = 1;
    invariants(&vm, 6 * PAGE, "basics");

    /* the reason this exists: freeing returns the space, and the same space is handed out again */
    CHECK(halo_vm_free(&vm, b, 2 * PAGE) == 2 * PAGE, "free b");
    live[(b - BASE) / PAGE] = live[(b - BASE) / PAGE + 1] = 0;
    uint32_t again = halo_vm_alloc(&vm, 2 * PAGE, PAGE);
    CHECK(again == b, "a freed range is reused (got 0x%x, wanted 0x%x)", again, b);
    live[(b - BASE) / PAGE] = live[(b - BASE) / PAGE + 1] = 1;
    CHECK(halo_vm_free(&vm, c, 3 * PAGE) == 3 * PAGE, "free the end");
    for (int i = 0; i < 3; i++) live[(c - BASE) / PAGE + i] = 0;
    CHECK(vm.next == b + 2 * PAGE, "freeing the end shrinks the used area back (next 0x%x)", vm.next);
    invariants(&vm, 3 * PAGE, "reuse");

    /* a double free and a free outside the region change nothing */
    uint64_t used_before = vm.used;
    CHECK(halo_vm_free(&vm, c, 3 * PAGE) == 0 && vm.used == used_before, "double free");
    CHECK(halo_vm_free(&vm, 0x1000, 0x2000) == 0 && halo_vm_free(&vm, LIMIT + PAGE, PAGE) == 0 && halo_vm_free(&vm, b, 0) == 0, "free outside / empty");

    /* freeing the middle of a block (munmap of a sub-range) splits it */
    halo_vm_free(&vm, a, PAGE);
    live[0] = 0;
    uint32_t big = halo_vm_alloc(&vm, 5 * PAGE, PAGE);
    for (int i = 0; i < 5; i++) live[(big - BASE) / PAGE + i] = 1;
    uint64_t freed = halo_vm_free(&vm, big + PAGE + 100, PAGE);   /* touches two pages */
    CHECK(freed == 2 * PAGE, "a range that touches two pages frees both (%llu)", (unsigned long long)freed);
    live[(big - BASE) / PAGE + 1] = live[(big - BASE) / PAGE + 2] = 0;
    invariants(&vm, 2 * PAGE + 3 * PAGE, "middle free");
    halo_vm_free(&vm, b, 2 * PAGE); halo_vm_free(&vm, big, 5 * PAGE);
    memset(live, 0, sizeof live);
    invariants(&vm, 0, "all freed");
    CHECK(vm.next == BASE && vm.holes == 0, "everything freed: the area is back to nothing (next 0x%x, %u holes)", vm.next, vm.holes);

    /* exhaustion: fill the region, fail cleanly, free one block, succeed again */
    halo_vm_init(&vm, BASE, LIMIT, PAGE);
    memset(live, 0, sizeof live);
    uint32_t chunk = 64 * 1024 * 1024;
    uint32_t got[16]; int n = 0;
    while (n < 16 && (got[n] = halo_vm_alloc(&vm, chunk, PAGE))) n++;
    CHECK(n == 12, "768 MiB holds twelve 64 MiB blocks (got %d)", n);
    CHECK(halo_vm_alloc(&vm, chunk, PAGE) == 0 && vm.failures > 0, "the thirteenth fails and is counted");
    halo_vm_free(&vm, got[4], chunk);
    uint32_t reused = halo_vm_alloc(&vm, chunk, PAGE);
    CHECK(reused == got[4], "a freed block makes room (got 0x%x)", reused);
    CHECK(halo_vm_alloc(&vm, chunk + PAGE, PAGE) == 0, "a request larger than any hole still fails");

    /* the long-session case that killed the game: allocate and free for ever and never run out */
    halo_vm_init(&vm, BASE, LIMIT, PAGE);
    memset(live, 0, sizeof live);
    for (long i = 0; i < 2000000; i++)
    {
        uint32_t size = 128u * 1024 + (uint32_t)(i % 37) * PAGE;
        uint32_t v = halo_vm_alloc(&vm, size, PAGE);
        if (!v) { CHECK(0, "ran out after %ld allocate/free pairs of ~0.6 MiB (the old allocator ran out after about 1200)", i); break; }
        halo_vm_free(&vm, v, size);
    }
    CHECK(vm.next == BASE && vm.used == 0, "an endless allocate/free loop leaves nothing used");

    /* random stress against the model: many live blocks, random sizes and alignments, random partial frees */
    halo_vm_init(&vm, BASE, LIMIT, PAGE);
    memset(live, 0, sizeof live);
    srand(12345);
    enum { MAXB = 4000 };
    static Block blocks[MAXB];
    int count = 0;
    uint64_t model = 0;
    for (long step = 0; step < 200000; step++)
    {
        int op = rand() % 100;
        if (op < 55 && count < MAXB)
        {
            uint32_t size = 1 + (uint32_t)(rand() % (rand() % 10 == 0 ? 40 * 1024 * 1024 : 600 * 1024));
            uint32_t align = (rand() % 6 == 0) ? (PAGE << (rand() % 4)) : PAGE;
            uint32_t v = halo_vm_alloc(&vm, size, align);
            if (!v) continue;
            uint32_t pages = (uint32_t)(halo_vm_round_up(size, PAGE) / PAGE);
            CHECK(v % align == 0 && v >= BASE && v + pages * PAGE <= LIMIT, "bad alloc 0x%x size %u align 0x%x", v, size, align);
            for (uint32_t p = 0; p < pages; p++)
            {
                if (live[(v - BASE) / PAGE + p]) { CHECK(0, "step %ld: 0x%x overlaps a live page", step, v + p * PAGE); return 1; }
                live[(v - BASE) / PAGE + p] = 1;
            }
            model += pages * PAGE;
            blocks[count].va = v; blocks[count].size = pages * PAGE; count++;
        }
        else if (count)
        {
            int k = rand() % count;
            uint32_t va = blocks[k].va, size = blocks[k].size;
            if (rand() % 4 == 0 && size > 2 * PAGE && count < MAXB)   /* munmap a slice out of the middle: the block becomes two */
            {
                uint32_t first = 1 + (uint32_t)(rand() % ((size / PAGE) - 1));   /* page index of the slice, never the first page */
                uint32_t cut = va + first * PAGE;
                uint32_t offset = (uint32_t)(rand() % (int)PAGE);                /* unaligned start inside that page ... */
                uint64_t got_freed = halo_vm_free(&vm, cut + offset, PAGE - offset ? PAGE - offset : PAGE);   /* ... and ends inside it: touches one page */
                CHECK(got_freed == PAGE, "a range inside one page frees that page (%llu)", (unsigned long long)got_freed);
                live[(cut - BASE) / PAGE] = 0;
                model -= PAGE;
                uint32_t tail_va = cut + PAGE, tail_size = va + size - tail_va;
                blocks[k].size = cut - va;                                        /* the head keeps its slot */
                if (tail_size && count < MAXB) { blocks[count].va = tail_va; blocks[count].size = tail_size; count++; }
            }
            else
            {
                CHECK(halo_vm_free(&vm, va, size) == size, "freeing a whole live block frees exactly its size");
                for (uint32_t p = 0; p < size / PAGE; p++) live[(va - BASE) / PAGE + p] = 0;
                model -= size;
                blocks[k] = blocks[--count];
            }
        }
        if (step % 5000 == 0) invariants(&vm, model, "stress");
        if (failures) return 1;
    }
    invariants(&vm, model, "stress end");
    while (count) { halo_vm_free(&vm, blocks[count - 1].va, blocks[count - 1].size); count--; }
    CHECK(vm.used == 0, "all blocks freed in the end (%llu)", (unsigned long long)vm.used);

    /* many holes: freeing every other page more than the table holds loses space but never corrupts */
    halo_vm_init(&vm, BASE, LIMIT, PAGE);
    uint32_t span = 5000 * PAGE;
    uint32_t arena = halo_vm_alloc(&vm, span, PAGE);
    uint32_t after = halo_vm_alloc(&vm, PAGE, PAGE);   /* keeps the end from shrinking */
    CHECK(arena == BASE && after == BASE + span, "setup");
    for (uint32_t p = 0; p < 5000; p += 2) halo_vm_free(&vm, arena + p * PAGE, PAGE);
    CHECK(vm.holes == HALO_VM_MAX_HOLES && vm.lost == (uint64_t)(2500 - HALO_VM_MAX_HOLES) * PAGE, "full hole table: %u holes, %llu lost", vm.holes, (unsigned long long)vm.lost);
    for (unsigned i = 1; i < vm.holes; i++) if (vm.hole[i - 1].end >= vm.hole[i].start) { CHECK(0, "table unsorted after overflow"); break; }

    /* the real guest memory manager: freed memory is released and comes back zeroed */
    if (!halo_guest_runtime_init()) { printf("SKIP the memory-release check: cannot reserve the arena here\n"); }
    else
    {
        uint32_t va = 0xA0000000u;
        CHECK(halo_guest_commit(va, 3 * PAGE), "commit");
        uint8_t *p = halo_guest_ptr(va, 3 * PAGE);
        memset(p, 0xAB, 3 * PAGE);
        CHECK(halo_guest_decommit(va, 3 * PAGE), "decommit");
        CHECK(halo_guest_commit(va, 3 * PAGE), "recommit");
        int clean = 1;
        for (size_t i = 0; i < 3 * PAGE; i++) if (p[i]) { clean = 0; break; }
        CHECK(clean, "memory handed out again must be zero, as mmap promises (the old decommit only changed the protection and left the old bytes)");
        halo_guest_decommit(va, 3 * PAGE);
    }

    if (!failures) printf("PASS: guest address space: reuse, merging, exhaustion and recovery, an endless allocate/free loop, 200000 random operations against a page model, hole-table overflow, and freed memory comes back zeroed\n");
    return failures ? 1 : 0;
}
