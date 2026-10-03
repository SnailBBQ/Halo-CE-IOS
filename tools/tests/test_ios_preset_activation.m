#import "HaloSettingsStore.h"
#include <stdio.h>
#include <stdlib.h>
static unsigned actions,flags;
void halo_ios_set_channel_gains(float a,float b,float c){(void)a;(void)b;(void)c;}
void halo_ios_audio_set_volume(float v){(void)v;}
void halo_ios_set_profiler_enabled(int v){(void)v;}
void halo_ios_gl_set_frame_cap(int v){(void)v;}
void halo_ios_set_cheat_flags(uint32_t v){flags=v;}
void halo_ios_set_viewmodel_flags(uint32_t v){(void)v;}
int halo_ios_queue_campaign_action(uint32_t v){if(v)actions++;return 1;}
#define CHECK(v) do{if(!(v)){fprintf(stderr,"FAIL line %d\n",__LINE__);exit(1);}}while(0)
int main(void){@autoreleasepool{
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"HaloSettingsV1"];
    HaloSettingsStore *store=HaloSettingsStore.shared;
    [store update:^(HsSettings *s){s->presets[0].cheat_flags=1;s->presets[0].cheat_actions=4;s->presets[1].cheat_flags=2;s->presets[1].cheat_weapon=1;}];
    CHECK(!flags && !actions);
    [store setCampaignActive:YES];CHECK(flags==1 && actions==1);
    [store setCampaignActive:YES];CHECK(actions==1);
    [store update:^(HsSettings *s){s->volume=.5;}];CHECK(actions==1);
    [store update:^(HsSettings *s){s->active=1;}];CHECK(flags==2 && actions==2);
    [store setCampaignActive:NO];CHECK(!flags);
    [store update:^(HsSettings *s){s->active=0;}];CHECK(!flags && actions==2);
    NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:@"HaloSettingsV1"];HsSettings parsed;hs_parse(&parsed,saved.UTF8String);
    CHECK(!hs_cheat_mask(&parsed) && parsed.presets[0].cheat_flags==1);
    [store setCampaignActive:YES];CHECK(flags==1 && actions==3);
    [store setCampaignActive:NO];
    [store update:^(HsSettings *s){s->hud_presets[2].elements[1].scale=.7f;s->presets[2].hud_choice=3;s->active=2;}];
    HsSettings linked=[store snapshot];CHECK(linked.hud[1].scale==.7f && linked.hud_presets[2].elements[1].scale==.7f);
    [store update:^(HsSettings *s){s->presets[2].place[HC_A].scale=1.2f;}];CHECK([store snapshot].hud_presets[2].elements[1].scale==.7f);
    [store update:^(HsSettings *s){s->presets[2].hud_choice=0;}];CHECK([store snapshot].hud[1].scale==1 && [store snapshot].hud_presets[2].elements[1].scale==.7f);
    puts("PASS: recipes activate on campaign entry/preset selection only, one-shots do not repeat, multiplayer clears runtime state, saves contain recipes only");
}return 0;}
