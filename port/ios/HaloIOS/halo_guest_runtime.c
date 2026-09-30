#include "halo_guest_runtime.h"

#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define HALO_GUEST_SPAN (UINT64_C(1) << 32)

static uint8_t *g_guest_base;
static size_t g_page_size;

int halo_guest_runtime_init(void)
{
    if (g_guest_base)
        return 1;

    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0 || ((size_t)page & ((size_t)page - 1)) != 0)
        return 0;

    void *reservation = mmap(NULL, (size_t)HALO_GUEST_SPAN, PROT_NONE,
                             MAP_PRIVATE | MAP_ANON, -1, 0);
    if (reservation == MAP_FAILED)
        return 0;

    g_page_size = (size_t)page;
    g_guest_base = (uint8_t *)reservation;
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

    return mprotect(g_guest_base + lo, (size_t)(hi - lo),
                    PROT_READ | PROT_WRITE) == 0;
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
