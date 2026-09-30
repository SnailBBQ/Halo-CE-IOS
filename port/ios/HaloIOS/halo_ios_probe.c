#include "halo_ios_probe.h"

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define HALO_GUEST_WINDOW_BASE 0x80000000u
#define HALO_GUEST_WINDOW_SIZE 0x08000000u
#define HALO_GUEST_IMAGE_BASE  0x88000000u
#define HALO_GUEST_IMAGE_SIZE  0x02000000u
#define HALO_GUEST_SPAN        (HALO_GUEST_WINDOW_SIZE + HALO_GUEST_IMAGE_SIZE)

typedef uint32_t guest_ptr32;

static uint8_t *g_arena;
static size_t g_arena_size;

static void say(void (^line)(const char *), const char *fmt, ...)
{
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    line(buf);
}

static void *guest_to_host(guest_ptr32 guest, size_t size)
{
    const uint64_t base = HALO_GUEST_WINDOW_BASE;
    const uint64_t end = base + g_arena_size;
    const uint64_t address = guest;

    if (!g_arena || !guest || address < base || address > end)
        return NULL;
    if (size > end - address)
        return NULL;
    return g_arena + (size_t)(address - base);
}

static uint32_t abi_scalar_probe(uint32_t a, uint32_t b, uint64_t wide)
{
    return (a ^ b) + (uint32_t)wide + (uint32_t)(wide >> 32);
}

/*
AArch64 machine code for:

    uint32_t guest_add1(uint32_t value) { return value + 1; }

    add w0, w0, #1    0x11000400
    ret                0xd65f03c0

The Android guest is also AArch64 machine code. This deliberately tiny blob
lets M0.5 test the separate iOS question: may a normal app execute AArch64
code copied into anonymous memory at runtime?
*/
static const uint8_t k_guest_add1_code[] = {
    0x00, 0x04, 0x00, 0x11,
    0xc0, 0x03, 0x5f, 0xd6
};

static int prepare_exec_page(void **page_out, void (^line)(const char *), int verbose)
{
    const long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0)
        return 0;

    void *page = mmap(NULL, (size_t)page_size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANON, -1, 0);
    if (page == MAP_FAILED)
    {
        if (verbose)
            say(line, "FAIL mmap RW executable-test page: errno=%d (%s)", errno, strerror(errno));
        return 0;
    }

    memcpy(page, k_guest_add1_code, sizeof(k_guest_add1_code));
    __builtin___clear_cache((char *)page, (char *)page + sizeof(k_guest_add1_code));

    if (mprotect(page, (size_t)page_size, PROT_READ | PROT_EXEC) != 0)
    {
        if (verbose)
            say(line, "BLOCKED RW->RX mprotect: errno=%d (%s)", errno, strerror(errno));
        munmap(page, (size_t)page_size);
        return 0;
    }

    if (verbose)
        say(line, "PASS RW->RX mprotect at %p (execution not attempted automatically)", page);
    *page_out = page;
    return 1;
}

void halo_ios_run_m0_probe(void (^line)(const char *text))
{
    int pass = 1;
    const long page = sysconf(_SC_PAGESIZE);

    say(line, "host pointer: %zu-bit", sizeof(void *) * 8);
    say(line, "guest pointer/long model: 32-bit ILP32");
    say(line, "page size: %ld", page);

    line("");
    line("[1] Relocated guest backing:");
    g_arena_size = HALO_GUEST_SPAN;
    g_arena = mmap(NULL, g_arena_size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANON, -1, 0);
    if (g_arena == MAP_FAILED)
    {
        g_arena = NULL;
        say(line, "FAIL 160 MiB arena: errno=%d (%s)", errno, strerror(errno));
        line("M0.5 RESULT: FAIL - guest backing unavailable.");
        return;
    }
    say(line, "PASS 160 MiB host=%p..%p", g_arena, g_arena + g_arena_size);

    line("");
    line("[2] Android-style scalar ABI boundary:");
    {
        uint32_t (*fn)(uint32_t, uint32_t, uint64_t) = abi_scalar_probe;
        const uint32_t result = fn(0x11223344u, 0x55667788u, UINT64_C(0x0102030405060708));
        const uint32_t expected = (0x11223344u ^ 0x55667788u) + 0x05060708u + 0x01020304u;
        const int ok = result == expected;
        say(line, "%s 32/32/64-bit register call result=0x%08x", ok ? "PASS" : "FAIL", result);
        pass &= ok;
    }

    line("");
    line("[3] Guest32 pointer boundary still translates correctly:");
    {
        const guest_ptr32 guest = HALO_GUEST_IMAGE_BASE + 0x12340u;
        uint32_t *host = (uint32_t *)guest_to_host(guest, sizeof(uint32_t));
        const int ok = host != NULL;
        if (host)
        {
            *host = 0x48414c4fu; /* HALO */
            say(line, "%s guest 0x%08x -> host %p value=0x%08x",
                *host == 0x48414c4fu ? "PASS" : "FAIL", guest, host, *host);
            pass &= (*host == 0x48414c4fu);
        }
        else
        {
            line("FAIL guest pointer translation");
            pass = 0;
        }
    }

    line("");
    line("[4] Runtime AArch64 code-page policy:");
    {
        void *page_ptr = NULL;
        const int rx_ok = prepare_exec_page(&page_ptr, line, 1);
        if (rx_ok)
        {
            munmap(page_ptr, (size_t)page);
            line("READY dynamic execution gate is available for the manual test below.");
        }
        else
        {
            line("BLOCKER iOS refused anonymous RW->RX memory for an Android-style loaded guest image.");
        }
    }

#ifdef MAP_JIT
    line("");
    line("[5] MAP_JIT availability (allocation only):");
    {
        void *jit = mmap(NULL, (size_t)page, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
        if (jit == MAP_FAILED)
            say(line, "INFO MAP_JIT unavailable: errno=%d (%s)", errno, strerror(errno));
        else
        {
            say(line, "PASS MAP_JIT allocation at %p; entitlement/write-protect rules still apply", jit);
            munmap(jit, (size_t)page);
        }
    }
#endif

    line("");
    if (pass)
    {
        line("M0.5 SAFE RESULT: PASS - ABI + translated data path remain valid.");
        line("NEXT: tap 'Run Guest Code Test' to test executing a copied AArch64 guest blob.");
        line("If iOS terminates the app, reopen Halo iOS; the app will report the interrupted test.");
    }
    else
    {
        line("M0.5 SAFE RESULT: FAIL - fix the reported prerequisite before guest execution.");
    }
}

int halo_ios_run_m05_dynamic_probe(void (^line)(const char *text))
{
    void *page = NULL;
    const long page_size = sysconf(_SC_PAGESIZE);

    line("[MANUAL] Preparing copied AArch64 guest code...");
    if (!prepare_exec_page(&page, line, 1))
    {
        line("M0.5 DYNAMIC RESULT: BLOCKED - iOS did not permit an executable anonymous page.");
        return 0;
    }

    line("[MANUAL] Calling copied guest_add1(41)...");
    __builtin___clear_cache((char *)page, (char *)page + sizeof(k_guest_add1_code));

    typedef uint32_t (*guest_add1_fn)(uint32_t);
    guest_add1_fn function = (guest_add1_fn)page;
    const uint32_t result = function(41u);

    munmap(page, (size_t)page_size);
    if (result == 42u)
    {
        line("PASS copied AArch64 guest code returned 42.");
        line("M0.5 DYNAMIC RESULT: PASS - runtime-loaded AArch64 code executed successfully.");
        return 1;
    }

    say(line, "FAIL copied guest code returned %u instead of 42", result);
    line("M0.5 DYNAMIC RESULT: FAIL - executable page returned but ABI/code result was wrong.");
    return 0;
}
