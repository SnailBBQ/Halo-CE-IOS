#ifndef HALO_ATTRIBUTE_NATIVE_H
#define HALO_ATTRIBUTE_NATIVE_H
#include <stdint.h>
#include <string.h>

/* Only native GL names, offsets and copied values live here: no guest pointers.
   The renderer owns this state on its GL thread. Every guest cache invalidation
   invalidates this shadow too, including uploads, presentation and VAO changes. */
struct halo_attribute_state {
    uint32_t buffer,type,flags,offset;
    int32_t size,stride;
    unsigned char enabled,pointer_valid,value_valid,value_kind;
    float value[4];
};
struct halo_attribute_cache { struct halo_attribute_state attributes[16]; };
static void halo_attribute_invalidate(struct halo_attribute_cache *cache)
{
    memset(cache,0,sizeof(*cache));
    for (unsigned i=0;i<16;i++) cache->attributes[i].enabled=2;
}
/* Return 1 only when GL_ARRAY_BUFFER was bound; the guest updates its buffer
   shadow in that case. Returning 0 does not change the current buffer binding. */
static int halo_attribute_pointer(struct halo_attribute_cache *cache,uint32_t index,uint32_t buffer,
    int32_t size,uint32_t type,uint32_t flags,int32_t stride,uint32_t offset)
{
    if (index>=16) return -1;
    struct halo_attribute_state *a=&cache->attributes[index];
    if (a->enabled!=1) { glEnableVertexAttribArray(index);a->enabled=1; }
    if (a->pointer_valid && a->buffer==buffer && a->size==size && a->type==type &&
        a->flags==flags && a->stride==stride && a->offset==offset) return 0;
    /* Other native/guest code may bind a different buffer between calls. */
    glBindBuffer(GL_ARRAY_BUFFER,buffer);
    if (flags&2) glVertexAttribIPointer(index,size,type,stride,(const void *)(uintptr_t)offset);
    else glVertexAttribPointer(index,size,type,(flags&1)?GL_TRUE:GL_FALSE,stride,(const void *)(uintptr_t)offset);
    a->buffer=buffer;a->size=size;a->type=type;a->flags=flags;
    a->stride=stride;a->offset=offset;a->pointer_valid=1;
    return 1;
}
static int halo_attribute_value(struct halo_attribute_cache *cache,uint32_t index,const float *value)
{
    if (index>=16) return -1;
    struct halo_attribute_state *a=&cache->attributes[index];
    unsigned char kind=value?0:1;
    if (a->enabled!=0) { glDisableVertexAttribArray(index);a->enabled=0; }
    if (a->value_valid && a->value_kind==kind && (!value || !memcmp(a->value,value,sizeof(a->value)))) return 0;
    if (value) { memcpy(a->value,value,sizeof(a->value));glVertexAttrib4fv(index,value); }
    else glVertexAttribI4ui(index,0,0,0,0);
    a->value_kind=kind;a->value_valid=1;
    return 1;
}
#endif
