#ifndef HALO_RENDER_SCAN_NATIVE_H
#define HALO_RENDER_SCAN_NATIVE_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
typedef const void *(*halo_scan_resolve)(void *,uint32_t,size_t);
#define HALO_SCAN_NODE_LIMIT 65536u
static uint32_t halo_scan_word(const void *p,size_t offset)
{ uint32_t v;memcpy(&v,(const unsigned char *)p+offset,4);return v; }
static int halo_scan_field(uint32_t size,uint32_t offset,uint32_t bytes)
{ return offset<=size && bytes<=size-offset; }
/* The original index loop starts at 0xffff/0, including an empty range.
   memcpy reads make unaligned input safe without changing 16-bit ordering. */
static void halo_scan_indices(const void *data,uint32_t count,uint32_t out[2])
{
    uint32_t low=65535,high=0;
    for (uint32_t i=0;i<count;i++) {
        uint16_t v;memcpy(&v,(const unsigned char *)data+(size_t)i*2,2);
        if (v<low) low=v;
        if (v>high) high=v;
    }
    out[0]=low;out[1]=high;
}
static uint32_t halo_scan_hash_words(const void *data,uint32_t size)
{
    uint32_t hash=2166136261u;
    for (uint32_t offset=0;offset<size;offset+=4) hash=(hash^halo_scan_word(data,offset))*16777619u;
    return hash;
}
/* Word-wise FNV is deliberately different from the byte-wise texel hash. */
static uint32_t halo_scan_palette(const void *palette)
{
    if (!palette) return 0;
    uint32_t hash=2166136261u;
    for (unsigned i=0;i<256;i++) hash=(hash^halo_scan_word(palette,i*4))*16777619u;
    return hash?hash:1;
}
/* Stateless list lookup. The guest supplies sizeof/offsetof from its own ABI;
   no native struct layout is assumed. Validate each complete node before use.
   A bounded walk also rejects malformed cycles. First-match order is retained. */
static int halo_scan_shader(halo_scan_resolve resolve,void *context,uint32_t head,
    uint32_t size,uint32_t next,uint32_t key_offset,uint32_t key_size,const void *key,
    uint32_t hash_offset,uint32_t hash,uint32_t use_hash,uint32_t *out,uint32_t *visited)
{
    *visited=0;
    if (!size || size>65536 || !key || !key_size || key_size>4096 || use_hash>2 ||
        !halo_scan_field(size,next,4) || !halo_scan_field(size,key_offset,key_size) ||
        (use_hash==1 && !halo_scan_field(size,hash_offset,4))) return 0;
    while (head) {
        if (*visited==HALO_SCAN_NODE_LIMIT) return 0;
        const unsigned char *node=resolve(context,head,size);
        if (!node) return 0;
        ++*visited;
        if ((use_hash!=1 || halo_scan_word(node,hash_offset)==hash) && !memcmp(node+key_offset,key,key_size)) {
            *out=head;return 1;
        }
        head=use_hash==2?0:halo_scan_word(node,next);
    }
    *out=0;return 1;
}
/* Texture walk also selects the first stalest palette variant. Ties keep the
   earlier node, exactly as the guest's strict-less-than comparison does. */
static int halo_scan_texture(halo_scan_resolve resolve,void *context,uint32_t head,
    uint32_t size,uint32_t next,uint32_t data_offset,uint32_t palette_offset,uint32_t frame_offset,
    const uint32_t key[4],uint32_t out[3],uint32_t *visited)
{
    uint32_t found=0,variants=0,oldest=0,oldest_frame=0;
    *visited=0;
    if (!size || size>65536 || !key || !halo_scan_field(size,next,4) ||
        !halo_scan_field(size,data_offset,12) || !halo_scan_field(size,palette_offset,4) ||
        !halo_scan_field(size,frame_offset,4)) return 0;
    while (head) {
        if (*visited==HALO_SCAN_NODE_LIMIT) return 0;
        const unsigned char *node=resolve(context,head,size);
        if (!node) return 0;
        ++*visited;
        if (!memcmp(node+data_offset,key,12)) {
            if (halo_scan_word(node,palette_offset)==key[3]) { found=head;break; }
            ++variants;
            uint32_t frame=halo_scan_word(node,frame_offset);
            if (!oldest || frame<oldest_frame) { oldest=head;oldest_frame=frame; }
        }
        head=halo_scan_word(node,next);
    }
    out[0]=found;out[1]=variants;out[2]=oldest;return 1;
}
#endif
