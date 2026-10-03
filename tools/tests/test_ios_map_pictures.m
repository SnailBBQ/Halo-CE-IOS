#import "HaloMapPictures.h"
#include <zlib.h>
#include <stdio.h>
#include <stdlib.h>
static void put32(uint8_t *b,size_t o,uint32_t v){v=CFSwapInt32HostToLittle(v);memcpy(b+o,&v,4);}
static void put16(uint8_t *b,size_t o,uint16_t v){v=CFSwapInt16HostToLittle(v);memcpy(b+o,&v,2);}
static uint32_t va(size_t relative){return 0x803a6000+(uint32_t)relative;}
static NSMutableData *fixture(void){
    NSMutableData *d=[NSMutableData dataWithLength:8192];uint8_t *b=d.mutableBytes;
    put32(b,0,0x68656164);put32(b,4,5);put32(b,8,8192);put32(b,16,2048);put32(b,20,4096);put32(b,2044,0x666f6f74);
    uint8_t *t=b+2048;put32(t,0,va(32));put32(t,12,2);
    memcpy(t+32,"aLeD",4);put32(t,48,va(256));put32(t,52,va(512));
    memcpy(t+64,"mtib",4);put32(t,80,va(320));put32(t,84,va(768));
    strcpy((char *)t+256,"ui\\shell\\main_menu\\solo_level_select\\map_picture");strcpy((char *)t+320,"ui\\shell\\bitmaps\\campaign_maps");
    put16(t,512,0);put32(t,512+0x44,1);put32(t,768+0x60,10);put32(t,768+0x64,va(1024));
    for(int i=0;i<10;i++){size_t o=1024+i*48;put16(t,o+4,4);put16(t,o+6,4);put16(t,o+8,1);put16(t,o+12,11);put16(t,o+14,16);put32(t,o+24,7000);put32(t,o+28,64);}
    for(int i=0;i<16;i++)put32(b,7000+i*4,0xff336699);return d;
}
static NSDictionary *ReadPictureFixture(NSMutableData *expanded,NSURL *url){
    uLongf n=compressBound(expanded.length-2048);NSMutableData *raw=[NSMutableData dataWithLength:2048+n];memcpy(raw.mutableBytes,expanded.bytes,2048);
    compress2((uint8_t *)raw.mutableBytes+2048,&n,(const uint8_t *)expanded.bytes+2048,expanded.length-2048,Z_BEST_SPEED);raw.length=2048+n;[raw writeToURL:url atomically:YES];return HaloReadMapPictures(url);
}
#define CHECK(v) do{if(!(v)){fprintf(stderr,"FAIL map pictures line %d\n",__LINE__);exit(1);}}while(0)
int main(void){@autoreleasepool{
    NSURL *url=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".map"]]];
    NSMutableData *d=fixture();NSDictionary *images=ReadPictureFixture(d,url);CHECK(images.count==10);UIImage *a=images[@"a10"];CHECK(a.width==4 && a.height==4);
    const uint8_t *p=a.rgba.bytes;CHECK(p[0]==0x33&&p[1]==0x66&&p[2]==0x99&&p[3]==255);
    /* Padded texture: preserve the colored 2×2 picture, remove outer black. */
    d=fixture();for(int i=0;i<16;i++)put32(d.mutableBytes,7000+i*4,0xff000000);
    for(int y=1;y<3;y++)for(int x=1;x<3;x++)put32(d.mutableBytes,7000+(y*4+x)*4,0xff336699);
    a=ReadPictureFixture(d,url)[@"a10"];CHECK(a.width==2 && a.height==2 && a.rgba.length==16);
    d=fixture();for(int i=0;i<16;i++)put32(d.mutableBytes,7000+i*4,0xff000000);
    a=ReadPictureFixture(d,url)[@"a10"];CHECK(a.width==4 && a.height==4);
    d=fixture();
    put32(d.mutableBytes,2048+512+0x44,99);CHECK(!ReadPictureFixture(d,url).count);
    d=fixture();put32(d.mutableBytes,2048+768+0x64,0xffffffff);CHECK(!ReadPictureFixture(d,url).count);
    d=fixture();for(int i=0;i<10;i++)put32(d.mutableBytes,2048+1024+i*48+24,8190);CHECK(!ReadPictureFixture(d,url).count);
    d=fixture();put32(d.mutableBytes,8,0xffffffff);CHECK(!ReadPictureFixture(d,url).count);
    [[NSData dataWithBytes:"broken" length:6] writeToURL:url atomically:YES];CHECK(!HaloReadMapPictures(url).count);
    [NSFileManager.defaultManager removeItemAtURL:url error:nil];puts("PASS: actual ui.map thumbnail parser, RGBA decoding, bounded tag references, invalid pixels, oversized expansion, truncation");
}return 0;}
