#include "halo_flex_base.h"

#include <stdint.h>
#include <stdio.h>

#define CHECK(c, ...) do { if (!(c)) { fprintf(stderr, "FAIL: "); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); failures++; } } while (0)

static int failures;

int main(void)
{
    HaloFlexBaseModel model = { UINT64_C(0x2A0000000), HALO_FLEX_GUEST_SPAN };
    const uint32_t samples[] = {
        UINT32_C(0x00001000), UINT32_C(0x10000000), UINT32_C(0x803A6000),
        UINT32_C(0x88000000), UINT32_C(0xC0000000), UINT32_C(0xEC000000)
    };

    CHECK(halo_flex_base_valid(&model), "the iPhone-style 4 GiB model is valid");
    CHECK(halo_flex_base_is_hostile(&model), "0x2a0000000 is deliberately not 4 GiB aligned");

    for (unsigned i = 0; i < sizeof(samples) / sizeof(samples[0]); ++i)
    {
        uint32_t roundtrip = 0;
        void *host = halo_flex_ptr(&model, samples[i], 16);
        CHECK(host != NULL, "guest 0x%08x translates", samples[i]);
        CHECK((uintptr_t)host == model.host_base + samples[i], "guest 0x%08x uses base + zero_extend(VA)", samples[i]);
        CHECK(halo_flex_guest_va(&model, host, 16, &roundtrip) && roundtrip == samples[i],
              "host roundtrip for 0x%08x", samples[i]);
        CHECK(!halo_flex_legacy_low32_matches(&model, samples[i]),
              "hostile base rejects the old low32 identity at 0x%08x", samples[i]);
    }

    CHECK(halo_flex_ptr(&model, UINT32_C(0xFFFFFFF0), 16) != NULL, "last 16 bytes are addressable");
    CHECK(halo_flex_ptr(&model, UINT32_C(0xFFFFFFF0), 17) == NULL, "crossing 4 GiB is rejected");
    CHECK(halo_flex_ptr(&model, 0, 0) == NULL, "zero-size translation is rejected");
    {
        uint32_t guest = 0;
        CHECK(!halo_flex_guest_va(&model, (void *)(model.host_base - 1), 1, &guest), "host pointer below base is rejected");
        CHECK(!halo_flex_guest_va(&model, (void *)(model.host_base + HALO_FLEX_GUEST_SPAN), 1, &guest), "host pointer at the end is rejected");
    }

    if (!failures)
        puts("PASS: flexible-base arithmetic round-trips representative Halo guest VAs at a hostile unaligned host base without low32 identity");
    return failures ? 1 : 0;
}
