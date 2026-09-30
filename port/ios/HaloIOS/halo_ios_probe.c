#include "halo_ios_probe.h"
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define XBOX_BASE       0x80000000ULL
#define XBOX_SIZE       0x08000000ULL
#define IMAGE_BASE      0x88000000ULL
#define IMAGE_SIZE      0x02000000ULL
#define GUEST_END       (IMAGE_BASE + IMAGE_SIZE)
#define GUEST_SPAN      (GUEST_END - XBOX_BASE) /* 160 MiB */
#define INVALID_GUEST   0x7FFFFFFFULL

static void say(void (^line)(const char *), const char *fmt, ...) {
    char buf[384];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    line(buf);
}

static uint8_t *guest_to_host(uint8_t *arena, uint64_t guest) {
    if (guest < XBOX_BASE || guest >= GUEST_END)
        return NULL;
    return arena + (size_t)(guest - XBOX_BASE);
}

static int test_translation(uint8_t *arena, uint64_t guest, uint32_t value,
                            void (^line)(const char *)) {
    uint8_t *host = guest_to_host(arena, guest);
    if (!host || guest + sizeof(value) > GUEST_END) {
        say(line, "TRANSLATE FAIL guest=0x%08" PRIx64, guest);
        return 0;
    }
    memcpy(host, &value, sizeof(value));
    uint32_t got = 0;
    memcpy(&got, host, sizeof(got));
    int ok = (got == value);
    say(line, "%s guest=0x%08" PRIx64 " -> host=%p value=0x%08x",
        ok ? "RW PASS" : "RW FAIL", guest, host, got);
    return ok;
}

void halo_ios_run_m0_probe(void (^line)(const char *text)) {
    const long page = sysconf(_SC_PAGESIZE);
    say(line, "pointer size: %zu-bit", sizeof(void *) * 8);
    say(line, "page size: %ld", page);
    say(line, "guest span: 0x%08llx bytes (%llu MiB)",
        (unsigned long long)GUEST_SPAN,
        (unsigned long long)(GUEST_SPAN / (1024ULL * 1024ULL)));

    line("");
    line("[1] Reserve relocated guest arena:");
    errno = 0;
    uint8_t *arena = mmap(NULL, (size_t)GUEST_SPAN,
                          PROT_READ | PROT_WRITE,
                          MAP_PRIVATE | MAP_ANON, -1, 0);
    if (arena == MAP_FAILED) {
        say(line, "ARENA FAIL: %s", strerror(errno));
        line("M0.2 RESULT: FAIL - could not reserve writable 160 MiB arena.");
        return;
    }
    say(line, "ARENA PASS host=%p..%p", arena, arena + GUEST_SPAN);
    say(line, "guest 0x80000000 maps to host %p", guest_to_host(arena, XBOX_BASE));
    say(line, "guest 0x88000000 maps to host %p", guest_to_host(arena, IMAGE_BASE));

    line("");
    line("[2] Translation + read/write tests:");
    int pass = 1;
    pass &= test_translation(arena, XBOX_BASE,                 0x48414C4Fu, line); /* HALO */
    pass &= test_translation(arena, XBOX_BASE + 0x00004000ULL, 0x12345678u, line);
    pass &= test_translation(arena, XBOX_BASE + XBOX_SIZE - 4, 0xA5A5A5A5u, line);
    pass &= test_translation(arena, IMAGE_BASE,                0x23422342u, line);
    pass &= test_translation(arena, GUEST_END - 4,             0xDEADBEEFu, line);

    line("");
    line("[3] Boundary rejection tests:");
    uint8_t *below = guest_to_host(arena, INVALID_GUEST);
    uint8_t *past  = guest_to_host(arena, GUEST_END);
    say(line, "%s below guest range", below == NULL ? "PASS reject" : "FAIL accept");
    say(line, "%s at/past guest end", past == NULL ? "PASS reject" : "FAIL accept");
    pass &= (below == NULL && past == NULL);

    line("");
    line("[4] 16-KiB page/alignment checks:");
    uintptr_t base = (uintptr_t)arena;
    int base_aligned = (page > 0) && ((base % (uintptr_t)page) == 0);
    int split_aligned = (page > 0) && (((uintptr_t)guest_to_host(arena, IMAGE_BASE) % (uintptr_t)page) == 0);
    say(line, "%s arena base alignment (%ld bytes)", base_aligned ? "PASS" : "FAIL", page);
    say(line, "%s image split alignment (%ld bytes)", split_aligned ? "PASS" : "FAIL", page);
    pass &= base_aligned && split_aligned;

    line("");
    line("[5] Simultaneous region integrity:");
    memset(arena, 0x11, 64);
    memset(guest_to_host(arena, IMAGE_BASE), 0x22, 64);
    int integrity = 1;
    for (int i = 0; i < 64; ++i) {
        if (arena[i] != 0x11 || guest_to_host(arena, IMAGE_BASE)[i] != 0x22) {
            integrity = 0;
            break;
        }
    }
    say(line, "%s Xbox + image regions remain independently writable", integrity ? "PASS" : "FAIL");
    pass &= integrity;

    munmap(arena, (size_t)GUEST_SPAN);
    line("");
    if (pass)
        line("M0.2 RESULT: PASS - relocated arena translation works for controlled accesses.");
    else
        line("M0.2 RESULT: FAIL - relocation model needs revision before guest integration.");
    line("NOTE: PASS does not prove raw 32-bit guest pointer dereferences are safe; M1 must solve pointer semantics.");
}
