#ifndef HALO_VERTEX_NATIVE_H
#define HALO_VERTEX_NATIVE_H
#include <stdint.h>
#include <string.h>

/* Validate all offsets before touching output. Duplicate offsets retain the
   original loop's sequential swaps, and trailing partial vertices are copied. */
static int halo_vertex_color_swizzle(unsigned char *dst, const unsigned char *src,
    uint32_t size, uint32_t stride, const uint32_t *offsets, uint32_t count)
{
    if (!dst || !src || !offsets || !stride || !count || count>16) return 0;
    for (uint32_t i=0;i<count;i++)
        if (stride<3 || offsets[i]>stride-3) return 0;
    memmove(dst,src,size);
    for (uint64_t vertex=0;vertex+stride<=size;vertex+=stride)
        for (uint32_t i=0;i<count;i++) {
            unsigned char *color=dst+vertex+offsets[i];
            unsigned char blue=color[0];color[0]=color[2];color[2]=blue;
        }
    return 1;
}
#endif
