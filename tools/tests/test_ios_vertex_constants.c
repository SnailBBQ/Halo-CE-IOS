#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef int GLint;
typedef int GLsizei;
typedef unsigned GLuint;
static GLint reflected[192];
static unsigned calls, written;
static float observed[192];
static GLint glGetUniformLocation(GLuint program, const char *name)
{
    assert(program == 7);
    if (!strcmp(name, "c")) return reflected[0];
    assert(!strncmp(name,"c[",2));
    int index = atoi(name+2);
    assert(index >= 0 && index < 192);
    return reflected[index];
}
static void glUniform4fv(GLint location, GLsizei count, const float *values)
{
    assert(location >= 0 && count > 0);
    ++calls;
    for (int i=0;i<count;++i) {
        int found = -1;
        for (int j=0;j<192;++j) if (reflected[j] == location+i) { found=j; break; }
        assert(found >= 0); /* Never send data to a hole or another uniform. */
        assert(values[i*4] == (float)(found+1));
        observed[found] = values[i*4];
        ++written;
    }
}
#include "../../port/linux/include/halo_vertex_constants.h"
static void reset(void)
{
    calls=written=0;
    memset(observed,0,sizeof(observed));
    for (int i=0;i<192;++i) reflected[i]=-1;
}
int main(void)
{
    struct halo_vertex_constant_locations map;
    float values[192][4]={{0}};
    for (int i=0;i<192;++i) values[i][0]=(float)(i+1);
    reset();
    for (int i=0;i<80;++i) reflected[i]=20+i;
    halo_vertex_constants_reflect(&map,7);
    assert(map.count==80 && map.consecutive);
    halo_vertex_constants_upload(&map,60,70,values);
    assert(calls==1 && written==11 && observed[60]==61 && observed[70]==71);
    /* A compiler-optimized hole before bone registers must not truncate them. */
    reset();
    reflected[0]=20; reflected[2]=22; reflected[60]=80; reflected[191]=211;
    halo_vertex_constants_reflect(&map,7);
    assert(map.count==192 && !map.consecutive);
    halo_vertex_constants_upload(&map,0,191,values);
    assert(calls==4 && written==4 && observed[60]==61 && observed[191]==192);
    /* Physical uniform locations may be reordered; c[0] can be inactive. */
    reset(); reflected[60]=17; reflected[61]=9; reflected[63]=28;
    halo_vertex_constants_reflect(&map,7);
    assert(map.count==64 && !map.consecutive);
    halo_vertex_constants_upload(&map,60,62,values);
    assert(calls==2 && observed[60]==61 && observed[61]==62 && !observed[63]);
    halo_vertex_constants_upload(&map,63,1000,values);
    assert(calls==3 && observed[63]==64);
    halo_vertex_constants_upload(&map,64,191,values);
    halo_vertex_constants_upload(&map,10,9,values);
    halo_vertex_constants_upload(&map,0,63,NULL);
    assert(calls==3);
    reset(); halo_vertex_constants_reflect(&map,7);
    assert(map.count==0);
    halo_vertex_constants_upload(&map,0,191,values);
    assert(calls==0);
    puts("vertex constant sparse/dirty-range regression tests passed");
    return 0;
}
