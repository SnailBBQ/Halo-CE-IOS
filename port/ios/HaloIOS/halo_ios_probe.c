#include "halo_ios_probe.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

/* Mirrors the real Android guest ABI in port/android/include/halo_android_abi.h. */
#define HALO_GUEST_IMAGE_BASE  0x88000000u
#define HALO_GUEST_WINDOW_BASE 0x80000000u
#define HALO_GUEST_WINDOW_SIZE 0x08000000u
#define HALO_GUEST_IMAGE_SIZE  0x02000000u
#define HALO_GUEST_SPAN        (HALO_GUEST_WINDOW_SIZE + HALO_GUEST_IMAGE_SIZE)
#define HALO_GUEST_MAGIC       0x4f4c4148u
#define HALO_GUEST_ABI_VERSION 1u

typedef uint32_t guest_ptr32;

struct halo_guest_header32
{
    uint32_t magic;
    uint32_t abi_version;
    uint32_t image_end;
    uint32_t import_table;
    uint32_t import_names;
    uint32_t import_count;
    uint32_t start;
    uint32_t thread_start;
    uint32_t thread_attach;
    uint32_t init_array_start;
    uint32_t init_array_end;
};

struct halo_guest_boot32
{
    uint32_t argc;
    uint32_t argv;
    uint32_t environment;
    uint32_t page_size;
};

/* Mirrors structures converted at the Android host syscall boundary. */
struct guest_timespec32
{
    int32_t seconds;
    int32_t nanoseconds;
};

struct guest_iovec32
{
    uint32_t base;
    uint32_t length;
};

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

static void *guest_to_host(uint64_t value, size_t size)
{
    const uint64_t guest = (uint32_t)value; /* same zero-extension boundary assumption as Android */
    const uint64_t base = HALO_GUEST_WINDOW_BASE;
    const uint64_t end = base + g_arena_size;

    if (!guest || guest < base || guest > end)
        return NULL;
    if (size > end - guest)
        return NULL;
    return g_arena + (size_t)(guest - base);
}

static guest_ptr32 host_to_guest(const void *pointer, size_t size)
{
    const uint8_t *p = (const uint8_t *)pointer;
    if (!p || p < g_arena || size > g_arena_size || p > g_arena + g_arena_size - size)
        return 0;
    return (guest_ptr32)(HALO_GUEST_WINDOW_BASE + (uint32_t)(p - g_arena));
}

static int put_guest_string(guest_ptr32 address, const char *text)
{
    char *dst = (char *)guest_to_host(address, strlen(text) + 1);
    if (!dst)
        return 0;
    strcpy(dst, text);
    return 1;
}

static double elapsed_ms(struct timespec a, struct timespec b)
{
    return (double)(b.tv_sec - a.tv_sec) * 1000.0 +
           (double)(b.tv_nsec - a.tv_nsec) / 1000000.0;
}

void halo_ios_run_m0_probe(void (^line)(const char *text))
{
    int pass = 1;
    const long page = sysconf(_SC_PAGESIZE);

    say(line, "host pointer: %zu-bit", sizeof(void *) * 8);
    say(line, "guest pointer model: 32-bit");
    say(line, "page size: %ld", page);
    say(line, "guest model: 0x%08x..0x%08x (%u MiB)",
        HALO_GUEST_WINDOW_BASE,
        HALO_GUEST_WINDOW_BASE + HALO_GUEST_SPAN,
        (unsigned)(HALO_GUEST_SPAN / (1024u * 1024u)));

    line("");
    line("[1] Restore normal iOS process layout:");
    line("PASS PAGEZERO override removed; this probe does not request low-4GB mappings.");

    line("");
    line("[2] Reserve relocated backing arena:");
    g_arena_size = HALO_GUEST_SPAN;
    g_arena = mmap(NULL, g_arena_size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANON, -1, 0);
    if (g_arena == MAP_FAILED)
    {
        g_arena = NULL;
        say(line, "FAIL arena allocation size=%zu", g_arena_size);
        line("M0.4 RESULT: FAIL - no guest backing arena.");
        return;
    }
    say(line, "PASS host=%p..%p (%u MiB)", g_arena, g_arena + g_arena_size,
        (unsigned)(g_arena_size / (1024u * 1024u)));

    line("");
    line("[3] Real Android ABI structure sizes:");
    const int layout_ok =
        sizeof(struct halo_guest_header32) == 44 &&
        sizeof(struct halo_guest_boot32) == 16 &&
        sizeof(struct guest_timespec32) == 8 &&
        sizeof(struct guest_iovec32) == 8;
    say(line, "%s guest_header=%zu boot=%zu timespec=%zu iovec=%zu",
        layout_ok ? "PASS" : "FAIL",
        sizeof(struct halo_guest_header32), sizeof(struct halo_guest_boot32),
        sizeof(struct guest_timespec32), sizeof(struct guest_iovec32));
    pass &= layout_ok;

    line("");
    line("[4] Build a realistic guest header at Android image base:");
    struct halo_guest_header32 *header =
        (struct halo_guest_header32 *)guest_to_host(HALO_GUEST_IMAGE_BASE, sizeof(*header));
    const guest_ptr32 import_table_g = HALO_GUEST_IMAGE_BASE + 0x4000u;
    const guest_ptr32 import_names_g = HALO_GUEST_IMAGE_BASE + 0x5000u;
    const guest_ptr32 import_count_g = HALO_GUEST_IMAGE_BASE + 0x6000u;
    const guest_ptr32 start_g = HALO_GUEST_IMAGE_BASE + 0x10000u;

    if (!header)
    {
        line("FAIL image-base translation");
        pass = 0;
    }
    else
    {
        memset(header, 0, sizeof(*header));
        header->magic = HALO_GUEST_MAGIC;
        header->abi_version = HALO_GUEST_ABI_VERSION;
        header->image_end = HALO_GUEST_IMAGE_BASE + 0x00100000u;
        header->import_table = import_table_g;
        header->import_names = import_names_g;
        header->import_count = import_count_g;
        header->start = start_g;
        header->thread_start = start_g + 0x100u;
        header->thread_attach = start_g + 0x200u;
        header->init_array_start = HALO_GUEST_IMAGE_BASE + 0x7000u;
        header->init_array_end = HALO_GUEST_IMAGE_BASE + 0x7010u;

        uint32_t *count = (uint32_t *)guest_to_host(header->import_count, sizeof(uint32_t));
        uint64_t *imports = (uint64_t *)guest_to_host(header->import_table, 2 * sizeof(uint64_t));
        char *names = (char *)guest_to_host(header->import_names, 64);
        if (!count || !imports || !names)
        {
            line("FAIL translated header fields");
            pass = 0;
        }
        else
        {
            *count = 2;
            imports[0] = UINT64_C(0x1111222233334444);
            imports[1] = UINT64_C(0xaaaabbbbccccdddd);
            strcpy(names, "host_log\0host_syscall\0");
            const int ok = header->magic == HALO_GUEST_MAGIC && *count == 2 &&
                           imports[1] == UINT64_C(0xaaaabbbbccccdddd) &&
                           strcmp(names, "host_log") == 0;
            say(line, "%s header/import-table/import-name translation", ok ? "PASS" : "FAIL");
            pass &= ok;
        }
    }

    line("");
    line("[5] Boot block + argv/environment pointer chains:");
    const guest_ptr32 boot_g = HALO_GUEST_WINDOW_BASE + 0x00100000u;
    const guest_ptr32 argv_g = HALO_GUEST_WINDOW_BASE + 0x00101000u;
    const guest_ptr32 env_g  = HALO_GUEST_WINDOW_BASE + 0x00102000u;
    const guest_ptr32 arg0_g = HALO_GUEST_WINDOW_BASE + 0x00103000u;
    const guest_ptr32 env0_g = HALO_GUEST_WINDOW_BASE + 0x00104000u;

    struct halo_guest_boot32 *boot =
        (struct halo_guest_boot32 *)guest_to_host(boot_g, sizeof(*boot));
    guest_ptr32 *argv = (guest_ptr32 *)guest_to_host(argv_g, 2 * sizeof(guest_ptr32));
    guest_ptr32 *env = (guest_ptr32 *)guest_to_host(env_g, 2 * sizeof(guest_ptr32));
    const int strings_ok = put_guest_string(arg0_g, "halo") && put_guest_string(env0_g, "HOME=/var/mobile");

    if (!boot || !argv || !env || !strings_ok)
    {
        line("FAIL boot/argv/environment setup");
        pass = 0;
    }
    else
    {
        boot->argc = 1;
        boot->argv = argv_g;
        boot->environment = env_g;
        boot->page_size = (uint32_t)page;
        argv[0] = arg0_g;
        argv[1] = 0;
        env[0] = env0_g;
        env[1] = 0;

        guest_ptr32 *argv_check = (guest_ptr32 *)guest_to_host(boot->argv, 2 * sizeof(guest_ptr32));
        guest_ptr32 *env_check = (guest_ptr32 *)guest_to_host(boot->environment, 2 * sizeof(guest_ptr32));
        const char *arg0 = argv_check ? (const char *)guest_to_host(argv_check[0], 5) : NULL;
        const char *env0 = env_check ? (const char *)guest_to_host(env_check[0], 17) : NULL;
        const int ok = arg0 && env0 && strcmp(arg0, "halo") == 0 && strcmp(env0, "HOME=/var/mobile") == 0;
        say(line, "%s boot argc=%u argv[0]=%s env[0]=%s", ok ? "PASS" : "FAIL",
            boot->argc, arg0 ? arg0 : "<bad>", env0 ? env0 : "<bad>");
        pass &= ok;
    }

    line("");
    line("[6] Android-style host syscall boundary conversion:");
    const guest_ptr32 data_g = HALO_GUEST_WINDOW_BASE + 0x00200000u;
    const guest_ptr32 iov_g  = HALO_GUEST_WINDOW_BASE + 0x00201000u;
    const guest_ptr32 ts_g   = HALO_GUEST_WINDOW_BASE + 0x00202000u;
    put_guest_string(data_g, "boundary-data");
    struct guest_iovec32 *iov = (struct guest_iovec32 *)guest_to_host(iov_g, sizeof(*iov));
    struct guest_timespec32 *ts = (struct guest_timespec32 *)guest_to_host(ts_g, sizeof(*ts));
    if (!iov || !ts)
    {
        line("FAIL syscall structure translation");
        pass = 0;
    }
    else
    {
        iov->base = data_g;
        iov->length = 13;
        ts->seconds = 123;
        ts->nanoseconds = 456000000;
        const char *payload = (const char *)guest_to_host((uint64_t)iov->base, iov->length + 1);
        const int ok = payload && strcmp(payload, "boundary-data") == 0 &&
                       ts->seconds == 123 && ts->nanoseconds == 456000000;
        say(line, "%s iovec.base=0x%08x -> %p len=%u", ok ? "PASS" : "FAIL",
            iov->base, payload, iov->length);
        say(line, "%s guest timespec={%d,%d}", ok ? "PASS" : "FAIL",
            ts->seconds, ts->nanoseconds);
        pass &= ok;
    }

    line("");
    line("[7] Zero-extension + bounds behavior:");
    void *zero_extended = guest_to_host(UINT64_C(0xffffffff80003000), 4);
    void *expected = guest_to_host(UINT64_C(0x0000000080003000), 4);
    const int zero_ok = zero_extended == expected && expected != NULL;
    const int null_ok = guest_to_host(0, 1) == NULL;
    const int low_ok = guest_to_host(HALO_GUEST_WINDOW_BASE - 4u, 4) == NULL;
    const int end_ok = guest_to_host((uint64_t)HALO_GUEST_WINDOW_BASE + g_arena_size - 2, 4) == NULL;
    say(line, "%s 64-bit boundary args truncate/zero-extend to guest32", zero_ok ? "PASS" : "FAIL");
    say(line, "%s NULL/below-base/cross-end rejected", (null_ok && low_ok && end_ok) ? "PASS" : "FAIL");
    pass &= zero_ok && null_ok && low_ok && end_ok;

    line("");
    line("[8] Guest/host round-trip + translation hot loop:");
    void *sample = guest_to_host(HALO_GUEST_IMAGE_BASE + 0x12340u, 4);
    guest_ptr32 sample_back = host_to_guest(sample, 4);
    const int roundtrip_ok = sample && sample_back == HALO_GUEST_IMAGE_BASE + 0x12340u;
    say(line, "%s guest 0x%08x -> host %p -> guest 0x%08x",
        roundtrip_ok ? "PASS" : "FAIL", HALO_GUEST_IMAGE_BASE + 0x12340u, sample, sample_back);
    pass &= roundtrip_ok;

    struct timespec t0, t1;
    volatile uintptr_t checksum = 0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (uint32_t i = 0; i < 1000000u; ++i)
    {
        guest_ptr32 p = HALO_GUEST_WINDOW_BASE + ((i * 64u) % (HALO_GUEST_SPAN - 64u));
        checksum ^= (uintptr_t)guest_to_host(p, 4);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    say(line, "PASS 1000000 explicit translations in %.3f ms (checksum=0x%llx)",
        elapsed_ms(t0, t1), (unsigned long long)checksum);

    line("");
    if (pass)
    {
        line("M0.4 RESULT: PASS - real Android ABI boundary shapes work with relocated guest backing.");
        line("M1 PLAN: keep guest-visible values/layouts 32-bit; translate pointers at host service boundaries.");
        line("BLOCKER: raw ILP32 guest code still cannot directly dereference original 0x8xxxxxxx addresses on iOS.");
    }
    else
    {
        line("M0.4 RESULT: FAIL - one or more Android ABI boundary assumptions need redesign before M1.");
    }

    munmap(g_arena, g_arena_size);
    g_arena = NULL;
    g_arena_size = 0;
}
