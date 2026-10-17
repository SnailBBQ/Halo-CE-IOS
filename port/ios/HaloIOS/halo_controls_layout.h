#ifndef HALO_CONTROLS_LAYOUT_H
#define HALO_CONTROLS_LAYOUT_H

/*
 * Original-Xbox controller layout for the on-screen controls: geometry and
 * input math only, in plain C so tools/tests/test_ios_controls_layout.c can
 * check it on any machine. Coordinates are points, y grows downwards.
 *
 * Button and axis numbers are SDL3's, which is what the guest's SDL gamepad
 * layer (port/linux/src/xinput_sdl.c) reads.
 */

#include <math.h>

enum { HC_AXIS_LX = 0, HC_AXIS_LY = 1, HC_AXIS_RX = 2, HC_AXIS_RY = 3, HC_AXIS_LT = 4, HC_AXIS_RT = 5 };

enum {
    HC_BTN_A = 0, HC_BTN_B = 1, HC_BTN_X = 2, HC_BTN_Y = 3, HC_BTN_BACK = 4, HC_BTN_START = 6,
    HC_BTN_LSTICK = 7, HC_BTN_RSTICK = 8,
    HC_BTN_WHITE = 9,  /* SDL left shoulder: the guest maps it to White */
    HC_BTN_BLACK = 10, /* SDL right shoulder: the guest maps it to Black */
    HC_BTN_DPAD_UP = 11, HC_BTN_DPAD_DOWN = 12, HC_BTN_DPAD_LEFT = 13, HC_BTN_DPAD_RIGHT = 14
};

enum { HC_KIND_CIRCLE = 0, HC_KIND_PILL = 1, HC_KIND_DPAD = 2, HC_KIND_STICK = 3 };
enum { HC_COLOR_GRAY = 0, HC_COLOR_GREEN, HC_COLOR_RED, HC_COLOR_BLUE, HC_COLOR_YELLOW, HC_COLOR_BLACK, HC_COLOR_WHITE, HC_COLOR_PINK };

/* control indices */
enum {
    HC_LT = 0, HC_RT, HC_BACK, HC_START, HC_LS, HC_RS,
    HC_A, HC_B, HC_X, HC_Y, HC_WHITE, HC_BLACK,
    HC_DPAD, HC_LSTICK, HC_RSTICK,
    HC_VOICE,   /* voice chat: Push to talk, or Mute in open mic; shown only while the microphone is on */
    HC_COUNT
};

typedef struct { float x, y, w, h; } HcRect;

typedef struct {
    int kind;
    HcRect r;
    int button;       /* SDL button for circles and pills, -1 if none */
    int axis;         /* trigger axis for LT/RT; first (X) axis for sticks; else -1 */
    int color;
    const char *label;
    const char *sub;  /* small second line, or "" */
    int hidden;       /* the player chose to hide it */
} HcControl;

static inline HcRect hc_rect(float x, float y, float w, float h) { HcRect r = { x, y, w, h }; return r; }
static inline float hc_cx(HcRect r) { return r.x + r.w * 0.5f; }
static inline float hc_cy(HcRect r) { return r.y + r.h * 0.5f; }
static inline HcRect hc_circle(float cx, float cy, float d) { return hc_rect(cx - d * 0.5f, cy - d * 0.5f, d, d); }

static inline float hc_scale(float left, float top, float right, float bottom)
{
    float by_height = (bottom - top) / 360.0f;
    float by_width = (right - left) / 760.0f;
    float s = by_height < by_width ? by_height : by_width;
    if (s < 0.70f) s = 0.70f;
    if (s > 1.40f) s = 1.40f;
    return s;
}

static inline void hc_set(HcControl *c, int kind, HcRect r, int button, int axis, int color,
                          const char *label, const char *sub)
{
    c->kind = kind; c->r = r; c->button = button; c->axis = axis; c->color = color;
    c->label = label; c->sub = sub; c->hidden = 0;
}

/* Lays every control out inside the safe rectangle; returns the scale used. */
static inline float hc_layout(float left, float top, float right, float bottom, HcControl out[HC_COUNT])
{
    float s = hc_scale(left, top, right, bottom);
    float m = 14.0f * s;
    float stick = 124.0f * s;
    float cx_left = left + m + stick * 0.5f + 6.0f * s;
    float cx_right = right - m - stick * 0.5f - 6.0f * s;
    float cy = bottom - m - stick * 0.5f;
    float face = 56.0f * s, spread = 44.0f * s;
    float pill_w = 92.0f * s, pill_h = 44.0f * s;
    float small_w = 80.0f * s, small_h = 40.0f * s;
    float mid = (left + right) * 0.5f;

    hc_set(&out[HC_LSTICK], HC_KIND_STICK, hc_circle(cx_left, cy, stick), -1, HC_AXIS_LX, HC_COLOR_GRAY, "", "");
    hc_set(&out[HC_RSTICK], HC_KIND_STICK, hc_circle(cx_right, cy, stick), -1, HC_AXIS_RX, HC_COLOR_GRAY, "", "");

    /* triggers in the top corners */
    hc_set(&out[HC_LT], HC_KIND_PILL, hc_rect(left + m, top + 8.0f * s, pill_w, pill_h), -1, HC_AXIS_LT, HC_COLOR_GRAY, "LT", "GRENADE");
    hc_set(&out[HC_RT], HC_KIND_PILL, hc_rect(right - m - pill_w, top + 8.0f * s, pill_w, pill_h), -1, HC_AXIS_RT, HC_COLOR_GRAY, "RT", "FIRE");

    /* stick clicks beside their sticks, on the inside */
    hc_set(&out[HC_LS], HC_KIND_PILL, hc_rect(cx_left + stick * 0.5f + 10.0f * s, cy + stick * 0.5f - small_h, small_w, small_h),
           HC_BTN_LSTICK, -1, HC_COLOR_GRAY, "LS", "CROUCH");
    hc_set(&out[HC_RS], HC_KIND_PILL, hc_rect(cx_right - stick * 0.5f - 10.0f * s - small_w, cy + stick * 0.5f - small_h, small_w, small_h),
           HC_BTN_RSTICK, -1, HC_COLOR_GRAY, "RS", "ZOOM");

    /* Back and Start low in the middle, the voice button between them */
    {
        float w = 68.0f * s, h = 32.0f * s, gap = 10.0f * s, vw = 52.0f * s;
        float y = bottom - m - h;
        hc_set(&out[HC_BACK], HC_KIND_PILL, hc_rect(mid - vw * 0.5f - gap - w, y, w, h), HC_BTN_BACK, -1, HC_COLOR_GRAY, "BACK", "");
        hc_set(&out[HC_VOICE], HC_KIND_PILL, hc_rect(mid - vw * 0.5f, y, vw, h), -1, -1, HC_COLOR_GRAY, "TALK", "");
        hc_set(&out[HC_START], HC_KIND_PILL, hc_rect(mid + vw * 0.5f + gap, y, w, h), HC_BTN_START, -1, HC_COLOR_GRAY, "START", "");
    }

    /* A/B/X/Y diamond above the right stick, as on the Xbox S pad */
    {
        float dcy = cy - stick * 0.5f - 10.0f * s - (spread + face * 0.5f);
        hc_set(&out[HC_Y], HC_KIND_CIRCLE, hc_circle(cx_right, dcy - spread, face), HC_BTN_Y, -1, HC_COLOR_YELLOW, "Y", "");
        hc_set(&out[HC_A], HC_KIND_CIRCLE, hc_circle(cx_right, dcy + spread, face), HC_BTN_A, -1, HC_COLOR_GREEN, "A", "");
        hc_set(&out[HC_X], HC_KIND_CIRCLE, hc_circle(cx_right - spread, dcy, face), HC_BTN_X, -1, HC_COLOR_BLUE, "X", "");
        hc_set(&out[HC_B], HC_KIND_CIRCLE, hc_circle(cx_right + spread, dcy, face), HC_BTN_B, -1, HC_COLOR_RED, "B", "");
    }

    /* White and Black, small, stacked left of the right stick */
    {
        float d = 46.0f * s, x = cx_right - stick * 0.5f - 50.0f * s;
        hc_set(&out[HC_WHITE], HC_KIND_CIRCLE, hc_circle(x, cy - 4.0f * s, d), HC_BTN_WHITE, -1, HC_COLOR_WHITE, "WHITE", "");
        hc_set(&out[HC_BLACK], HC_KIND_CIRCLE, hc_circle(x, cy - 4.0f * s - d - 8.0f * s, d), HC_BTN_BLACK, -1, HC_COLOR_BLACK, "BLACK", "");
    }

    /* D-pad above the left stick */
    {
        float size = 108.0f * s;
        hc_set(&out[HC_DPAD], HC_KIND_DPAD, hc_circle(cx_left, cy - stick * 0.5f - 10.0f * s - size * 0.5f, size), -1, -1, HC_COLOR_GRAY, "", "");
    }
    return s;
}

/* Bounding box a control is drawn in (pills and circles: their rect). */
static inline HcRect hc_bounds(const HcControl *c) { return c->r; }

/* Touch target: the drawn rect grown by a margin; sticks get a generous radius. */
static inline int hc_contains(const HcControl *c, float x, float y, float s)
{
    float pad = (c->kind == HC_KIND_STICK ? 18.0f : 7.0f) * s;
    HcRect r = c->r;
    if (c->hidden)
        return 0;
    if (c->kind == HC_KIND_CIRCLE || c->kind == HC_KIND_STICK) {
        float dx = x - hc_cx(r), dy = y - hc_cy(r), rad = r.w * 0.5f + pad;
        return dx * dx + dy * dy <= rad * rad;
    }
    return x >= r.x - pad && x <= r.x + r.w + pad && y >= r.y - pad && y <= r.y + r.h + pad;
}

/* Index of the control a new touch belongs to (nearest centre wins), or -1. */
static inline int hc_hit(const HcControl *controls, float x, float y, float s)
{
    int best = -1;
    float best_d = 1e30f;
    for (int i = 0; i < HC_COUNT; i++) {
        if (!hc_contains(&controls[i], x, y, s)) continue;
        float dx = x - hc_cx(controls[i].r), dy = y - hc_cy(controls[i].r);
        float d = dx * dx + dy * dy;
        if (d < best_d) { best_d = d; best = i; }
    }
    return best;
}

/* Stick position: knob offset (clamped to the base radius) and SDL axis values.
 * SDL's Y axis grows downwards like the screen, so no flip is needed.
 * `dead` is the dead zone as a fraction of the radius (0...0.4) and `curve` the response
 * exponent: 1 is linear, above 1 gives finer control near the centre. Full deflection is
 * reached at 90% of the radius so a thumb never has to reach the very edge. */
static inline void hc_stick_ex(HcRect base, float x, float y, float dead, float curve,
                               float *knob_dx, float *knob_dy, int *axis_x, int *axis_y)
{
    float radius = base.w * 0.5f;
    float dx = x - hc_cx(base), dy = y - hc_cy(base);
    float d = sqrtf(dx * dx + dy * dy);
    if (d > radius && d > 0.0f) { dx *= radius / d; dy *= radius / d; d = radius; }
    float n = radius > 0.0f ? d / (radius * 0.9f) : 0.0f;
    if (n > 1.0f) n = 1.0f;
    if (dead < 0.0f) dead = 0.0f;
    if (dead > 0.4f) dead = 0.4f;
    if (curve < 1.0f) curve = 1.0f;
    if (curve > 3.0f) curve = 3.0f;
    float m = n < dead ? 0.0f : (n - dead) / (1.0f - dead);
    if (m > 0.0f && curve != 1.0f) m = powf(m, curve);
    if (knob_dx) *knob_dx = dx;
    if (knob_dy) *knob_dy = dy;
    if (d <= 0.0f || m <= 0.0f) { *axis_x = 0; *axis_y = 0; return; }
    *axis_x = (int)lroundf(dx / d * m * 32767.0f);
    *axis_y = (int)lroundf(dy / d * m * 32767.0f);
}

static inline void hc_stick(HcRect base, float x, float y, float *knob_dx, float *knob_dy, int *axis_x, int *axis_y)
{
    hc_stick_ex(base, x, y, 0.08f, 1.0f, knob_dx, knob_dy, axis_x, axis_y);
}

/* A floating stick re-centres where the thumb lands; the ring is kept inside the safe area. */
static inline HcRect hc_floating_base(HcRect base, float x, float y, float left, float top, float right, float bottom)
{
    float half = base.w * 0.5f;
    float cx = x, cy = y;
    if (cx < left + half) cx = left + half;
    if (cx > right - half) cx = right - half;
    if (cy < top + half) cy = top + half;
    if (cy > bottom - half) cy = bottom - half;
    return hc_circle(cx, cy, base.w);
}

/* D-pad directions as a bit mask over SDL button indices (bit = button - 11). */
static inline unsigned hc_dpad_mask(HcRect r, float x, float y)
{
    float ux = (x - hc_cx(r)) / (r.w * 0.5f), uy = (y - hc_cy(r)) / (r.h * 0.5f);
    unsigned mask = 0;
    if (sqrtf(ux * ux + uy * uy) < 0.20f) return 0;
    if (uy < -0.38f) mask |= 1u << 0; /* up */
    if (uy > 0.38f) mask |= 1u << 1;  /* down */
    if (ux < -0.38f) mask |= 1u << 2; /* left */
    if (ux > 0.38f) mask |= 1u << 3;  /* right */
    return mask;
}

#endif
