#ifndef HALO_FLEX_BASE_H
#define HALO_FLEX_BASE_H

/*
 * Stage-2 Non-Jailbreak flexible-base model.
 *
 * The real arm64_32 guest still uses aligned-arena-v1.  This helper is the
 * deliberately smaller experiment that proves the address conversion we need
 * before changing the real guest:
 *
 *     host = guest_base + zero_extend(guest_va)
 *     guest = host - guest_base
 *
 * No low-32-bit identity is required.  Keep this header plain C so the same
 * arithmetic is exercised by host tests and by the on-device synthetic guest.
 */

#include <stddef.h>
#include <stdint.h>

#define HALO_FLEX_GUEST_SPAN (UINT64_C(1) << 32)

typedef struct HaloFlexBaseModel {
    uintptr_t host_base;
    uint64_t span;
} HaloFlexBaseModel;

static inline int halo_flex_base_valid(const HaloFlexBaseModel *model)
{
    return model && model->host_base && model->span == HALO_FLEX_GUEST_SPAN &&
           model->host_base <= UINTPTR_MAX - (uintptr_t)model->span;
}

static inline int halo_flex_base_is_hostile(const HaloFlexBaseModel *model)
{
    return halo_flex_base_valid(model) &&
           ((model->host_base & (uintptr_t)(HALO_FLEX_GUEST_SPAN - 1)) != 0);
}

static inline void *halo_flex_ptr(const HaloFlexBaseModel *model,
                                  uint32_t guest_va, size_t size)
{
    uint64_t start = guest_va;
    uint64_t end = start + (uint64_t)size;
    if (!halo_flex_base_valid(model) || !size || end < start || end > model->span)
        return NULL;
    return (void *)(model->host_base + (uintptr_t)start);
}

static inline int halo_flex_guest_va(const HaloFlexBaseModel *model,
                                     const void *host, size_t size,
                                     uint32_t *guest_va)
{
    uintptr_t address;
    uint64_t delta, end;
    if (!halo_flex_base_valid(model) || !host || !size || !guest_va)
        return 0;
    address = (uintptr_t)host;
    if (address < model->host_base)
        return 0;
    delta = (uint64_t)(address - model->host_base);
    end = delta + (uint64_t)size;
    if (delta > UINT32_MAX || end < delta || end > model->span)
        return 0;
    *guest_va = (uint32_t)delta;
    return 1;
}

/* The old aligned-arena contract. Stage 2 expects this to be false for a
 * representative pointer while the explicit base-relative round trip passes. */
static inline int halo_flex_legacy_low32_matches(const HaloFlexBaseModel *model,
                                                 uint32_t guest_va)
{
    void *host = halo_flex_ptr(model, guest_va, 1);
    return host && (uint32_t)(uintptr_t)host == guest_va;
}

#endif
