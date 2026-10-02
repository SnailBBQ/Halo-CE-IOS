#ifndef HALO_GUEST_EXEC_BRIDGE_H
#define HALO_GUEST_EXEC_BRIDGE_H

#include <setjmp.h>
#include <stdint.h>

enum halo_guest_abort_reason
{
    HALO_GUEST_ABORT_NONE = 0,
    HALO_GUEST_ABORT_SIGNAL = 2,
    HALO_GUEST_ABORT_MISSING_IMPORT = 3,
    HALO_GUEST_ABORT_EXIT = 4,
    HALO_GUEST_ABORT_HOST = 5
};

typedef struct halo_guest_exec_stats
{
    uint64_t pointer_upgrades;
    uint64_t pc_translations;
    uint64_t handled_faults;
    uint64_t unhandled_faults;
    uint64_t last_fault_address;
    uint64_t last_host_pc;
    uint32_t last_guest_pc;
    uint32_t last_instruction;
    uint32_t last_base_register;
} halo_guest_exec_stats;

int halo_guest_exec_bridge_install(void);
void halo_guest_exec_bridge_register_code(uint32_t guest_start, uint32_t guest_end);
void halo_guest_exec_bridge_reset_ranges(void);

sigjmp_buf *halo_guest_exec_guard_buffer(void);
void halo_guest_exec_guard_set_active(int active);
void halo_guest_exec_abort(int reason);

/* Current calling thread only; excludes background audio-worker faults. */
uint64_t halo_guest_exec_thread_pointer_upgrades(void);

/* Pointer-upgrade faults by guest PC (async-signal-safe, lock-free). */
#define HALO_FAULT_HIST_SLOTS 8192
typedef struct halo_fault_hist_entry { uint32_t pc; uint32_t count; } halo_fault_hist_entry;
/* Copies and clears the non-empty slots; returns how many were copied. */
unsigned halo_guest_fault_hist_take(halo_fault_hist_entry *out, unsigned capacity);

void halo_guest_exec_stats_get(halo_guest_exec_stats *stats);
void halo_guest_exec_stats_reset(void);

#endif
