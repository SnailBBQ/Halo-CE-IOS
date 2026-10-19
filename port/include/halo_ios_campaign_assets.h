#ifndef HALO_IOS_CAMPAIGN_ASSETS_H
#define HALO_IOS_CAMPAIGN_ASSETS_H

#include <stdint.h>

#define HALO_CAMPAIGN_ASSET_MAX 256
#define HALO_CAMPAIGN_ASSET_NAME_MAX 128

enum {
    HALO_CAMPAIGN_ASSET_WEAPON = 1,
    HALO_CAMPAIGN_ASSET_VEHICLE = 2
};

typedef struct {
    uint32_t token;
    uint32_t kind;
    char name[HALO_CAMPAIGN_ASSET_NAME_MAX];
} HaloCampaignAssetEntry;

typedef char halo_campaign_asset_entry_size_check[
    sizeof(HaloCampaignAssetEntry) == HALO_CAMPAIGN_ASSET_NAME_MAX + 8 ? 1 : -1];

#define HALO_CAMPAIGN_ASSET_ACTION_FLAG UINT32_C(0x80000000)
#define HALO_CAMPAIGN_ASSET_ACTION_MODE_SHIFT 28
#define HALO_CAMPAIGN_ASSET_ACTION_TOKEN_MASK UINT32_C(0x0fffffff)
#define HALO_CAMPAIGN_ASSET_ACTION(token, mode) \
    (HALO_CAMPAIGN_ASSET_ACTION_FLAG | (((uint32_t)(mode) & 3u) << HALO_CAMPAIGN_ASSET_ACTION_MODE_SHIFT) | \
     ((uint32_t)(token) & HALO_CAMPAIGN_ASSET_ACTION_TOKEN_MASK))

#endif
