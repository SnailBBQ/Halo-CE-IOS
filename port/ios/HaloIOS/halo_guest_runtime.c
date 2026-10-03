#include "halo_guest_runtime.h"

#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define HALO_GUEST_SPAN    (UINT64_C(1) << 32)
#define HALO_RESERVE_SPAN  (UINT64_C(2) << 32)

static uint8_t *g_guest_base;
static size_t g_page_size;

static int guest_page_range(halo_guest_va_t va, size_t size,
                            uint64_t *lo_out, uint64_t *hi_out)
{
    if (!g_guest_base || !g_page_size || size == 0)
        return 0;

    uint64_t start = (uint64_t)va;
    uint64_t end = start + (uint64_t)size;
    if (end > HALO_GUEST_SPAN || end < start)
        return 0;

    uint64_t mask = (uint64_t)g_page_size - 1;
    uint64_t lo = start & ~mask;
    uint64_t hi = (end + mask) & ~mask;
    if (hi > HALO_GUEST_SPAN)
        hi = HALO_GUEST_SPAN;

    *lo_out = lo;
    *hi_out = hi;
    return 1;
}

int halo_guest_runtime_init(void)
{
    if (g_guest_base)
        return 1;

    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0 || ((size_t)page & ((size_t)page - 1)) != 0)
        return 0;

    /*
     * The execution bridge depends on this property:
     *
     *   low32(host_pointer) == guest_virtual_address
     *
     * Reserve 8 GiB, choose a 4-GiB-aligned 4 GiB sub-window, then discard
     * the prefix/suffix. Pointer truncation performed by arm64_32 guest code
     * therefore recovers the original guest VA exactly.
     */
    void *raw = mmap(NULL, (size_t)HALO_RESERVE_SPAN, PROT_NONE,
                     MAP_PRIVATE | MAP_ANON, -1, 0);
    if (raw == MAP_FAILED)
        return 0;

    uintptr_t raw_address = (uintptr_t)raw;
    uintptr_t aligned =
        (raw_address + (uintptr_t)HALO_GUEST_SPAN - 1) &
        ~((uintptr_t)HALO_GUEST_SPAN - 1);

    uintptr_t raw_end = raw_address + (uintptr_t)HALO_RESERVE_SPAN;
    uintptr_t aligned_end = aligned + (uintptr_t)HALO_GUEST_SPAN;
    if (aligned_end > raw_end)
    {
        munmap(raw, (size_t)HALO_RESERVE_SPAN);
        return 0;
    }

    size_t prefix = (size_t)(aligned - raw_address);
    size_t suffix = (size_t)(raw_end - aligned_end);
    if (prefix)
        munmap((void *)raw_address, prefix);
    if (suffix)
        munmap((void *)aligned_end, suffix);

    g_page_size = (size_t)page;
    g_guest_base = (uint8_t *)aligned;
    return 1;
}

void halo_guest_runtime_shutdown(void)
{
    if (g_guest_base)
        munmap(g_guest_base, (size_t)HALO_GUEST_SPAN);
    g_guest_base = NULL;
    g_page_size = 0;
}

void *halo_guest_ptr(halo_guest_va_t va, size_t size)
{
    uint64_t start = (uint64_t)va;
    uint64_t end = start + (uint64_t)size;
    if (!g_guest_base || end > HALO_GUEST_SPAN || end < start)
        return NULL;
    return g_guest_base + start;
}

int halo_guest_commit(halo_guest_va_t va, size_t size)
{
    uint64_t lo, hi;
    if (!guest_page_range(va, size, &lo, &hi))
        return 0;

    return mprotect(g_guest_base + lo, (size_t)(hi - lo),
                    PROT_READ | PROT_WRITE) == 0;
}

int halo_guest_protect(halo_guest_va_t va, size_t size, int protection)
{
    uint64_t lo, hi;
    if (!guest_page_range(va, size, &lo, &hi))
        return 0;

    return mprotect(g_guest_base + lo, (size_t)(hi - lo), protection) == 0;
}

int halo_guest_decommit(halo_guest_va_t va, size_t size)
{
    uint64_t lo, hi;
    if (!guest_page_range(va, size, &lo, &hi))
        return 0;

    /*
     * munmap: give the memory back. Mapping fresh anonymous pages over the range releases what was in it to the system
     * and makes the next commit of the same range hand out zeroed pages, which is what mmap promises. (This used to be
     * only mprotect(PROT_NONE): the pages stayed resident and kept their contents, so freed memory was never returned
     * and a long session grew until iOS ended the app.)
     */
    return mmap(g_guest_base + lo, (size_t)(hi - lo), PROT_NONE,
                MAP_FIXED | MAP_PRIVATE | MAP_ANON, -1, 0) != MAP_FAILED;
}

int halo_guest_read(halo_guest_va_t va, void *dst, size_t size)
{
    void *src = halo_guest_ptr(va, size);
    if (!src || !dst)
        return 0;
    memcpy(dst, src, size);
    return 1;
}

int halo_guest_write(halo_guest_va_t va, const void *src, size_t size)
{
    void *dst = halo_guest_ptr(va, size);
    if (!dst || !src)
        return 0;
    memcpy(dst, src, size);
    return 1;
}

void *halo_guest_base_address(void)
{
    return g_guest_base;
}

size_t halo_guest_page_size(void)
{
    return g_page_size;
}

uint64_t halo_guest_span(void)
{
    return HALO_GUEST_SPAN;
}

int halo_guest_base_is_4gb_aligned(void)
{
    return g_guest_base &&
           (((uintptr_t)g_guest_base & (uintptr_t)(HALO_GUEST_SPAN - 1)) == 0);
}
