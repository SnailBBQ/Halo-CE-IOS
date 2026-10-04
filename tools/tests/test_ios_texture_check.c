#include "halo_texture_check.h"
#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <time.h>
static HtCache cache;
static unsigned char data[HT_MAX_ITEM+1];
int main(void) {
    for(size_t i=0;i<sizeof(data);i++)data[i]=(unsigned char)(i*71u);
    size_t sizes[]={0,1,4095,4096,4097,65536,HT_MAX_ITEM,HT_MAX_ITEM+1};
    for(unsigned i=0;i<sizeof(sizes)/sizeof(sizes[0]);i++) {
        size_t n=sizes[i];uint32_t expected=halo_hash_bytes(data,n);
        assert(ht_hash(&cache,0x80000000u,data,n)==expected);
        assert(ht_hash(&cache,0x80000000u,data,n)==expected);
        if(n){data[n-1]^=1;assert(ht_hash(&cache,0x80000000u,data,n)==halo_hash_bytes(data,n));data[n-1]^=1;}
    }
    ht_reset(&cache);
    /* Every byte, including trailing bytes, must invalidate a reused hash. */
    for(unsigned i=0;i<4097;i++) {
        data[i]^=1;assert(ht_hash(&cache,0x80000000u,data,4097)==halo_hash_bytes(data,4097));data[i]^=1;
    }
    ht_reset(&cache);
    for(unsigned i=0;i<HT_SLOTS*2;i++){ht_hash(&cache,0x80000000u+i*HT_MAX_ITEM,data,HT_MAX_ITEM);assert(cache.allocated<=HT_BUDGET);}
    ht_reset(&cache);ht_hash(&cache,0xfffff000u,data,4096);
    ht_forget(&cache,0xfffffff0u,32);assert(cache.allocated==0); /* wide overlap math */
    ht_hash(&cache,0x80000000u,data,65536);uint64_t hits=cache.hits;
    ht_forget(&cache,0x80010000u,1);ht_hash(&cache,0x80000000u,data,65536);assert(cache.hits==hits+1);
    ht_forget(&cache,0x8000ffffu,1);assert(cache.allocated==0);
    assert(ht_hash(&cache,0,NULL,4096)==1);
    ht_reset(&cache);
    volatile uint32_t sink=0;clock_t a=clock();
    for(unsigned i=0;i<10000;i++)sink^=halo_hash_bytes(data,65536);
    clock_t b=clock();
    for(unsigned i=0;i<10000;i++)sink^=ht_hash(&cache,0x80000000u,data,65536);
    clock_t c=clock();
    printf("PASS: exact hash, mutations, trailing bytes, bounded eviction, forget/reset; repeated 64KiB full hash %.1fms, exact reuse %.1fms (sink %u)\n",1000.0*(b-a)/CLOCKS_PER_SEC,1000.0*(c-b)/CLOCKS_PER_SEC,(unsigned)sink);
    ht_reset(&cache);assert(cache.allocated==0);return 0;
}
