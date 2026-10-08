#ifndef HALO_GUEST_RUNTIME_H
#define HALO_GUEST_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

typedef uint32_t halo_guest_va_t;

int halo_guest_runtime_init(void);
/* Diagnostic only; describes the most recent initialization failure. */
const char *halo_guest_runtime_last_error(void);
void halo_guest_runtime_shutdown(void);

void *halo_guest_ptr(halo_guest_va_t va, size_t size);
int halo_guest_commit(halo_guest_va_t va, size_t size);
int halo_guest_protect(halo_guest_va_t va, size_t size, int protection);
int halo_guest_decommit(halo_guest_va_t va, size_t size);
int halo_guest_read(halo_guest_va_t va, void *dst, size_t size);
int halo_guest_write(halo_guest_va_t va, const void *src, size_t size);

void *halo_guest_base_address(void);
size_t halo_guest_page_size(void);
uint64_t halo_guest_span(void);
int halo_guest_base_is_4gb_aligned(void);
/* Nonzero only when the active real guest arena came from the Non-JB arbitrary-base fallback. */
int halo_guest_runtime_is_flexible_base(void);

#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
/* Non-Jailbreak Version diagnostics. The first is the address-space survey written when the production reservation was refused
   (empty otherwise); the second probes whether this process may make memory executable without executing code. */
const char *halo_guest_runtime_nonjb_report(void);
void halo_guest_runtime_exec_report(char *out, size_t size);
/* The process's address-space map (range, mapped ranges, free gaps), read before anything is reserved. */
void halo_guest_runtime_vm_report(char *out, size_t size);
/* Stage 2 only: reserve one hostile 4 GiB arena, exercise base+uint32 guest addressing, threads/imports/remap, and an AArch64
   execution canary, then release it. The real Halo guest is never started by this test. `phase` may persist progress to disk. */
int halo_guest_runtime_nonjb_flex_stage2(char *out, size_t size, void (*phase)(const char *));
#endif

#endif
