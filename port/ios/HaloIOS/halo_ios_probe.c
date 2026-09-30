#include "halo_ios_probe.h"
#include "halo_m11_real_slice.h"

#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define HALO_GUEST_SPAN        (UINT64_C(1) << 32)
#define HALO_XBOX_MEMORY_BASE  UINT32_C(0x80000000)
#define HALO_SLICE_A_VA        UINT32_C(0x80010000)
#define HALO_SLICE_B_VA        UINT32_C(0x80010010)
#define HALO_SLICE_RESULT_VA   UINT32_C(0x80010020)

typedef uint32_t halo_guest_va_t;

static uint8_t *g_guest_base;
static size_t g_page_size;

static void say(void (^line)(const char *), const char *fmt, ...)
{
    char buf[640];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    line(buf);
}

static void *guest_ptr(halo_guest_va_t va, size_t size)
{
    const uint64_t start = (uint64_t)va;
    const uint64_t end = start + (uint64_t)size;
    if (!g_guest_base || end > HALO_GUEST_SPAN || end < start)
        return NULL;
    return g_guest_base + start;
}

static int commit_guest_range(halo_guest_va_t va, size_t size, void (^line)(const char *))
{
    const uint64_t mask = (uint64_t)g_page_size - 1;
    const uint64_t lo = (uint64_t)va & ~mask;
    const uint64_t hi = ((uint64_t)va + size + mask) & ~mask;
    const uint64_t length = hi - lo;
    void *host = g_guest_base + lo;

    if (mprotect(host, (size_t)length, PROT_READ | PROT_WRITE) != 0)
    {
        say(line, "FAIL commit guest 0x%08x..0x%08llx: errno=%d (%s)",
            va, (unsigned long long)((uint64_t)va + size), errno, strerror(errno));
        return 0;
    }

    say(line, "PASS commit guest 0x%08x..0x%08llx -> host %p",
        va, (unsigned long long)((uint64_t)va + size), host);
    return 1;
}

static int close_enough(float a, float b)
{
    return fabsf(a - b) < 0.00001f;
}

void halo_ios_run_m11_probe(void (^line)(const char *text))
{
    int pass = 1;
    const long page = sysconf(_SC_PAGESIZE);
    g_page_size = page > 0 ? (size_t)page : 0;

    say(line, "host pointer: %zu-bit", sizeof(void *) * 8);
    say(line, "guest address model: original 32-bit VA");
    say(line, "page size: %zu", g_page_size);
    line("real slice: source/math/real_math.c :: vectors_interpolate()");

    if (!g_page_size || (g_page_size & (g_page_size - 1)) != 0)
    {
        line("M1.1 RESULT: FAIL - unsupported host page size.");
        return;
    }

    line("");
    line("[1] Reserve complete 32-bit guest address space:");
    void *reservation = mmap(NULL, (size_t)HALO_GUEST_SPAN, PROT_NONE,
                             MAP_PRIVATE | MAP_ANON, -1, 0);
    if (reservation == MAP_FAILED)
    {
        say(line, "FAIL 4 GiB reservation: errno=%d (%s)", errno, strerror(errno));
        line("M1.1 RESULT: BLOCKED - M1.0 memory model regressed.");
        return;
    }
    g_guest_base = (uint8_t *)reservation;
    say(line, "PASS guest_base=%p .. %p", g_guest_base, g_guest_base + HALO_GUEST_SPAN);

    line("");
    line("[2] Commit real-slice input/output pages at original Xbox VAs:");
    pass &= commit_guest_range(HALO_SLICE_A_VA, 0x40, line);

    halo_real_vector3d *a = (halo_real_vector3d *)guest_ptr(HALO_SLICE_A_VA, sizeof(*a));
    halo_real_vector3d *b = (halo_real_vector3d *)guest_ptr(HALO_SLICE_B_VA, sizeof(*b));
    halo_real_vector3d *result = (halo_real_vector3d *)guest_ptr(HALO_SLICE_RESULT_VA, sizeof(*result));

    if (!a || !b || !result)
    {
        line("FAIL guest pointer translation for function-slice buffers.");
        pass = 0;
    }

    if (pass)
    {
        a->i = 1.0f; a->j = 2.0f; a->k = 3.0f;
        b->i = 9.0f; b->j = 6.0f; b->k = -1.0f;
        memset(result, 0, sizeof(*result));

        say(line, "PASS a      guest=0x%08x host=%p = {%g,%g,%g}",
            HALO_SLICE_A_VA, a, a->i, a->j, a->k);
        say(line, "PASS b      guest=0x%08x host=%p = {%g,%g,%g}",
            HALO_SLICE_B_VA, b, b->i, b->j, b->k);
        say(line, "PASS result guest=0x%08x host=%p",
            HALO_SLICE_RESULT_VA, result);
    }

    line("");
    line("[3] Execute recovered Halo Universal function natively:");
    if (pass)
    {
        halo_m11_vectors_interpolate(a, b, 0.25f, result);

        const int ok =
            close_enough(result->i, 3.0f) &&
            close_enough(result->j, 3.0f) &&
            close_enough(result->k, 2.0f);

        say(line, "%s vectors_interpolate(t=0.25) -> {%g,%g,%g}",
            ok ? "PASS" : "FAIL", result->i, result->j, result->k);
        pass &= ok;
    }

    line("");
    line("[4] Guest-visible state remains original-address data:");
    if (pass)
    {
        const halo_guest_va_t guest_result = HALO_SLICE_RESULT_VA;
        const uintptr_t expected_host = (uintptr_t)g_guest_base + (uint64_t)guest_result;
        const int ok = (uintptr_t)result == expected_host;
        say(line, "%s guest result VA=0x%08x -> base+VA=%p",
            ok ? "PASS" : "FAIL", guest_result, result);
        pass &= ok;
    }

    line("");
    line("[5] Source-slice milestone:");
    line("PASS real recovered Halo function body is compiled into the native iOS executable.");
    line("PASS function inputs/results live inside the 4 GiB original-address guest reservation.");
    line("INFO M1.1 still passes translated host pointers into this isolated C slice.");
    line("INFO next step is rewriting/generalizing real Halo memory accesses so guest32 values can flow through larger call chains.");

    line("");
    if (pass)
    {
        line("M1.1 RESULT: PASS - real Halo Universal function executed against original-address guest-backed data.");
        line("NEXT: M1.2 multi-function slice + reusable guest-memory access layer.");
    }
    else
    {
        line("M1.1 RESULT: FAIL - real function slice or guest-backed data verification failed.");
    }

    munmap(g_guest_base, (size_t)HALO_GUEST_SPAN);
    g_guest_base = NULL;
}
