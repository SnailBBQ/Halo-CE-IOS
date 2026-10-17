#ifndef HALO_ENGINE_SETTINGS_H
#define HALO_ENGINE_SETTINGS_H
#include "halo_settings_core.h"
/* Fixed text slots, copied through a bounded arena span. No profile pointers
 * leave the game thread. Halo profile fields are saved by the engine, not here. */
/* slots 20 to 22 follow the voice chat mode (0 off, 1 open mic, 2 push to talk), the voices' volume and reverb, shared with the in-game audio menu */
enum { HE_COUNT=23, HE_PROFILE=9 };
static inline int he_is_profile(int i) { return i>=HE_PROFILE && i<19; }
static inline void he_text(const HsSettings *s,int i,char text[64]) {
    double v=0;
    switch(i){case 0:v=s->volume;break;case 1:v=s->music_volume;break;case 2:v=s->effects_volume;break;
    case 3:v=s->game_vsync;break;case 4:v=s->fps_mode!=0;break;case 5:v=s->game_online;break;case 6:v=s->game_upnp;break;
    case 7:v=s->join_from_clipboard;break;case 8:v=s->audio_enabled;break;
    case 17:snprintf(text,64,"%s",s->game_name);return;case 18:v=s->game_color;break;
    case 19:v=s->game_player_names;break;
    case 20:v=s->voice_mode;break;case 21:v=s->voice_volume;break;case 22:v=s->reverb;break;
    default:if(i>=9 && i<17)v=s->game_controls[i-9];break;}
    snprintf(text,64,"%.4f",v);
}
static inline void he_set(HsSettings *s,int i,const char *text) {
    float v=(float)atof(text);if(!isfinite(v))return;
    /* Bound numeric slots before converting to integers, including malformed
     * values supplied by a configuration file. Names use the original text. */
    v=hs_clampf(v,-1,100);
    switch(i){case 0:s->volume=v;break;case 1:s->music_volume=v;break;case 2:s->effects_volume=v;break;
    case 3:s->game_vsync=v!=0;break;case 4:if(v==0)s->fps_mode=0;else if(!s->fps_mode)s->fps_mode=1;break;
    case 5:s->game_online=v!=0;break;case 6:s->game_upnp=v!=0;break;case 7:s->join_from_clipboard=v!=0;break;case 8:s->audio_enabled=v!=0;break;
    case 17:snprintf(s->game_name,24,"%s",text);s->game_profile_ready=1;break;case 18:s->game_color=(int)v;break;
    case 19:s->game_player_names=(int)v;break;
    case 20:s->voice_mode=hs_clampi((int)v,0,2);break;case 21:s->voice_volume=hs_clampf(v,0,2);break;case 22:s->reverb=v!=0;break;
    default:if(i>=9 && i<17)s->game_controls[i-9]=(int)v;break;}
}
#endif
