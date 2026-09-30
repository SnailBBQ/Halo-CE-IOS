#include "halo_ios_probe.h"
#include <errno.h>
#include <inttypes.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define XBOX_BASE  0x80000000ULL
#define XBOX_SIZE  0x08000000ULL
#define IMAGE_BASE 0x88000000ULL
#define IMAGE_SIZE 0x02000000ULL
#define COMBINED_SIZE (XBOX_SIZE + IMAGE_SIZE)

static void say(void (^line)(const char *), const char *fmt, ...) {
    char buf[320];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    line(buf);
}

static void probe_hint(uint64_t base, uint64_t size, void (^line)(const char *)) {
    errno = 0;
    void *p = mmap((void *)(uintptr_t)base, (size_t)size, PROT_NONE,
                   MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) {
        say(line, "HINT FAIL 0x%08" PRIx64 " + 0x%08" PRIx64 ": %s", base, size, strerror(errno));
        return;
    }
    say(line, "HINT 0x%08" PRIx64 " -> %p%s", base, p,
        ((uint64_t)(uintptr_t)p == base) ? " (exact)" : " (relocated)");
    munmap(p, (size_t)size);
}

static int probe_mach_fixed(uint64_t base, uint64_t size, void (^line)(const char *)) {
    vm_address_t addr = (vm_address_t)base;
    kern_return_t kr = vm_allocate(mach_task_self(), &addr,
                                   (vm_size_t)size, VM_FLAGS_FIXED);
    if (kr != KERN_SUCCESS) {
        say(line, "FIXED FAIL 0x%08" PRIx64 " + 0x%08" PRIx64 ": kr=%d (%s)",
            base, size, kr, mach_error_string(kr));
        return 0;
    }
    say(line, "FIXED PASS 0x%08" PRIx64 " + 0x%08" PRIx64, base, size);
    vm_deallocate(mach_task_self(), addr, (vm_size_t)size);
    return 1;
}

static void probe_anywhere(uint64_t size, void (^line)(const char *)) {
    errno = 0;
    void *p = mmap(NULL, (size_t)size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) {
        say(line, "ANYWHERE FAIL size=0x%08" PRIx64 ": %s", size, strerror(errno));
        return;
    }
    say(line, "ANYWHERE PASS size=0x%08" PRIx64 " at %p%s", size, p,
        ((uint64_t)(uintptr_t)p < 0x100000000ULL) ? " (<4GB)" : " (>4GB)");
    munmap(p, (size_t)size);
}

static void survey_low4g(void (^line)(const char *)) {
    static const uint64_t points[] = {
        0x10000000ULL, 0x20000000ULL, 0x40000000ULL, 0x60000000ULL,
        0x70000000ULL, 0x78000000ULL, 0x80000000ULL, 0x88000000ULL,
        0x90000000ULL, 0xA0000000ULL, 0xC0000000ULL, 0xE0000000ULL
    };
    const uint64_t page = (uint64_t)sysconf(_SC_PAGESIZE);
    line("Low-4GB fixed-page survey (one page each):");
    for (size_t i = 0; i < sizeof(points) / sizeof(points[0]); ++i)
        probe_mach_fixed(points[i], page, line);
}

void halo_ios_run_m0_probe(void (^line)(const char *text)) {
    say(line, "pointer size: %zu-bit", sizeof(void *) * 8);
    say(line, "page size: %ld", sysconf(_SC_PAGESIZE));

    line("");
    line("[1] Halo address hints (non-destructive):");
    probe_hint(XBOX_BASE, XBOX_SIZE, line);
    probe_hint(IMAGE_BASE, IMAGE_SIZE, line);

    line("");
    line("[2] Exact Halo ranges via Mach VM:");
    int xbox = probe_mach_fixed(XBOX_BASE, XBOX_SIZE, line);
    int image = probe_mach_fixed(IMAGE_BASE, IMAGE_SIZE, line);

    line("");
    line("[3] Contiguous arenas chosen by iOS:");
    probe_anywhere(XBOX_SIZE, line);
    probe_anywhere(IMAGE_SIZE, line);
    probe_anywhere(COMBINED_SIZE, line);

    line("");
    line("[4] Address-space survey:");
    survey_low4g(line);

    line("");
    if (xbox && image)
        line("M0.1: exact Halo layout is viable.");
    else
        line("M0.1: exact layout unavailable; use survey results to choose relocation/translation strategy.");
}
