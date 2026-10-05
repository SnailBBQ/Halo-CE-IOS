#include <stdio.h>
#include <stdlib.h>
#include "halo_checkpoint.h"
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x);return 1;}}while(0)
static void array(unsigned char *b,size_t p,const char *name,unsigned count,unsigned stride) {
    memcpy(b+p,name,strlen(name)+1);hc_put16(b,p+32,(uint16_t)count);hc_put16(b,p+34,(uint16_t)stride);
    b[p+36]=1;hc_put32(b,p+40,0x64407440);hc_put16(b,p+46,1);hc_put16(b,p+48,1);hc_put32(b,p+52,HC_BASE+(uint32_t)p+56);
}
static void header(unsigned char *b,size_t h,unsigned salt,unsigned type,unsigned size,size_t datum) {
    hc_put16(b,h,(uint16_t)salt);b[h+3]=(unsigned char)type;hc_put16(b,h+6,(uint16_t)size);hc_put32(b,h+8,HC_BASE+(uint32_t)datum);
}
int main(int argc,char **argv) {
    unsigned char *b=calloc(1,HC_SIZE),*original=malloc(HC_SIZE);CHECK(b&&original);
    if(argc==2){FILE *f=fopen(argv[1],"rb");CHECK(f);CHECK(fread(b,1,HC_SIZE,f)==HC_SIZE);CHECK(fgetc(f)==EOF);fclose(f);}
    else {
        memcpy(b+4,"levels\\a10\\a10",15);memcpy(b+0x104,"01.01.14.2342",13);hc_put16(b,0x124,1);hc_put16(b,0x126,2);
        array(b,0x200,"players",128,0xd4);array(b,0x10000,"object",8192,12);
        size_t p=0x238,h=0x10038,u=0x40000,w=0x42000;
        hc_put16(b,p,7);hc_put32(b,p+0x34,0x12340000);
        header(b,h,0x1234,0,0x480,u);header(b,h+12,0x2345,2,0x27c,w);
        hc_putfloat(b,u+0x90,.6f);hc_putfloat(b,u+0x94,.4f);
        for(unsigned i=0;i<4;i++)hc_put32(b,u+0x2a8+i*4,UINT32_MAX);
        hc_put32(b,u+0x2a8,0x23450001);b[u+0x2ce]=2;b[u+0x2cf]=3;
        hc_put16(b,w+0x25e,120);hc_put16(b,w+0x260,60);hc_put32(b,0x148,hc_crc(b));
    }
    HcView view,after;CHECK(hc_read(b,HC_SIZE,&view));memcpy(original,b,HC_SIZE);
    unsigned reserve[4][2]={{222,0}},loaded[4][2]={{33,0}};
    CHECK(!hc_edit(b,HC_SIZE,&view,0,1,4,4,reserve,loaded));CHECK(!memcmp(b,original,HC_SIZE));
    CHECK(!hc_edit(b,HC_SIZE,&view,NAN,1,4,4,reserve,loaded));CHECK(!memcmp(b,original,HC_SIZE));
    CHECK(!hc_edit(b,HC_SIZE,&view,1,1,128,4,reserve,loaded));CHECK(!memcmp(b,original,HC_SIZE));
    CHECK(!hc_edit(b,HC_SIZE,&view,1,1,4,999,reserve,loaded));CHECK(!memcmp(b,original,HC_SIZE));
    CHECK(!hc_edit(b,HC_SIZE,&view,10,1,4,4,reserve,loaded));CHECK(!memcmp(b,original,HC_SIZE));
    CHECK(!hc_edit(b,HC_SIZE,&view,1,10,4,4,reserve,loaded));CHECK(!memcmp(b,original,HC_SIZE));
    CHECK(!hc_edit(b,HC_SIZE,&view,1,INFINITY,4,4,reserve,loaded));CHECK(!memcmp(b,original,HC_SIZE));
    reserve[0][0]=1000;
    if(view.weapons){CHECK(!hc_edit(b,HC_SIZE,&view,1,1,4,4,reserve,loaded));CHECK(!memcmp(b,original,HC_SIZE));}
    reserve[0][0]=999;reserve[0][1]=222;loaded[0][0]=999;loaded[0][1]=33;
    CHECK(hc_edit(b,HC_SIZE,&view,HC_MAX_VITALITY,HC_MAX_VITALITY,127,127,reserve,loaded));CHECK(hc_read(b,HC_SIZE,&after));
    CHECK(hc_float(b,view.unit+0x90)==HC_MAX_VITALITY&&hc_float(b,view.unit+0x94)==HC_MAX_VITALITY&&b[view.unit+0x2ce]==127&&b[view.unit+0x2cf]==127);
    if(view.weapons)CHECK(hc_u16(b,view.weapon[0]+0x25e)==999&&hc_u16(b,view.weapon[0]+0x260)==999&&hc_u16(b,view.weapon[0]+0x26a)==222&&hc_u16(b,view.weapon[0]+0x26c)==33);
    /* Only requested scalar fields and the checksum can differ. */
    for(size_t i=0;i<HC_SIZE;i++)if(b[i]!=original[i]) {
        int allowed=(i>=0x148&&i<0x14c)||(i>=view.unit+0x90&&i<view.unit+0x98)||(i>=view.unit+0x2ce&&i<view.unit+0x2d0);
        for(unsigned j=0;j<view.weapons;j++)for(unsigned m=0;m<2;m++)if(i>=view.weapon[j]+0x25e + m*12&&i<view.weapon[j]+0x262+m*12)allowed=1;
        CHECK(allowed);
    }
    CHECK(!hc_read(b,HC_SIZE-1,&after));b[500]^=1;CHECK(!hc_read(b,HC_SIZE,&after));b[500]^=1;
    size_t headers;CHECK(hc_array(b,"object",8192,12,&headers));for(unsigned i=0;i<8192;i++)if(hc_u32(b,headers+i*12+8)==HC_BASE+view.unit){hc_put32(b,headers+i*12+8,UINT32_MAX);break;}hc_put32(b,0x148,hc_crc(b));CHECK(!hc_read(b,HC_SIZE,&after));
    free(original);free(b);puts("checkpoint validation, bounded edits, checksum and corruption rejection: PASS");return 0;
}
