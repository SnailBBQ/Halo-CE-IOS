#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "halo_render_scan_native.h"
static unsigned char arena[8192];
static const void *resolve(void *ctx,uint32_t va,size_t size)
{ (void)ctx;return va && va<=sizeof(arena) && size<=sizeof(arena)-va?arena+va:NULL; }
static uint32_t rng=5;
static uint32_t random_word(void) { rng=rng*1664525u+1013904223u;return rng; }
static void word(uint32_t va,uint32_t v) { memcpy(arena+va,&v,4); }
int main(void)
{
    uint32_t result[3],visited;
    for (unsigned trial=0;trial<10000;trial++) {
        unsigned count=random_word()%1025;uint32_t low=65535,high=0;
        for (unsigned i=0;i<count;i++) {
            uint16_t v=(uint16_t)random_word();memcpy(arena+1+i*2,&v,2);
            if (v<low) low=v;
            if (v>high) high=v;
        }
        halo_scan_indices(arena+1,count,result);assert(result[0]==low && result[1]==high);
    }
    halo_scan_indices(NULL,0,result);assert(result[0]==65535 && result[1]==0);
    assert(halo_scan_palette(NULL)==0);
    for (unsigned trial=0;trial<1000;trial++) {
        uint32_t hash=2166136261u;
        for (unsigned i=0;i<256;i++) { uint32_t v=random_word();word(1+i*4,v);hash=(hash^v)*16777619u; }
        assert(halo_scan_hash_words(arena+1,1024)==hash);
        assert(halo_scan_palette(arena+1)==(hash?hash:1));
    }
    assert(halo_scan_hash_words(NULL,0)==2166136261u);
    /* Random lists: compare native output with the exact ordered guest walk. */
    for (unsigned trial=0;trial<1000;trial++) {
        uint32_t key[4]={random_word()%3,7,8,random_word()%5};
        unsigned count=random_word()%60;uint32_t expect=0,variants=0,oldest=0,frame=0;
        for (unsigned i=0;i<count;i++) {
            uint32_t va=32+i*32;
            word(va,i+1<count?va+32:0);word(va+4,random_word()%3);word(va+8,7);word(va+12,8);
            word(va+16,random_word()%5);word(va+20,random_word()%7);
        }
        for (unsigned i=0;i<count;i++) {
            uint32_t va=32+i*32;
            if (halo_scan_word(arena+va,4)!=key[0]) continue;
            if (halo_scan_word(arena+va,16)==key[3]) { expect=va;break; }
            variants++;
            uint32_t f=halo_scan_word(arena+va,20);
            if (!oldest || f<frame) { oldest=va;frame=f; }
        }
        assert(halo_scan_texture(resolve,NULL,count?32:0,24,0,4,16,20,key,result,&visited));
        assert(result[0]==expect && result[1]==variants && result[2]==oldest && visited<=count);
        expect=0;
        for (unsigned i=0;i<count;i++) { uint32_t va=32+i*32;
            if (!memcmp(arena+va+4,key,12)) { expect=va;break; } }
        assert(halo_scan_shader(resolve,NULL,count?32:0,24,0,4,12,key,0,0,0,result,&visited) && result[0]==expect);
    }
    memset(arena,0,sizeof(arena));word(32,64);word(64,0);word(36,1);word(68,2);word(72,99);
    uint32_t key=2;
    assert(halo_scan_shader(resolve,NULL,32,16,0,4,4,&key,8,99,1,result,&visited) && result[0]==64 && visited==2);
    assert(halo_scan_shader(resolve,NULL,32,16,0,4,4,&key,0,0,2,result,&visited) && result[0]==0 && visited==1);
    result[0]=123;
    assert(!halo_scan_shader(resolve,NULL,32,16,15,4,4,&key,0,0,0,result,&visited) && result[0]==123);
    assert(!halo_scan_shader(resolve,NULL,8190,16,0,4,4,&key,0,0,0,result,&visited) && result[0]==123);
    word(32,32);key=3;
    assert(!halo_scan_shader(resolve,NULL,32,16,0,4,4,&key,0,0,0,result,&visited) && result[0]==123 && visited==HALO_SCAN_NODE_LIMIT);
    uint32_t texture_key[4]={3,0,0,0};result[0]=123;result[1]=456;result[2]=789;
    assert(!halo_scan_texture(resolve,NULL,32,24,0,4,16,20,texture_key,result,&visited));
    assert(result[0]==123 && result[1]==456 && result[2]==789);
    puts("PASS: 10000 index, 1000 palette/hash and 1000 ordered shader/texture differential cases; empty, unaligned, ties, malformed spans and cycles");
    return 0;
}
