#include "halo_ios_probe.h"

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define HALO_GUEST_SPAN            (UINT64_C(1) << 32)
#define HALO_XBOX_MEMORY_BASE       UINT32_C(0x80000000)
#define HALO_XBOX_MEMORY_SIZE       UINT32_C(0x08000000)
#define HALO_GUEST_IMAGE_BASE       UINT32_C(0x88000000)
#define HALO_GUEST_IMAGE_SIZE       UINT32_C(0x02000000)
#define HALO_STACK_TEST_BASE        UINT32_C(0x00100000)

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

static int commit_guest_page(halo_guest_va_t va, void (^line)(const char *))
{
    const uint64_t mask = (uint64_t)g_page_size - 1;
    const uint64_t aligned = (uint64_t)va & ~mask;
    void *host = g_guest_base + aligned;
    if (mprotect(host, g_page_size, PROT_READ | PROT_WRITE) != 0)
    {
        say(line, "FAIL commit guest 0x%08x -> host %p: errno=%d (%s)",
            va, host, errno, strerror(errno));
        return 0;
    }
    say(line, "PASS commit guest 0x%08x -> host %p", va, host);
    return 1;
}

static int rw32(halo_guest_va_t va, uint32_t value, void (^line)(const char *))
{
    uint32_t *p = (uint32_t *)guest_ptr(va, sizeof(uint32_t));
    if (!p)
    {
        say(line, "FAIL guest_ptr(0x%08x)", va);
        return 0;
    }
    *p = value;
    const int ok = *p == value;
    say(line, "%s guest 0x%08x -> host %p value=0x%08x",
        ok ? "PASS" : "FAIL", va, p, *p);
    return ok;
}

static void survey_fallback_sizes(void (^line)(const char *))
{
    static const uint64_t sizes[] = {
        UINT64_C(0x80000000), /* 2 GiB */
        UINT64_C(0x40000000), /* 1 GiB */
        UINT64_C(0x20000000), /* 512 MiB */
        UINT64_C(0x10000000)  /* 256 MiB */
    };

    line("Fallback reservation survey:");
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i)
    {
        const uint64_t size = sizes[i];
        void *p = mmap(NULL, (size_t)size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (p == MAP_FAILED)
            say(line, "  FAIL %4llu MiB: errno=%d (%s)",
                (unsigned long long)(size >> 20), errno, strerror(errno));
        else
        {
            say(line, "  PASS %4llu MiB at %p", (unsigned long long)(size >> 20), p);
            munmap(p, (size_t)size);
        }
    }
}

void halo_ios_run_m1_probe(void (^line)(const char *text))
{
    int pass = 1;
    const long page = sysconf(_SC_PAGESIZE);
    g_page_size = page > 0 ? (size_t)page : 0;

    say(line, "host pointer: %zu-bit", sizeof(void *) * 8);
    say(line, "guest address model: original 32-bit VA");
    say(line, "page size: %zu", g_page_size);
    say(line, "guest span requested: 0x%llx bytes (4 GiB)",
        (unsigned long long)HALO_GUEST_SPAN);

    if (!g_page_size || (g_page_size & (g_page_size - 1)) != 0)
    {
        line("M1.0 RESULT: FAIL - unsupported host page size.");
        return;
    }

    line("");
    line("[1] Reserve complete 32-bit guest address space:");
    errno = 0;
    void *reservation = mmap(NULL, (size_t)HALO_GUEST_SPAN, PROT_NONE,
                             MAP_PRIVATE | MAP_ANON, -1, 0);
    if (reservation == MAP_FAILED)
    {
        g_guest_base = NULL;
        say(line, "FAIL 4 GiB PROT_NONE reservation: errno=%d (%s)", errno, strerror(errno));
        survey_fallback_sizes(line);
        line("");
        line("M1.0 RESULT: BLOCKED - this installation does not currently provide a full 4 GiB guest reservation.");
        line("NEXT: verify effective Extended Virtual Addressing entitlement/signing before changing the address model.");
        return;
    }

    g_guest_base = (uint8_t *)reservation;
    say(line, "PASS guest_base=%p .. %p", g_guest_base, g_guest_base + HALO_GUEST_SPAN);
    say(line, "PASS guest 0x80000000 -> host %p", guest_ptr(HALO_XBOX_MEMORY_BASE, 1));
    say(line, "PASS guest 0x88000000 -> host %p", guest_ptr(HALO_GUEST_IMAGE_BASE, 1));

    line("");
    line("[2] Sparse commit at original Halo/Xbox guest addresses:");
    pass &= commit_guest_page(HALO_STACK_TEST_BASE, line);
    pass &= commit_guest_page(HALO_XBOX_MEMORY_BASE, line);
    pass &= commit_guest_page(HALO_XBOX_MEMORY_BASE + HALO_XBOX_MEMORY_SIZE - (uint32_t)g_page_size, line);
    pass &= commit_guest_page(HALO_GUEST_IMAGE_BASE, line);
    pass &= commit_guest_page(HALO_GUEST_IMAGE_BASE + HALO_GUEST_IMAGE_SIZE - (uint32_t)g_page_size, line);

    line("");
    line("[3] Original-address read/write semantics:");
    if (pass)
    {
        pass &= rw32(HALO_STACK_TEST_BASE, UINT32_C(0x5354414b), line); /* STAK */
        pass &= rw32(HALO_XBOX_MEMORY_BASE, UINT32_C(0x58424f58), line); /* XBOX */
        pass &= rw32(HALO_XBOX_MEMORY_BASE + HALO_XBOX_MEMORY_SIZE - 4, UINT32_C(0x87ffffff), line);
        pass &= rw32(HALO_GUEST_IMAGE_BASE, UINT32_C(0x48414c4f), line); /* HALO */
        pass &= rw32(HALO_GUEST_IMAGE_BASE + HALO_GUEST_IMAGE_SIZE - 4, UINT32_C(0x89ffffff), line);
    }

    line("");
    line("[4] Guest values remain 32-bit; host addresses stay private:");
    {
        const halo_guest_va_t guest = HALO_GUEST_IMAGE_BASE + UINT32_C(0x00123440);
        void *host = guest_ptr(guest, 4);
        const uintptr_t expected = (uintptr_t)g_guest_base + (uint64_t)guest;
        const int ok = host && (uintptr_t)host == expected && (uint64_t)guest == UINT64_C(0x88123440);
        say(line, "%s guest=0x%08x base+guest=%p", ok ? "PASS" : "FAIL", guest, host);
        pass &= ok;
    }

    line("");
    line("[5] Protection model:");
    line("PASS reservation began PROT_NONE; only sampled guest pages were committed RW.");
    line("INFO translated/AOT game code must access memory as guest_base + guestVA.");
    line("INFO native host/code pointers must never be stored in guest-visible 32-bit state.");

    line("");
    if (pass)
    {
        line("M1.0 RESULT: PASS - Project Reach-style original-address guest memory works on this device.");
        line("NEXT: compile a real Halo Universal function slice against guest_base + guestVA accesses.");
    }
    else
    {
        line("M1.0 RESULT: FAIL - 4 GiB reservation succeeded, but sparse guest memory semantics failed.");
    }

    munmap(g_guest_base, (size_t)HALO_GUEST_SPAN);
    g_guest_base = NULL;
}
