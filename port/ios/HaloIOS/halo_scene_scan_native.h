#ifndef HALO_SCENE_SCAN_NATIVE_H
#define HALO_SCENE_SCAN_NATIVE_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
typedef const void *(*halo_scene_resolve)(uint32_t,size_t);
static uint32_t halo_scene_u32(const void *p,size_t o) { uint32_t v;
    memcpy(&v,(const unsigned char *)p+o,4);
    return v; }
static int16_t halo_scene_i16(const void *p,size_t o) { int16_t v;
    memcpy(&v,(const unsigned char *)p+o,2);
    return v; }
static void halo_scene_write32(void *p,size_t o,uint32_t v) { memcpy((unsigned char *)p+o,&v,4); }
/* Read fresh datum metadata on every call. Layout comes from guest offsetof;
   native LP64 padding is never used. Invalid metadata returns to the guest's
   existing assertion path, rather than suppressing its diagnostics. */
static int halo_scene_datum(halo_scene_resolve resolve,uint32_t kind,uint32_t address,uint32_t index,
const uint32_t l[13],uint32_t out[3],uint64_t *visited)
{
    if (kind<1 || kind>4 || !l[0] || l[0]>4096) return 0;
    static const uint32_t widths[10]={2,2,1,1,4,2,2,2,4,2};
    for (unsigned i=1;i<=10;i++) if (l[i]>l[0] || widths[i-1]>l[0]-l[i]) return 0;
    const unsigned char *iterator=NULL;
    if (kind==2) {
        iterator=resolve(address,16);
        if (!iterator) return 0;
        address=halo_scene_u32(iterator,0);
        if (halo_scene_u32(iterator,12)!=(address^l[12])) return 0;
    }
    if (kind==4 && index==UINT32_MAX) { out[0]=0;
        return 1; }
    const unsigned char *data=resolve(address,l[0]);
    if (!data) return 0;
    int32_t maximum=halo_scene_i16(data,l[1]),stride=halo_scene_i16(data,l[2]);
    int32_t count=halo_scene_i16(data,l[7]),actual=halo_scene_i16(data,l[8]),free_index=halo_scene_i16(data,l[6]);
    uint32_t base=halo_scene_u32(data,l[9]);
    if (!base || maximum<0 || stride<2 || count<0 || count>maximum || actual<0 || actual>count ||
    free_index<0 || free_index>maximum || halo_scene_u32(data,l[5])!=l[11] || !data[l[3]]) return 0;
    if (kind>=3) {
        int32_t slot=(int16_t)index;uint16_t identifier=(uint16_t)(index>>16);
        if (!identifier && data[l[4]]) return 0;
        int32_t limit=kind==4?maximum:count;
        if (slot<0 || slot>=limit) { if (kind==4) { out[0]=0;
                return 1; }return 0; }
        uint64_t va=(uint64_t)base+(uint64_t)(uint32_t)slot*(uint32_t)stride;
        const void *header=va<=UINT32_MAX?resolve((uint32_t)va,(size_t)stride):NULL;
        if (!header) return 0;
        ++*visited;uint16_t salt=(uint16_t)halo_scene_i16(header,0);
        if (!salt || (identifier && salt!=identifier)) { if(kind==4){out[0]=0;
                return 1;}return 0; }
        out[0]=(uint32_t)va;
        return 1;
    }
    int32_t slot=kind==2?halo_scene_i16(iterator,4):(int16_t)(index+1u);
    uint32_t old_datum=kind==2?halo_scene_u32(iterator,8):UINT32_MAX;
    if (slot<0) { if (kind==1) {out[0]=UINT32_MAX;
            return 1;}return 0; }
    out[0]=kind==2?0:UINT32_MAX;out[1]=(uint32_t)slot;out[2]=old_datum;
    if (slot>=count) return 1;
    uint64_t start=(uint64_t)base+(uint64_t)(uint32_t)slot*(uint32_t)stride;
    size_t bytes=(size_t)(count-slot)*(uint32_t)stride;
    const unsigned char *rows=start<=UINT32_MAX?resolve((uint32_t)start,bytes):NULL;
    if (!rows) return 0;
    for (;slot<count;slot++,rows+=stride) {
        ++*visited;uint16_t salt=(uint16_t)halo_scene_i16(rows,0);
        if (salt) {
            uint32_t datum=((uint32_t)salt<<16)|(uint32_t)slot;
            out[0]=kind==2?base+(uint64_t)(uint32_t)slot*(uint32_t)stride:datum;
            out[1]=(uint32_t)slot+1;out[2]=datum;
            return 1;
        }
    }
    out[1]=(uint32_t)slot;
    return 1;
}
/* Validate every selected index before writing triangle outputs. Six bytes per
   structure_surface; vertex bits are copied unchanged, including 0xffff. */
static int halo_scene_triangles(const void *surfaces,uint32_t total,const void *indices,uint32_t count,void *triangles)
{
    for (uint32_t i=0;i<count;i++) if (halo_scene_u32(indices,(size_t)i*4)>=total) return 0;
    for (uint32_t i=0;i<count;i++) {
        uint32_t index=halo_scene_u32(indices,(size_t)i*4);
        memcpy((unsigned char *)triangles+(size_t)i*6,(const unsigned char *)surfaces+(size_t)index*6,6);
    }
    return 1;
}
/* This replaces only compare_surface_indices: a pure signed integer ordering.
   Equal entries are indistinguishable, so no stable-sort dependency exists.
   No recovered callback is invoked by the native library sort. */
static int halo_scene_compare_index(const void *a,const void *b)
{
    int32_t x,y;memcpy(&x,a,4);memcpy(&y,b,4);
    return (x>y)-(x<y);
}
static int halo_scene_sorted_triangles(const void *surfaces,uint32_t total,void *indices,uint32_t count,void *triangles)
{
    for(uint32_t i=0;i<count;i++)if(halo_scene_u32(indices,(size_t)i*4)>=total)return 0;
    if(count>1)qsort(indices,count,4,halo_scene_compare_index);
    return halo_scene_triangles(surfaces,total,indices,count,triangles);
}
static int halo_scene_bit_triangles(const void *surfaces,uint32_t total,const void *flags,uint32_t capacity,
void *indices,void *triangles,uint32_t *selected)
{
    uint32_t count=0;
    for (uint32_t i=0;i<total;i++) if (halo_scene_u32(flags,(size_t)(i>>5)*4)&(1u<<(i&31))) {
        if (count==capacity) return 0;
        ++count;
    }
    count=0;
    for (uint32_t word=0;word<(total+31u)/32u;word++) {
        uint32_t bits=halo_scene_u32(flags,(size_t)word*4);
        if (!bits) continue;
        for (unsigned bit=0;bit<32;bit++) {
            uint32_t index=word*32u+bit;
            if(index>=total) break;
            if (bits&(1u<<bit)) {
                halo_scene_write32(indices,(size_t)count*4,index);
                memcpy((unsigned char *)triangles+(size_t)count*6,(const unsigned char *)surfaces+(size_t)index*6,6);++count;
            }
        }
    }
    *selected=count;
    return 1;
}
/* Always consume the first index, matching the original do/while. */
static uint32_t halo_scene_material_run(const void *indices,uint32_t count,int32_t end)
{ uint32_t i=1;while(i<count && (int32_t)halo_scene_u32(indices,(size_t)i*4)<end) ++i;
    return i; }
/* Preserve duplicate handling and stop only when a new surface would exceed
   capacity. Do not examine indices beyond that early-out. */
static int halo_scene_mark(const void *indices,uint32_t count,uint32_t total,void *flags,
uint32_t current,uint32_t maximum,uint32_t *updated,uint64_t *visited)
{
    for(uint32_t i=0;i<count;i++) {
        uint32_t index=halo_scene_u32(indices,(size_t)i*4);++*visited;
        if(index>=total) return 0;
        size_t offset=(size_t)(index>>5)*4;
        uint32_t bits=halo_scene_u32(flags,offset),mask=1u<<(index&31);
        if (!(bits&mask)) { if(current>=maximum) break;halo_scene_write32(flags,offset,bits|mask);++current; }
    }
    *updated=current;
    return 1;
}
static int halo_scene_leaf(const void *references,uint32_t count,uint32_t stride,uint32_t offset,uint32_t total,
const void *allowed,void *seen,void *indices,uint32_t maximum,uint32_t *found,uint64_t *visited)
{
    uint32_t result=0;
    for(uint32_t i=0;i<count;i++) {
        uint32_t index=halo_scene_u32(references,(size_t)i*stride+offset);++*visited;
        if(index>=total) return 0;
        size_t word=(size_t)(index>>5)*4;
        uint32_t mask=1u<<(index&31),bits=halo_scene_u32(seen,word);
        if ((halo_scene_u32(allowed,word)&mask) && !(bits&mask)) {
            if(result>=maximum) break;
            halo_scene_write32(seen,word,bits|mask);halo_scene_write32(indices,(size_t)result*4,index);++result;
        }
    }
    *found=result;
    return 1;
}

/* Shadow-only rejection. Invisible parents/widgets stay in the guest path.
   Guest callers query ONE scratch entry immediately before its callback; no
   eligibility snapshot survives another callback. Stage bulk output so even
   a late malformed datum leaves the caller's input and count untouched. */
static inline int halo_scene_filter_objects(halo_scene_resolve resolve,
    uint32_t data_va,const uint32_t *layout,uint32_t *indices,uint32_t count,
    uint32_t mask,uint32_t *kept,uint64_t *visited)
{
    uint32_t staged[512],out_count=0;
    static const uint32_t widths[10]={2,2,1,1,4,2,2,2,4,2};
    if(!resolve || !layout || !indices || !kept || !visited || count>512 ||
       (mask&~2u) || !layout[0] || layout[0]>4096) return 0;
    for(unsigned i=1;i<=10;i++)
        if(layout[i]>layout[0] || widths[i-1]>layout[0]-layout[i]) return 0;
    const void *data=resolve(data_va,layout[0]);
    if(!data || halo_scene_i16(data,layout[2])<12) return 0;
    for(uint32_t i=0;i<count;i++) {
        uint32_t result[3];
        /* Strict datum lookup: invalid salts/rows fall back to guest asserts. */
        if(!halo_scene_datum(resolve,3,data_va,indices[i],layout,result,visited)) return 0;
        const void *header=resolve(result[0],12);
        if(!header) return 0;
        const void *object=resolve(halo_scene_u32(header,8),8);
        if(!object) return 0;
        uint32_t flags=halo_scene_u32(object,4);
        if(!(mask&2u) || !(flags&(1u<<18))) staged[out_count++]=indices[i];
    }
    if(out_count) memcpy(indices,staged,(size_t)out_count*4);
    *kept=out_count;
    return 1;
}
#endif
