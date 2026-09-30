#include "halo_ios_probe.h"
#include <errno.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define XBOX_BASE       0x80000000ULL
#define XBOX_SIZE       0x08000000ULL
#define IMAGE_BASE      0x88000000ULL
#define IMAGE_SIZE      0x02000000ULL
#define GUEST_END       (IMAGE_BASE + IMAGE_SIZE)
#define GUEST_SPAN      (GUEST_END - XBOX_BASE) /* 160 MiB */

typedef uint32_t guest_ptr32;

typedef struct guest_node32 {
    uint32_t magic;
    uint32_t value;
    guest_ptr32 next;
} guest_node32;

typedef struct guest_root32 {
    guest_ptr32 first_node;
    uint32_t node_count;
    guest_ptr32 label;
    uint32_t flags;
} guest_root32;

_Static_assert(sizeof(guest_ptr32) == 4, "guest pointers must remain 32-bit");
_Static_assert(sizeof(guest_node32) == 12, "guest_node32 layout changed");
_Static_assert(offsetof(guest_node32, next) == 8, "guest_node32 pointer offset changed");
_Static_assert(sizeof(guest_root32) == 16, "guest_root32 layout changed");
_Static_assert(offsetof(guest_root32, label) == 8, "guest_root32 pointer offset changed");

static void say(void (^line)(const char *), const char *fmt, ...) {
    char buf[448];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    line(buf);
}

static void *guest_to_host(uint8_t *arena, guest_ptr32 guest, size_t bytes) {
    uint64_t g = (uint64_t)guest;
    if (g < XBOX_BASE || g >= GUEST_END)
        return NULL;
    if (bytes > (size_t)(GUEST_END - g))
        return NULL;
    return arena + (size_t)(g - XBOX_BASE);
}

static int host_to_guest(uint8_t *arena, const void *host, guest_ptr32 *out_guest) {
    uintptr_t base = (uintptr_t)arena;
    uintptr_t p = (uintptr_t)host;
    if (p < base || p >= base + (uintptr_t)GUEST_SPAN)
        return 0;
    uint64_t guest = XBOX_BASE + (uint64_t)(p - base);
    if (guest > UINT32_MAX)
        return 0;
    *out_guest = (guest_ptr32)guest;
    return 1;
}

static uint64_t ns_since(const struct timespec *a, const struct timespec *b) {
    return ((uint64_t)(b->tv_sec - a->tv_sec) * 1000000000ULL) +
           (uint64_t)(b->tv_nsec - a->tv_nsec);
}

void halo_ios_run_m0_probe(void (^line)(const char *text)) {
    const long page = sysconf(_SC_PAGESIZE);
    int pass = 1;

    say(line, "pointer size: %zu-bit host / %zu-bit guest pointer", sizeof(void *) * 8, sizeof(guest_ptr32) * 8);
    say(line, "page size: %ld", page);
    say(line, "guest span: %llu MiB", (unsigned long long)(GUEST_SPAN / (1024ULL * 1024ULL)));

    line("");
    line("[1] Reserve relocated guest arena:");
    errno = 0;
    uint8_t *arena = mmap(NULL, (size_t)GUEST_SPAN,
                          PROT_READ | PROT_WRITE,
                          MAP_PRIVATE | MAP_ANON, -1, 0);
    if (arena == MAP_FAILED) {
        say(line, "ARENA FAIL: %s", strerror(errno));
        line("M0.3 RESULT: FAIL - could not reserve guest arena.");
        return;
    }
    say(line, "ARENA PASS host=%p..%p", arena, arena + GUEST_SPAN);

    line("");
    line("[2] 32-bit guest structure layout:");
    say(line, "%s guest_ptr32=%zu bytes", sizeof(guest_ptr32) == 4 ? "PASS" : "FAIL", sizeof(guest_ptr32));
    say(line, "%s node=%zu bytes next@%zu", (sizeof(guest_node32) == 12 && offsetof(guest_node32, next) == 8) ? "PASS" : "FAIL", sizeof(guest_node32), offsetof(guest_node32, next));
    say(line, "%s root=%zu bytes label@%zu", (sizeof(guest_root32) == 16 && offsetof(guest_root32, label) == 8) ? "PASS" : "FAIL", sizeof(guest_root32), offsetof(guest_root32, label));

    const guest_ptr32 ROOT_G  = 0x80010000u;
    const guest_ptr32 NODE1_G = 0x80020000u;
    const guest_ptr32 NODE2_G = 0x80021000u;
    const guest_ptr32 LABEL_G = 0x80030000u;

    guest_root32 *root = (guest_root32 *)guest_to_host(arena, ROOT_G, sizeof(*root));
    guest_node32 *n1 = (guest_node32 *)guest_to_host(arena, NODE1_G, sizeof(*n1));
    guest_node32 *n2 = (guest_node32 *)guest_to_host(arena, NODE2_G, sizeof(*n2));
    char *label = (char *)guest_to_host(arena, LABEL_G, 32);
    if (!root || !n1 || !n2 || !label) {
        line("SETUP FAIL: translated test structures are outside arena.");
        munmap(arena, (size_t)GUEST_SPAN);
        return;
    }

    memset(root, 0, sizeof(*root));
    memset(n1, 0, sizeof(*n1));
    memset(n2, 0, sizeof(*n2));
    memset(label, 0, 32);

    root->first_node = NODE1_G;
    root->node_count = 2;
    root->label = LABEL_G;
    root->flags = 0xCE2342u;
    n1->magic = 0x48414C4Fu; /* HALO */
    n1->value = 117;
    n1->next = NODE2_G;
    n2->magic = 0x58424F58u; /* XBOX */
    n2->value = 343;
    n2->next = 0;
    snprintf(label, 32, "Halo CE guest32");

    line("");
    line("[3] Nested guest-pointer chain:");
    guest_node32 *walk1 = (guest_node32 *)guest_to_host(arena, root->first_node, sizeof(guest_node32));
    guest_node32 *walk2 = walk1 ? (guest_node32 *)guest_to_host(arena, walk1->next, sizeof(guest_node32)) : NULL;
    char *walk_label = (char *)guest_to_host(arena, root->label, 1);
    int chain_ok = walk1 && walk2 && walk_label &&
                   walk1->magic == 0x48414C4Fu && walk1->value == 117 &&
                   walk2->magic == 0x58424F58u && walk2->value == 343 &&
                   strcmp(walk_label, "Halo CE guest32") == 0;
    say(line, "%s root 0x%08x -> node1 0x%08x -> node2 0x%08x",
        chain_ok ? "PASS" : "FAIL", ROOT_G, root->first_node, walk1 ? walk1->next : 0);
    say(line, "%s label via guest pointer: %s", chain_ok ? "PASS" : "FAIL", walk_label ? walk_label : "<null>");
    pass &= chain_ok;

    line("");
    line("[4] Guest/host pointer round-trip:");
    guest_ptr32 round1 = 0, round2 = 0;
    int rt1 = host_to_guest(arena, walk1, &round1) && round1 == NODE1_G;
    int rt2 = host_to_guest(arena, walk2, &round2) && round2 == NODE2_G;
    say(line, "%s host %p -> guest 0x%08x", rt1 ? "PASS" : "FAIL", walk1, round1);
    say(line, "%s host %p -> guest 0x%08x", rt2 ? "PASS" : "FAIL", walk2, round2);
    pass &= rt1 && rt2;

    line("");
    line("[5] Null + bounds semantics:");
    int null_ok = guest_to_host(arena, 0, 1) == NULL;
    int low_ok = guest_to_host(arena, 0x7FFFFFFFu, 1) == NULL;
    int end_ok = guest_to_host(arena, 0x89FFFFFFu, 2) == NULL;
    say(line, "%s guest NULL stays invalid", null_ok ? "PASS" : "FAIL");
    say(line, "%s below-base pointer rejected", low_ok ? "PASS" : "FAIL");
    say(line, "%s crossing guest-end rejected", end_ok ? "PASS" : "FAIL");
    pass &= null_ok && low_ok && end_ok;

    line("");
    line("[6] Translation hot-loop sanity:");
    const uint32_t iterations = 1000000u;
    volatile uintptr_t checksum = 0;
    struct timespec t0 = {0}, t1 = {0};
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (uint32_t i = 0; i < iterations; ++i) {
        guest_ptr32 g = (guest_ptr32)(0x80000000u + ((i & 0x3FFFu) << 2));
        void *p = guest_to_host(arena, g, sizeof(uint32_t));
        checksum ^= (uintptr_t)p;
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    uint64_t elapsed = ns_since(&t0, &t1);
    say(line, "PASS %u translations in %.3f ms (checksum=0x%llx)",
        iterations, (double)elapsed / 1000000.0, (unsigned long long)checksum);

    munmap(arena, (size_t)GUEST_SPAN);
    line("");
    if (pass) {
        line("M0.3 RESULT: PASS - explicit 32-bit guest-pointer translation works for nested data structures.");
        line("NEXT: inspect Android ILP32 call/data boundaries before selecting the M1 execution strategy.");
    } else {
        line("M0.3 RESULT: FAIL - guest-pointer abstraction needs revision.");
    }
}
