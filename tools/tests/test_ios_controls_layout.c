/* Layout and input-math checks for port/ios/HaloIOS/halo_controls_layout.h.
 * Prints PASS, or with --dump prints one line per control for rendering. */
#include "halo_controls_layout.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

static int is_round(const HcControl *c) { return c->kind != HC_KIND_PILL; }

/* shape-aware: circles (buttons, sticks, the d-pad's disc) versus pill rectangles */
static int overlap(const HcControl *a, const HcControl *b, float gap)
{
    HcRect ra = a->r, rb = b->r;
    if (is_round(a) && is_round(b)) {
        float dx = hc_cx(ra) - hc_cx(rb), dy = hc_cy(ra) - hc_cy(rb), reach = ra.w * 0.5f + rb.w * 0.5f + gap;
        return dx * dx + dy * dy < reach * reach;
    }
    if (!is_round(a) && !is_round(b))
        return ra.x < rb.x + rb.w + gap && rb.x < ra.x + ra.w + gap && ra.y < rb.y + rb.h + gap && rb.y < ra.y + ra.h + gap;
    const HcControl *round = is_round(a) ? a : b, *box = is_round(a) ? b : a;
    float cx = hc_cx(round->r), cy = hc_cy(round->r), rad = round->r.w * 0.5f + gap;
    float nx = cx < box->r.x ? box->r.x : (cx > box->r.x + box->r.w ? box->r.x + box->r.w : cx);
    float ny = cy < box->r.y ? box->r.y : (cy > box->r.y + box->r.h ? box->r.y + box->r.h : cy);
    return (cx - nx) * (cx - nx) + (cy - ny) * (cy - ny) < rad * rad;
}

static void check_screen(const char *name, float w, float h, float il, float it, float ir, float ib, int dump)
{
    HcControl c[HC_COUNT];
    float s = hc_layout(il, it, w - ir, h - ib, c);
    for (int i = 0; i < HC_COUNT; i++) {
        HcRect r = c[i].r;
        if (dump) printf("%s %d %d %.2f %.2f %.2f %.2f %s|%s|%d\n", name, i, c[i].kind, r.x, r.y, r.w, r.h, c[i].label, c[i].sub, c[i].color);
        CHECK(r.x >= il - 0.01f && r.y >= it - 0.01f && r.x + r.w <= w - ir + 0.01f && r.y + r.h <= h - ib + 0.01f,
              "%s: control %d leaves the safe area (%.1f %.1f %.1f %.1f)", name, i, r.x, r.y, r.w, r.h);
        for (int j = i + 1; j < HC_COUNT; j++) {
            CHECK(!overlap(&c[i], &c[j], 2.0f * s), "%s: controls %d and %d overlap", name, i, j);
        }
        CHECK(r.w >= 40.0f * s * 0.95f && r.h >= 28.0f * s, "%s: control %d is too small to hit (%.1f x %.1f)", name, i, r.w, r.h);
    }
    /* thumb-sized touch targets: every control's centre must hit itself */
    for (int i = 0; i < HC_COUNT; i++)
        CHECK(hc_hit(c, hc_cx(c[i].r), hc_cy(c[i].r), s) == i, "%s: centre of control %d hits %d", name, i,
              hc_hit(c, hc_cx(c[i].r), hc_cy(c[i].r), s));
    /* nothing in the middle third of the screen except Back/Start (keeps the view clear) */
    float third = (w - il - ir) / 3.0f;
    for (int i = 0; i < HC_COUNT; i++) {
        if (i == HC_BACK || i == HC_START) continue;
        HcRect r = c[i].r;
        CHECK(r.x + r.w <= il + third + 40.0f * s || r.x >= w - ir - third - 40.0f * s,
              "%s: control %d intrudes into the middle of the screen", name, i);
    }
}

int main(int argc, char **argv)
{
    int dump = argc > 1 && !strcmp(argv[1], "--dump");
    /* name, width, height, safe insets l/t/r/b (landscape) */
    check_screen("iphone_se",   667, 375, 0, 0, 0, 0, dump);
    check_screen("iphone_14",   844, 390, 47, 0, 47, 21, dump);
    check_screen("iphone_15pm", 932, 430, 59, 0, 59, 21, dump);
    check_screen("iphone_mini", 812, 375, 44, 0, 44, 21, dump);
    check_screen("ipad_mini",  1133, 744, 0, 0, 0, 20, dump);
    check_screen("ipad_pro",   1366, 1024, 0, 0, 0, 20, dump);

    /* stick math */
    HcRect base = hc_rect(0, 0, 100, 100);
    int ax, ay; float kx, ky;
    hc_stick(base, 50, 50, &kx, &ky, &ax, &ay);
    CHECK(ax == 0 && ay == 0, "stick centre");
    hc_stick(base, 53, 50, &kx, &ky, &ax, &ay);
    CHECK(ax == 0 && ay == 0, "stick dead zone");
    hc_stick(base, 100, 50, &kx, &ky, &ax, &ay);
    CHECK(ax == 32767 && ay == 0, "stick full right is %d,%d", ax, ay);
    hc_stick(base, 50, 0, &kx, &ky, &ax, &ay);
    CHECK(ax == 0 && ay == -32767, "stick up must be negative like SDL: %d,%d", ax, ay);
    hc_stick(base, 50, 400, &kx, &ky, &ax, &ay);
    CHECK(ax == 0 && ay == 32767 && fabsf(ky - 50.0f) < 0.01f, "stick far down clamps: %d,%d knob %.1f", ax, ay, ky);
    hc_stick(base, 150, 150, &kx, &ky, &ax, &ay);
    CHECK(abs(ax - ay) <= 1 && ax > 20000 && ax < 24000 && fabsf(kx - ky) < 0.01f && fabsf(kx * kx + ky * ky - 2500.0f) < 1.0f,
          "diagonal is clamped to the circle, not the square: %d,%d knob %.2f,%.2f", ax, ay, kx, ky);

    /* d-pad */
    HcRect pad = hc_rect(0, 0, 100, 100);
    CHECK(hc_dpad_mask(pad, 50, 50) == 0, "dpad centre");
    CHECK(hc_dpad_mask(pad, 50, 5) == 1u, "dpad up");
    CHECK(hc_dpad_mask(pad, 50, 95) == 2u, "dpad down");
    CHECK(hc_dpad_mask(pad, 5, 50) == 4u, "dpad left");
    CHECK(hc_dpad_mask(pad, 95, 50) == 8u, "dpad right");
    CHECK(hc_dpad_mask(pad, 90, 10) == 9u, "dpad up-right diagonal");

    /* SDL numbering the guest depends on */
    CHECK(HC_BTN_WHITE == 9 && HC_BTN_BLACK == 10 && HC_BTN_START == 6 && HC_BTN_BACK == 4, "SDL button numbers");
    CHECK(HC_AXIS_LT == 4 && HC_AXIS_RT == 5, "SDL trigger axes");

    if (!failures && !dump) printf("PASS: on-screen Xbox controls fit, do not overlap and map to SDL buttons/axes on 6 screen sizes\n");
    return failures ? 1 : 0;
}
