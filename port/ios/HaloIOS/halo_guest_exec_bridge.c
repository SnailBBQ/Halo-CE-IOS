#include "halo_guest_exec_bridge.h"
#include "halo_guest_runtime.h"

#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <ucontext.h>

#define MAX_CODE_RANGES 16
#define FOUR_GB UINT64_C(0x100000000)

struct code_range
{
    uint32_t guest_start;
    uint32_t guest_end;
};

static struct code_range g_ranges[MAX_CODE_RANGES];
static unsigned g_range_count;
static int g_installed;
static struct sigaction g_old_segv;
static struct sigaction g_old_bus;
static halo_guest_exec_stats g_stats;

static _Thread_local sigjmp_buf g_guard;
static _Thread_local int g_guard_active;

static int guest_code_va(uint32_t va)
{
    for (unsigned i = 0; i < g_range_count; ++i)
        if (va >= g_ranges[i].guest_start && va < g_ranges[i].guest_end)
            return 1;
    return 0;
}

static int host_pc_is_guest(uint64_t pc, uint32_t *guest_pc)
{
    uint64_t base = (uint64_t)(uintptr_t)halo_guest_base_address();
    if (!base || pc < base || pc - base >= FOUR_GB)
        return 0;

    uint32_t va = (uint32_t)(pc - base);
    if (!guest_code_va(va))
        return 0;

    if (guest_pc)
        *guest_pc = va;
    return 1;
}

#if defined(__arm64__) || defined(__aarch64__)
static uint64_t get_register(ucontext_t *context, unsigned index)
{
#if defined(__APPLE__)
    mcontext_t mc = context->uc_mcontext;
    if (index < 29)
        return mc->__ss.__x[index];
    if (index == 29)
        return mc->__ss.__fp;
    if (index == 30)
        return mc->__ss.__lr;
    return mc->__ss.__sp;
#else
    return context->uc_mcontext.regs[index];
#endif
}

static void set_register(ucontext_t *context, unsigned index, uint64_t value)
{
#if defined(__APPLE__)
    mcontext_t mc = context->uc_mcontext;
    if (index < 29)
        mc->__ss.__x[index] = value;
    else if (index == 29)
        mc->__ss.__fp = value;
    else if (index == 30)
        mc->__ss.__lr = value;
    else
        mc->__ss.__sp = value;
#else
    context->uc_mcontext.regs[index] = value;
#endif
}

static uint64_t get_pc(ucontext_t *context)
{
#if defined(__APPLE__)
    return context->uc_mcontext->__ss.__pc;
#else
    return context->uc_mcontext.pc;
#endif
}

static void set_pc(ucontext_t *context, uint64_t value)
{
#if defined(__APPLE__)
    context->uc_mcontext->__ss.__pc = value;
#else
    context->uc_mcontext.pc = value;
#endif
}
#endif

static void abort_guest_from_signal(uint64_t fault_address, uint64_t pc, uint32_t instruction)
{
    g_stats.unhandled_faults++;
    g_stats.last_fault_address = fault_address;
    g_stats.last_host_pc = pc;
    g_stats.last_instruction = instruction;

    if (g_guard_active)
        siglongjmp(g_guard, HALO_GUEST_ABORT_SIGNAL);
}

static void bridge_signal(int signal_number, siginfo_t *info, void *opaque)
{
#if defined(__arm64__) || defined(__aarch64__)
    ucontext_t *context = (ucontext_t *)opaque;
    uint64_t pc = get_pc(context);
    uint64_t fault = (uint64_t)(uintptr_t)info->si_addr;
    uint64_t base = (uint64_t)(uintptr_t)halo_guest_base_address();

    /*
     * Indirect guest branches carry 32-bit function pointers. The CPU tries
     * to fetch at that low VA and faults in iOS' 4-GiB PAGEZERO. Redirect
     * execution to the same guest VA inside the relocated arena.
     */
    if (pc < FOUR_GB && pc != 0 && guest_code_va((uint32_t)pc))
    {
        set_pc(context, base + (uint32_t)pc);
        g_stats.pc_translations++;
        g_stats.handled_faults++;
        g_stats.last_guest_pc = (uint32_t)pc;
        return;
    }

    uint32_t guest_pc = 0;
    if (fault < FOUR_GB && fault != 0 && host_pc_is_guest(pc, &guest_pc))
    {
        uint32_t instruction = *(const uint32_t *)(uintptr_t)pc;

        /*
         * All ordinary AArch64 load/store encodings place Rn in bits 9:5.
         * An arm64_32 pointer loaded from memory is zero-extended, so the
         * first dereference hits PAGEZERO. Upgrade only that base register to
         * host_base + guestVA and retry the same instruction.
         *
         * Once upgraded, arithmetic and comparisons continue to work; stores
         * into 32-bit pointer fields use Wn and naturally truncate back to the
         * original guest VA because host_base is exactly 4-GiB aligned.
         */
        unsigned rn = (instruction >> 5) & 31u;
        uint64_t value = get_register(context, rn);

        if (rn != 31 && value != 0 && value < FOUR_GB)
        {
            set_register(context, rn, base + (uint32_t)value);
            g_stats.pointer_upgrades++;
            g_stats.handled_faults++;
            g_stats.last_fault_address = fault;
            g_stats.last_host_pc = pc;
            g_stats.last_guest_pc = guest_pc;
            g_stats.last_instruction = instruction;
            g_stats.last_base_register = rn;
            return;
        }

        abort_guest_from_signal(fault, pc, instruction);
        return;
    }

    abort_guest_from_signal(fault, pc, 0);
    if (g_guard_active)
        return;

    struct sigaction *old = signal_number == SIGBUS ? &g_old_bus : &g_old_segv;
    sigaction(signal_number, old, NULL);
    raise(signal_number);
#else
    (void)signal_number;
    (void)info;
    (void)opaque;
#endif
}

int halo_guest_exec_bridge_install(void)
{
    if (g_installed)
        return 1;

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = bridge_signal;
    action.sa_flags = SA_SIGINFO | SA_NODEFER;
    sigemptyset(&action.sa_mask);

    if (sigaction(SIGSEGV, &action, &g_old_segv) != 0)
        return 0;
    if (sigaction(SIGBUS, &action, &g_old_bus) != 0)
    {
        sigaction(SIGSEGV, &g_old_segv, NULL);
        return 0;
    }

    g_installed = 1;
    return 1;
}

void halo_guest_exec_bridge_register_code(uint32_t guest_start, uint32_t guest_end)
{
    if (guest_start >= guest_end || g_range_count >= MAX_CODE_RANGES)
        return;
    g_ranges[g_range_count++] = (struct code_range){ guest_start, guest_end };
}

void halo_guest_exec_bridge_reset_ranges(void)
{
    g_range_count = 0;
}

sigjmp_buf *halo_guest_exec_guard_buffer(void)
{
    return &g_guard;
}

void halo_guest_exec_guard_set_active(int active)
{
    g_guard_active = active;
}

void halo_guest_exec_abort(int reason)
{
    if (reason == 0)
        reason = HALO_GUEST_ABORT_HOST;
    if (g_guard_active)
        siglongjmp(g_guard, reason);
}

void halo_guest_exec_stats_get(halo_guest_exec_stats *stats)
{
    if (stats)
        *stats = g_stats;
}

void halo_guest_exec_stats_reset(void)
{
    memset(&g_stats, 0, sizeof(g_stats));
}
