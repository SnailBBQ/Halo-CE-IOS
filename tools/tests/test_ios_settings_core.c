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
    CHECK(!strcmp(s.presets[0].name, "Classic Xbox UI") && !strcmp(s.presets[4].name, "Preset 5"), "default names");
    CHECK(s.active == 0 && s.volume == 1.0f && s.audio_enabled && !s.join_from_clipboard && s.profiler == 1 && s.fps_mode == 1 && s.hires_hud == 0 && s.hires_text == 0 && s.controls_mode == 0 && hs_cheat_mask(&s) == 0, "default globals (cheats off)");
    CHECK(s.presets[2].touch_look && s.presets[2].floating_sticks && near(s.presets[2].look_curve, 1.5f), "default aim");

    /* First-person visibility is persistent and applies independently from cheats. */
    CHECK(s.viewmodel_mode == 0 && hs_viewmodel_mask(&s) == 3u, "legacy/default both meshes");
    for (int mode=0;mode<4;++mode) {
        static const unsigned masks[4]={3u,1u,2u,0u};
        s.viewmodel_mode=mode;
        CHECK(hs_serialize(&s,text,sizeof(text))>0,"viewmodel serialize");
        hs_parse(&t,text);
        CHECK(t.viewmodel_mode==mode && hs_viewmodel_mask(&t)==masks[mode],"viewmodel round trip");
    }
    hs_parse(&t,"HALO1\nviewmodel=999\n");
    CHECK(t.viewmodel_mode==3 && hs_viewmodel_mask(&t)==0,"viewmodel upper bound");
    hs_parse(&t,"HALO1\nviewmodel=-1\n");
    CHECK(t.viewmodel_mode==0 && hs_viewmodel_mask(&t)==3,"viewmodel lower bound");
    hs_defaults(&s);

    /* round trip, including a renamed preset with accents, moved/scaled/hidden controls */
    hs_set_name(s.presets[1].name, "  Thumbs ñ ☃ wide  ");
    s.active = 3;
    s.volume = 0.35f;
    s.audio_enabled = 0;
    s.join_from_clipboard = 1;
    s.profiler = 0;
    s.fps_mode = 2;
    s.controls_mode = 1;
    s.cheat_god = 1;
    s.cheat_grenades = 1;
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
    CHECK(t.active == 3 && near(t.volume, 0.35f) && !t.audio_enabled && t.join_from_clipboard && t.profiler == 0 && t.fps_mode == 2 && t.hires_hud == 1 && t.hires_text == 1 && t.controls_mode == 1 && !t.cheat_god && !t.cheat_ammo && !t.cheat_grenades && !t.cheat_reload, "globals round trip");
    CHECK(!strcmp(t.presets[1].name, "Thumbs ñ ☃ wide"), "name round trip got '%s'", t.presets[1].name);
    CHECK(near(t.presets[1].opacity, 0.5f) && near(t.presets[1].look_sensitivity, 2.25f) && t.presets[1].invert_look_y, "aim round trip");
    CHECK(t.presets[1].place[HC_A].placed && near(t.presets[1].place[HC_A].fx, 0.9f) && near(t.presets[1].place[HC_A].fy, 0.4f) &&
          near(t.presets[1].place[HC_A].scale, 1.4f), "placement round trip");
    CHECK(t.presets[1].place[HC_DPAD].hidden && !t.presets[1].place[HC_B].placed, "hidden round trip, untouched stays default");
    CHECK(near(t.presets[4].place[HC_RT].scale, 0.8f) && t.presets[4].place[HC_RT].placed, "second preset round trip");
    CHECK(!strcmp(t.presets[0].name, "Classic Xbox UI"), "other names stay");

    /* cheat mask, frame cap and files written by M2.6.33-35 (which had "smooth=" and no cheats) */
    {
        HsSettings m; hs_defaults(&m);
        CHECK(hs_cheat_mask(&m) == 0, "no cheats by default");
        m.cheat_god = 1; m.cheat_reload = 1;
        CHECK(hs_cheat_mask(&m) == 9u, "god + no reload = 1 + 8, got %u", hs_cheat_mask(&m));
        m.cheat_ammo = 1; m.cheat_grenades = 1;
        CHECK(hs_cheat_mask(&m) == 15u, "all four = 15");
        m.fps_mode = 0; CHECK(hs_frame_cap(&m) == 0, "original 30 is paced by the game, no host cap");
        m.fps_mode = 1; CHECK(hs_frame_cap(&m) == 60, "smooth 60 caps presentation at 60");
        m.fps_mode = 2; CHECK(hs_frame_cap(&m) == 0, "uncapped has no cap");
        HsSettings old;
        hs_parse(&old, "HALO1\nactive=1\nsmooth=0\nhireshud=1\n");
        CHECK(old.fps_mode == 0 && old.hires_hud == 1 && old.active == 1 && hs_cheat_mask(&old) == 0, "an M2.6.35 file with smooth=0 reads as the original 30");
        hs_parse(&old, "HALO1\nsmooth=1\n");
        CHECK(old.fps_mode == 1, "smooth=1 reads as smooth 60");
        hs_parse(&old, "HALO1\nfpsmode=9\ncontrols=-4\ncheatgod=7\n");
        CHECK(old.fps_mode == 2 && old.controls_mode == 0 && old.cheat_god == 0, "out of range values are clamped");
    }

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
    CHECK(hs_parse(&t, "garbage") == 0 && !strcmp(t.presets[0].name, "Classic Xbox UI"), "no header gives defaults");
    CHECK(hs_parse(&t, NULL) == 0, "NULL text");
    hs_parse(&t, "HALO1\nactive=99\nvolume=7\np0.opacity=-4\np0.sens=1e30\np0.dead=nan\np0.c.a=1,9,-9,50,7\np9.name=x\nunknown=1\nno equals line\n\n");
    CHECK(t.active == 4 && t.volume == 1.0f, "global clamps (%d, %f)", t.active, t.volume);
    CHECK(near(t.presets[0].opacity, 0.25f) && near(t.presets[0].look_sensitivity, 3.0f) && near(t.presets[0].stick_dead_zone, 0.0f), "preset clamps");
    CHECK(t.presets[0].place[HC_A].fx == 1.0f && t.presets[0].place[HC_A].fy == 0.0f && near(t.presets[0].place[HC_A].scale, 1.8f) && t.presets[0].place[HC_A].hidden == 1, "placement clamps");
    char huge[40000];
    memset(huge, 'x', sizeof(huge)); memcpy(huge, "HALO1\n", 6); huge[sizeof(huge) - 1] = 0;
    hs_parse(&t, huge);
    CHECK(!strcmp(t.presets[0].name, "Classic Xbox UI"), "one enormous line is skipped");
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

    hs_defaults(&s);
    s.cheat_jump = 2.5f; s.cheat_speed = 3.25f; s.cheat_fov = 80.f;
    s.cheat_one_hit = s.cheat_flashlight = s.cheat_no_fall = 1;
    s.cheat_rapid = s.cheat_no_recoil = s.cheat_third_person = s.cheat_noclip = 1;
    CHECK(hs_serialize(&s, text, sizeof(text)) > 0, "serialize campaign tools");
    hs_parse(&t, text);
    CHECK(near(t.cheat_jump, 1.f) && near(t.cheat_speed, 1.f) && near(t.cheat_fov, 0.f), "numeric tools round trip");
    CHECK(!t.cheat_one_hit && !t.cheat_flashlight && !t.cheat_no_fall && !t.cheat_rapid && !t.cheat_no_recoil && !t.cheat_third_person && !t.cheat_noclip, "toggles round trip");
    hs_parse(&t, "HALO1\ncheatjump=nan\ncheatspeed=999999\ncheatfov=inf\n");
    CHECK(t.cheat_jump == 1 && t.cheat_speed == 1 && t.cheat_fov == 0, "hostile numeric tools clamped");
    hs_parse(&t, "HALO1\ncheatgod=1\ncheatreload=1\n");
    CHECK(t.cheat_jump == 1 && t.cheat_speed == 1 && t.cheat_fov == 0 && hs_cheat_mask(&t) == 0, "old settings keep defaults and bottomless clip");

    hs_defaults(&s);
    s.presets[1].cheat_flags=2047u;s.presets[1].cheat_actions=15;s.presets[1].cheat_weapon=6;
    s.presets[1].cheat_jump=2.5f;s.presets[1].cheat_speed=3.25f;s.presets[1].cheat_fov=80.f;
    hs_apply_preset_cheats(&s,1);
    CHECK(hs_cheat_mask(&s)==15u && s.cheat_noclip && s.cheat_speed==3.25f,"explicit preset apply");
    CHECK(hs_serialize(&s,text,sizeof(text))>0,"preset recipe serialize");hs_parse(&t,text);
    CHECK(hs_cheat_mask(&t)==0 && t.cheat_speed==1 && !t.cheat_noclip,"active cheats never persist");
    CHECK(t.presets[1].cheat_flags==2047u && t.presets[1].cheat_actions==15 && t.presets[1].cheat_weapon==6 && t.presets[1].cheat_jump==2.5f,"recipe persists independently");
    HcControl ps[HC_COUNT];hc_layout(0,0,800,390,ps);hs_apply_preset(&t.presets[1],0,0,800,390,ps);
    CHECK(!strcmp(ps[HC_A].label,"×") && !strcmp(ps[HC_X].label,"□") && ps[HC_A].button==HC_BTN_A,"PlayStation presentation retains input mapping");
    hs_apply_preset_cheats(&t,1);hs_clear_cheats(&t);
    CHECK(hs_cheat_mask(&t)==0 && t.cheat_jump==1 && t.cheat_fov==0 && t.presets[1].cheat_flags==2047,"lobby reset preserves recipes");
    hs_defaults(&s);
    s.hud[2].x=.125f;s.hud[2].scale=.8f;s.hud[2].opacity=.4f;s.hud[3].hidden=1;
    memcpy(s.hud_presets[1].elements,s.hud,sizeof(s.hud));hs_set_name(s.hud_presets[1].name,"Quiet HUD");
    s.music_volume=.3f;s.dialogue_volume=.7f;s.effects_volume=.5f;s.presets[2].place[HC_A].opacity=.25f;
    s.presets[2].cheat_flags=2048u|4096u;hs_apply_preset_cheats(&s,2);
    CHECK(s.cheat_camo&&s.cheat_overshield,"infinite powerups activate explicitly");
    CHECK(hs_serialize(&s,text,sizeof(text))>0,"serialize HUD and audio");CHECK(hs_parse(&t,text),"parse HUD and audio");
    CHECK(near(t.hud[2].x,.125f)&&near(t.hud[2].scale,.8f)&&near(t.hud[2].opacity,.4f)&&t.hud[3].hidden,"independent HUD settings persist");
    CHECK(!strcmp(t.hud_presets[1].name,"Quiet HUD")&&near(t.hud_presets[1].elements[2].opacity,.4f),"named HUD recipes persist");
    CHECK(near(t.music_volume,.3f)&&near(t.dialogue_volume,.7f)&&near(t.effects_volume,.5f),"audio channels persist");
    CHECK(near(t.presets[2].place[HC_A].opacity,.25f)&&!t.cheat_camo&&!t.cheat_overshield,"individual control opacity persists but infinite effects do not");
    hs_parse(&t,"HALO1\nhud2=nan,999,0,2,1\nmusic=nan\ndialogue=999\neffects=-3\n");
    CHECK(t.hud[2].x==-.45f&&t.hud[2].y==.45f&&t.hud[2].scale==.5f&&t.hud[2].opacity==1,"hostile HUD values bounded");
    CHECK(t.music_volume==0&&t.dialogue_volume==1&&t.effects_volume==0,"hostile audio gains bounded");
    hs_defaults(&s);CHECK(s.presets[4].startup_auto==1,"default direct boot");
    s.presets[2].hud_choice=3;s.presets[2].startup_auto=0;s.gear_placed=1;s.gear_x=.75f;s.gear_y=.25f;
    CHECK(hs_serialize(&s,text,sizeof(text))>0 && hs_parse(&t,text),"profile links serialize");
    CHECK(t.presets[2].hud_choice==3 && !t.presets[2].startup_auto && t.gear_placed && near(t.gear_x,.75f),"HUD link, startup and floating settings persist");
    hc_layout(0,0,800,390,ps);hs_apply_preset(&t.presets[1],0,0,800,390,ps);
    CHECK(!strcmp(ps[HC_LT].label,"L2") && !strcmp(ps[HC_RT].label,"R2") && !strcmp(ps[HC_LS].label,"L3") && !strcmp(ps[HC_RS].label,"R3"),"PlayStation trigger/stick labels");
    hs_parse(&t,"HALO1\np2.hudchoice=999\np2.startauto=7\ngear=1,nan,999\n");CHECK(t.presets[2].hud_choice==3 && t.presets[2].startup_auto==1 && t.gear_x==0 && t.gear_y==1,"new settings bounded");
    hs_defaults(&s);CHECK(s.gear_scale==1 && s.ui_theme==0,"Options defaults");s.gear_scale=1.5f;s.ui_theme=2;
    CHECK(hs_serialize(&s,text,sizeof(text))>0 && hs_parse(&t,text) && near(t.gear_scale,1.5f) && t.ui_theme==2,"Options persist");
    hs_parse(&t,"HALO1\ngearscale=nan\nuitheme=999\n");CHECK(t.gear_scale==.75f && t.ui_theme==4,"Options bounds");
    /* ---- M2.6.48: accent colours, installed-files list, ambient sound, controller shaping, gyro, left-handed, toggles, new cheats */
    hs_defaults(&s);
    CHECK(s.accent_mode==0 && s.accent_rgb==0x3385FAu && near(s.chroma_seconds,12.f),"accent defaults");
    CHECK(!s.maps_show_files && !s.maps_mp_alpha && !s.maps_mp_only,"installed files hidden, game order, campaign shown by default");
    CHECK(near(s.ambient_volume,1.f) && s.thermal_cap==1 && !s.perf_overlay,"audio and display defaults");
    CHECK(near(s.pad_dead,0) && near(s.pad_curve,1),"controller shaping off by default");
    { int identity=1; for(int b=0;b<14;b++) if(s.pad_map[b]!=b) identity=0; CHECK(identity,"controller map defaults to identity"); }
    CHECK(near(s.presets[0].gyro_sens,1.f) && !s.presets[0].gyro && !s.presets[0].mirror && s.presets[0].toggle_mask==0,"control defaults");
    s.accent_mode=2;s.accent_rgb=0xA1B2C3u;s.chroma_seconds=20.f;s.maps_show_files=1;s.maps_mp_alpha=1;s.maps_mp_only=1;
    s.ambient_volume=.4f;s.perf_overlay=1;s.thermal_cap=0;s.pad_dead=.15f;s.pad_curve=2.f;s.pad_map[0]=1;s.pad_map[1]=0;s.pad_map[13]=6;
    s.presets[3].mirror=1;s.presets[3].toggle_mask=(1u<<HC_LS)|(1u<<HC_RS);s.presets[3].gyro=1;s.presets[3].gyro_sens=1.75f;
    s.presets[3].gyro_flip_yaw=1;s.presets[3].cheat_slow=3;s.presets[3].cheat_flags=8192u|16384u|1u;
    CHECK(hs_serialize(&s,text,sizeof(text))>0 && hs_parse(&t,text),"serialize the new settings");
    CHECK(t.accent_mode==2 && t.accent_rgb==0xA1B2C3u && near(t.chroma_seconds,20.f),"accent persists");
    CHECK(t.maps_show_files && t.maps_mp_alpha && t.maps_mp_only,"installed-files options persist");
    CHECK(near(t.ambient_volume,.4f) && t.perf_overlay && !t.thermal_cap && near(t.pad_dead,.15f) && near(t.pad_curve,2.f),"ambient, overlay, thermal, controller shaping persist");
    CHECK(t.pad_map[0]==1 && t.pad_map[1]==0 && t.pad_map[2]==2 && t.pad_map[13]==6,"controller remap persists");
    CHECK(t.presets[3].mirror && t.presets[3].toggle_mask==((1u<<HC_LS)|(1u<<HC_RS)) && t.presets[3].gyro && near(t.presets[3].gyro_sens,1.75f) &&
          t.presets[3].gyro_flip_yaw && !t.presets[3].gyro_flip_pitch && t.presets[3].cheat_slow==3 && t.presets[3].cheat_flags==(8192u|16384u|1u),"per-profile controls and recipe persist");
    hs_apply_preset_cheats(&t,3);
    CHECK(t.cheat_jetpack && t.cheat_ai_ignore && t.cheat_god && t.cheat_slow==3,"a recipe activates jetpack, AI ignore and slow motion");
    t.cheat_jetpack=t.cheat_ai_ignore=1;t.cheat_slow=2;
    CHECK(hs_serialize(&t,text,sizeof(text))>0 && hs_parse(&s,text) && !s.cheat_jetpack && !s.cheat_ai_ignore && s.cheat_slow==0,"running session cheats are never saved");
    hs_clear_cheats(&t);CHECK(!t.cheat_jetpack && !t.cheat_ai_ignore && t.cheat_slow==0,"clearing cheats clears the new ones");
    hs_parse(&t,"HALO1\naccentmode=9\naccentrgb=99999999999\nchroma=nan\nmapsshow=5\nmapsalpha=-3\nambient=9\nperf=7\nthermal=2\npaddead=-4\npadcurve=nan\npadmap=99,1,2,x,5\n"
                "p1.slow=99\np1.mirror=5\np1.toggle=4294967295\np1.gyro=3\np1.gyrosens=nan\np1.cheats=4294967295\n");
    CHECK(t.accent_mode==2 && (t.accent_rgb&~0xFFFFFFu)==0 && t.chroma_seconds>=3.f && t.chroma_seconds<=60.f,"hostile accent values are bounded (mode %d rgb %x chroma %f)",t.accent_mode,t.accent_rgb,t.chroma_seconds);
    CHECK(t.maps_show_files==1 && t.maps_mp_alpha==1 && t.ambient_volume==1.f && t.perf_overlay==1 && t.thermal_cap==1,"hostile flags and volumes are bounded");
    CHECK(t.pad_dead==0 && t.pad_curve>=1.f && t.pad_curve<=3.f,"hostile controller shaping is bounded");
    { int ok=t.pad_map[0]==0 && t.pad_map[1]==1 && t.pad_map[2]==2 && t.pad_map[3]==3 && t.pad_map[4]==4; for(int b=0;b<14;b++) if(t.pad_map[b]>13) ok=0; CHECK(ok,"a damaged remap keeps the entries before the damage and the rest stay identity (%u %u %u %u %u)",t.pad_map[0],t.pad_map[1],t.pad_map[2],t.pad_map[3],t.pad_map[4]); }
    CHECK(t.presets[1].cheat_slow==4 && t.presets[1].mirror==1 && t.presets[1].gyro==1 && t.presets[1].gyro_sens>=.25f && t.presets[1].gyro_sens<=3.f,"hostile profile fields are bounded");
    CHECK((t.presets[1].toggle_mask&~HS_TOGGLE_ALLOWED)==0 && t.presets[1].toggle_mask==HS_TOGGLE_ALLOWED && (t.presets[1].cheat_flags&~32767u)==0,"only buttons can latch and only known recipe bits survive");
    /* the old file format still reads: a file from before this update has none of the new keys */
    hs_parse(&t,"HALO1\nactive=2\nvolume=0.5\n");
    CHECK(t.active==2 && t.accent_rgb==0x3385FAu && t.pad_curve==1.f && t.thermal_cap==1 && t.presets[0].gyro_sens==1.f,"older files read with the new defaults");
    /* left-handed mirror: every control swaps sides, sizes and heights are kept, mirroring twice is the original */
    {
        HcControl a[HC_COUNT], b[HC_COUNT];
        HsPreset plain, left; hs_default_preset(&plain,2); left=plain; left.mirror=1;
        hc_layout(10,0,810,390,a);hs_apply_preset(&plain,10,0,810,390,a);
        hc_layout(10,0,810,390,b);hs_apply_preset(&left,10,0,810,390,b);
        int ok=1; for(int i=0;i<HC_COUNT;i++){ if(!near(hc_cx(b[i].r),10+810-hc_cx(a[i].r))||!near(b[i].r.w,a[i].r.w)||!near(b[i].r.y,a[i].r.y)||!near(b[i].r.h,a[i].r.h)||b[i].hidden!=a[i].hidden) ok=0; }
        CHECK(ok,"left-handed mirrors every control about the centre of the safe area");
        CHECK(hc_cx(a[HC_LSTICK].r)<hc_cx(a[HC_RSTICK].r) && hc_cx(b[HC_LSTICK].r)>hc_cx(b[HC_RSTICK].r),"the move stick is on the right when mirrored");
        HsPreset moved=plain; moved.place[HC_A].placed=1;moved.place[HC_A].fx=.9f;moved.place[HC_A].fy=.5f;moved.place[HC_A].scale=1.f;moved.place[HC_A].opacity=1.f; HsPreset moved_left=moved; moved_left.mirror=1;
        hc_layout(10,0,810,390,a);hs_apply_preset(&moved,10,0,810,390,a);hc_layout(10,0,810,390,b);hs_apply_preset(&moved_left,10,0,810,390,b);
        CHECK(near(hc_cx(b[HC_A].r),10+810-hc_cx(a[HC_A].r)),"a control the player moved is mirrored too");
        ok=1;
        for(int i=0;i<HC_COUNT;i++){ if(b[i].r.x<10-.01f||b[i].r.x+b[i].r.w>810+.01f) ok=0; }
        CHECK(ok,"the mirrored layout stays on screen");
    }
    /* heat-aware frame cap */
    hs_defaults(&s);s.fps_mode=1;s.thermal_cap=1;
    CHECK(hs_effective_cap(&s,0,0)==60 && hs_effective_cap(&s,1,0)==60,"smooth 60 is held at 60 while the phone is cool or warm");
    CHECK(hs_effective_cap(&s,2,0)==45 && hs_effective_cap(&s,3,0)==30,"serious heat gives 45, critical heat 30");
    CHECK(hs_effective_cap(&s,0,1)==45 && hs_effective_cap(&s,3,1)==30,"Low Power Mode gives 45, and heat can still lower it further");
    s.fps_mode=2;
    CHECK(hs_effective_cap(&s,0,0)==0 && hs_effective_cap(&s,2,0)==45 && hs_effective_cap(&s,3,0)==30,"uncapped has no cap until the phone is hot");
    s.thermal_cap=0;
    CHECK(hs_effective_cap(&s,3,1)==0,"with the option off the mode's own cap is used whatever the heat");
    s.fps_mode=1;CHECK(hs_effective_cap(&s,3,1)==60,"... also for smooth 60");
    s.fps_mode=0;s.thermal_cap=1;CHECK(hs_effective_cap(&s,3,1)==0,"the original 30 FPS mode is never touched");
    s.fps_mode=1;CHECK(hs_effective_cap(&s,-5,0)==60 && hs_effective_cap(&s,99,0)==30,"odd thermal values are safe");
    if (!failures) printf("PASS: settings core: 5 named presets round-trip, hostile input is clamped, layouts stay on screen, stick feel\n");
    return failures ? 1 : 0;
}
