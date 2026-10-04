#include <stdio.h>
#include <stdint.h>
#include "../../port/include/halo_wireframe_edges.h"
#define CHECK(x) do{if(!(x)){printf("FAIL line %d\n",__LINE__);return 1;}}while(0)
int main(void){size_t n;uint16_t *out;uint16_t source[]={7,9,8,8,9,10,99};
 out=halo_wireframe_edges(0,source,7,7,&n);CHECK(out&&n==12&&out[0]==0&&out[1]==2&&out[5]==0&&out[11]==1);free(out);
 out=halo_wireframe_edges(1,NULL,4,0,&n);CHECK(out&&n==12&&out[6]==1&&out[11]==1);free(out);
 out=halo_wireframe_edges(2,NULL,4,0,&n);CHECK(out&&n==12&&out[6]==0&&out[7]==2&&out[9]==3);free(out);
 out=halo_wireframe_edges(3,NULL,5,0,&n);CHECK(out&&n==12&&out[6]==0&&out[7]==2&&out[9]==3);free(out);
 CHECK(!halo_wireframe_edges(0,source,3,8,&n)&&n==0);
 CHECK(!halo_wireframe_edges(0,NULL,65537,0,&n)&&n==0);
 CHECK(!halo_wireframe_edges(0,source,262145,0,&n)&&n==0);
 CHECK(!halo_wireframe_edges(1,NULL,2,0,&n)&&n==0);
 puts("PASS: wireframe edges: indexed rebasing, lists/strips/fans/quads, trailing vertices, bounded allocations");return 0;}
