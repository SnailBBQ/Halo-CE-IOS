#import "HaloMapPictures.h"
#include "halo_texel_native.h"
#include "halo_dxt_decode.h"
#include <zlib.h>
#ifdef HALO_MAP_PICTURE_TEST
@implementation UIImage
@end
#endif

static uint32_t mp32(const uint8_t *p){uint32_t v;memcpy(&v,p,4);return CFSwapInt32LittleToHost(v);}
static uint16_t mp16(const uint8_t *p){uint16_t v;memcpy(&v,p,2);return CFSwapInt16LittleToHost(v);}
static const uint8_t *mpSpan(NSData *data,uint64_t offset,uint64_t count){return offset<=data.length && count<=data.length-offset?(const uint8_t *)data.bytes+offset:NULL;}
static const uint8_t *mpTag(NSData *data,uint32_t start,uint32_t size,uint32_t address,uint32_t count){
    if(address<0x803a6000)return NULL;uint64_t relative=(uint64_t)address-0x803a6000;
    return relative<=size && count<=size-relative?mpSpan(data,(uint64_t)start+relative,count):NULL;
}
static NSString *mpName(NSData *data,uint32_t start,uint32_t size,uint32_t address){
    const uint8_t *p=mpTag(data,start,size,address,1);if(!p)return nil;
    size_t available=MIN((size_t)512,(size_t)size-(address-0x803a6000));const uint8_t *end=memchr(p,0,available);
    return end?[[NSString alloc] initWithBytes:p length:(NSUInteger)(end-p) encoding:NSUTF8StringEncoding]:nil;
}
static UIImage *mpImage(NSData *data,const uint8_t *bitmap){
    uint32_t w=mp16(bitmap+4),h=mp16(bitmap+6),format=mp16(bitmap+12),flags=mp16(bitmap+14);
    if(!w||!h||w>1024||h>1024||mp16(bitmap+8)!=1)return nil;
    uint32_t offset=mp32(bitmap+24),size=mp32(bitmap+28),bytes=0,kind=0,dxt=0;
    switch(format){
        case 0:kind=_texel_a8;bytes=1;break;case 1:kind=_texel_l8;bytes=1;break;
        case 2:kind=_texel_al8;bytes=1;break;case 3:kind=_texel_a8l8;bytes=2;break;
        case 6:kind=_texel_r5g6b5;bytes=2;break;case 8:kind=_texel_a1r5g5b5;bytes=2;break;
        case 9:kind=_texel_a4r4g4b4;bytes=2;break;case 10:kind=_texel_x8r8g8b8;bytes=4;break;
        case 11:kind=_texel_a8r8g8b8;bytes=4;break;case 14:dxt=1;break;case 15:dxt=3;break;case 16:dxt=5;break;
        default:return nil;
    }
    BOOL linear=flags&0x10;
    // Morton addressing requires power-of-two surfaces; never infer a span.
    if(!linear && !dxt && ((w&(w-1))||(h&(h-1))))return nil;
    uint64_t needed=dxt?(uint64_t)((w+3)/4)*((h+3)/4)*(dxt==1?8:16):(uint64_t)w*h*bytes;
    const uint8_t *pixels=size>=needed?mpSpan(data,offset,needed):NULL;if(!pixels)return nil;
    NSMutableData *decoded=[NSMutableData dataWithLength:(size_t)w*h*4];uint32_t *argbPixels=decoded.mutableBytes;
    if(dxt)halo_dxt_decode_level((unsigned char)dxt,pixels,w,h,1,argbPixels);
    else if(!halo_texel_native(kind,bytes,linear,w,h,1,w*bytes,pixels,NULL,argbPixels))return nil;
    // Convert explicitly to premultiplied RGBA for CoreGraphics on every host.
    uint8_t *rgba=decoded.mutableBytes;for(size_t i=0;i<(size_t)w*h;i++){uint32_t c=argbPixels[i],a=c>>24;rgba[i*4]=(uint8_t)(((c>>16)&255)*a/255);rgba[i*4+1]=(uint8_t)(((c>>8)&255)*a/255);rgba[i*4+2]=(uint8_t)((c&255)*a/255);rgba[i*4+3]=(uint8_t)a;}
    /* Menu pictures occupy part of their padded power-of-two textures. Trim
       only the outer transparent/pure-black padding; preserve internal pixels.
       A fully black image keeps its original dimensions. No UIKit work here. */
    uint32_t left=w,top=h,right=0,bottom=0;BOOL occupied=NO;
    for(uint32_t y=0;y<h;y++)for(uint32_t x=0;x<w;x++){
        const uint8_t *pixel=rgba+((size_t)y*w+x)*4;
        if(pixel[3] && (pixel[0]||pixel[1]||pixel[2])){occupied=YES;left=MIN(left,x);right=MAX(right,x);top=MIN(top,y);bottom=MAX(bottom,y);}
    }
    if(occupied && (left || top || right+1<w || bottom+1<h)){
        uint32_t cw=right-left+1,ch=bottom-top+1;
        NSMutableData *cropped=[NSMutableData dataWithLength:(size_t)cw*ch*4];
        for(uint32_t y=0;y<ch;y++)memcpy((uint8_t *)cropped.mutableBytes+(size_t)y*cw*4,rgba+((size_t)(top+y)*w+left)*4,(size_t)cw*4);
        decoded=cropped;w=cw;h=ch;
    }
#ifdef HALO_MAP_PICTURE_TEST
    UIImage *image=[UIImage new];image.rgba=decoded;image.width=w;image.height=h;return image;
#else
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)decoded);CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGImageRef cg=CGImageCreate(w,h,8,32,w*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,YES,kCGRenderingIntentDefault);
    UIImage *image=cg?[UIImage imageWithCGImage:cg]:nil;if(cg)CGImageRelease(cg);CGColorSpaceRelease(space);CGDataProviderRelease(provider);return image;
#endif
}

NSDictionary<NSString *,UIImage *> *HaloReadMapPictures(NSURL *url){
    @autoreleasepool {
        NSData *raw=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
        const uint8_t *header=mpSpan(raw,0,2048);if(!header||raw.length>64*1024*1024)return @{};
        if(mp32(header)!=0x68656164||mp32(header+4)!=5||mp32(header+2044)!=0x666f6f74)return @{};
        uint32_t length=mp32(header+8),start=mp32(header+16),size=mp32(header+20);
        if(length<2048||length>128*1024*1024||!size||size>32*1024*1024||(uint64_t)start+size>length)return @{};
        NSMutableData *data=[NSMutableData dataWithLength:length];memcpy(data.mutableBytes,header,2048);
        uLongf expanded=length-2048;int result=uncompress((uint8_t *)data.mutableBytes+2048,&expanded,(const uint8_t *)raw.bytes+2048,(uLong)(raw.length-2048));
        if(result!=Z_OK||expanded!=length-2048)return @{};
        const uint8_t *tags=mpSpan(data,start,16);if(!tags)return @{};
        uint32_t count=mp32(tags+12),address=mp32(tags);if(count>10000)return @{};
        const uint8_t *instances=mpTag(data,start,size,address,count*32);if(!instances)return @{};
        NSArray *campaign=@[@"a10",@"a30",@"a50",@"b30",@"b40",@"c10",@"c20",@"c40",@"d20",@"d40"];
        NSArray *multiplayer=@[@"beavercreek",@"sidewinder",@"damnation",@"ratrace",@"prisoner",@"hangemhigh",@"chillout",@"carousel",@"boardingaction",@"bloodgulch",@"wizard",@"putput",@"longest"];
        NSMutableDictionary *images=[NSMutableDictionary new];
        // Follow the same bitmap reference used by the map-selection widget;
        // do not mistake titles or decorative menu assets for map pictures.
        for(uint32_t i=0;i<count;i++){
            const uint8_t *instance=instances+i*32;if(memcmp(instance,"aLeD",4))continue;
            NSString *name=mpName(data,start,size,mp32(instance+16)).lowercaseString;
            BOOL solo=[name containsString:@"solo_level_select"],multi=[name containsString:@"mp_map_select"] || [name containsString:@"game_settings"];
            if((!solo&&!multi)||(![name.lastPathComponent containsString:@"map"]&&![name.lastPathComponent containsString:@"pic"]))continue;
            const uint8_t *widget=mpTag(data,start,size,mp32(instance+20),0x48);if(!widget||mp16(widget)!=0)continue;
            uint32_t index=mp32(widget+0x44)&0xffff;if(index>=count)continue;
            const uint8_t *bitm=instances+index*32;if(memcmp(bitm,"mtib",4))continue;
            const uint8_t *group=mpTag(data,start,size,mp32(bitm+20),0x6c);if(!group)continue;
            uint32_t n=mp32(group+0x60);NSArray *names=solo?campaign:multiplayer;
            if(n<names.count||n>64)continue;
            const uint8_t *bitmaps=mpTag(data,start,size,mp32(group+0x64),n*0x30);if(!bitmaps)continue;
            for(NSUInteger frame=0;frame<names.count;frame++){UIImage *image=mpImage(data,bitmaps+frame*0x30);if(image)images[names[frame]]=image;}
        }
        return images;
    }
}
