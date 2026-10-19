#ifndef HALO_GEOMETRY_CACHE_H
#define HALO_GEOMETRY_CACHE_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
/* Owned byte snapshots only, never live guest pointers. Logical 4 KiB blocks
   are comparisons, not VM protection pages; no 16 KiB protection changes. */
#define HG_PAGE_SIZE 4096u
#define HG_PAGE_COUNT (0x10000000u / HG_PAGE_SIZE) /* the 256 MiB Xbox memory window of the iOS guest */
typedef const void *(*HgResolve)(void *, uint32_t, size_t);
typedef struct { unsigned char *page[HG_PAGE_COUNT]; uint64_t compared, changed; } HgCache;
static inline void hg_reset(HgCache *c) {
    for (unsigned i=0;i<HG_PAGE_COUNT;++i) { free(c->page[i]); c->page[i]=NULL; }
}
static inline int hg_compare(HgCache *c, HgResolve resolve, void *context,
    uint32_t first, uint32_t count, unsigned char *dirty) {
    if (!resolve || !dirty || !count || count>256 || first>=HG_PAGE_COUNT || count>HG_PAGE_COUNT-first) return 0;
    /* Validate the entire range before mutating cache state or output. */
    const unsigned char *source=resolve(context,0x80000000u+first*HG_PAGE_SIZE,(size_t)count*HG_PAGE_SIZE);
    if (!source) return 0;
    for (uint32_t i=0;i<count;++i) {
        unsigned char **saved=&c->page[first+i];
        const unsigned char *bytes=source+(size_t)i*HG_PAGE_SIZE;
        dirty[i]=!(*saved) || memcmp(*saved,bytes,HG_PAGE_SIZE)!=0;
        c->compared+=HG_PAGE_SIZE;
        if (dirty[i]) {
            if (!*saved) *saved=malloc(HG_PAGE_SIZE);
            if (!*saved) return 0; /* caller uploads the whole range on failure */
            memcpy(*saved,bytes,HG_PAGE_SIZE);++c->changed;
        }
    }
    return 1;
}
#endif
