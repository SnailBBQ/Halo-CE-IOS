#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define GL_ARRAY_BUFFER 1
#define GL_TRUE 1
#define GL_FALSE 0
static unsigned enables,disables,binds,pointers,values,bound,last_buffer,last_flags,last_offset;
static void glEnableVertexAttribArray(unsigned i) { assert(i<16);enables++; }
static void glDisableVertexAttribArray(unsigned i) { assert(i<16);disables++; }
static void glBindBuffer(unsigned t,unsigned b) { assert(t==1);bound=b;binds++; }
static void glVertexAttribPointer(unsigned i,int s,unsigned t,int n,int stride,const void *p)
{ assert(i<16 && s>0 && t>0 && stride>=0);pointers++;last_buffer=bound;last_flags=(unsigned)n;last_offset=(unsigned)(uintptr_t)p; }
static void glVertexAttribIPointer(unsigned i,int s,unsigned t,int stride,const void *p)
{ glVertexAttribPointer(i,s,t,0,stride,p);last_flags=2; }
static void glVertexAttrib4fv(unsigned i,const float *v) { assert(i<16 && v);values++; }
static void glVertexAttribI4ui(unsigned i,unsigned a,unsigned b,unsigned c,unsigned d)
{ assert(i<16 && !(a|b|c|d));values++; }
#include "halo_attribute_native.h"
int main(void)
{
    struct halo_attribute_cache cache;
    float v[4]={1,2,3,4};
    halo_attribute_invalidate(&cache);
    assert(halo_attribute_pointer(&cache,0,7,4,3,1,16,8)==1);
    assert(enables==1 && binds==1 && pointers==1 && last_buffer==7 && last_flags==1 && last_offset==8);
    bound=99; /* A cache hit must leave unrelated array-buffer binding intact. */
    assert(halo_attribute_pointer(&cache,0,7,4,3,1,16,8)==0 && bound==99 && binds==1);
    assert(halo_attribute_value(&cache,0,v)==1 && disables==1 && values==1);
    assert(halo_attribute_value(&cache,0,v)==0 && values==1);
    assert(halo_attribute_pointer(&cache,0,7,4,3,1,16,8)==0 && enables==2 && bound==99);
    assert(halo_attribute_value(&cache,0,NULL)==1 && values==2);
    assert(halo_attribute_value(&cache,0,NULL)==0 && values==2);
    assert(halo_attribute_value(&cache,0,v)==1 && values==3);
    v[0]=-0.0f;assert(halo_attribute_value(&cache,0,v)==1);
    v[0]=0.0f;assert(halo_attribute_value(&cache,0,v)==1);
    for (unsigned field=0;field<7;field++) {
        halo_attribute_invalidate(&cache);
        assert(halo_attribute_pointer(&cache,1,7,4,3,1,16,8)==1);
        unsigned before=pointers;
        assert(halo_attribute_pointer(&cache,1,field==0?9:7,field==1?3:4,field==2?4:3,
            field==3?0:field==4?2:1,field==5?20:16,field==6?12:8)==1);
        assert(pointers==before+1 && last_buffer==(field==0?9u:7u));
    }
    unsigned before=values;
    halo_attribute_invalidate(&cache);
    assert(halo_attribute_value(&cache,0,v)==1 && values==before+1);
    before=enables+disables+binds+pointers+values;
    assert(halo_attribute_pointer(&cache,16,1,4,3,0,16,0)==-1);
    assert(halo_attribute_value(&cache,16,v)==-1);
    assert(before==enables+disables+binds+pointers+values);
    puts("PASS: native vertex attribute cache, every descriptor field, buffer side effects, enable/value transitions, bitwise values, invalidation and bounds");
    return 0;
}
