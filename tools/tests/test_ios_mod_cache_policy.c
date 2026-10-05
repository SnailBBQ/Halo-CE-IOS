#include <assert.h>
#include <stdio.h>
#include "../../source/cache/cache_mod_test_policy.h"
int main(void)
{
    const uint32_t base = 0x803A6000, tags = 0x00CC0000;
    assert(halo_mod_test_header(0x17100000, 0x16000000, tags, 0));
    assert(!halo_mod_test_header(0x17100000, 0x16000000, tags, 1));
    assert(!halo_mod_test_header(0x18000001, 0x1000, tags, 0));
    assert(!halo_mod_test_header(0x17100000, 0xfffffff0, 0x1000, 0));
    assert(!halo_mod_test_header(0x17100000, 0x1000, 0x01600001, 0));
    assert(!halo_mod_test_header(0x17100000, 0x1000, 0, 0));
    assert(halo_mod_test_bsp(tags, 0x1000, 0x00830000, 0x17100000, base+tags, base));
    assert(!halo_mod_test_bsp(tags, 0x1000, 0x00A00000, 0x17100000, base+tags, base));
    assert(!halo_mod_test_bsp(tags, 0x1000, 0x1000, 0x17100000, base+tags-1, base));
    assert(!halo_mod_test_bsp(tags, 0x17100000, 0x1000, 0x17100000, base+tags, base));
    assert(!halo_mod_test_bsp(tags, 0x1000, 0xffffffff, 0x17100000, base+tags, base));
    assert(!halo_mod_test_bsp(tags, 0x1000, 1, 0x17100000, base+tags, base));
    assert(!halo_mod_test_bsp(tags, 0x1000, 513, 0x17100000, base+0x015FFE00, base));
    assert(halo_mod_test_bsp(tags, 0x1000, 512, 0x17100000, base+0x015FFE00, base));
    puts("PASS: extended campaign headers, unchanged tag capacity, BSP overlap/overflow and sector-rounded destination bounds");
    return 0;
}
