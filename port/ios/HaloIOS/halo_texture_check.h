#ifndef HALO_TEXTURE_CHECK_H
#define HALO_TEXTURE_CHECK_H
#include "halo_hash_native.h"
#include <stdlib.h>
#define HT_SLOTS 32
#define HT_BUDGET (8u*1024u*1024u)
#define HT_MAX_ITEM (1024u*1024u)
typedef struct { uint32_t address,hash; size_t size; unsigned char *snapshot; uint64_t used; } HtEntry;
typedef struct { HtEntry entries[HT_SLOTS]; size_t allocated; uint64_t clock,calls,hits,compared,hashed; } HtCache;
/* Caller resolves the full guest span and serializes access. Only owned byte
 * snapshots and scalar guest addresses survive calls. Every hit compares ALL
 * bytes; no frame-based assumptions, sampled hashes or write protection. */
static inline void ht_reset(HtCache *c) {
    for(unsigned i=0;i<HT_SLOTS;i++){free(c->entries[i].snapshot);memset(&c->entries[i],0,sizeof(HtEntry));}
    c->allocated=0;
}
static inline void ht_forget(HtCache *c,uint32_t address,uint32_t size) {
    uint64_t end=(uint64_t)address+size;
    for(unsigned i=0;i<HT_SLOTS;i++) {
        HtEntry *e=&c->entries[i];
        if(e->snapshot && size && (uint64_t)e->address<end && (uint64_t)address<(uint64_t)e->address+e->size) {
            c->allocated-=e->size;free(e->snapshot);memset(e,0,sizeof(*e));
        }
    }
}
static inline uint32_t ht_hash(HtCache *c,uint32_t address,const void *bytes,size_t size) {
    ++c->calls;
    if(!bytes)return 1;
    if(size<4096 || size>HT_MAX_ITEM) {c->hashed+=size;return halo_hash_bytes(bytes,size);}
    HtEntry *entry=NULL;
    for(unsigned i=0;i<HT_SLOTS;i++) {
        HtEntry *e=&c->entries[i];
        if(e->snapshot && e->address==address && e->size==size) {entry=e;break;}
    }
    if(entry) {
        c->compared+=size;entry->used=++c->clock;
        if(!memcmp(entry->snapshot,bytes,size)){++c->hits;return entry->hash;}
    }
    c->hashed+=size;
    if(!entry) {
        /* Evict the least recently used snapshot until both limits fit. */
        for(;;) {
            HtEntry *oldest=NULL;
            for(unsigned i=0;i<HT_SLOTS;i++) {
                HtEntry *e=&c->entries[i];
                if(!e->snapshot){if(!entry)entry=e;continue;}
                if(!oldest || e->used<oldest->used)oldest=e;
            }
            if(entry && c->allocated+size<=HT_BUDGET)break;
            c->allocated-=oldest->size;free(oldest->snapshot);memset(oldest,0,sizeof(*oldest));entry=NULL;
        }
        entry->snapshot=malloc(size);
        if(!entry->snapshot)return halo_hash_bytes(bytes,size); /* Original full hash remains usable. */
        entry->address=address;entry->size=size;c->allocated+=size;
    }
    /* Hash the owned snapshot, not a second read of live data. Even if a
     * worker writes during capture, the saved hash matches the saved bytes;
     * the next full comparison will detect the live data's new contents. */
    memcpy(entry->snapshot,bytes,size);
    entry->hash=halo_hash_bytes(entry->snapshot,size);entry->used=++c->clock;
    return entry->hash;
}
#endif
