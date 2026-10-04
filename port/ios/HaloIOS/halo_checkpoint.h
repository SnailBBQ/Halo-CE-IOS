#ifndef HALO_CHECKPOINT_H
#define HALO_CHECKPOINT_H
/* Xbox 2342 persistent snapshot reader. All offsets describe the guest's
 * fixed 32-bit layout, never the host's pointer size. See the guest assertions
 * in game_state.c. No tag creation, pointer relocation or runtime cheat injection. */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#define HC_SIZE (16u * 1024u * 1024u)
#define HC_BASE 0x81a00000u
typedef struct { size_t unit, weapon[4]; unsigned weapons; } HcView;
static uint16_t hc_u16(const unsigned char *b,size_t p) { return (uint16_t)(b[p]|(unsigned)b[p+1]<<8); }
static uint32_t hc_u32(const unsigned char *b,size_t p) { return hc_u16(b,p)|((uint32_t)hc_u16(b,p+2)<<16); }
static void hc_put16(unsigned char *b,size_t p,uint16_t v) { b[p]=(unsigned char)v;b[p+1]=(unsigned char)(v>>8); }
static void hc_put32(unsigned char *b,size_t p,uint32_t v) { hc_put16(b,p,(uint16_t)v);hc_put16(b,p+2,(uint16_t)(v>>16)); }
static float hc_float(const unsigned char *b,size_t p) { uint32_t v=hc_u32(b,p);float f;memcpy(&f,&v,4);return f; }
static void hc_putfloat(unsigned char *b,size_t p,float f) { uint32_t v;memcpy(&v,&f,4);hc_put32(b,p,v); }
static uint32_t hc_crc(const unsigned char *b) {
    uint32_t table[256],crc=UINT32_MAX;
    for(unsigned i=0;i<256;i++){uint32_t c=i;for(unsigned j=0;j<8;j++)c=(c>>1)^((c&1)?0xedb88320u:0);table[i]=c;}
    for(size_t i=0;i<HC_SIZE;i++){unsigned char c=(i>=0x148&&i<0x14c)?0:b[i];crc=(crc>>8)^table[(crc^c)&255];}
    return crc;
}
static int hc_span(uint32_t pointer,size_t length,size_t *offset) {
    if(pointer<HC_BASE)return 0;
    size_t p=pointer-HC_BASE;
    if(p>HC_SIZE||length>HC_SIZE-p)return 0;
    *offset=p;return 1;
}
/* Descriptors are self-identifying, aligned and followed by their allocation.
 * Reject duplicate valid descriptors rather than guessing which is live. */
static int hc_array(const unsigned char *b,const char *name,unsigned count,unsigned stride,size_t *data) {
    unsigned found=0;size_t len=strlen(name);
    for(size_t p=0x14c;p+56+(size_t)count*stride<=HC_SIZE;p+=4) {
        if(memcmp(b+p,name,len+1)||hc_u16(b,p+32)!=count||hc_u16(b,p+34)!=stride||b[p+36]!=1||
           hc_u32(b,p+40)!=0x64407440u||hc_u16(b,p+46)>count||hc_u16(b,p+48)>count)continue;
        size_t d;if(!hc_span(hc_u32(b,p+52),(size_t)count*stride,&d)||d!=p+56)continue;
        *data=d;if(++found>1)return 0;
    }
    return found==1;
}
static int hc_object(const unsigned char *b,size_t headers,uint32_t id,unsigned type,size_t required,size_t *object) {
    unsigned index=id&65535;if(id==UINT32_MAX||index>=8192)return 0;
    size_t h=headers+(size_t)index*12;
    if(hc_u16(b,h)!=(id>>16)||!hc_u16(b,h)||b[h+3]!=type||hc_u16(b,h+6)<required)return 0;
    return hc_span(hc_u32(b,h+8),hc_u16(b,h+6),object);
}
static int hc_read(const unsigned char *b,size_t size,HcView *view) {
    if(!b||!view)return 0;
    memset(view,0,sizeof(*view));
    if(size!=HC_SIZE||memcmp(b+0x104,"01.01.14.2342",13)||!memchr(b+4,0,256)||
       memcmp(b+4,"levels\\",7)||hc_u16(b,0x124)!=1||hc_u16(b,0x126)>3||hc_u32(b,0x148)!=hc_crc(b))return 0;
    size_t players,headers;
    if(!hc_array(b,"players",128,0xd4,&players)||!hc_array(b,"object",8192,12,&headers))return 0;
    unsigned found=0;
    for(unsigned i=0;i<128;i++) {
        size_t p=players+(size_t)i*0xd4;
        if(!hc_u16(b,p)||hc_u16(b,p+2)!=0)continue;
        size_t u;if(!hc_object(b,headers,hc_u32(b,p+0x34),0,0x480,&u))return 0;
        if(++found>1)return 0;
        view->unit=u;
        float health=hc_float(b,u+0x90),shield=hc_float(b,u+0x94);
        if((hc_u16(b,u+0xb6)&4u)||!isfinite(health)||!isfinite(shield)||health<=0||health>1||shield<0||shield>3||b[u+0x2ce]>4||b[u+0x2cf]>4)return 0;
        for(unsigned slot=0;slot<4;slot++) {
            uint32_t id=hc_u32(b,u+0x2a8+slot*4);if(id==UINT32_MAX)continue;
            size_t w;if(!hc_object(b,headers,id,2,0x27c,&w))return 0;
            for(unsigned j=0;j<view->weapons;j++)if(view->weapon[j]==w)return 0;
            view->weapon[view->weapons++]=w;
        }
    }
    return found==1;
}
/* Edits are finite checkpoint values. Infinite health, gravity, camera and
 * projectile behavior belong to runtime cheats and are not saved fields. */
static int hc_edit(unsigned char *b,size_t size,const HcView *view,float health,float shield,unsigned frag,unsigned plasma,
                   const unsigned reserve[4][2],const unsigned loaded[4][2]) {
    if(!view)return 0;
    HcView verified;if(!hc_read(b,size,&verified)||memcmp(&verified,view,sizeof(verified))||
       !isfinite(health)||health<=0||health>1||!isfinite(shield)||shield<0||shield>1||frag>4||plasma>4)return 0;
    for(unsigned i=0;i<view->weapons;i++)for(unsigned m=0;m<2;m++)if(reserve[i][m]>999||loaded[i][m]>999)return 0;
    hc_putfloat(b,view->unit+0x90,health);hc_putfloat(b,view->unit+0x94,shield);
    b[view->unit+0x2ce]=(unsigned char)frag;b[view->unit+0x2cf]=(unsigned char)plasma;
    for(unsigned i=0;i<view->weapons;i++)for(unsigned m=0;m<2;m++) {
        size_t mag=view->weapon[i]+0x258+m*12;
        hc_put16(b,mag+6,(uint16_t)reserve[i][m]);hc_put16(b,mag+8,(uint16_t)loaded[i][m]);
    }
    hc_put32(b,0x148,hc_crc(b));return 1;
}
#endif
