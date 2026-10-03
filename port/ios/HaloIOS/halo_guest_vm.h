#ifndef HALO_GUEST_VM_H
#define HALO_GUEST_VM_H

/*
 * The guest's address space for mmap/munmap, as plain C so tools/tests/test_ios_guest_vm.c can stress it.
 *
 * It used to be a bump pointer: every mmap moved it forward and munmap never moved it back, and munmap
 * only made pages inaccessible, so a long session of allocate/free (the game does it constantly) used up the
 * whole 768 MiB region. mmap then failed, malloc returned NULL, and the game died reading NULL + 0x10.
 *
 * Here freed ranges go on a sorted list of holes, merged with their neighbours, and the next allocation
 * takes the first hole that fits (a range freed at the very end of the used area shrinks it again).
 * Sizes are whole pages. The region is [base, limit); `next` is the first address never handed out.
 */

#include <stdint.h>
#include <string.h>

#define HALO_VM_MAX_HOLES 2048

typedef struct { uint32_t start, end; } HaloVmHole; /* free: [start, end) */

typedef struct
{
    uint32_t base, limit, page;
    uint32_t next;         /* [next, limit) has never been handed out */
    uint32_t peak;         /* the highest `next` has been */
    uint64_t used;         /* bytes handed out and not freed */
    uint64_t lost;         /* freed bytes the hole table had no room to record */
    uint64_t failures;     /* allocations that found no room */
    unsigned holes;
    HaloVmHole hole[HALO_VM_MAX_HOLES]; /* sorted by start, never touching or overlapping */
} HaloVm;

static inline void halo_vm_init(HaloVm *vm, uint32_t base, uint32_t limit, uint32_t page)
{
    memset(vm, 0, sizeof(*vm));
    vm->base = base;
    vm->limit = limit;
    vm->page = page ? page : 4096;
    vm->next = base;
    vm->peak = base;
}

static inline uint64_t halo_vm_round_up(uint64_t value, uint64_t unit)
{
    return (value + unit - 1) & ~(unit - 1);
}

static inline void halo_vm_remove_hole(HaloVm *vm, unsigned index)
{
    memmove(&vm->hole[index], &vm->hole[index + 1], (vm->holes - index - 1) * sizeof(HaloVmHole));
    vm->holes--;
}

/* Puts [start, end) on the list in order, without merging; returns 0 if the table is full. */
static inline int halo_vm_insert_hole(HaloVm *vm, uint32_t start, uint32_t end)
{
    unsigned at = 0;

    if (end <= start)
        return 1;
    if (vm->holes >= HALO_VM_MAX_HOLES)
        return 0;
    while (at < vm->holes && vm->hole[at].start < start)
        at++;
    memmove(&vm->hole[at + 1], &vm->hole[at], (vm->holes - at) * sizeof(HaloVmHole));
    vm->hole[at].start = start;
    vm->hole[at].end = end;
    vm->holes++;
    return 1;
}

/* A range of `size` bytes (rounded up to pages) aligned to `alignment` (a power of two, at least a page), or 0. */
static inline uint32_t halo_vm_alloc(HaloVm *vm, uint32_t size, uint32_t alignment)
{
    uint64_t need, a;

    if (!size)
        return 0;
    need = halo_vm_round_up(size, vm->page);
    a = alignment < vm->page || (alignment & (alignment - 1)) ? vm->page : alignment;
    for (unsigned i = 0; i < vm->holes; i++)
    {
        uint64_t start = halo_vm_round_up(vm->hole[i].start, a);

        if (start + need <= vm->hole[i].end)
        {
            uint32_t hole_start = vm->hole[i].start, hole_end = vm->hole[i].end;

            halo_vm_remove_hole(vm, i);
            /* what is left of the hole on either side goes back; if the table is full the remainder is lost */
            if (!halo_vm_insert_hole(vm, hole_start, (uint32_t)start))
                vm->lost += start - hole_start;
            if (!halo_vm_insert_hole(vm, (uint32_t)(start + need), hole_end))
                vm->lost += hole_end - (start + need);
            vm->used += need;
            return (uint32_t)start;
        }
    }
    a = halo_vm_round_up(vm->next, a);
    if (a + need > vm->limit)
    {
        vm->failures++;
        return 0;
    }
    if (a > vm->next && !halo_vm_insert_hole(vm, vm->next, (uint32_t)a))
        vm->lost += a - vm->next;
    vm->next = (uint32_t)(a + need);
    if (vm->next > vm->peak)
        vm->peak = vm->next;
    vm->used += need;
    return (uint32_t)a;
}

/* munmap(va, size): every page the range touches is free again. Only pages inside the used area count; a range that
 * is already free (or never was ours) changes nothing. Returns the bytes newly freed. */
static inline uint64_t halo_vm_free(HaloVm *vm, uint32_t va, uint32_t size)
{
    uint64_t lo = va & ~(uint64_t)(vm->page - 1);
    uint64_t hi = halo_vm_round_up((uint64_t)va + size, vm->page);
    uint64_t freed, overlap = 0;
    unsigned i = 0;

    if (!size)
        return 0;
    if (lo < vm->base) lo = vm->base;
    if (hi > vm->next) hi = vm->next;
    if (hi <= lo)
        return 0;
    freed = hi - lo;
    /* absorb every hole that overlaps or touches [lo, hi) */
    while (i < vm->holes)
    {
        const HaloVmHole *h = &vm->hole[i];

        if (h->end < lo || h->start > hi)
        {
            i++;
            continue;
        }
        {
            uint64_t o_lo = h->start > lo ? h->start : lo, o_hi = h->end < hi ? h->end : hi;
            if (o_hi > o_lo)
                overlap += o_hi - o_lo;
        }
        if (h->start < lo) lo = h->start;
        if (h->end > hi) hi = h->end;
        halo_vm_remove_hole(vm, i);
    }
    freed -= overlap;
    if (hi == vm->next)
        vm->next = (uint32_t)lo;                       /* the end of the used area is free again */
    else if (!halo_vm_insert_hole(vm, (uint32_t)lo, (uint32_t)hi))
        vm->lost += hi - lo;
    vm->used = vm->used > freed ? vm->used - freed : 0;
    return freed;
}

static inline uint64_t halo_vm_hole_bytes(const HaloVm *vm)
{
    uint64_t total = 0;

    for (unsigned i = 0; i < vm->holes; i++)
        total += vm->hole[i].end - vm->hole[i].start;
    return total;
}

static inline uint64_t halo_vm_largest_hole(const HaloVm *vm)
{
    uint64_t best = 0;

    for (unsigned i = 0; i < vm->holes; i++)
        if (vm->hole[i].end - vm->hole[i].start > best)
            best = vm->hole[i].end - vm->hole[i].start;
    return best;
}

#endif
