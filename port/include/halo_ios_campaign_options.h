#ifndef HALO_IOS_CAMPAIGN_OPTIONS_H
#define HALO_IOS_CAMPAIGN_OPTIONS_H
#include <stdint.h>
enum { IOS_CHEAT_ONE_HIT=16, IOS_CHEAT_FLASHLIGHT=32, IOS_CHEAT_NO_FALL=64,
       IOS_CHEAT_RAPID=128, IOS_CHEAT_NO_RECOIL=256, IOS_CHEAT_THIRD_PERSON=512,
       IOS_CHEAT_NOCLIP=1024 };
/* Exactly 20 bytes on both sides of the arm64_32/native boundary. */
typedef struct { uint32_t flags, action; float jump, speed, fov; } HaloCampaignOptions;
typedef char halo_campaign_options_size_check[sizeof(HaloCampaignOptions) == 20 ? 1 : -1];
#endif
