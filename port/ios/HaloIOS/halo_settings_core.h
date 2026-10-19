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
    float opacity; /* independent control opacity, multiplied by preset opacity */
} HsPlacement;

typedef struct
{
    char name[HS_NAME_MAX + 1];
    HsPlacement place[HC_COUNT];
    float opacity;            /* 0.25 ... 1.0 */
    int auto_fire, fire_drag, stick_fire; /* opt-in touch aiming, saved per profile */
    int touch_look;           /* drag on empty screen to look */
    float look_sensitivity;   /* 0.25 ... 3.0 */
    int invert_look_y;
    int floating_sticks;      /* the stick centres where the thumb lands */
    float stick_dead_zone;    /* 0 ... 0.4 */
    float move_curve;         /* 1 ... 3 */
    float look_curve;         /* 1 ... 3 */
    int haptics;
    int hud_choice; /* 0 Default, 1..3 saved HUD recipe; never edits recipes */
    int startup_auto; /* launch immediately when maps are ready */
    int face_style; /* 0 Xbox, 1 PlayStation; input mapping is unchanged */
    unsigned cheat_flags, cheat_actions;
    int cheat_alliance, cheat_projectile;
    float cheat_jump, cheat_speed, cheat_fov;
    int cheat_weapon; /* 0 none, 1..10 weapon choices */
    int cheat_slow;           /* recipe: 0 off, 1..7 = 75, 50, 25, 10, 150, 200, 300 percent game speed */
    int mirror;               /* left-handed: the whole touch layout is mirrored left to right */
    unsigned toggle_mask;     /* bit n: control n latches on a tap instead of being held (buttons only) */
    int gyro;                 /* aim by turning the device */
    float gyro_sens;          /* 0.25 ... 3 */
    int gyro_flip_yaw, gyro_flip_pitch;
} HsPreset;

/* the touch buttons that can latch: the face buttons, the stick clicks (crouch and zoom) and the shoulders */
#define HS_TOGGLE_ALLOWED ((1u<<HC_A)|(1u<<HC_B)|(1u<<HC_X)|(1u<<HC_Y)|(1u<<HC_LS)|(1u<<HC_RS)|(1u<<HC_WHITE)|(1u<<HC_BLACK))

#define HS_HUD_COUNT 5
/* FPS, weapon HUD, health/shields/radar, navigation, damage indicators.
 * Offsets are fractions of the game viewport; groupings follow engine draw ownership. */
typedef struct { float x,y,scale,opacity; int hidden; } HsHud;
typedef struct { char name[HS_NAME_MAX+1]; HsHud elements[HS_HUD_COUNT]; } HsHudPreset;
typedef struct { char sequence[96]; float gap, total; int action; } HsShortcut;
typedef struct
{
    HsShortcut shortcuts[4]; /* 0 Settings visibility, 1..3 campaign modifiers */
    int game_vsync, game_online, game_upnp, game_player_names;
    int game_controls[8]; /* sensitivity, invert, flight, autocenter, buttons, sticks, vibration, help */
    char game_name[24]; int game_color, game_profile_ready;
    float gear_opacity; int gear_icon;   /* 0..3 symbols, 4 the older photo, 5 gear_token */
    char gear_token[40];      /* "e:<emoji>" or "p:<8 hex>" when gear_icon is 5 */
    char gear_favs[100];      /* favourite icons: tokens ("s0".."s3", "e:..", "p:..") separated by | */
    float gear_scale; int ui_theme; /* shared Options; theme indexes 0..4 */
    int gear_placed; float gear_x, gear_y; /* safe-area fractions */
    HsHud hud[HS_HUD_COUNT];
    HsHudPreset hud_presets[3];
    float music_volume, dialogue_volume, effects_volume;
    int cheat_camo, cheat_overshield;
    int cheat_alliance, cheat_projectile;
    int cheat_detach_camera;
    int cheat_wireframe, cheat_hijack_vehicle;
    int cheat_medusa, cheat_low_gravity, cheat_hijack_npc, cheat_vehicle_health;
    int cheat_jetpack, cheat_ai_ignore, cheat_slow;   /* session cheats; cheat_slow: 0 normal, 1..7 */
    int accent_mode; unsigned accent_rgb; float chroma_seconds; /* 0 preset colour, 1 chosen colour, 2 colour cycle */
    int maps_show_files, maps_mp_alpha, maps_mp_only;          /* Mods: files shown; maps_mp_alpha is no longer used; maps_mp_only lists only multiplayer maps, A-Z */
    int maps_campaign_only;   /* Mods: only the campaign maps */
    int custom_hide, custom_filter; /* Custom Edition maps: list hidden; 0 all, 1 multiplayer A-Z, 2 campaign */
    float ambient_volume;     /* device and ambient sound classes */
    int perf_overlay, thermal_cap;
    int display_mode, render_quality; /* 0 4:3 / 1 16:9 / 2 screen aspect; 480 / 720 / 960 / 1080 lines */
    int menu_style;           /* 0 the PC menus (server browser, Direct Link, Create Game), 1 the Xbox menus; read at launch */
    float pad_dead, pad_curve; unsigned char pad_map[14]; /* physical controller: stick shaping and button remap */
    int active;               /* 0 ... 4 */
    HsPreset presets[HS_PRESET_COUNT];
    float volume;             /* 0 ... 1 */
    int audio_enabled;
    int join_from_clipboard;  /* look at the clipboard for an invite when returning to the game */
    int show_fps;
    int fps_mode;             /* 0 original 30, 1 smooth 60, 2 uncapped (the display's maximum); 0 vs the others applies at launch */
    int controls_mode;        /* on-screen controls: 0 auto (hidden while a controller is connected), 1 always, 2 never */
    int cheat_god;            /* campaign only: the game's deathless-player cheat */
    int cheat_ammo;           /* ... infinite ammo */
    int cheat_grenades;       /* ... infinite grenades */
    int cheat_reload;         /* ... no reloading (bottomless clip) */
    int cheat_one_hit;
    int cheat_flashlight;
    int cheat_no_fall;
    int cheat_rapid;
    int cheat_no_recoil;
    int cheat_third_person;
    int cheat_noclip;
    float cheat_jump, cheat_speed, cheat_fov; /* multipliers; vertical degrees, 0 = default */
    int viewmodel_mode;       /* 0 both, 1 weapon only, 2 hands only, 3 hidden; local rendering only */
    int hires_hud;            /* build 73: the HUD from the high-res assets; applies at launch */
    int hires_text;           /* build 73: menu and HUD text from the Overpass fonts at display resolution; applies at launch */
    int profiler;             /* sample the game thread for the log (about 1% of one core) */
    int voice_mode;           /* voice chat microphone: 0 off, 1 open mic, 2 push to talk (audio.voice_chat; synced with the in-game menu) */
    float voice_volume;       /* other players' voices, 0 ... 2 (audio.voice_volume) */
    int reverb;               /* the maps' sound environments (audio.reverb) */
    /* Video and multiplayer options shared with the in-game menus (config.toml's display.*, network.* and streamer.*); the slot
     * numbers and the values the engine takes are in halo_engine_settings.h */
    int aa_mode;              /* display.anti_aliasing: 0 off, 1 fxaa, 2 smaa, 3 ssaa2x, 4 msaa2x, 5 msaa4x, 6 msaa8x */
    int shadow_res;           /* display.shadow_resolution: 0 128, 1 256, 2 512, 3 1024 */
    int per_pixel, shield_glow, glow_light_show; /* per-pixel lighting; shield glow on; glow intensity 0 default, 1 light show */
    float fov, viewmodel_fov; /* display.fov and display.viewmodel_fov: 0 for the game's own, else 80 ... 150 */
    int vm_shield, legs;      /* the shield's flare on the arms; your legs in first person */
    int shield_color;         /* display.shield_color: 0 the shield's own, 1 ... 18 the multiplayer armor colors */
    float name_scale;         /* display.player_name_scale: 0.5 ... 2 */
    int sb_layout, sb_panel;  /* scoreboard: 0 by team, 1 by score; the panel behind it */
    int text_chat, chat_style;/* the text chat shown; 0 colored names, 1 all white */
    int streamer, streamer_slurs, streamer_swearing, streamer_insults; /* streamer.*: on; each filter 0 off, 1 severe, 2 strong, 3 mild */
    int cheat_target;         /* splitscreen campaign: the local player the cheats act on: 0 player 1, 1 player 2, 2 both */
} HsSettings;

/* Only changes to the active touch scheme may cancel an owned touch. Engine
 * audio, video, profile and cheat synchronization must not interrupt a hold.
 * Compare members explicitly: serialized structs may contain padding bytes. */
static inline int hs_touch_scheme_changed(const HsSettings *a, const HsSettings *b)
{
    if (a->active != b->active || a->controls_mode != b->controls_mode) return 1;
    const HsPreset *x=&a->presets[a->active], *y=&b->presets[b->active];
#define HS_TOUCH_DIFF(field) if (x->field != y->field) return 1
    HS_TOUCH_DIFF(opacity); HS_TOUCH_DIFF(auto_fire); HS_TOUCH_DIFF(fire_drag);
    HS_TOUCH_DIFF(stick_fire); HS_TOUCH_DIFF(touch_look); HS_TOUCH_DIFF(look_sensitivity);
    HS_TOUCH_DIFF(invert_look_y); HS_TOUCH_DIFF(floating_sticks); HS_TOUCH_DIFF(stick_dead_zone);
    HS_TOUCH_DIFF(move_curve); HS_TOUCH_DIFF(look_curve); HS_TOUCH_DIFF(haptics);
    HS_TOUCH_DIFF(face_style); HS_TOUCH_DIFF(mirror); HS_TOUCH_DIFF(toggle_mask);
    HS_TOUCH_DIFF(gyro); HS_TOUCH_DIFF(gyro_sens); HS_TOUCH_DIFF(gyro_flip_yaw); HS_TOUCH_DIFF(gyro_flip_pitch);
#undef HS_TOUCH_DIFF
    for (int i=0;i<HC_COUNT;i++) {
        const HsPlacement *p=&x->place[i], *q=&y->place[i];
        if (p->placed!=q->placed || p->fx!=q->fx || p->fy!=q->fy ||
            p->scale!=q->scale || p->hidden!=q->hidden || p->opacity!=q->opacity) return 1;
    }
    return 0;
}

/* Logical scene dimensions stay at 480 lines; target scale supplies extra detail.
 * The even width matches the renderer's surface requirements. Invalid metrics
 * fall back to the established 4:3 path, including NaN and zero-sized windows. */
static inline int hs_display_width(int mode, double width, double height)
{
    if (mode == 1) return 854;
    if (mode != 2 || !isfinite(width) || !isfinite(height) || width <= 0 || height <= 0) return 640;
    double short_side = fmin(width, height), long_side = fmax(width, height);
    double wanted = 480.0 * (long_side / short_side);
    if (wanted < 640) return 640;
    if (wanted > 1600) return 1600;
    return ((int)wanted) & ~1;
}
static inline double hs_render_scale(int quality) { return quality == 1 ? 1.5 : quality == 2 ? 2.0 : quality == 3 ? 2.25 : 1.0; }

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
    static const char *names[HS_PRESET_COUNT] = { "Classic Xbox UI", "Playstation UI", "Preset 3", "Preset 4", "Preset 5" };

    memset(p, 0, sizeof(*p));
    hs_set_name(p->name, names[hs_clampi(index, 0, HS_PRESET_COUNT - 1)]);
    for (int i = 0; i < HC_COUNT; i++) { p->place[i].scale = 1.0f; p->place[i].opacity=1.f; }
    p->opacity = 0.85f;
    p->touch_look = 1;
    p->look_sensitivity = 1.0f;
    p->invert_look_y = 0;
    p->floating_sticks = 1;
    p->stick_dead_zone = 0.08f;
    p->move_curve = 1.0f;
    p->look_curve = 1.5f;
    p->haptics = 1;
    p->face_style = index == 1;
    p->startup_auto = 1;
    p->cheat_jump = p->cheat_speed = 1.f;
    p->gyro_sens = 1.0f;
}

/* The mask the game reads (host_cheat_flags): 1 god mode, 2 infinite ammo, 4 infinite grenades, 8 no reloading. */
static inline unsigned hs_cheat_mask(const HsSettings *s)
{
    return (s->cheat_god ? 1u : 0u) | (s->cheat_ammo ? 2u : 0u) | (s->cheat_grenades ? 4u : 0u) | (s->cheat_reload ? 8u : 0u);
}

/* Independent weapon/hands visibility; neither simulation nor remote players change. */
static inline unsigned hs_viewmodel_mask(const HsSettings *s)
{
    static const unsigned masks[4] = {3u, 1u, 2u, 0u};
    return masks[hs_clampi(s->viewmodel_mode, 0, 3)];
}

/* Frame cap the host paces presentation to: 0 means none (the display's own refresh limits it). */
static inline int hs_frame_cap(const HsSettings *s)
{
    return s->fps_mode == 1 ? 60 : 0;
}

/* The cap to use right now: the chosen mode's cap, lowered when the phone is hot or in Low Power Mode (if allowed).
 * thermal_state is NSProcessInfoThermalState: 0 nominal, 1 fair, 2 serious, 3 critical. The original 30 FPS mode is never raised or lowered. */
static inline int hs_effective_cap(const HsSettings *s, int thermal_state, int low_power)
{
    int cap = hs_frame_cap(s), limit = 0;

    if (s->fps_mode == 0 || !s->thermal_cap)
        return cap;
    if (thermal_state >= 3) limit = 30;
    else if (thermal_state == 2 || low_power) limit = 45;
    if (limit && (cap == 0 || limit < cap))
        cap = limit;
    return cap;
}

static inline void hs_defaults(HsSettings *s)
{
    memset(s, 0, sizeof(*s));
    for (int i = 0; i < HS_PRESET_COUNT; i++) hs_default_preset(&s->presets[i], i);
    s->active = 0;
    s->volume = 1.0f;
    s->music_volume=s->dialogue_volume=s->effects_volume=1.f;
    s->ambient_volume=1.f;
    s->voice_mode=0;s->voice_volume=1.f;s->reverb=1; /* the microphone starts off */
    s->accent_rgb=0x3385FAu;s->chroma_seconds=12.f;
    s->thermal_cap=1;
    s->pad_curve=1.f;
    for(int b=0;b<14;b++) s->pad_map[b]=(unsigned char)b;
    for(int h=0;h<HS_HUD_COUNT;h++) { s->hud[h].scale=s->hud[h].opacity=1.f; }
    for(int p=0;p<3;p++) { snprintf(s->hud_presets[p].name,HS_NAME_MAX+1,"HUD %d",p+1); memcpy(s->hud_presets[p].elements,s->hud,sizeof(s->hud)); }
    s->cheat_jump = s->cheat_speed = 1.0f;
    s->audio_enabled = 1;
    s->join_from_clipboard = 0; /* reading the clipboard shows an iOS paste prompt */
    s->gear_scale=1.f;s->gear_opacity=1.f;
    s->game_vsync=s->game_online=1;
    s->game_controls[0]=3;s->game_controls[6]=s->game_controls[7]=1;
    for(int k=0;k<4;k++){s->shortcuts[k].gap=2;s->shortcuts[k].total=15;}
    strcpy(s->shortcuts[0].sequence,"11,11,12,12,13,14,13,14,1,0");
    s->show_fps = 0;
    s->profiler = 1;
    s->fps_mode = 1;
    s->hires_hud = 0; /* off until the new code has run on a device; switches in Settings */
    s->hires_text = 0;
    /* the in-game defaults (config.toml's), so that a first start never changes what the game shows */
    s->name_scale = 1.f;s->sb_panel = 1;s->text_chat = 1;
    s->streamer_slurs = 3;s->streamer_swearing = 2;
    s->cheat_target = 2;
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
        p->place[i].opacity=hs_clampf(p->place[i].opacity,0.1f,1.f);
    }
    p->opacity = hs_clampf(p->opacity, 0.25f, 1.0f);
    p->auto_fire = !!p->auto_fire; p->fire_drag = !!p->fire_drag; p->stick_fire = !!p->stick_fire;
    p->touch_look = p->touch_look ? 1 : 0;
    p->look_sensitivity = hs_clampf(p->look_sensitivity, 0.25f, 3.0f);
    p->invert_look_y = p->invert_look_y ? 1 : 0;
    p->floating_sticks = p->floating_sticks ? 1 : 0;
    p->stick_dead_zone = hs_clampf(p->stick_dead_zone, 0.0f, 0.4f);
    p->move_curve = hs_clampf(p->move_curve, 1.0f, 3.0f);
    p->look_curve = hs_clampf(p->look_curve, 1.0f, 3.0f);
    p->haptics = p->haptics ? 1 : 0;
    p->hud_choice=hs_clampi(p->hud_choice,0,3);p->startup_auto=!!p->startup_auto;
    p->face_style = hs_clampi(p->face_style,0,1);
    p->cheat_flags &= 0x01FC7FFFu; p->cheat_alliance=hs_clampi(p->cheat_alliance,0,4);p->cheat_projectile=hs_clampi(p->cheat_projectile,0,6); p->cheat_actions &= 15u;
    p->cheat_slow=hs_clampi(p->cheat_slow,0,7);p->mirror=!!p->mirror;p->toggle_mask&=HS_TOGGLE_ALLOWED;
    p->gyro=!!p->gyro;p->gyro_sens=hs_clampf(p->gyro_sens,.25f,3.f);p->gyro_flip_yaw=!!p->gyro_flip_yaw;p->gyro_flip_pitch=!!p->gyro_flip_pitch;
    p->cheat_weapon=hs_clampi(p->cheat_weapon,0,10);
    p->cheat_jump=hs_clampf(p->cheat_jump,1,10);
    p->cheat_speed=hs_clampf(p->cheat_speed,1,5);
    p->cheat_fov=p->cheat_fov==0 ? 0 : hs_clampf(p->cheat_fov,20,90);
}

static inline void hs_sanitize_hud(HsHud *h) {
 h->x=hs_clampf(h->x,-0.45f,0.45f);h->y=hs_clampf(h->y,-0.45f,0.45f);
 h->scale=hs_clampf(h->scale,0.5f,1.5f);h->opacity=hs_clampf(h->opacity,0.f,1.f);h->hidden=!!h->hidden;
}
/* Keeps printable bytes only (UTF-8 emoji pass), always terminated; '|' separates favourites so only a list may hold it. */
static inline void hs_clean_token(char *text, size_t size, int allow_bar)
{
    size_t out = 0;

    text[size - 1] = 0;
    for (size_t i = 0; text[i] && i < size; i++)
    {
        unsigned char c = (unsigned char)text[i];
        if (c < 0x20 || c == 0x7f || (c == '|' && !allow_bar))
            continue;
        text[out++] = (char)c;
    }
    text[out] = 0;
}

static inline void hs_sanitize(HsSettings *s)
{
    for (int i = 0; i < HS_PRESET_COUNT; i++) hs_sanitize_preset(&s->presets[i]);
    s->active = hs_clampi(s->active, 0, HS_PRESET_COUNT - 1);
    for(int h=0;h<HS_HUD_COUNT;h++) hs_sanitize_hud(&s->hud[h]);
    for(int p=0;p<3;p++) { char name[HS_NAME_MAX+1];hs_set_name(name,s->hud_presets[p].name);memcpy(s->hud_presets[p].name,name,sizeof(name));for(int h=0;h<HS_HUD_COUNT;h++) hs_sanitize_hud(&s->hud_presets[p].elements[h]); }
    s->music_volume=hs_clampf(s->music_volume,0,1);s->dialogue_volume=hs_clampf(s->dialogue_volume,0,1);s->effects_volume=hs_clampf(s->effects_volume,0,1);
    s->cheat_camo=!!s->cheat_camo;s->cheat_overshield=!!s->cheat_overshield;
    s->cheat_jetpack=!!s->cheat_jetpack;s->cheat_ai_ignore=!!s->cheat_ai_ignore;s->cheat_slow=hs_clampi(s->cheat_slow,0,7);
    s->accent_mode=hs_clampi(s->accent_mode,0,2);s->accent_rgb&=0xFFFFFFu;s->chroma_seconds=hs_clampf(s->chroma_seconds,3.f,60.f);
    s->maps_show_files=!!s->maps_show_files;s->maps_mp_alpha=!!s->maps_mp_alpha;s->maps_mp_only=!!s->maps_mp_only;
    s->ambient_volume=hs_clampf(s->ambient_volume,0,1);s->perf_overlay=!!s->perf_overlay;s->thermal_cap=!!s->thermal_cap;s->menu_style=hs_clampi(s->menu_style,0,1);
    s->pad_dead=hs_clampf(s->pad_dead,0,.4f);s->pad_curve=hs_clampf(s->pad_curve,1,3);
    for(int b=0;b<14;b++) if(s->pad_map[b]>13) s->pad_map[b]=(unsigned char)b;
    s->volume = hs_clampf(s->volume, 0.0f, 1.0f);
    s->audio_enabled = s->audio_enabled ? 1 : 0;
    s->join_from_clipboard = s->join_from_clipboard ? 1 : 0;
    s->show_fps = s->show_fps ? 1 : 0;
    s->profiler = s->profiler ? 1 : 0;
    s->voice_mode=hs_clampi(s->voice_mode,0,2);s->voice_volume=hs_clampf(s->voice_volume,0,2);s->reverb=!!s->reverb;
    s->gear_opacity=hs_clampf(s->gear_opacity,.15f,1);s->gear_icon=hs_clampi(s->gear_icon,0,5);
    hs_clean_token(s->gear_token,sizeof(s->gear_token),0);hs_clean_token(s->gear_favs,sizeof(s->gear_favs),1);
    if(s->gear_icon==5&&!s->gear_token[0])s->gear_icon=0;
    s->maps_campaign_only=!!s->maps_campaign_only;if(s->maps_mp_only)s->maps_campaign_only=0;
    s->custom_hide=!!s->custom_hide;s->custom_filter=hs_clampi(s->custom_filter,0,2);
    s->game_vsync=!!s->game_vsync;s->game_online=!!s->game_online;s->game_upnp=!!s->game_upnp;
    s->game_controls[0]=hs_clampi(s->game_controls[0],1,10);
    for(int k=1;k<8;k++)s->game_controls[k]=hs_clampi(s->game_controls[k],0,k==4?4:k==5?3:1);
    s->game_name[23]=0;s->game_color=hs_clampi(s->game_color,0,17);
    s->game_player_names=hs_clampi(s->game_player_names,0,3);
    for(int k=0;k<4;k++){s->shortcuts[k].sequence[95]=0;s->shortcuts[k].gap=hs_clampf(s->shortcuts[k].gap,.25f,10);s->shortcuts[k].total=hs_clampf(s->shortcuts[k].total,1,60);s->shortcuts[k].action=hs_clampi(s->shortcuts[k].action,0,31);if(s->shortcuts[k].action==29)s->shortcuts[k].action=0; /* retired equipment action; never reuse ID */}
    s->gear_scale=hs_clampf(s->gear_scale,.75f,1.75f);s->ui_theme=hs_clampi(s->ui_theme,0,4);
    s->gear_placed=!!s->gear_placed;s->gear_x=hs_clampf(s->gear_x,0,1);s->gear_y=hs_clampf(s->gear_y,0,1);
    s->display_mode = hs_clampi(s->display_mode, 0, 2);
    s->render_quality = hs_clampi(s->render_quality, 0, 3);
    s->fps_mode = hs_clampi(s->fps_mode, 0, 2);
    s->controls_mode = hs_clampi(s->controls_mode, 0, 2);
    s->cheat_god = s->cheat_god ? 1 : 0;
    s->cheat_ammo = s->cheat_ammo ? 1 : 0;
    s->cheat_grenades = s->cheat_grenades ? 1 : 0;
    s->cheat_reload = s->cheat_reload ? 1 : 0;
    s->cheat_one_hit = !!s->cheat_one_hit;
    s->cheat_flashlight = !!s->cheat_flashlight;
    s->cheat_no_fall = !!s->cheat_no_fall;
    s->cheat_rapid = !!s->cheat_rapid;
    s->cheat_no_recoil = !!s->cheat_no_recoil;
    s->cheat_third_person = !!s->cheat_third_person;
    s->cheat_noclip = !!s->cheat_noclip;
    s->cheat_jump = hs_clampf(s->cheat_jump, 1.0f, 10.0f);
    s->cheat_speed = hs_clampf(s->cheat_speed, 1.0f, 5.0f);
    s->cheat_fov = s->cheat_fov == 0 ? 0 : hs_clampf(s->cheat_fov, 20.0f, 90.0f);
    s->viewmodel_mode = hs_clampi(s->viewmodel_mode, 0, 3);
    s->hires_hud = s->hires_hud ? 1 : 0;
    s->hires_text = s->hires_text ? 1 : 0;
    s->aa_mode = hs_clampi(s->aa_mode, 0, 6);s->shadow_res = hs_clampi(s->shadow_res, 0, 3);
    s->per_pixel = !!s->per_pixel;s->shield_glow = !!s->shield_glow;s->glow_light_show = !!s->glow_light_show;
    s->fov = s->fov < 1 ? 0 : hs_clampf(s->fov, 20, 150);s->viewmodel_fov = s->viewmodel_fov < 1 ? 0 : hs_clampf(s->viewmodel_fov, 20, 150);
    s->vm_shield = !!s->vm_shield;s->legs = !!s->legs;s->shield_color = hs_clampi(s->shield_color, 0, 18);
    s->name_scale = hs_clampf(s->name_scale, 0.25f, 4);
    s->sb_layout = hs_clampi(s->sb_layout, 0, 1);s->sb_panel = !!s->sb_panel;
    s->text_chat = !!s->text_chat;s->chat_style = hs_clampi(s->chat_style, 0, 1);
    s->streamer = !!s->streamer;s->streamer_slurs = hs_clampi(s->streamer_slurs, 0, 3);
    s->streamer_swearing = hs_clampi(s->streamer_swearing, 0, 3);s->streamer_insults = hs_clampi(s->streamer_insults, 0, 3);
    s->cheat_target = hs_clampi(s->cheat_target, 0, 2);
}

/* ---------- layout: where the player's presets put the controls on this screen */

/* Moves and sizes the controls of `layout` (from hc_layout) as the preset says. A control never
 * leaves the safe area and never gets smaller than a thumb can hit. */
static inline void hs_apply_preset(const HsPreset *preset, float left, float top, float right, float bottom,
                                   HcControl controls[HC_COUNT])
{
    if (preset->face_style) {
        controls[HC_LT].label="L2";controls[HC_RT].label="R2";
        controls[HC_LS].label="L3";controls[HC_RS].label="R3";
        controls[HC_A].label="×"; controls[HC_A].color=HC_COLOR_BLUE;
        controls[HC_B].label="○"; controls[HC_B].color=HC_COLOR_RED;
        controls[HC_X].label="□"; controls[HC_X].color=HC_COLOR_PINK;
        controls[HC_Y].label="△"; controls[HC_Y].color=HC_COLOR_GREEN;
    }
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
    if (preset->mirror)
    {
        /* left-handed: every control swaps sides (the layout is edited and stored unmirrored) */
        for (int i = 0; i < HC_COUNT; i++)
            controls[i].r.x = left + right - (controls[i].r.x + controls[i].r.w);
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

/* Active cheats belong to this campaign session, never to saved settings. */
static inline void hs_clear_cheats(HsSettings *s) {
    s->cheat_god=s->cheat_ammo=s->cheat_grenades=s->cheat_reload=0;
    s->cheat_one_hit=s->cheat_flashlight=s->cheat_no_fall=s->cheat_rapid=0;
    s->cheat_no_recoil=s->cheat_third_person=s->cheat_noclip=0;
    s->cheat_camo=s->cheat_overshield=0;
    s->cheat_alliance=s->cheat_projectile=0;
    s->cheat_detach_camera=0;
    s->cheat_wireframe=s->cheat_hijack_vehicle=0;
    s->cheat_medusa=s->cheat_low_gravity=s->cheat_hijack_npc=s->cheat_vehicle_health=0;
    s->cheat_jetpack=s->cheat_ai_ignore=s->cheat_slow=0;
    s->cheat_jump=s->cheat_speed=1.f;s->cheat_fov=0;
}
static inline void hs_apply_preset_cheats(HsSettings *s,int index) {
    const HsPreset *p=&s->presets[hs_clampi(index,0,HS_PRESET_COUNT-1)];
    unsigned f=p->cheat_flags;
    s->cheat_god=!!(f&1);s->cheat_ammo=!!(f&2);s->cheat_grenades=!!(f&4);s->cheat_reload=!!(f&8);
    s->cheat_one_hit=!!(f&16);s->cheat_flashlight=!!(f&32);s->cheat_no_fall=!!(f&64);
    s->cheat_rapid=!!(f&128);s->cheat_no_recoil=!!(f&256);s->cheat_third_person=!!(f&512);s->cheat_noclip=!!(f&1024);
    s->cheat_camo=!!(f&2048);s->cheat_overshield=!!(f&4096);
    s->cheat_medusa=!!(f&262144);s->cheat_low_gravity=!!(f&524288);s->cheat_hijack_npc=!!(f&1048576);
    s->cheat_vehicle_health=!!(f&2097152);s->cheat_wireframe=!!(f&4194304);s->cheat_hijack_vehicle=!!(f&8388608);s->cheat_detach_camera=!!(f&16777216);
    s->cheat_alliance=p->cheat_alliance;s->cheat_projectile=p->cheat_projectile;
    s->cheat_jetpack=!!(f&8192);s->cheat_ai_ignore=!!(f&16384);s->cheat_slow=hs_clampi(p->cheat_slow,0,7);
    s->cheat_jump=p->cheat_jump;s->cheat_speed=p->cheat_speed;s->cheat_fov=p->cheat_fov;
}

/* ---------- saving and loading: one text blob of key=value lines */

static const char *const hs_control_keys[HC_COUNT] = {
    "lt", "rt", "back", "start", "ls", "rs", "a", "b", "x", "y", "white", "black", "dpad", "lstick", "rstick", "voice"
};

static inline int hs_serialize(const HsSettings *s, char *out, size_t size)
{
    HsSettings saved=*s;
    hs_clear_cheats(&saved);s=&saved;
    size_t n = 0;
#define EMIT(...) do { int w = snprintf(out + n, n < size ? size - n : 0, __VA_ARGS__); if (w < 0) return -1; n += (size_t)w; } while (0)
    EMIT("HALO1\n");
    EMIT("gamevsync=%d\ngameonline=%d\ngameupnp=%d\n",s->game_vsync,s->game_online,s->game_upnp);
    EMIT("gearopacity=%.3f\ngearicon=%d\n",s->gear_opacity,s->gear_icon);
    EMIT("geartoken=%s\ngearfavs=%s\n",s->gear_token,s->gear_favs);
    EMIT("mapscampaign=%d\ncustomhide=%d\ncustomfilter=%d\n",s->maps_campaign_only,s->custom_hide,s->custom_filter);
    EMIT("gamenames=%d\n",s->game_player_names);
    for(int k=0;k<4;k++) EMIT("shortcut%d=%s\nshortcutgap%d=%.3f\nshortcuttotal%d=%.3f\nshortcutaction%d=%d\n",k,s->shortcuts[k].sequence,k,s->shortcuts[k].gap,k,s->shortcuts[k].total,k,s->shortcuts[k].action);
    EMIT("gearscale=%.3f\nuitheme=%d\n",s->gear_scale,s->ui_theme);
    EMIT("gear=%d,%.4f,%.4f\n",s->gear_placed,s->gear_x,s->gear_y);
    EMIT("music=%.3f\ndialogue=%.3f\neffects=%.3f\n",s->music_volume,s->dialogue_volume,s->effects_volume);
    for(int h=0;h<HS_HUD_COUNT;h++) { const HsHud *q=&s->hud[h];EMIT("hud%d=%.4f,%.4f,%.3f,%.3f,%d\n",h,q->x,q->y,q->scale,q->opacity,q->hidden); }
    for(int p=0;p<3;p++) { EMIT("hn%d=%s\n",p,s->hud_presets[p].name);for(int h=0;h<HS_HUD_COUNT;h++) { const HsHud *q=&s->hud_presets[p].elements[h];EMIT("hp%d.%d=%.4f,%.4f,%.3f,%.3f,%d\n",p,h,q->x,q->y,q->scale,q->opacity,q->hidden); } }
    EMIT("active=%d\nvolume=%.3f\naudio=%d\nclipboard=%d\nfps=%d\nprofiler=%d\nfpsmode=%d\nhireshud=%d\nhirestext=%d\ncontrols=%d\ncheatgod=%d\ncheatammo=%d\ncheatgrenades=%d\ncheatreload=%d\n", s->active, s->volume, s->audio_enabled,
         s->join_from_clipboard, s->show_fps, s->profiler, s->fps_mode, s->hires_hud, s->hires_text, s->controls_mode,
         s->cheat_god, s->cheat_ammo, s->cheat_grenades, s->cheat_reload);
    EMIT("viewmodel=%d\n", s->viewmodel_mode);
    EMIT("aamode=%d\nshadowres=%d\nperpixel=%d\nshieldglow=%d\nglowshow=%d\n", s->aa_mode, s->shadow_res, s->per_pixel, s->shield_glow, s->glow_light_show);
    EMIT("fov=%.1f\nvmfov=%.1f\nvmshield=%d\nlegs=%d\nshieldcolor=%d\n", s->fov, s->viewmodel_fov, s->vm_shield, s->legs, s->shield_color);
    EMIT("namescale=%.3f\nsblayout=%d\nsbpanel=%d\ntextchat=%d\nchatstyle=%d\n", s->name_scale, s->sb_layout, s->sb_panel, s->text_chat, s->chat_style);
    EMIT("streamer=%d\nstreamslurs=%d\nstreamswear=%d\nstreaminsults=%d\ncheattarget=%d\n", s->streamer, s->streamer_slurs, s->streamer_swearing, s->streamer_insults, s->cheat_target);
    EMIT("voicemode=%d\nvoicevol=%.3f\nreverb=%d\n", s->voice_mode, s->voice_volume, s->reverb);
    EMIT("accentmode=%d\naccentrgb=%u\nchroma=%.2f\n", s->accent_mode, s->accent_rgb, s->chroma_seconds);
    EMIT("mapsshow=%d\nmapsalpha=%d\nmapsmponly=%d\nambient=%.3f\nperf=%d\nthermal=%d\npaddead=%.3f\npadcurve=%.3f\n",
         s->maps_show_files, s->maps_mp_alpha, s->maps_mp_only, s->ambient_volume, s->perf_overlay, s->thermal_cap, s->pad_dead, s->pad_curve);
    EMIT("padmap=");
    for (int b = 0; b < 14; b++) EMIT("%u%s", (unsigned)s->pad_map[b], b + 1 < 14 ? "," : "\n");
    EMIT("menus=%d\ndisplaymode=%d\nrenderquality=%d\n", s->menu_style, s->display_mode, s->render_quality);
    EMIT("cheatone_hit=%d\n", s->cheat_one_hit);
    EMIT("cheatflashlight=%d\n", s->cheat_flashlight);
    EMIT("cheatno_fall=%d\n", s->cheat_no_fall);
    EMIT("cheatrapid=%d\n", s->cheat_rapid);
    EMIT("cheatno_recoil=%d\n", s->cheat_no_recoil);
    EMIT("cheatthird_person=%d\n", s->cheat_third_person);
    EMIT("cheatnoclip=%d\n", s->cheat_noclip);
    EMIT("cheatjump=%.3f\ncheatspeed=%.3f\ncheatfov=%.3f\n", s->cheat_jump, s->cheat_speed, s->cheat_fov);
    for (int i = 0; i < HS_PRESET_COUNT; i++)
    {
        const HsPreset *p = &s->presets[i];

        EMIT("p%d.name=%s\n", i, p->name);
        EMIT("p%d.hudchoice=%d\np%d.startauto=%d\n",i,p->hud_choice,i,p->startup_auto);
        EMIT("p%d.alliance=%d\np%d.projectile=%d\n",i,p->cheat_alliance,i,p->cheat_projectile);
        EMIT("p%d.face=%d\np%d.cheats=%u\np%d.actions=%u\np%d.weapon=%d\np%d.jump=%.3f\np%d.speed=%.3f\np%d.fov=%.3f\n",i,p->face_style,i,p->cheat_flags,i,p->cheat_actions,i,p->cheat_weapon,i,p->cheat_jump,i,p->cheat_speed,i,p->cheat_fov);
        EMIT("p%d.slow=%d\np%d.mirror=%d\np%d.toggle=%u\np%d.gyro=%d\np%d.gyrosens=%.3f\np%d.gyroflipy=%d\np%d.gyroflipp=%d\n",
             i, p->cheat_slow, i, p->mirror, i, p->toggle_mask, i, p->gyro, i, p->gyro_sens, i, p->gyro_flip_yaw, i, p->gyro_flip_pitch);
        EMIT("p%d.autofire=%d\np%d.firedrag=%d\np%d.stickfire=%d\n", i, p->auto_fire, i, p->fire_drag, i, p->stick_fire);
        EMIT("p%d.opacity=%.3f\np%d.look=%d\np%d.sens=%.3f\np%d.invert=%d\np%d.float=%d\n", i, p->opacity, i, p->touch_look,
             i, p->look_sensitivity, i, p->invert_look_y, i, p->floating_sticks);
        EMIT("p%d.dead=%.3f\np%d.movecurve=%.3f\np%d.lookcurve=%.3f\np%d.haptics=%d\n", i, p->stick_dead_zone, i, p->move_curve,
             i, p->look_curve, i, p->haptics);
        for (int c = 0; c < HC_COUNT; c++)
        {
            const HsPlacement *q = &p->place[c];

            if (q->placed || q->scale != 1.0f || q->hidden || q->opacity != 1.f)
                EMIT("p%d.c.%s=%d,%.4f,%.4f,%.3f,%d,%.3f\n", i, hs_control_keys[c], q->placed, q->fx, q->fy, q->scale, q->hidden,q->opacity);
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
                else if (!strcmp(key,"voicemode")) s->voice_mode=atoi(value);
                else if (!strcmp(key,"voicevol")) s->voice_volume=(float)atof(value);
                else if (!strcmp(key,"reverb")) s->reverb=atoi(value);
                else if (!strcmp(key,"music")) s->music_volume=(float)atof(value);
                else if (!strcmp(key,"dialogue")) s->dialogue_volume=(float)atof(value);
                else if (!strcmp(key,"effects")) s->effects_volume=(float)atof(value);
                else if (!strncmp(key,"hud",3) || !strncmp(key,"hp",2)) {
                    int h=-1,p=-1;HsHud *q=NULL;
                    if (sscanf(key,"hud%d",&h)==1 && h>=0 && h<HS_HUD_COUNT) q=&s->hud[h];
                    else if (sscanf(key,"hp%d.%d",&p,&h)==2 && p>=0 && p<3 && h>=0 && h<HS_HUD_COUNT) q=&s->hud_presets[p].elements[h];
                    if(q) { HsHud v=*q;if(sscanf(value,"%f,%f,%f,%f,%d",&v.x,&v.y,&v.scale,&v.opacity,&v.hidden)==5)*q=v; }
                }
                else if (!strncmp(key,"hn",2)) { int p=-1;if(sscanf(key,"hn%d",&p)==1 && p>=0 && p<3)hs_set_name(s->hud_presets[p].name,value); }
                else if (!strcmp(key,"gamevsync")) s->game_vsync=atoi(value);
                else if (!strcmp(key,"gameonline")) s->game_online=atoi(value);
                else if (!strcmp(key,"gameupnp")) s->game_upnp=atoi(value);
                else if (!strcmp(key,"gearopacity")) s->gear_opacity=(float)atof(value);
                else if (!strcmp(key,"gamenames")) s->game_player_names=atoi(value);
                else if (!strcmp(key,"gearicon")) s->gear_icon=atoi(value);
                else if (!strcmp(key,"geartoken")) { strncpy(s->gear_token,value,sizeof(s->gear_token)-1); s->gear_token[sizeof(s->gear_token)-1]=0; }
                else if (!strcmp(key,"gearfavs")) { strncpy(s->gear_favs,value,sizeof(s->gear_favs)-1); s->gear_favs[sizeof(s->gear_favs)-1]=0; }
                else if (!strcmp(key,"mapscampaign")) s->maps_campaign_only=atoi(value);
                else if (!strcmp(key,"customhide")) s->custom_hide=atoi(value);
                else if (!strcmp(key,"customfilter")) s->custom_filter=atoi(value);
                else if (!strncmp(key,"shortcut",8)) {int k=-1;
                    if(sscanf(key,"shortcutgap%d",&k)==1 && k>=0 && k<4)s->shortcuts[k].gap=(float)atof(value);
                    else if(sscanf(key,"shortcuttotal%d",&k)==1 && k>=0 && k<4)s->shortcuts[k].total=(float)atof(value);
                    else if(sscanf(key,"shortcutaction%d",&k)==1 && k>=0 && k<4)s->shortcuts[k].action=atoi(value);
                    else if(sscanf(key,"shortcut%d",&k)==1 && k>=0 && k<4)snprintf(s->shortcuts[k].sequence,96,"%s",value);
                }
                else if (!strcmp(key,"gearscale")) s->gear_scale=(float)atof(value);
                else if (!strcmp(key,"uitheme")) s->ui_theme=atoi(value);
                else if (!strcmp(key,"gear")) { int placed;float x,y;if(sscanf(value,"%d,%f,%f",&placed,&x,&y)==3){s->gear_placed=placed;s->gear_x=x;s->gear_y=y;} }
                else if (!strcmp(key, "fps")) s->show_fps = atoi(value);
                else if (!strcmp(key, "profiler")) s->profiler = atoi(value);
                else if (!strcmp(key, "smooth")) s->fps_mode = atoi(value) ? 1 : 0; /* M2.6.33-35 files */
                else if (!strcmp(key, "fpsmode")) s->fps_mode = atoi(value);
                else if (!strcmp(key, "controls")) s->controls_mode = atoi(value);
                else if (!strcmp(key, "cheatgod")) s->cheat_god = atoi(value);
                else if (!strcmp(key, "cheatammo")) s->cheat_ammo = atoi(value);
                else if (!strcmp(key, "cheatgrenades")) s->cheat_grenades = atoi(value);
                else if (!strcmp(key, "cheatreload")) s->cheat_reload = atoi(value);
                else if (!strcmp(key, "cheatone_hit")) s->cheat_one_hit = atoi(value);
                else if (!strcmp(key, "cheatflashlight")) s->cheat_flashlight = atoi(value);
                else if (!strcmp(key, "cheatno_fall")) s->cheat_no_fall = atoi(value);
                else if (!strcmp(key, "cheatrapid")) s->cheat_rapid = atoi(value);
                else if (!strcmp(key, "cheatno_recoil")) s->cheat_no_recoil = atoi(value);
                else if (!strcmp(key, "cheatthird_person")) s->cheat_third_person = atoi(value);
                else if (!strcmp(key, "cheatnoclip")) s->cheat_noclip = atoi(value);
                else if (!strcmp(key, "cheatjump")) s->cheat_jump = (float)atof(value);
                else if (!strcmp(key, "cheatspeed")) s->cheat_speed = (float)atof(value);
                else if (!strcmp(key, "cheatfov")) s->cheat_fov = (float)atof(value);

                else if (!strcmp(key, "viewmodel")) s->viewmodel_mode = atoi(value);
                else if (!strcmp(key, "aamode")) s->aa_mode = atoi(value);
                else if (!strcmp(key, "shadowres")) s->shadow_res = atoi(value);
                else if (!strcmp(key, "perpixel")) s->per_pixel = atoi(value);
                else if (!strcmp(key, "shieldglow")) s->shield_glow = atoi(value);
                else if (!strcmp(key, "glowshow")) s->glow_light_show = atoi(value);
                else if (!strcmp(key, "fov")) s->fov = (float)atof(value);
                else if (!strcmp(key, "vmfov")) s->viewmodel_fov = (float)atof(value);
                else if (!strcmp(key, "vmshield")) s->vm_shield = atoi(value);
                else if (!strcmp(key, "legs")) s->legs = atoi(value);
                else if (!strcmp(key, "shieldcolor")) s->shield_color = atoi(value);
                else if (!strcmp(key, "namescale")) s->name_scale = (float)atof(value);
                else if (!strcmp(key, "sblayout")) s->sb_layout = atoi(value);
                else if (!strcmp(key, "sbpanel")) s->sb_panel = atoi(value);
                else if (!strcmp(key, "textchat")) s->text_chat = atoi(value);
                else if (!strcmp(key, "chatstyle")) s->chat_style = atoi(value);
                else if (!strcmp(key, "streamer")) s->streamer = atoi(value);
                else if (!strcmp(key, "streamslurs")) s->streamer_slurs = atoi(value);
                else if (!strcmp(key, "streamswear")) s->streamer_swearing = atoi(value);
                else if (!strcmp(key, "streaminsults")) s->streamer_insults = atoi(value);
                else if (!strcmp(key, "cheattarget")) s->cheat_target = atoi(value);
                else if (!strcmp(key, "hireshud")) s->hires_hud = atoi(value);
                else if (!strcmp(key, "hirestext")) s->hires_text = atoi(value);
                else if (!strcmp(key, "accentmode")) s->accent_mode = atoi(value);
                else if (!strcmp(key, "accentrgb")) s->accent_rgb = (unsigned)strtoul(value, NULL, 10);
                else if (!strcmp(key, "chroma")) s->chroma_seconds = (float)atof(value);
                else if (!strcmp(key, "mapsshow")) s->maps_show_files = atoi(value);
                else if (!strcmp(key, "mapsalpha")) s->maps_mp_alpha = atoi(value);
                else if (!strcmp(key, "mapsmponly")) s->maps_mp_only = atoi(value);
                else if (!strcmp(key, "ambient")) s->ambient_volume = (float)atof(value);
                else if (!strcmp(key, "perf")) s->perf_overlay = atoi(value);
                else if (!strcmp(key, "thermal")) s->thermal_cap = atoi(value);
                else if (!strcmp(key, "displaymode")) s->display_mode = atoi(value);
                else if (!strcmp(key, "renderquality")) s->render_quality = atoi(value);
                else if (!strcmp(key, "menus")) s->menu_style = atoi(value);
                else if (!strcmp(key, "paddead")) s->pad_dead = (float)atof(value);
                else if (!strcmp(key, "padcurve")) s->pad_curve = (float)atof(value);
                else if (!strcmp(key, "padmap"))
                {
                    const char *at = value;
                    for (int b = 0; b < 14 && *at; b++)
                    {
                        char *end = NULL;
                        long v = strtol(at, &end, 10);
                        if (end == at) break;
                        s->pad_map[b] = (unsigned char)(v >= 0 && v <= 13 ? v : b);
                        at = *end == ',' ? end + 1 : end;
                    }
                }
                else if (key[0] == 'p' && key[1] >= '0' && key[1] < '0' + HS_PRESET_COUNT && key[2] == '.')
                {
                    HsPreset *p = &s->presets[key[1] - '0'];
                    const char *field = key + 3;

                    if (!strcmp(field, "name")) hs_set_name(p->name, value);
                    else if (!strcmp(field,"hudchoice")) p->hud_choice=atoi(value);
                    else if (!strcmp(field,"startauto")) p->startup_auto=atoi(value);
                    else if (!strcmp(field,"face")) p->face_style=atoi(value);
                    else if (!strcmp(field,"alliance")) p->cheat_alliance=atoi(value);
                    else if (!strcmp(field,"projectile")) p->cheat_projectile=atoi(value);
                    else if (!strcmp(field,"cheats")) p->cheat_flags=(unsigned)strtoul(value,NULL,10);
                    else if (!strcmp(field,"actions")) p->cheat_actions=(unsigned)strtoul(value,NULL,10);
                    else if (!strcmp(field,"weapon")) p->cheat_weapon=atoi(value);
                    else if (!strcmp(field,"slow")) p->cheat_slow=atoi(value);
                    else if (!strcmp(field,"mirror")) p->mirror=atoi(value);
                    else if (!strcmp(field,"toggle")) p->toggle_mask=(unsigned)strtoul(value,NULL,10);
                    else if (!strcmp(field,"gyro")) p->gyro=atoi(value);
                    else if (!strcmp(field,"gyrosens")) p->gyro_sens=(float)atof(value);
                    else if (!strcmp(field,"gyroflipy")) p->gyro_flip_yaw=atoi(value);
                    else if (!strcmp(field,"gyroflipp")) p->gyro_flip_pitch=atoi(value);
                    else if (!strcmp(field,"jump")) p->cheat_jump=(float)atof(value);
                    else if (!strcmp(field,"speed")) p->cheat_speed=(float)atof(value);
                    else if (!strcmp(field,"fov")) p->cheat_fov=(float)atof(value);
                    else if (!strcmp(field, "opacity")) p->opacity = (float)atof(value);
                    else if (!strcmp(field, "autofire")) p->auto_fire = atoi(value);
                    else if (!strcmp(field, "firedrag")) p->fire_drag = atoi(value);
                    else if (!strcmp(field, "stickfire")) p->stick_fire = atoi(value);
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
                                float fx = 0, fy = 0, scale = 1,opacity=1;

                                if (sscanf(value, "%d,%f,%f,%f,%d,%f", &placed, &fx, &fy, &scale, &hidden,&opacity) >= 5)
                                {
                                    q->placed = placed; q->fx = fx; q->fy = fy; q->scale = scale; q->hidden = hidden; q->opacity=opacity;
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
    hs_clear_cheats(s); /* discard legacy persisted active cheats as well */
    if (!strcmp(s->presets[0].name,"Classic Xbox")) hs_set_name(s->presets[0].name,"Classic Xbox UI");
    if (!strcmp(s->presets[1].name,"Preset 2")) hs_set_name(s->presets[1].name,"Playstation UI");
    return 1;
}

#endif
