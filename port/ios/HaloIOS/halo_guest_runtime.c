#include "halo_guest_runtime.h"

#include <stdint.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#if defined(HALO_ALIGNED_ARENA_TEST) && HALO_ALIGNED_ARENA_TEST
#include <mach/mach.h>
#include <mach/vm_map.h>
#endif
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
#include "halo_va_plan.h"
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
#endif

#define HALO_GUEST_SPAN    (UINT64_C(1) << 32)
#define HALO_RESERVE_SPAN  (UINT64_C(2) << 32)

static uint8_t *g_guest_base;
static size_t g_page_size;
static char g_init_error[256];
const char *halo_guest_runtime_last_error(void) { return g_init_error; }


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

#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
/* Non-Jailbreak Version only. See halo_va_plan.h. */
static char g_nonjb_report[1536];
const char *halo_guest_runtime_nonjb_report(void) { return g_nonjb_report; }

static int nonjb_reserve(void *context, uint64_t hint, uint64_t size, uint64_t *base, int *error)
{
    void *request = hint ? (void *)(uintptr_t)hint : NULL;
    void *placed = mmap(request, (size_t)size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    (void)context;
    if (placed == MAP_FAILED) { *error = errno; return 0; }
    *base = (uint64_t)(uintptr_t)placed;   /* halo_va_reserve_at refuses a different address than a fixed request */
    return 1;
}

static void nonjb_release(void *context, uint64_t base, uint64_t size)
{
    (void)context;
    munmap((void *)(uintptr_t)base, (size_t)size);
}

/* Whether this process may make memory executable. Nothing is executed: pages are only mapped and re-protected, then released. */
void halo_guest_runtime_exec_report(char *out, size_t size)
{
    HaloJitProbe probe;
    unsigned int flags = 0;
    const size_t probe_size = 16384;
    void *writable, *direct;
    memset(&probe, 0, sizeof(probe));
    probe.csops_ok = csops(getpid(), 0 /* CS_OPS_STATUS */, &flags, sizeof(flags)) == 0;
    probe.debugged = probe.csops_ok && (flags & 0x10000000u) != 0;   /* CS_DEBUGGED */
    writable = mmap(NULL, probe_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (writable == MAP_FAILED)
        probe.mprotect_error = errno;
    else
    {
        if (mprotect(writable, probe_size, PROT_READ | PROT_EXEC) != 0)
            probe.mprotect_error = errno;
        munmap(writable, probe_size);
    }
    direct = mmap(NULL, probe_size, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (direct == MAP_FAILED)
        probe.direct_error = errno;
    else
        munmap(direct, probe_size);
#ifdef MAP_JIT
    {
        void *jit = mmap(NULL, probe_size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
        if (jit == MAP_FAILED)
            probe.map_jit_error = errno;
        else
            munmap(jit, probe_size);
    }
#else
    probe.map_jit_error = -1;
#endif
    halo_jit_describe(&probe, out, size);
}
#endif

int halo_guest_runtime_init(void)
{
    g_init_error[0]=0;
    if (g_guest_base)
        return 1;

    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0 || ((size_t)page & ((size_t)page - 1)) != 0) {
        snprintf(g_init_error,sizeof(g_init_error),"invalid system page size: %ld",page);
        return 0;
    }

#if defined(HALO_ALIGNED_ARENA_TEST) && HALO_ALIGNED_ARENA_TEST
    /* Test app only: let Mach choose an unoccupied aligned range. ANYWHERE
     * never overwrites an existing mapping. No guest addressing rule changes. */
    _Static_assert(sizeof(vm_address_t)==8 && sizeof(vm_size_t)==8, "aligned arena requires 64-bit Mach address types");
    vm_address_t aligned=0;
    kern_return_t result=vm_map(mach_task_self(), &aligned,
        (vm_size_t)HALO_GUEST_SPAN, (vm_offset_t)(HALO_GUEST_SPAN-1),
        VM_FLAGS_ANYWHERE, MEMORY_OBJECT_NULL, 0, FALSE,
        VM_PROT_NONE, VM_PROT_ALL, VM_INHERIT_NONE);
    if (result != KERN_SUCCESS) {
        snprintf(g_init_error,sizeof(g_init_error),
            "arena reservation: size=0x100000000 alignment=0x100000000 initial=NONE max=ALL ANYWHERE; Mach error=%d (%s)",result,mach_error_string(result));
        return 0;
    }
    if (!aligned || (aligned & (HALO_GUEST_SPAN-1)) || aligned > UINTPTR_MAX-HALO_GUEST_SPAN) {
        vm_deallocate(mach_task_self(),aligned,HALO_GUEST_SPAN);
        snprintf(g_init_error,sizeof(g_init_error),"Mach returned an invalid aligned guest range");
        return 0;
    }
#else
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
    if(raw==MAP_FAILED) {
        int error=errno; /* Preserve the original error before any logging. */
        snprintf(g_init_error,sizeof(g_init_error),"8 GiB virtual reservation failed: mmap errno=%d (%s)",error,strerror(error));
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
        {
            /* Non-Jailbreak Version only, and only because the production reservation was just refused: survey what this
             * install allows, then try one fixed 4 GiB-aligned window instead of the 8 GiB one. That window is exactly what
             * the production path would have kept, so nothing after this point differs. */
            HaloVaReserver reserver = { NULL, nonjb_reserve, nonjb_release };
            HaloVaProbe probe;
            uint64_t fixed = 0;
            int fixed_error = 0;
            unsigned tried = 0;
            size_t used;
            halo_va_probe_run(&reserver, &probe);
            halo_va_probe_format(&probe, g_nonjb_report, sizeof(g_nonjb_report));
            used = strlen(g_nonjb_report);
            if (halo_va_try_fixed_arena(&reserver, &fixed, &fixed_error, &tried))
            {
                halo_va_text(g_nonjb_report, sizeof(g_nonjb_report), &used,
                    "Fallback: the 8 GiB reservation failed (errno %d), but a fixed 4 GiB window at 0x%llx was reserved after %u tries.\n",
                    error, (unsigned long long)fixed, tried);
                g_init_error[0] = 0;
                g_page_size = (size_t)page;
                g_guest_base = (uint8_t *)(uintptr_t)fixed;
                return 1;
            }
            halo_va_text(g_nonjb_report, sizeof(g_nonjb_report), &used,
                "Fallback: no fixed 4 GiB window could be reserved either (%u tried, first error %d).\n", tried, fixed_error);
        }
#endif
        return 0;
    }

    uintptr_t raw_address = (uintptr_t)raw;
    uintptr_t aligned =
        (raw_address + (uintptr_t)HALO_GUEST_SPAN - 1) &
        ~((uintptr_t)HALO_GUEST_SPAN - 1);

    uintptr_t raw_end = raw_address + (uintptr_t)HALO_RESERVE_SPAN;
    uintptr_t aligned_end = aligned + (uintptr_t)HALO_GUEST_SPAN;
    if (aligned_end > raw_end)
    {
        snprintf(g_init_error,sizeof(g_init_error),"aligned 4 GiB window did not fit reserved virtual range");
        munmap(raw, (size_t)HALO_RESERVE_SPAN);
        return 0;
    }

    size_t prefix = (size_t)(aligned - raw_address);
    size_t suffix = (size_t)(raw_end - aligned_end);
    if (prefix)
        munmap((void *)raw_address, prefix);
    if (suffix)
        munmap((void *)aligned_end, suffix);
#endif

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
