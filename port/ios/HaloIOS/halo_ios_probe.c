#include "halo_ios_probe.h"
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define XBOX_BASE  0x80000000ULL
#define XBOX_SIZE  0x08000000ULL
#define IMAGE_BASE 0x88000000ULL
#define IMAGE_SIZE 0x02000000ULL

static void emit(void (^line)(const char *), const char *fmt, uint64_t a, uint64_t b) {
    char buf[256];
    snprintf(buf, sizeof(buf), fmt, a, b);
    line(buf);
}

static int probe_exact(uint64_t base, uint64_t size, void (^line)(const char *)) {
    errno = 0;
    void *p = mmap((void *)(uintptr_t)base, (size_t)size, PROT_NONE,
                   MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
    if (p == MAP_FAILED) {
        char buf[256];
        snprintf(buf, sizeof(buf), "FAIL mmap 0x%08" PRIx64 " + 0x%08" PRIx64 ": %s", base, size, strerror(errno));
        line(buf);
        return 0;
    }
    emit(line, "PASS mapped 0x%08" PRIx64 " + 0x%08" PRIx64, base, size);
    munmap(p, (size_t)size);
    return 1;
}

void halo_ios_run_m0_probe(void (^line)(const char *text)) {
    char buf[256];
    snprintf(buf, sizeof(buf), "pointer size: %zu-bit", sizeof(void *) * 8);
    line(buf);
    snprintf(buf, sizeof(buf), "page size: %ld", sysconf(_SC_PAGESIZE));
    line(buf);
    line("Testing Halo's fixed low-4GB address ranges...");
    int xbox = probe_exact(XBOX_BASE, XBOX_SIZE, line);
    int image = probe_exact(IMAGE_BASE, IMAGE_SIZE, line);
    if (xbox && image)
        line("M0 RESULT: PASS - required fixed ranges can be reserved on this device/OS.");
    else
        line("M0 RESULT: FAIL - do not begin guest integration until the address strategy is revised.");
}
