#ifndef HALO_SETTINGS_CORE_H
#define HALO_SETTINGS_CORE_H

/*
 * Control schemes (5 presets with names) and the other settings, in plain C so
 * tools/tests/test_ios_settings_core.c can check saving, loading and layout on any
 * machine. The Objective-C side stores hs_serialize()'s text in NSUserDefaults.
 *
 * A preset is a whole control scheme: where every control sits, how big it is,
 * which are hidden, plus the aim settings (touch-look, sensitivity, stick feel).
 * Audio and multiplayer settings are shared by all presets.
 */

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "halo_controls_layout.h"

#define HS_PRESET_COUNT 5
#define HS_NAME_MAX 24 /* bytes, not counting the terminator */

typedef struct
{
    int placed;  /* 0: the default position for this screen */
    float fx, fy; /* centre as a fraction of the safe area */
    float scale;  /* 0.6 ... 1.8 */
    int hidden;
} HsPlacement;

typedef struct
{
    char name[HS_NAME_MAX + 1];
    HsPlacement place[HC_COUNT];
    float opacity;            /* 0.25 ... 1.0 */
    int touch_look;           /* drag on empty screen to look */
    float look_sensitivity;   /* 0.25 ... 3.0 */
    int invert_look_y;
    int floating_sticks;      /* the stick centres where the thumb lands */
    float stick_dead_zone;    /* 0 ... 0.4 */
    float move_curve;         /* 1 ... 3 */
    float look_curve;         /* 1 ... 3 */
    int haptics;
} HsPreset;

typedef struct
{
    int active;               /* 0 ... 4 */
    HsPreset presets[HS_PRESET_COUNT];
    float volume;             /* 0 ... 1 */
    int audio_enabled;
    int join_from_clipboard;  /* look at the clipboard for an invite when returning to the game */
    int show_fps;
    int smooth_fps;           /* draw a frame per display refresh (60) instead of the original 30; applies at launch */
    int hires_hud;            /* build 73: the HUD from the high-res assets; applies at launch */
    int hires_text;           /* build 73: menu and HUD text from the Overpass fonts at display resolution; applies at launch */
    int profiler;             /* sample the game thread for the log (about 1% of one core) */
} HsSettings;

static inline float hs_clampf(float v, float lo, float hi)
{
    if (!(v == v)) return lo; /* NaN */
    return v < lo ? lo : (v > hi ? hi : v);
}

static inline int hs_clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

/* A name: no control characters, trimmed, at most HS_NAME_MAX bytes and never a split UTF-8 character. */
static inline void hs_set_name(char out[HS_NAME_MAX + 1], const char *name)
{
    char clean[256];
    size_t n = 0;

    for (const unsigned char *c = (const unsigned char *)(name ? name : ""); *c && n < sizeof(clean) - 1; c++)
        if (*c >= 0x20 && *c != 0x7f)
            clean[n++] = (char)*c;
    clean[n] = 0;
    size_t start = 0;
    while (start < n && clean[start] == ' ') start++;
    while (n > start && clean[n - 1] == ' ') n--;
    size_t length = n - start;
    if (length > HS_NAME_MAX)
    {
        length = HS_NAME_MAX;
        /* back up over continuation bytes so a multi-byte character is not cut in half */
        while (length > 0 && ((unsigned char)clean[start + length] & 0xC0) == 0x80) length--;
    }
    memcpy(out, clean + start, length);
    out[length] = 0;
}

static inline void hs_default_preset(HsPreset *p, int index)
{
    static const char *names[HS_PRESET_COUNT] = { "Classic Xbox", "Preset 2", "Preset 3", "Preset 4", "Preset 5" };

    memset(p, 0, sizeof(*p));
    hs_set_name(p->name, names[hs_clampi(index, 0, HS_PRESET_COUNT - 1)]);
    for (int i = 0; i < HC_COUNT; i++) p->place[i].scale = 1.0f;
    p->opacity = 0.85f;
    p->touch_look = 1;
    p->look_sensitivity = 1.0f;
    p->invert_look_y = 0;
    p->floating_sticks = 1;
    p->stick_dead_zone = 0.08f;
    p->move_curve = 1.0f;
    p->look_curve = 1.5f;
    p->haptics = 1;
}

static inline void hs_defaults(HsSettings *s)
{
    memset(s, 0, sizeof(*s));
    for (int i = 0; i < HS_PRESET_COUNT; i++) hs_default_preset(&s->presets[i], i);
    s->active = 0;
    s->volume = 1.0f;
    s->audio_enabled = 1;
    s->join_from_clipboard = 0; /* reading the clipboard shows an iOS paste prompt */
    s->show_fps = 0;
    s->profiler = 1;
    s->smooth_fps = 1;
    s->hires_hud = 0; /* off until the new code has run on a device; switches in Settings */
    s->hires_text = 0;
}

static inline void hs_sanitize_preset(HsPreset *p)
{
    char name[HS_NAME_MAX + 1];

    hs_set_name(name, p->name);
    memcpy(p->name, name, sizeof(name));
    for (int i = 0; i < HC_COUNT; i++)
    {
        p->place[i].placed = p->place[i].placed ? 1 : 0;
        p->place[i].fx = hs_clampf(p->place[i].fx, 0.0f, 1.0f);
        p->place[i].fy = hs_clampf(p->place[i].fy, 0.0f, 1.0f);
        p->place[i].scale = hs_clampf(p->place[i].scale, 0.6f, 1.8f);
        p->place[i].hidden = p->place[i].hidden ? 1 : 0;
    }
    p->opacity = hs_clampf(p->opacity, 0.25f, 1.0f);
    p->touch_look = p->touch_look ? 1 : 0;
    p->look_sensitivity = hs_clampf(p->look_sensitivity, 0.25f, 3.0f);
    p->invert_look_y = p->invert_look_y ? 1 : 0;
    p->floating_sticks = p->floating_sticks ? 1 : 0;
    p->stick_dead_zone = hs_clampf(p->stick_dead_zone, 0.0f, 0.4f);
    p->move_curve = hs_clampf(p->move_curve, 1.0f, 3.0f);
    p->look_curve = hs_clampf(p->look_curve, 1.0f, 3.0f);
    p->haptics = p->haptics ? 1 : 0;
}

static inline void hs_sanitize(HsSettings *s)
{
    for (int i = 0; i < HS_PRESET_COUNT; i++) hs_sanitize_preset(&s->presets[i]);
    s->active = hs_clampi(s->active, 0, HS_PRESET_COUNT - 1);
    s->volume = hs_clampf(s->volume, 0.0f, 1.0f);
    s->audio_enabled = s->audio_enabled ? 1 : 0;
    s->join_from_clipboard = s->join_from_clipboard ? 1 : 0;
    s->show_fps = s->show_fps ? 1 : 0;
    s->profiler = s->profiler ? 1 : 0;
    s->smooth_fps = s->smooth_fps ? 1 : 0;
    s->hires_hud = s->hires_hud ? 1 : 0;
    s->hires_text = s->hires_text ? 1 : 0;
}

/* ---------- layout: where the player's presets put the controls on this screen */

/* Moves and sizes the controls of `layout` (from hc_layout) as the preset says. A control never
 * leaves the safe area and never gets smaller than a thumb can hit. */
static inline void hs_apply_preset(const HsPreset *preset, float left, float top, float right, float bottom,
                                   HcControl controls[HC_COUNT])
{
    float width = right - left, height = bottom - top;

    for (int i = 0; i < HC_COUNT; i++)
    {
        const HsPlacement *p = &preset->place[i];
        HcRect r = controls[i].r;
        float cx = hc_cx(r), cy = hc_cy(r);

        controls[i].hidden = p->hidden;
        if (!p->placed && p->scale == 1.0f)
            continue; /* untouched: the standard position, bit for bit */
        if (p->scale != 1.0f)
        {
            r.w *= p->scale; r.h *= p->scale;
        }
        if (p->placed)
        {
            cx = left + p->fx * width;
            cy = top + p->fy * height;
        }
        r.x = cx - r.w * 0.5f; r.y = cy - r.h * 0.5f;
        /* keep the whole control on screen */
        if (r.x < left) r.x = left;
        if (r.y < top) r.y = top;
        if (r.x + r.w > right) r.x = right - r.w;
        if (r.y + r.h > bottom) r.y = bottom - r.h;
        controls[i].r = r;
    }
}

/* Records a control's new centre (from dragging) as fractions of the safe area. */
static inline void hs_place_control(HsPreset *preset, int control, float cx, float cy,
                                    float left, float top, float right, float bottom)
{
    HsPlacement *p = &preset->place[hs_clampi(control, 0, HC_COUNT - 1)];

    p->placed = 1;
    p->fx = hs_clampf((cx - left) / (right - left), 0.0f, 1.0f);
    p->fy = hs_clampf((cy - top) / (bottom - top), 0.0f, 1.0f);
}

static inline void hs_reset_layout(HsPreset *preset)
{
    for (int i = 0; i < HC_COUNT; i++)
    {
        preset->place[i].placed = 0;
        preset->place[i].scale = 1.0f;
        preset->place[i].hidden = 0;
    }
}

/* ---------- saving and loading: one text blob of key=value lines */

static const char *const hs_control_keys[HC_COUNT] = {
    "lt", "rt", "back", "start", "ls", "rs", "a", "b", "x", "y", "white", "black", "dpad", "lstick", "rstick"
};

static inline int hs_serialize(const HsSettings *s, char *out, size_t size)
{
    size_t n = 0;
#define EMIT(...) do { int w = snprintf(out + n, n < size ? size - n : 0, __VA_ARGS__); if (w < 0) return -1; n += (size_t)w; } while (0)
    EMIT("HALO1\n");
    EMIT("active=%d\nvolume=%.3f\naudio=%d\nclipboard=%d\nfps=%d\nprofiler=%d\nsmooth=%d\nhireshud=%d\nhirestext=%d\n", s->active, s->volume, s->audio_enabled,
         s->join_from_clipboard, s->show_fps, s->profiler, s->smooth_fps, s->hires_hud, s->hires_text);
    for (int i = 0; i < HS_PRESET_COUNT; i++)
    {
        const HsPreset *p = &s->presets[i];

        EMIT("p%d.name=%s\n", i, p->name);
        EMIT("p%d.opacity=%.3f\np%d.look=%d\np%d.sens=%.3f\np%d.invert=%d\np%d.float=%d\n", i, p->opacity, i, p->touch_look,
             i, p->look_sensitivity, i, p->invert_look_y, i, p->floating_sticks);
        EMIT("p%d.dead=%.3f\np%d.movecurve=%.3f\np%d.lookcurve=%.3f\np%d.haptics=%d\n", i, p->stick_dead_zone, i, p->move_curve,
             i, p->look_curve, i, p->haptics);
        for (int c = 0; c < HC_COUNT; c++)
        {
            const HsPlacement *q = &p->place[c];

            if (q->placed || q->scale != 1.0f || q->hidden)
                EMIT("p%d.c.%s=%d,%.4f,%.4f,%.3f,%d\n", i, hs_control_keys[c], q->placed, q->fx, q->fy, q->scale, q->hidden);
        }
    }
#undef EMIT
    return n < size ? (int)n : -1;
}

/* Unknown or malformed lines are ignored; whatever is read is clamped. Returns 1 if the text had the header. */
static inline int hs_parse(HsSettings *s, const char *text)
{
    hs_defaults(s);
    if (!text || strncmp(text, "HALO1\n", 6) != 0)
        return 0;
    const char *cursor = text + 6;

    while (*cursor)
    {
        const char *end = strchr(cursor, '\n');
        size_t length = end ? (size_t)(end - cursor) : strlen(cursor);
        char line[160];
        char *equals;

        if (length < sizeof(line))
        {
            memcpy(line, cursor, length);
            line[length] = 0;
            equals = strchr(line, '=');
            if (equals)
            {
                const char *value = equals + 1;
                *equals = 0;
                const char *key = line;
                int index;

                if (!strcmp(key, "active")) s->active = atoi(value);
                else if (!strcmp(key, "volume")) s->volume = (float)atof(value);
                else if (!strcmp(key, "audio")) s->audio_enabled = atoi(value);
                else if (!strcmp(key, "clipboard")) s->join_from_clipboard = atoi(value);
                else if (!strcmp(key, "fps")) s->show_fps = atoi(value);
                else if (!strcmp(key, "profiler")) s->profiler = atoi(value);
                else if (!strcmp(key, "smooth")) s->smooth_fps = atoi(value);
                else if (!strcmp(key, "hireshud")) s->hires_hud = atoi(value);
                else if (!strcmp(key, "hirestext")) s->hires_text = atoi(value);
                else if (key[0] == 'p' && key[1] >= '0' && key[1] < '0' + HS_PRESET_COUNT && key[2] == '.')
                {
                    HsPreset *p = &s->presets[key[1] - '0'];
                    const char *field = key + 3;

                    if (!strcmp(field, "name")) hs_set_name(p->name, value);
                    else if (!strcmp(field, "opacity")) p->opacity = (float)atof(value);
                    else if (!strcmp(field, "look")) p->touch_look = atoi(value);
                    else if (!strcmp(field, "sens")) p->look_sensitivity = (float)atof(value);
                    else if (!strcmp(field, "invert")) p->invert_look_y = atoi(value);
                    else if (!strcmp(field, "float")) p->floating_sticks = atoi(value);
                    else if (!strcmp(field, "dead")) p->stick_dead_zone = (float)atof(value);
                    else if (!strcmp(field, "movecurve")) p->move_curve = (float)atof(value);
                    else if (!strcmp(field, "lookcurve")) p->look_curve = (float)atof(value);
                    else if (!strcmp(field, "haptics")) p->haptics = atoi(value);
                    else if (!strncmp(field, "c.", 2))
                    {
                        for (index = 0; index < HC_COUNT; index++)
                        {
                            if (!strcmp(field + 2, hs_control_keys[index]))
                            {
                                HsPlacement *q = &p->place[index];
                                int placed = 0, hidden = 0;
                                float fx = 0, fy = 0, scale = 1;

                                if (sscanf(value, "%d,%f,%f,%f,%d", &placed, &fx, &fy, &scale, &hidden) == 5)
                                {
                                    q->placed = placed; q->fx = fx; q->fy = fy; q->scale = scale; q->hidden = hidden;
                                }
                                break;
                            }
                        }
                    }
                }
            }
        }
        if (!end)
            break;
        cursor = end + 1;
    }
    hs_sanitize(s);
    return 1;
}

#endif
