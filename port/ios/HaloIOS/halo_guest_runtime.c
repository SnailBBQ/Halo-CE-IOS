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
#include "halo_va_map.h"
#include "halo_flex_base.h"
#include <pthread.h>
#include <stdatomic.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/vm_map.h>
#endif
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
static char g_nonjb_report[2048];
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

/* Let the system search for a free window aligned to its own size. This is the same request the Mod Test app's direct allocation makes
 * (vm_map, any address, aligned to the size, no access until committed); the Non-Jailbreak Version tries it only after the production
 * reservation was refused. */
#if defined(__APPLE__)
static int nonjb_reserve_aligned(void *context, uint64_t size, uint64_t *base, int *error)
{
    vm_address_t address = 0;
    kern_return_t result;
    (void)context;
    result = vm_map(mach_task_self(), &address, (vm_size_t)size, (vm_offset_t)(size - 1), VM_FLAGS_ANYWHERE, MEMORY_OBJECT_NULL, 0, FALSE,
        VM_PROT_NONE, VM_PROT_ALL, VM_INHERIT_NONE);
    if (result != KERN_SUCCESS)
    {
        *error = (int)result;
        return 0;
    }
    *base = (uint64_t)address;
    return 1;
}
#else
static int nonjb_reserve_aligned(void *context, uint64_t size, uint64_t *base, int *error)
{
    (void)context; (void)size; (void)base;
    *error = HALO_VA_ERR_NOT_ATTEMPTED;
    return 0;
}
#endif

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

/* The process's own address-space map, for the Non-Jailbreak Version's log: the range the system allows, what is already mapped and
 * where the free gaps are. Read-only; nothing is reserved. Run before the arena is reserved so the map shows what the game starts with. */
#if defined(__APPLE__)
void halo_guest_runtime_vm_report(char *out, size_t size)
{
    HaloVaRegion regions[HALO_VA_REGION_MAX];
    HaloVaMapStats stats;
    unsigned count = 0;
    int truncated = 0;
    uint64_t low = 0, high = 0;
    task_vm_info_data_t info;
    mach_msg_type_number_t info_count = TASK_VM_INFO_COUNT;
    vm_address_t address = 0;
    natural_t depth = 0;

    memset(&info, 0, sizeof(info));
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &info_count) == KERN_SUCCESS)
    {
        low = (uint64_t)info.min_address;
        high = (uint64_t)info.max_address;
    }
    for (;;)
    {
        vm_size_t length = 0;
        vm_region_submap_info_data_64_t region;
        mach_msg_type_number_t region_count = VM_REGION_SUBMAP_INFO_COUNT_64;
        if (vm_region_recurse_64(mach_task_self(), &address, &length, &depth, (vm_region_recurse_info_t)&region, &region_count) != KERN_SUCCESS)
            break;
        if (region.is_submap)
        {
            depth++;
            continue;
        }
        if (count < HALO_VA_REGION_MAX)
        {
            regions[count].start = (uint64_t)address;
            regions[count].size = (uint64_t)length;
            count++;
        }
        else
            truncated = 1;
        if (!length || address + length < address)
            break;
        address += length;
    }
    halo_va_map_analyze(regions, count, truncated, low, high, &stats);
    halo_va_map_format(&stats, out, size);
}
#else
void halo_guest_runtime_vm_report(char *out, size_t size)
{
    snprintf(out, size, "Address-space map: not available on this platform.\n");
}
#endif

/* ---- Stage 2 flexible-base synthetic guest ---------------------------------
 *
 * This never becomes g_guest_base and never starts the real Halo guest.  It is
 * deliberately isolated from aligned-arena-v1: reserve one exact 4 GiB span at
 * any address, require that address to be hostile (not 4-GiB aligned), then
 * exercise the base+uint32 guest-address model against representative Halo VAs.
 *
 * If this passes on a sideloaded device, it proves the memory model and a tiny
 * instruction fetch at an arbitrary base.  It does NOT prove that the real
 * OpenCE guest has been converted yet.
 */

typedef struct NonjbFlexThreadContext {
    HaloFlexBaseModel model;
    uint32_t counter_va;
    uint32_t result_va;
} NonjbFlexThreadContext;

typedef struct NonjbFlexGuestState {
    uint32_t global_ptr;
    uint32_t first_node;
    uint32_t stack_top;
    uint32_t callback_target;
    uint32_t import_index;
} NonjbFlexGuestState;

typedef struct NonjbFlexNode {
    uint32_t next;
    uint32_t payload;
} NonjbFlexNode;

typedef uint32_t (*NonjbFlexImport)(const HaloFlexBaseModel *, uint32_t, uint32_t);
typedef uint32_t (*NonjbFlexCallback)(const HaloFlexBaseModel *, uint32_t, uint32_t);

static int nonjb_flex_range(const HaloFlexBaseModel *model, size_t page,
                            uint32_t va, size_t size,
                            uint64_t *lo_out, uint64_t *hi_out)
{
    uint64_t start = va, end = start + (uint64_t)size;
    uint64_t mask;
    if (!halo_flex_base_valid(model) || !page || (page & (page - 1)) || !size ||
        end < start || end > model->span)
        return 0;
    mask = (uint64_t)page - 1;
    *lo_out = start & ~mask;
    *hi_out = (end + mask) & ~mask;
    return *hi_out <= model->span;
}

static int nonjb_flex_commit(const HaloFlexBaseModel *model, size_t page,
                             uint32_t va, size_t size, int protection)
{
    uint64_t lo, hi;
    if (!nonjb_flex_range(model, page, va, size, &lo, &hi))
        return 0;
    return mprotect((void *)(model->host_base + (uintptr_t)lo),
                    (size_t)(hi - lo), protection) == 0;
}

static int nonjb_flex_decommit(const HaloFlexBaseModel *model, size_t page,
                               uint32_t va, size_t size)
{
    uint64_t lo, hi;
    if (!nonjb_flex_range(model, page, va, size, &lo, &hi))
        return 0;
    return mmap((void *)(model->host_base + (uintptr_t)lo), (size_t)(hi - lo),
                PROT_NONE, MAP_FIXED | MAP_PRIVATE | MAP_ANON, -1, 0) != MAP_FAILED;
}

static uint32_t nonjb_flex_import_store(const HaloFlexBaseModel *model,
                                        uint32_t guest_va, uint32_t value)
{
    uint32_t *slot = (uint32_t *)halo_flex_ptr(model, guest_va, sizeof(*slot));
    if (!slot)
        return 0;
    *slot = value;
    return *slot;
}

static uint32_t nonjb_flex_guest_callback(const HaloFlexBaseModel *model,
                                          uint32_t guest_va, uint32_t value)
{
    uint32_t *slot = (uint32_t *)halo_flex_ptr(model, guest_va, sizeof(*slot));
    if (!slot)
        return 0;
    *slot ^= value;
    return *slot;
}

static void *nonjb_flex_thread(void *opaque)
{
    NonjbFlexThreadContext *context = (NonjbFlexThreadContext *)opaque;
    _Atomic uint32_t *counter = (_Atomic uint32_t *)halo_flex_ptr(
        &context->model, context->counter_va, sizeof(*counter));
    uint32_t *result = (uint32_t *)halo_flex_ptr(
        &context->model, context->result_va, sizeof(*result));
    if (!counter || !result)
        return (void *)(uintptr_t)1;
    for (unsigned i = 0; i < 2048; ++i)
        atomic_fetch_add_explicit(counter, 1, memory_order_relaxed);
    *result = UINT32_C(0x54485244); /* THRD */
    return NULL;
}

int halo_guest_runtime_nonjb_flex_stage2(char *out, size_t size,
                                         void (*phase)(const char *))
{
    enum {
        FLEX_EXEC_VA   = 0x0FFF0000u,
        FLEX_GLOBAL_VA = 0x00100000u,
        FLEX_STATE_VA  = 0x10000000u,
        FLEX_ATOMIC_VA = 0x20000000u,
        FLEX_HEAP_VA   = 0x803A0000u,
        FLEX_MMAP_VA   = 0xC0000000u,
        FLEX_STACK_VA  = 0xEC000000u,
        FLEX_CALLBACK_VA = 0x0ABC0000u,
        FLEX_EXEC_MAGIC = 0x4842u
    };
    static const uint32_t exec_code[] = {
        0x52890840u, /* movz w0, #0x4842 */
        0xD65F03C0u  /* ret */
    };
    void *reservation = MAP_FAILED;
    HaloFlexBaseModel model = { 0, HALO_FLEX_GUEST_SPAN };
    long page_long = sysconf(_SC_PAGESIZE);
    size_t page = page_long > 0 ? (size_t)page_long : 0;
    size_t used = 0;
    const char *failure = NULL;
    int exec_pass = 0;
    int result = 0;

    if (size)
        out[0] = 0;
    if (phase)
        phase("nonjb 520 flex stage2 reserve");
    halo_va_text(out, size, &used, "FLEXIBLE-BASE STAGE 2: synthetic guest at an intentionally hostile host base\n");

    if (sizeof(uintptr_t) < 8 || sizeof(size_t) < 8 || !page || (page & (page - 1)))
    {
        failure = "host is not a supported 64-bit power-of-two-page environment";
        goto cleanup;
    }

    reservation = mmap(NULL, (size_t)HALO_FLEX_GUEST_SPAN, PROT_NONE,
                       MAP_PRIVATE | MAP_ANON, -1, 0);
    if (reservation == MAP_FAILED)
    {
        halo_va_text(out, size, &used,
            "  arena: FAILED to reserve one exact 4 GiB span anywhere (errno=%d: %s)\n",
            errno, strerror(errno));
        failure = "no contiguous 4 GiB reservation";
        goto cleanup;
    }
    model.host_base = (uintptr_t)reservation;
    if (!halo_flex_base_valid(&model))
    {
        failure = "the system returned an invalid 4 GiB host span";
        goto cleanup;
    }
    halo_va_text(out, size, &used,
        "  arena: 0x%llx-0x%llx, page=%zu, 4-GiB-aligned=%s, offset=0x%llx\n",
        (unsigned long long)model.host_base,
        (unsigned long long)(model.host_base + HALO_FLEX_GUEST_SPAN), page,
        halo_flex_base_is_hostile(&model) ? "NO (hostile as required)" : "YES",
        (unsigned long long)(model.host_base & (HALO_FLEX_GUEST_SPAN - 1)));

    if (!halo_flex_base_is_hostile(&model))
    {
        halo_va_text(out, size, &used,
            "  hostile-base requirement: INCONCLUSIVE (this reservation happened to be 4-GiB aligned; real guest remains unchanged)\n");
        failure = "test did not receive a non-4-GiB-aligned arena";
        goto cleanup;
    }
    if (phase)
        phase("nonjb 521 flex stage2 hostile arena ready");

    /* Representative globals and a guest-owned structure containing only
     * 32-bit guest addresses. */
    if (!nonjb_flex_commit(&model, page, FLEX_GLOBAL_VA, page, PROT_READ | PROT_WRITE) ||
        !nonjb_flex_commit(&model, page, FLEX_STATE_VA, page, PROT_READ | PROT_WRITE) ||
        !nonjb_flex_commit(&model, page, FLEX_HEAP_VA, page, PROT_READ | PROT_WRITE) ||
        !nonjb_flex_commit(&model, page, FLEX_STACK_VA, page, PROT_READ | PROT_WRITE) ||
        !nonjb_flex_commit(&model, page, FLEX_ATOMIC_VA, page, PROT_READ | PROT_WRITE))
    {
        failure = "one of the synthetic guest data pages could not be committed";
        goto cleanup;
    }
    {
        uint32_t *global = (uint32_t *)halo_flex_ptr(&model, FLEX_GLOBAL_VA, sizeof(*global));
        NonjbFlexGuestState *state = (NonjbFlexGuestState *)halo_flex_ptr(&model, FLEX_STATE_VA, sizeof(*state));
        NonjbFlexNode *first = (NonjbFlexNode *)halo_flex_ptr(&model, FLEX_HEAP_VA + 0x100u, sizeof(*first));
        NonjbFlexNode *second = (NonjbFlexNode *)halo_flex_ptr(&model, FLEX_HEAP_VA + 0x200u, sizeof(*second));
        uint32_t roundtrip = 0;
        uint32_t sp = FLEX_STACK_VA + (uint32_t)page;
        uint32_t *stack_word;
        unsigned char *src = (unsigned char *)halo_flex_ptr(&model, FLEX_HEAP_VA + 0x400u, 64);
        unsigned char *dst = (unsigned char *)halo_flex_ptr(&model, FLEX_HEAP_VA + 0x500u, 64);
        if (!global || !state || !first || !second || !src || !dst)
        {
            failure = "base-relative pointer translation returned NULL";
            goto cleanup;
        }
        *global = UINT32_C(0x474C4F42); /* GLOB */
        state->global_ptr = FLEX_GLOBAL_VA;
        state->first_node = FLEX_HEAP_VA + 0x100u;
        state->stack_top = sp;
        state->callback_target = FLEX_CALLBACK_VA;
        state->import_index = 0;
        first->next = FLEX_HEAP_VA + 0x200u;
        first->payload = UINT32_C(0x11112222);
        second->next = 0;
        second->payload = UINT32_C(0x33334444);
        if (*(uint32_t *)halo_flex_ptr(&model, state->global_ptr, 4) != UINT32_C(0x474C4F42) ||
            ((NonjbFlexNode *)halo_flex_ptr(&model, first->next, sizeof(*second)))->payload != UINT32_C(0x33334444))
        {
            failure = "32-bit pointers stored in guest structures did not dereference through base+VA";
            goto cleanup;
        }
        if (!halo_flex_guest_va(&model, second, sizeof(*second), &roundtrip) || roundtrip != first->next ||
            halo_flex_legacy_low32_matches(&model, roundtrip))
        {
            failure = "host-to-guest roundtrip or hostile low32 rejection failed";
            goto cleanup;
        }
        if ((unsigned char *)halo_flex_ptr(&model, state->first_node + 0x20u, 1) !=
            (unsigned char *)first + 0x20u)
        {
            failure = "guest pointer arithmetic did not preserve the base-relative address";
            goto cleanup;
        }
        sp -= 4;
        stack_word = (uint32_t *)halo_flex_ptr(&model, sp, sizeof(*stack_word));
        if (!stack_word)
        {
            failure = "synthetic guest stack translation failed";
            goto cleanup;
        }
        *stack_word = UINT32_C(0x5354414B); /* STAK */
        if (*(uint32_t *)halo_flex_ptr(&model, sp, 4) != UINT32_C(0x5354414B))
        {
            failure = "synthetic guest stack push/pop failed";
            goto cleanup;
        }
        memset(src, 0x5A, 64);
        memset(dst, 0, 64);
        memcpy(dst, src, 64);
        if (memcmp(src, dst, 64) != 0)
        {
            failure = "memset/memcpy through translated guest memory failed";
            goto cleanup;
        }
    }
    halo_va_text(out, size, &used,
        "  globals/stack/heap/pointer-structs/arithmetic/memcpy: PASS (old low32 identity intentionally FALSE)\n");

    /* A guest-mmap analogue: decommit a page, recommit it and verify fresh
     * anonymous storage is zeroed. */
    if (!nonjb_flex_commit(&model, page, FLEX_MMAP_VA, page, PROT_READ | PROT_WRITE))
    {
        failure = "synthetic guest mmap page could not be committed";
        goto cleanup;
    }
    memset(halo_flex_ptr(&model, FLEX_MMAP_VA, page), 0xA5, page);
    if (!nonjb_flex_decommit(&model, page, FLEX_MMAP_VA, page) ||
        !nonjb_flex_commit(&model, page, FLEX_MMAP_VA, page, PROT_READ | PROT_WRITE))
    {
        failure = "synthetic guest mmap decommit/recommit failed";
        goto cleanup;
    }
    {
        const unsigned char *fresh = (const unsigned char *)halo_flex_ptr(&model, FLEX_MMAP_VA, 64);
        for (unsigned i = 0; i < 64; ++i)
            if (fresh[i] != 0)
            {
                failure = "synthetic guest mmap recommit did not return zeroed memory";
                goto cleanup;
            }
    }
    halo_va_text(out, size, &used, "  guest mmap/decommit/recommit: PASS\n");
    if (phase)
        phase("nonjb 522 flex stage2 memory and remap passed");

    /* Atomics plus a second host thread operating on a 32-bit guest VA. */
    {
        _Atomic uint32_t *counter = (_Atomic uint32_t *)halo_flex_ptr(&model, FLEX_ATOMIC_VA, sizeof(*counter));
        uint32_t *thread_result = (uint32_t *)halo_flex_ptr(&model, FLEX_ATOMIC_VA + 64u, sizeof(*thread_result));
        NonjbFlexThreadContext context = { model, FLEX_ATOMIC_VA, FLEX_ATOMIC_VA + 64u };
        pthread_t thread;
        void *thread_return = NULL;
        if (!counter || !thread_result || !atomic_is_lock_free(counter))
        {
            failure = "32-bit guest atomic is not lock-free/aligned on this host";
            goto cleanup;
        }
        atomic_init(counter, 0);
        *thread_result = 0;
        if (pthread_create(&thread, NULL, nonjb_flex_thread, &context) != 0)
        {
            failure = "second synthetic guest thread could not be created";
            goto cleanup;
        }
        for (unsigned i = 0; i < 2048; ++i)
            atomic_fetch_add_explicit(counter, 1, memory_order_relaxed);
        if (pthread_join(thread, &thread_return) != 0 || thread_return != NULL ||
            atomic_load_explicit(counter, memory_order_relaxed) != 4096 ||
            *thread_result != UINT32_C(0x54485244))
        {
            failure = "atomic/second-thread guest-address test failed";
            goto cleanup;
        }
    }
    if (phase)
        phase("nonjb 523 flex stage2 atomics and thread passed");
    halo_va_text(out, size, &used, "  atomics + second thread: PASS\n");

    /* Host import and callback dispatch stay explicit: the guest stores a
     * small ID / guest target, never a truncated host function pointer. */
    {
        static NonjbFlexImport imports[] = { nonjb_flex_import_store };
        static NonjbFlexCallback callbacks[] = { nonjb_flex_guest_callback };
        NonjbFlexGuestState *state = (NonjbFlexGuestState *)halo_flex_ptr(&model, FLEX_STATE_VA, sizeof(*state));
        uint32_t import_slot_va = FLEX_GLOBAL_VA + 4u;
        uint32_t callback_slot_va = FLEX_GLOBAL_VA + 8u;
        uint32_t *callback_slot = (uint32_t *)halo_flex_ptr(&model, callback_slot_va, 4);
        NonjbFlexImport import_fn;
        NonjbFlexCallback callback_fn;
        if (!state || state->import_index >= sizeof(imports) / sizeof(imports[0]) || !callback_slot)
        {
            failure = "synthetic import/callback descriptor is invalid";
            goto cleanup;
        }
        import_fn = imports[state->import_index];
        callback_fn = callbacks[0];
        if (import_fn(&model, import_slot_va, UINT32_C(0x494D5054)) != UINT32_C(0x494D5054))
        {
            failure = "indirect host import dispatch failed";
            goto cleanup;
        }
        *callback_slot = UINT32_C(0xCA110000);
        if (state->callback_target != FLEX_CALLBACK_VA ||
            callback_fn(&model, callback_slot_va, UINT32_C(0x0000BACC)) != UINT32_C(0xCA11BACC))
        {
            failure = "callback dispatch with a 32-bit guest target failed";
            goto cleanup;
        }
    }
    if (phase)
        phase("nonjb 524 flex stage2 imports and callbacks passed");
    halo_va_text(out, size, &used, "  host-import + callback/indirect dispatch: PASS\n");

    /* Finally, execute the same two-instruction AArch64 style of canary used
     * by M2.6.84, but from this genuinely unaligned 4 GiB reservation. */
    if (!nonjb_flex_commit(&model, page, FLEX_EXEC_VA, page, PROT_READ | PROT_WRITE))
    {
        failure = "unaligned-arena execution page could not be committed RW";
        goto cleanup;
    }
    memcpy(halo_flex_ptr(&model, FLEX_EXEC_VA, sizeof(exec_code)), exec_code, sizeof(exec_code));
    __builtin___clear_cache((char *)halo_flex_ptr(&model, FLEX_EXEC_VA, sizeof(exec_code)),
                            (char *)halo_flex_ptr(&model, FLEX_EXEC_VA, sizeof(exec_code)) + sizeof(exec_code));
    if (!nonjb_flex_commit(&model, page, FLEX_EXEC_VA, page, PROT_READ | PROT_EXEC))
    {
        failure = "unaligned-arena execution page could not be protected RX";
        goto cleanup;
    }
#if defined(__aarch64__) || defined(__arm64__)
    if (phase)
        phase("nonjb 525 flex stage2 exec canary entering");
    halo_va_text(out, size, &used,
        "  unaligned RX canary: entering host 0x%llx (guest 0x%08x); if the process vanishes, launch-phase stays at 525\n",
        (unsigned long long)(model.host_base + FLEX_EXEC_VA), FLEX_EXEC_VA);
    {
        uint32_t (*entry)(void) = (uint32_t (*)(void))halo_flex_ptr(&model, FLEX_EXEC_VA, sizeof(exec_code));
        uint32_t value = entry();
        if (phase)
            phase("nonjb 526 flex stage2 exec canary returned");
        exec_pass = value == FLEX_EXEC_MAGIC;
        halo_va_text(out, size, &used, "  unaligned RX canary: returned 0x%04x (expected 0x%04x): %s\n",
            value, FLEX_EXEC_MAGIC, exec_pass ? "PASS" : "FAIL");
    }
#else
    exec_pass = 1;
    halo_va_text(out, size, &used, "  unaligned RX canary: SKIPPED on non-AArch64 host test environment\n");
#endif
    if (!exec_pass)
    {
        failure = "unaligned-arena executable canary returned the wrong value";
        goto cleanup;
    }

    result = 1;
    if (phase)
        phase("nonjb 527 flex stage2 synthetic guest passed");
    halo_va_text(out, size, &used,
        "  RESULT: PASS — base+uint32 synthetic guest works at a hostile base. The real OpenCE guest is still deliberately disabled on this path.\n");

cleanup:
    if (!result && failure)
        halo_va_text(out, size, &used, "  RESULT: %s — %s. Real Halo guest was not started.\n",
            reservation == MAP_FAILED ? "BLOCKED" : "FAIL", failure);
    if (reservation != MAP_FAILED)
        munmap(reservation, (size_t)HALO_FLEX_GUEST_SPAN);
    return result;
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
            HaloVaReserver reserver = { NULL, nonjb_reserve, nonjb_release, nonjb_reserve_aligned };
            HaloVaProbe probe;
            uint64_t fixed = 0;
            int fixed_error = 0;
            int aligned_error = 0;
            unsigned tried = 0;
            size_t used;
            halo_va_probe_run(&reserver, &probe);
            halo_va_probe_format(&probe, g_nonjb_report, sizeof(g_nonjb_report));
            used = strlen(g_nonjb_report);
            if (halo_va_try_aligned_arena(&reserver, &fixed, &aligned_error))
            {
                halo_va_text(g_nonjb_report, sizeof(g_nonjb_report), &used,
                    "Fallback: the 8 GiB reservation failed (errno %d), but the system itself found a 4 GiB-aligned 4 GiB window at 0x%llx.\n",
                    error, (unsigned long long)fixed);
                g_init_error[0] = 0;
                g_page_size = (size_t)page;
                g_guest_base = (uint8_t *)(uintptr_t)fixed;
                return 1;
            }
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
            {
                char why[96], aligned_why[96];
                halo_va_error_text(fixed_error, why, sizeof(why));
                halo_va_aligned_error_text(aligned_error, aligned_why, sizeof(aligned_why));
                halo_va_text(g_nonjb_report, sizeof(g_nonjb_report), &used,
                    "Fallback: no 4 GiB-aligned window could be had. The system's own search was refused (%s), and no fixed window could be reserved either (%u tried, first refusal: %s).\n",
                    aligned_why, tried, why);
            }
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
