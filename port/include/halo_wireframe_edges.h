#ifndef HALO_WIREFRAME_EDGES_H
#define HALO_WIREFRAME_EDGES_H
#include <stdint.h>
#include <stdlib.h>
/* Diagnostic conversion only. Never used by the normal filled renderer.
 * Topology: 0 triangle list, 1 strip, 2 fan, 3 quad list.
 * Null input means sequential vertices. Returned indices are rebased to min.
 * Bound allocation and reject underflow rather than wrapping vertex indices. */
static inline uint16_t *halo_wireframe_edges(unsigned topology,const uint16_t *input,
    size_t count,uint16_t minimum,size_t *output_count) {
    size_t triangles,i,j;uint16_t *out;
    *output_count=0;
    if(topology>3 || count>262144 || (!input && count>65536))return NULL;
    triangles=topology==0?count/3:topology==3?(count/4)*2:count>=3?count-2:0;
    if(!triangles)return NULL;
    out=(uint16_t *)malloc(triangles*6*sizeof(*out));if(!out)return NULL;
    for(i=0;i<triangles;i++) {
        size_t v[3];uint16_t a[3];
        if(topology==0){v[0]=i*3;v[1]=v[0]+1;v[2]=v[0]+2;}
        else if(topology==1){v[0]=i;v[1]=i+1;v[2]=i+2;}
        else if(topology==2){v[0]=0;v[1]=i+1;v[2]=i+2;}
        else {size_t base=(i/2)*4;v[0]=base;v[1]=base+(i%2?2:1);v[2]=base+(i%2?3:2);}
        for(j=0;j<3;j++) {
            unsigned value=input?input[v[j]]:(unsigned)v[j];
            if(value<minimum){free(out);return NULL;}a[j]=(uint16_t)(value-minimum);
        }
        out[i*6]=a[0];out[i*6+1]=a[1];out[i*6+2]=a[1];
        out[i*6+3]=a[2];out[i*6+4]=a[2];out[i*6+5]=a[0];
    }
    *output_count=triangles*6;return out;
}
#endif
