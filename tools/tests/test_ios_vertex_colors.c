#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "halo_vertex_native.h"
static uint32_t random_state=2622;
static uint32_t next(void){random_state=random_state*1664525u+1013904223u;return random_state;}
static void reference(unsigned char *dst,const unsigned char *src,uint32_t size,uint32_t stride,const uint32_t *offsets,uint32_t count)
{
    memcpy(dst,src,size);
    for(uint32_t vertex=0;vertex+stride<=size;vertex+=stride)
        for(uint32_t i=0;i<count;i++){
            unsigned char *color=dst+vertex+offsets[i];
            unsigned char blue=color[0];color[0]=color[2];color[2]=blue;
        }
}
int main(void)
{
    unsigned char input[4160],output[4160],expected[4160];uint32_t offsets[16];
    for(unsigned test=0;test<10000;test++){
        uint32_t stride=3+next()%125,size=next()%4097,count=1+next()%16;
        for(unsigned i=0;i<sizeof(input);i++)input[i]=(unsigned char)(next()>>24);
        for(unsigned i=0;i<count;i++)offsets[i]=next()%(stride-2);
        memset(output,0xa5,sizeof(output));memset(expected,0xa5,sizeof(expected));
        reference(expected+16,input+16,size,stride,offsets,count);
        assert(halo_vertex_color_swizzle(output+16,input+16,size,stride,offsets,count));
        assert(!memcmp(output,expected,sizeof(output)));
        /* Same-buffer operation also preserves the exact sequential swaps. */
        memcpy(output,input,sizeof(input));memcpy(expected,input,sizeof(input));
        reference(expected+16,input+16,size,stride,offsets,count);
        assert(halo_vertex_color_swizzle(output+16,output+16,size,stride,offsets,count));
        assert(!memcmp(output,expected,sizeof(output)));
    }
    memset(output,0xa5,sizeof(output));memcpy(expected,output,sizeof(output));
    offsets[0]=0;offsets[1]=2;
    assert(!halo_vertex_color_swizzle(output,input,64,4,offsets,2));
    assert(!memcmp(output,expected,sizeof(output)));
    assert(!halo_vertex_color_swizzle(output,input,64,0,offsets,1));
    assert(!halo_vertex_color_swizzle(output,input,64,4,offsets,17));
    assert(!halo_vertex_color_swizzle(output,input,64,4,offsets,0));
    assert(!halo_vertex_color_swizzle(output,input,64,4,0,1));
    assert(!memcmp(output,expected,sizeof(output)));
    puts("PASS: 10000 vertex-color cases and in-place equivalents; duplicate offsets, partial vertices, guard bytes and invalid-input rejection");
}
