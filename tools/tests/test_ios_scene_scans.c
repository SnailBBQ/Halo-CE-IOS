#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "halo_scene_scan_native.h"
static unsigned char arena[65536];
static const void *resolve(uint32_t va,size_t size) { return va && va<=sizeof(arena) && size<=sizeof(arena)-va?arena+va:NULL; }
static uint32_t random_state=123;
static uint32_t random_word(void) { random_state=random_state*1664525u+1013904223u;return random_state; }
static void half(unsigned offset,int16_t value) { memcpy(arena+offset,&value,2); }
int main(void) {
    uint32_t l[13]={56,32,34,36,37,40,44,46,48,52,50,0x64407440u,0x69746572u};
    uint32_t out[3];uint64_t visited=0;
    for(unsigned trial=0;trial<10000;trial++) {
        unsigned count=random_word()%200;
        memset(arena,0,sizeof(arena));half(32+32,200);half(32+34,8);arena[32+36]=1;
        halo_scene_write32(arena,32+40,l[11]);half(32+46,(int16_t)count);halo_scene_write32(arena,32+52,1024);
        for(unsigned i=0;i<count;i++)half(1024+i*8,(int16_t)(random_word()%3?random_word()|1u:0));
        uint32_t from=trial%2?UINT32_MAX:random_word()%200;
        int16_t start=(int16_t)(from+1u);uint32_t expected=UINT32_MAX;
        for(int i=start;i>=0 && i<(int)count;i++)if(halo_scene_i16(arena+1024+i*8,0)) {expected=((uint32_t)(uint16_t)halo_scene_i16(arena+1024+i*8,0)<<16)|(unsigned)i;break;}
        assert(halo_scene_datum(resolve,1,32,from,l,out,&visited) && out[0]==expected);
        halo_scene_write32(arena,256,32);half(260,start);halo_scene_write32(arena,264,77);halo_scene_write32(arena,268,32^l[12]);
        assert(halo_scene_datum(resolve,2,256,0,l,out,&visited));
        if(expected==UINT32_MAX)assert(out[0]==0 && out[2]==77 && out[1]==(uint32_t)(start<(int)count?(int)count:start));
        else assert(out[0]==1024+(expected&65535u)*8 && out[1]==(expected&65535u)+1 && out[2]==expected);
        if(expected!=UINT32_MAX) {
            assert(halo_scene_datum(resolve,3,32,expected,l,out,&visited) && out[0]==1024+(expected&65535u)*8);
            assert(halo_scene_datum(resolve,4,32,expected^0x20000u,l,out,&visited) && out[0]==0);
        }
    }
    assert(halo_scene_datum(resolve,4,0,UINT32_MAX,l,out,&visited) && out[0]==0);
    assert(!halo_scene_datum(resolve,1,65535,0,l,out,&visited));
    uint32_t bad[13];memcpy(bad,l,sizeof(l));bad[9]=55;assert(!halo_scene_datum(resolve,1,32,0,bad,out,&visited));
    /* Same-address mutation must be visible on the next call. */
    half(78,3);half(1032,5);assert(halo_scene_datum(resolve,1,32,0,l,out,&visited));
    half(1032,6);assert(halo_scene_datum(resolve,1,32,0,l,out,&visited) && (out[0]>>16)==6);
    for(unsigned trial=0;trial<10000;trial++) {
        uint16_t surfaces[200][3];uint32_t indices[200],flags[7]={0},actual_indices[200];
        uint16_t triangles[200][3],expected_triangles[200][3];
        unsigned total=random_word()%200,count=random_word()%(total+1),selected=0;
        for(unsigned i=0;i<total;i++) { for(unsigned j=0;j<3;j++)surfaces[i][j]=(uint16_t)random_word();
            if(random_word()%2)flags[i>>5]|=1u<<(i&31); }
        for(unsigned i=0;i<count;i++) {indices[i]=random_word()%total;memcpy(expected_triangles[i],surfaces[indices[i]],6);}
        assert(halo_scene_triangles(surfaces,total,indices,count,triangles) && !memcmp(triangles,expected_triangles,count*6));
        uint32_t sorted[200];memcpy(sorted,indices,count*4);
        for(unsigned i=1;i<count;i++){uint32_t v=sorted[i];unsigned j=i;while(j && sorted[j-1]>v){sorted[j]=sorted[j-1];--j;}sorted[j]=v;}
        assert(halo_scene_sorted_triangles(surfaces,total,indices,count,triangles));
        assert(!memcmp(indices,sorted,count*4));
        for(unsigned i=0;i<count;i++)assert(!memcmp(triangles[i],surfaces[sorted[i]],6));
        for(unsigned i=0;i<total;i++)if(flags[i>>5]&(1u<<(i&31))) {actual_indices[selected]=i;memcpy(expected_triangles[selected++],surfaces[i],6);}
        uint32_t written;
        assert(halo_scene_bit_triangles(surfaces,total,flags,200,indices,triangles,&written));
        assert(written==selected && !memcmp(indices,actual_indices,selected*4) && !memcmp(triangles,expected_triangles,selected*6));
        memset(triangles,0xaa,sizeof(triangles));
        if(selected) {assert(!halo_scene_bit_triangles(surfaces,total,flags,selected-1,indices,triangles,&written));assert(((unsigned char *)triangles)[0]==0xaa);}
        uint32_t run[10];for(unsigned i=0;i<10;i++)run[i]=random_word()%20;
        int32_t end=(int32_t)(random_word()%20);unsigned consumed=1;while(consumed<10 && (int32_t)run[consumed]<end)consumed++;
        assert(halo_scene_material_run(run,10,end)==consumed);
    }
    for(unsigned trial=0;trial<10000;trial++) {
        uint32_t indices[100],refs[100][2],allowed[4],seen[4],expected[4],output[100],wanted[100];
        for(unsigned i=0;i<4;i++){allowed[i]=random_word();seen[i]=random_word();expected[i]=seen[i];}
        unsigned count=random_word()%100,maximum=random_word()%60,current=random_word()%(maximum+1),updated=current;
        for(unsigned i=0;i<count;i++){indices[i]=random_word()%128;refs[i][0]=0;refs[i][1]=indices[i];}
        for(unsigned i=0;i<count;i++){uint32_t v=indices[i],mask=1u<<(v&31);if(!(expected[v>>5]&mask)){if(updated>=maximum)break;expected[v>>5]|=mask;updated++;}}
        uint32_t got;assert(halo_scene_mark(indices,count,128,seen,current,maximum,&got,&visited));
        assert(got==updated && !memcmp(seen,expected,sizeof(seen)));
        for(unsigned i=0;i<4;i++)seen[i]=expected[i]=random_word();
        unsigned found=0;
        for(unsigned i=0;i<count;i++){uint32_t v=refs[i][1],mask=1u<<(v&31);if((allowed[v>>5]&mask)&&!(expected[v>>5]&mask)){if(found>=maximum)break;expected[v>>5]|=mask;wanted[found++]=v;}}
        assert(halo_scene_leaf(refs,count,8,4,128,allowed,seen,output,maximum,&got,&visited));
        assert(got==found && !memcmp(seen,expected,sizeof(seen)) && !memcmp(output,wanted,found*4));
    }
    uint32_t early[3]={1,2,UINT32_MAX},bits=0,got;visited=0;
    assert(halo_scene_mark(early,3,32,&bits,0,1,&got,&visited) && got==1 && bits==2 && visited==2);
    puts("PASS: 30000 randomized datum/BSP/visibility cases, salts, same-address mutation, ordered outputs, duplicates, caps, partial words and untouched trailing outputs");return 0;
}
