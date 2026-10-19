#ifndef HALO_ENGINE_SETTINGS_H
#define HALO_ENGINE_SETTINGS_H
#include "halo_settings_core.h"
/* Fixed text slots, copied through a bounded arena span. No profile pointers
 * leave the game thread. Halo profile fields are saved by the engine, not here. */
/* slots 20 to 22 follow the voice chat mode (0 off, 1 open mic, 2 push to talk), the voices' volume and reverb, shared with the in-game audio menu */
/* slots 23 and up follow config.toml's display.* (video, first person, names, scoreboard, chat) and streamer.* the same way: 23 anti_aliasing,
 * 24 shadow_resolution, 25 per_pixel_lighting, 26 shield_glow, 27 shield_glow_intensity, 28 fov, 29 viewmodel_fov, 30 viewmodel_visible (the
 * app's first-person "Hidden"), 31 viewmodel_shield, 32 first_person_legs, 33 shield_color, 34 player_name_scale, 35 scoreboard_team_layout,
 * 36 scoreboard_background, 37 text_chat, 38 chat_style, 39 to 42 streamer enabled, slurs, swearing and insults; the engine side's table
 * (port/linux/game/menu_functions.c) lists each one's values */
enum { HE_COUNT=43, HE_PROFILE=9 };
static inline int he_is_profile(int i) { return i>=HE_PROFILE && i<19; }
static inline void he_text(const HsSettings *s,int i,char text[64]) {
    double v=0;
    switch(i){case 0:v=s->volume;break;case 1:v=s->music_volume;break;case 2:v=s->effects_volume;break;
    case 3:v=s->game_vsync;break;case 4:v=s->fps_mode!=0;break;case 5:v=s->game_online;break;case 6:v=s->game_upnp;break;
    case 7:v=s->join_from_clipboard;break;case 8:v=s->audio_enabled;break;
    case 17:snprintf(text,64,"%s",s->game_name);return;case 18:v=s->game_color;break;
    case 19:v=s->game_player_names;break;
    case 20:v=s->voice_mode;break;case 21:v=s->voice_volume;break;case 22:v=s->reverb;break;
    case 23:v=s->aa_mode;break;case 24:v=s->shadow_res;break;case 25:v=s->per_pixel;break;case 26:v=s->shield_glow;break;
    case 27:v=s->glow_light_show;break;case 28:snprintf(text,64,"%.1f",s->fov);return;case 29:snprintf(text,64,"%.1f",s->viewmodel_fov);return;
    case 30:v=s->viewmodel_mode!=3;break;case 31:v=s->vm_shield;break;case 32:v=s->legs;break;case 33:v=s->shield_color;break;
    case 34:v=s->name_scale;break;case 35:v=s->sb_layout;break;case 36:v=s->sb_panel;break;case 37:v=s->text_chat;break;
    case 38:v=s->chat_style;break;case 39:v=s->streamer;break;case 40:v=s->streamer_slurs;break;case 41:v=s->streamer_swearing;break;
    case 42:v=s->streamer_insults;break;
    default:if(i>=9 && i<17)v=s->game_controls[i-9];break;}
    snprintf(text,64,"%.4f",v);
}
static inline void he_set(HsSettings *s,int i,const char *text) {
    float v=(float)atof(text);if(!isfinite(v))return;
    /* Bound numeric slots before converting to integers, including malformed
     * values supplied by a configuration file. Names use the original text. */
    v=hs_clampf(v,-1,200);
    switch(i){case 0:s->volume=v;break;case 1:s->music_volume=v;break;case 2:s->effects_volume=v;break;
    case 3:s->game_vsync=v!=0;break;case 4:if(v==0)s->fps_mode=0;else if(!s->fps_mode)s->fps_mode=1;break;
    case 5:s->game_online=v!=0;break;case 6:s->game_upnp=v!=0;break;case 7:s->join_from_clipboard=v!=0;break;case 8:s->audio_enabled=v!=0;break;
    case 17:snprintf(s->game_name,24,"%s",text);s->game_profile_ready=1;break;case 18:s->game_color=(int)v;break;
    case 19:s->game_player_names=(int)v;break;
    case 20:s->voice_mode=hs_clampi((int)v,0,2);break;case 21:s->voice_volume=hs_clampf(v,0,2);break;case 22:s->reverb=v!=0;break;
    case 23:s->aa_mode=hs_clampi((int)v,0,6);break;case 24:s->shadow_res=hs_clampi((int)v,0,3);break;case 25:s->per_pixel=v!=0;break;
    case 26:s->shield_glow=v!=0;break;case 27:s->glow_light_show=v!=0;break;
    case 28:s->fov=v<1?0:hs_clampf(v,20,150);break;case 29:s->viewmodel_fov=v<1?0:hs_clampf(v,20,150);break;
    case 30:if(v==0)s->viewmodel_mode=3;else if(s->viewmodel_mode==3)s->viewmodel_mode=0;break;
    case 31:s->vm_shield=v!=0;break;case 32:s->legs=v!=0;break;case 33:s->shield_color=hs_clampi((int)v,0,18);break;
    case 34:s->name_scale=hs_clampf(v,0.25f,4);break;case 35:s->sb_layout=hs_clampi((int)v,0,1);break;case 36:s->sb_panel=v!=0;break;
    case 37:s->text_chat=v!=0;break;case 38:s->chat_style=hs_clampi((int)v,0,1);break;case 39:s->streamer=v!=0;break;
    case 40:s->streamer_slurs=hs_clampi((int)v,0,3);break;case 41:s->streamer_swearing=hs_clampi((int)v,0,3);break;
    case 42:s->streamer_insults=hs_clampi((int)v,0,3);break;
    default:if(i>=9 && i<17)s->game_controls[i-9]=(int)v;break;}
}
#endif
