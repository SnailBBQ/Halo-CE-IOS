/* Mod Test builds only (HALO_MOD_TEST). File capacity is not resident tag capacity.
 * Keep arithmetic unsigned and subtraction-based so hostile offsets cannot wrap.
 * No guest layout, pointer bridge or tag arena size changes are made here.
 * Official iOS builds leave HALO_MOD_TEST undefined and keep the stock limit. */
#ifndef HALO_CACHE_MOD_TEST_POLICY_H
#define HALO_CACHE_MOD_TEST_POLICY_H
#include <stdint.h>
#define HALO_STOCK_CACHE_FILE_LIMIT UINT32_C(0x11600000)
#define HALO_MOD_TEST_CACHE_FILE_LIMIT UINT32_C(0x18000000)
#define HALO_MOD_TEST_TAG_CAPACITY UINT32_C(0x01600000)
#if defined(HALO_MOD_TEST)
#define HALO_ENGINE_CACHE_FILE_LIMIT HALO_MOD_TEST_CACHE_FILE_LIMIT
#else
#define HALO_ENGINE_CACHE_FILE_LIMIT HALO_STOCK_CACHE_FILE_LIMIT
#endif
static inline int halo_mod_test_range(uint32_t offset, uint32_t size, uint32_t limit)
{
    return offset <= limit && size <= limit - offset;
}
static inline int halo_mod_test_header(uint32_t length, uint32_t offset,
                                      uint32_t size, int scenario_type)
{
    return length >= 0x800 && length <= HALO_MOD_TEST_CACHE_FILE_LIMIT &&
        (length <= HALO_STOCK_CACHE_FILE_LIMIT || scenario_type == 0) &&
        offset >= 0x800 && size >= 0x24 && size <= HALO_MOD_TEST_TAG_CAPACITY &&
        halo_mod_test_range(offset, size, length);
}
static inline int halo_mod_test_bsp(uint32_t tags, uint32_t offset, uint32_t size,
                                  uint32_t length, uint32_t address, uint32_t base)
{
    /* cache_file_read rounds transfers to 512-byte sectors. Validate that
     * actual destination write, not merely the unrounded declared BSP size. */
    uint32_t rounded;
    if (size < 0x18 || size > UINT32_MAX - 511 || tags > HALO_MOD_TEST_TAG_CAPACITY ||
        offset < 0x800 || !halo_mod_test_range(offset, size, length) || address < base)
        return 0;
    rounded = (size + 511) & ~UINT32_C(511);
    return address - base >= tags &&
        halo_mod_test_range(address - base, rounded, HALO_MOD_TEST_TAG_CAPACITY);
}
#endif
