#ifndef HALO_IOS_HUD_OPTIONS_H
#define HALO_IOS_HUD_OPTIONS_H
#include <stdint.h>
typedef struct { float x,y,scale,opacity;int32_t hidden; } HaloHudOptions;
typedef char halo_hud_size_check[sizeof(HaloHudOptions)==20?1:-1];
extern HaloHudOptions halo_ios_hud[5];
extern int halo_ios_hud_group;
#endif
