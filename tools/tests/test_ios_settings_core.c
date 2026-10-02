#include "halo_settings_core.h"
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)
static int near(float a, float b) { return fabsf(a - b) < 0.002f; }

int main(void)
{
    HsSettings s, t;
    char text[16384];

    /* defaults: five named presets, sensible values */
    hs_defaults(&s);
    CHECK(!strcmp(s.presets[0].name, "Classic Xbox") && !strcmp(s.presets[4].name, "Preset 5"), "default names");
    CHECK(s.active == 0 && s.volume == 1.0f && s.audio_enabled && !s.join_from_clipboard && s.profiler == 1 && s.smooth_fps == 1 && s.hires_hud == 0 && s.hires_text == 0, "default globals");
    CHECK(s.presets[2].touch_look && s.presets[2].floating_sticks && near(s.presets[2].look_curve, 1.5f), "default aim");

    /* round trip, including a renamed preset with accents, moved/scaled/hidden controls */
    hs_set_name(s.presets[1].name, "  Thumbs ñ ☃ wide  ");
    s.active = 3;
    s.volume = 0.35f;
    s.audio_enabled = 0;
    s.join_from_clipboard = 1;
    s.profiler = 0;
    s.smooth_fps = 0;
    s.hires_hud = 1;
    s.hires_text = 1;
    s.presets[1].opacity = 0.5f;
    s.presets[1].look_sensitivity = 2.25f;
    s.presets[1].invert_look_y = 1;
    s.presets[1].place[HC_A].placed = 1; s.presets[1].place[HC_A].fx = 0.9f; s.presets[1].place[HC_A].fy = 0.4f; s.presets[1].place[HC_A].scale = 1.4f;
    s.presets[1].place[HC_DPAD].hidden = 1;
    s.presets[4].place[HC_RT].placed = 1; s.presets[4].place[HC_RT].fx = 0.1f; s.presets[4].place[HC_RT].fy = 0.2f; s.presets[4].place[HC_RT].scale = 0.8f;
    int written = hs_serialize(&s, text, sizeof(text));
    CHECK(written > 0 && written < (int)sizeof(text), "serialize wrote %d", written);
    CHECK(hs_parse(&t, text) == 1, "parse header");
    CHECK(t.active == 3 && near(t.volume, 0.35f) && !t.audio_enabled && t.join_from_clipboard && t.profiler == 0 && t.smooth_fps == 0 && t.hires_hud == 1 && t.hires_text == 1, "globals round trip");
    CHECK(!strcmp(t.presets[1].name, "Thumbs ñ ☃ wide"), "name round trip got '%s'", t.presets[1].name);
    CHECK(near(t.presets[1].opacity, 0.5f) && near(t.presets[1].look_sensitivity, 2.25f) && t.presets[1].invert_look_y, "aim round trip");
    CHECK(t.presets[1].place[HC_A].placed && near(t.presets[1].place[HC_A].fx, 0.9f) && near(t.presets[1].place[HC_A].fy, 0.4f) &&
          near(t.presets[1].place[HC_A].scale, 1.4f), "placement round trip");
    CHECK(t.presets[1].place[HC_DPAD].hidden && !t.presets[1].place[HC_B].placed, "hidden round trip, untouched stays default");
    CHECK(near(t.presets[4].place[HC_RT].scale, 0.8f) && t.presets[4].place[HC_RT].placed, "second preset round trip");
    CHECK(!strcmp(t.presets[0].name, "Classic Xbox"), "other names stay");

    /* names: control characters, newlines (which would break the file format), length, UTF-8 safety */
    char name[HS_NAME_MAX + 1];
    hs_set_name(name, "Line1\nLine2\tTab\r");
    CHECK(!strchr(name, '\n') && !strchr(name, '\t') && !strchr(name, '\r') && !strcmp(name, "Line1Line2Tab"), "control characters removed: '%s'", name);
    hs_set_name(name, "abcdefghijklmnopqrstuvwxyz0123456789");
    CHECK(strlen(name) == HS_NAME_MAX && !strncmp(name, "abcdefghijklmnopqrstuvwx", 24), "long names are cut to %d bytes", HS_NAME_MAX);
    hs_set_name(name, "aaaaaaaaaaaaaaaaaaaaaaañ"); /* 23 a's then a 2-byte character: cutting at 24 would split it */
    CHECK(strlen(name) == 23, "multi-byte character is dropped whole, length %zu", strlen(name));
    hs_set_name(name, "   ");
    CHECK(name[0] == 0, "blank name is empty");
    hs_set_name(name, NULL);
    CHECK(name[0] == 0, "NULL name");
    /* a name containing '=' or the header survives the file format */
    hs_defaults(&s);
    hs_set_name(s.presets[2].name, "a=b HALO1");
    hs_serialize(&s, text, sizeof(text));
    hs_parse(&t, text);
    CHECK(!strcmp(t.presets[2].name, "a=b HALO1"), "equals sign in a name: '%s'", t.presets[2].name);

    /* hostile or damaged data: defaults for anything unreadable, everything clamped */
    CHECK(hs_parse(&t, "garbage") == 0 && !strcmp(t.presets[0].name, "Classic Xbox"), "no header gives defaults");
    CHECK(hs_parse(&t, NULL) == 0, "NULL text");
    hs_parse(&t, "HALO1\nactive=99\nvolume=7\np0.opacity=-4\np0.sens=1e30\np0.dead=nan\np0.c.a=1,9,-9,50,7\np9.name=x\nunknown=1\nno equals line\n\n");
    CHECK(t.active == 4 && t.volume == 1.0f, "global clamps (%d, %f)", t.active, t.volume);
    CHECK(near(t.presets[0].opacity, 0.25f) && near(t.presets[0].look_sensitivity, 3.0f) && near(t.presets[0].stick_dead_zone, 0.0f), "preset clamps");
    CHECK(t.presets[0].place[HC_A].fx == 1.0f && t.presets[0].place[HC_A].fy == 0.0f && near(t.presets[0].place[HC_A].scale, 1.8f) && t.presets[0].place[HC_A].hidden == 1, "placement clamps");
    char huge[40000];
    memset(huge, 'x', sizeof(huge)); memcpy(huge, "HALO1\n", 6); huge[sizeof(huge) - 1] = 0;
    hs_parse(&t, huge);
    CHECK(!strcmp(t.presets[0].name, "Classic Xbox"), "one enormous line is skipped");
    char tiny[8];
    hs_defaults(&s);
    CHECK(hs_serialize(&s, tiny, sizeof(tiny)) == -1, "too small a buffer is reported");

    /* layout: presets move, scale and hide controls, always inside the safe area */
    float left = 47, top = 0, right = 844 - 47, bottom = 390 - 21;
    HcControl base[HC_COUNT], c[HC_COUNT];
    hc_layout(left, top, right, bottom, base);
    hs_defaults(&s);
    memcpy(c, base, sizeof(c));
    hs_apply_preset(&s.presets[0], left, top, right, bottom, c);
    CHECK(!memcmp(base, c, sizeof(c)), "the default preset leaves the standard layout alone");
    HsPreset *p = &s.presets[1];
    hs_place_control(p, HC_A, 700, 200, left, top, right, bottom);
    p->place[HC_A].scale = 1.5f;
    p->place[HC_DPAD].hidden = 1;
    p->place[HC_RT].placed = 1; p->place[HC_RT].fx = 2.0f; p->place[HC_RT].fy = -3.0f; /* clamped by sanitize */
    hs_sanitize(&s);
    memcpy(c, base, sizeof(c));
    hs_apply_preset(p, left, top, right, bottom, c);
    CHECK(near(hc_cx(c[HC_A].r), 700) && near(hc_cy(c[HC_A].r), 200) && near(c[HC_A].r.w, base[HC_A].r.w * 1.5f), "A moved and scaled");
    CHECK(c[HC_DPAD].hidden && hc_hit(c, hc_cx(c[HC_DPAD].r), hc_cy(c[HC_DPAD].r), 1.0f) != HC_DPAD, "hidden control cannot be hit");
    for (int i = 0; i < HC_COUNT; i++)
        CHECK(c[i].r.x >= left - 0.01f && c[i].r.y >= top - 0.01f && c[i].r.x + c[i].r.w <= right + 0.01f && c[i].r.y + c[i].r.h <= bottom + 0.01f,
              "control %d stays inside the safe area", i);
    /* dragging to a corner and beyond cannot push it off screen */
    HsPreset q; hs_default_preset(&q, 0);
    hs_place_control(&q, HC_LSTICK, -500, 9000, left, top, right, bottom);
    q.place[HC_LSTICK].scale = 1.8f;
    memcpy(c, base, sizeof(c));
    hs_apply_preset(&q, left, top, right, bottom, c);
    CHECK(c[HC_LSTICK].r.x >= left && c[HC_LSTICK].r.y + c[HC_LSTICK].r.h <= bottom + 0.01f, "dragged-away stick is clamped on screen");
    hs_reset_layout(p);
    CHECK(!p->place[HC_A].placed && p->place[HC_A].scale == 1.0f && !p->place[HC_DPAD].hidden, "reset layout");
    /* the same placement on a different screen lands in the same relative spot */
    float l2 = 0, t2 = 0, r2 = 1366, b2 = 1004;
    HcControl big[HC_COUNT]; hc_layout(l2, t2, r2, b2, big);
    HsPreset z; hs_default_preset(&z, 0); hs_place_control(&z, HC_Y, 0.25f * (right - left) + left, 0.5f * (bottom - top) + top, left, top, right, bottom);
    hs_apply_preset(&z, l2, t2, r2, b2, big);
    CHECK(near(hc_cx(big[HC_Y].r) / (r2 - l2), 0.25f) && near(hc_cy(big[HC_Y].r) / (b2 - t2), 0.5f), "placement is relative to the screen");

    /* stick feel */
    HcRect ring = hc_rect(0, 0, 100, 100);
    int ax, ay;
    hc_stick_ex(ring, 50 + 45, 50, 0.08f, 1.0f, NULL, NULL, &ax, &ay);
    CHECK(ax == 32767 && ay == 0, "full deflection at 90%% of the radius, got %d", ax);
    int lin, curved;
    hc_stick_ex(ring, 50 + 22, 50, 0.08f, 1.0f, NULL, NULL, &lin, &ay);
    hc_stick_ex(ring, 50 + 22, 50, 0.08f, 2.0f, NULL, NULL, &curved, &ay);
    CHECK(curved < lin && curved > 0, "a curve gives finer control near the centre (%d vs %d)", curved, lin);
    hc_stick_ex(ring, 50 + 3, 50, 0.08f, 1.0f, NULL, NULL, &ax, &ay);
    CHECK(ax == 0, "inside the dead zone");
    hc_stick_ex(ring, 50 + 3, 50, 0.0f, 1.0f, NULL, NULL, &ax, &ay);
    CHECK(ax > 0, "no dead zone when set to 0");
    HcRect float_base = hc_floating_base(hc_circle(100, 300, 100), 10, 380, 0, 0, 800, 390);
    CHECK(near(hc_cx(float_base), 50) && near(hc_cy(float_base), 340), "floating ring is kept inside the safe area (%.1f,%.1f)", hc_cx(float_base), hc_cy(float_base));
    float_base = hc_floating_base(hc_circle(100, 300, 100), 200, 250, 0, 0, 800, 390);
    CHECK(near(hc_cx(float_base), 200) && near(hc_cy(float_base), 250), "floating ring follows the thumb");

    if (!failures) printf("PASS: settings core: 5 named presets round-trip, hostile input is clamped, layouts stay on screen, stick feel\n");
    return failures ? 1 : 0;
}
