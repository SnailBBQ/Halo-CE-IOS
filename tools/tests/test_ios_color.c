#include "halo_color.h"
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

int main(void)
{
    unsigned c = 0;

    /* hex input the player may type */
    CHECK(hx_parse("#3385FA", &c) && c == 0x3385FAu, "#RRGGBB");
    CHECK(hx_parse("3385fa", &c) && c == 0x3385FAu, "no hash, lower case");
    CHECK(hx_parse("  #0a0B0c \n", &c) && c == 0x0A0B0Cu, "spaces around");
    CHECK(hx_parse("#38F", &c) && c == 0x3388FFu, "three digits are doubled");
    CHECK(hx_parse("#000000", &c) && c == 0, "black");
    CHECK(hx_parse("FFFFFF", &c) && c == 0xFFFFFFu, "white");
    c = 0x123456u;
    const char *bad[] = { "", "#", "#12", "#1234", "#12345", "#1234567", "12345g", "#12 345", "0x3385FA", "red", "#-12345", "\xC3\xA9\xC3\xA9\xC3\xA9", NULL };
    for (int i = 0; bad[i]; i++) CHECK(!hx_parse(bad[i], &c) && c == 0x123456u, "rejects '%s' and leaves the value alone", bad[i]);
    CHECK(!hx_parse(NULL, &c), "NULL");

    /* readability: the clamp keeps every colour inside the luminance band, and leaves good colours alone */
    CHECK(hx_clamp_accent(0x3385FAu) == 0x3385FAu, "the default blue is fine as it is");
    CHECK(hx_clamp_accent(0x147A42u) == 0x147A42u, "the green preset is untouched");
    unsigned black = hx_clamp_accent(0x000000u), white = hx_clamp_accent(0xFFFFFFu);
    CHECK(hx_luminance(black) >= 0.055f && hx_luminance(black) <= 0.41f, "black is lightened into range (%f)", hx_luminance(black));
    CHECK(hx_luminance(white) >= 0.055f && hx_luminance(white) <= 0.41f, "white is darkened into range (%f)", hx_luminance(white));
    int out_of_range = 0, not_idempotent = 0;
    for (unsigned r = 0; r < 256; r += 15)
        for (unsigned g = 0; g < 256; g += 15)
            for (unsigned b = 0; b < 256; b += 15)
            {
                unsigned in = (r << 16) | (g << 8) | b, once = hx_clamp_accent(in);
                float l = hx_luminance(once);
                if (l < 0.055f || l > 0.41f) out_of_range++;
                if (hx_clamp_accent(once) != once) not_idempotent++;
            }
    CHECK(out_of_range == 0, "%d of 4913 sampled colours left the band", out_of_range);
    CHECK(not_idempotent == 0, "%d colours changed again when clamped twice", not_idempotent);
    /* the hue of a clamped colour is kept (a dark red stays red, not grey) */
    unsigned dark_red = hx_clamp_accent(0x200000u);
    CHECK(((dark_red >> 16) & 255) > ((dark_red >> 8) & 255) && ((dark_red >> 16) & 255) > (dark_red & 255), "dark red stays reddish (%06x)", dark_red);

    /* hsv */
    CHECK(hx_hsv(0.0f, 1.0f, 1.0f) == 0xFF0000u && hx_hsv(1.0f / 3.0f, 1.0f, 1.0f) == 0x00FF00u && hx_hsv(2.0f / 3.0f, 1.0f, 1.0f) == 0x0000FFu, "primaries");
    CHECK(hx_hsv(0.5f, 0.0f, 0.5f) == 0x808080u && hx_hsv(0.3f, 0.9f, 0.0f) == 0, "grey and black");
    CHECK(hx_hsv(1.25f, 1.0f, 1.0f) == hx_hsv(0.25f, 1.0f, 1.0f) && hx_hsv(-0.75f, 1.0f, 1.0f) == hx_hsv(0.25f, 1.0f, 1.0f), "the hue wraps");

    /* chroma: a full cycle comes back, it moves, and every step is readable */
    CHECK(hx_chroma(0.0, 12.0f) == hx_chroma(12.0, 12.0f) && hx_chroma(3.0, 12.0f) == hx_chroma(15.0, 12.0f), "a cycle repeats");
    CHECK(hx_chroma(0.0, 12.0f) != hx_chroma(4.0, 12.0f) && hx_chroma(4.0, 12.0f) != hx_chroma(8.0, 12.0f), "it moves");
    int unreadable = 0; unsigned previous = hx_chroma(0.0, 12.0f); int jumps = 0;
    for (int i = 0; i <= 1200; i++)
    {
        unsigned now = hx_chroma(i * 0.01, 12.0f);
        float l = hx_luminance(now);
        if (l < 0.055f || l > 0.41f) unreadable++;
        int dr = (int)((now >> 16) & 255) - (int)((previous >> 16) & 255), dg = (int)((now >> 8) & 255) - (int)((previous >> 8) & 255), db = (int)(now & 255) - (int)(previous & 255);
        if (dr * dr + dg * dg + db * db > 40 * 40) jumps++;
        previous = now;
    }
    CHECK(unreadable == 0, "%d chroma steps were outside the readable band", unreadable);
    CHECK(jumps == 0, "the cycle changes smoothly, %d jumps", jumps);
    CHECK(hx_chroma(1e9, 0.0f) <= 0xFFFFFFu && hx_chroma(-5.0, 12.0f) <= 0xFFFFFFu && hx_chroma(5.0, -3.0f) <= 0xFFFFFFu, "silly periods and times stay valid");

    if (!failures) printf("PASS: hex input, readable accent clamp (4913 colours), hsv, smooth chroma cycle\n");
    return failures ? 1 : 0;
}
