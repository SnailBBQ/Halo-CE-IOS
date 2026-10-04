/* XDVDFS format and partition probing follow XboxDev/extract-xiso and the
 * desktop port's xiso.c. No executable patching, guest code or ISO label tests.
 * Some parts are copyright in@fishtank.com. This product includes software
 * developed by in <in@fishtank.com>. See port/third_party/extract-xiso/LICENSE.TXT.
 * All directory traversal is iterative, bounded and fail-closed. */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
#include "halo_xiso.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#ifdef _WIN32
#define seek64 _fseeki64
#define tell64 _ftelli64
#else
#define seek64 fseeko
#define tell64 ftello
#endif
enum { SECTOR=2048, MAX_FILES=256, MAX_DIR=4*1024*1024, CHUNK=256*1024 };
typedef struct { char name[256]; uint32_t sector, size; } Entry;
typedef struct {
    FILE *file; uint64_t size, base; char *error; unsigned error_size;
    halo_xiso_progress progress; void *context;
} Image;
static uint32_t u32(const unsigned char *b) {
    return (uint32_t)b[0]|(uint32_t)b[1]<<8|(uint32_t)b[2]<<16|(uint32_t)b[3]<<24;
}
static int fail(Image *i, const char *reason) {
    if(i->error_size)snprintf(i->error,i->error_size,"%s",reason);
    return 0;
}
static int read_at(Image *i,uint64_t offset,void *buffer,size_t size) {
    return offset<=i->size && size<=i->size-offset &&
        seek64(i->file,(int64_t)offset,SEEK_SET)==0 && fread(buffer,1,size,i->file)==size;
}
static int cancelled(Image *i,const char *name,uint64_t done,uint64_t total) {
    return i->progress && i->progress(i->context,name,done,total);
}
static int volume(Image *i,Entry *root) {
    static const uint64_t offsets[]={0,0x0FD90000,0x02080000,0x18300000};
    unsigned char b[SECTOR];
    for(unsigned n=0;n<sizeof(offsets)/sizeof(offsets[0]);n++) {
        if(!read_at(i,offsets[n]+0x10000,b,sizeof(b)))continue;
        if(memcmp(b,"MICROSOFT*XBOX*MEDIA",20)||memcmp(b+0x7ec,"MICROSOFT*XBOX*MEDIA",20))continue;
        i->base=offsets[n];root->sector=u32(b+20);root->size=u32(b+24);return 1;
    }
    return fail(i,"Not an Xbox Halo CE disc image. PC, MCC and Custom Edition ISOs are unsupported.");
}
/* Only safe ASCII names are ever used as output paths. Case is normalized so
 * FAT-style disc names cannot produce duplicate files on a case-sensitive host. */
static int name_at(const unsigned char *p,unsigned length,char *name) {
    if(!length)return 0;
    for(unsigned n=0;n<length;n++) {
        unsigned char c=p[n];
        if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c=='.'))return 0;
        name[n]=(char)(c>='A'&&c<='Z'?c+32:c);
    }
    name[length]=0;return name[0]!='.';
}
static int directory(Image *i,Entry dir,Entry *entries,unsigned *count,int root) {
    unsigned char *b=NULL,*visited=NULL;uint32_t *stack=NULL;unsigned used=0,seen=0;int result=0;
    uint64_t start=i->base+(uint64_t)dir.sector*SECTOR;
    if(!dir.size || dir.size>MAX_DIR)return fail(i,"Invalid Xbox directory size.");
    b=malloc(dir.size);visited=calloc((dir.size+3)/4,1);stack=malloc(65536*sizeof(*stack));
    if(!b||!visited||!stack){fail(i,"Not enough memory to read the disc directory.");goto done;}
    if(!read_at(i,start,b,dir.size)){fail(i,"Truncated Xbox disc directory.");goto done;}
    stack[used++]=0;
    while(used) {
        uint32_t off=stack[--used];
        if(cancelled(i,"Reading disc directory",0,0)){result=-1;goto done;}
        if(off>dir.size || dir.size-off<14 || visited[off/4] || ++seen>65536){fail(i,"Corrupt Xbox directory tree.");goto done;}
        visited[off/4]=1;
        const unsigned char *p=b+off;unsigned left=p[0]|p[1]<<8,right=p[2]|p[3]<<8,len=p[13];
        if(left==65535)continue; /* empty/padded directory */
        if(!len || len>dir.size-off-14){fail(i,"Invalid Xbox filename length.");goto done;}
        if((left&&left==off/4)||(right&&right==off/4)||used+2>65536){fail(i,"Corrupt Xbox directory links.");goto done;}
        if(right)stack[used++]=right*4;
        if(left)stack[used++]=left*4;
        Entry e;memset(&e,0,sizeof(e));
        if(!name_at(p+14,len,e.name)) {
            /* Unrelated root entries may have legitimate names outside our
             * output alphabet. Reject unsafe names inside maps instead. */
            if(root)continue;
            fail(i,"Unsafe filename in the Xbox maps directory.");goto done;
        }
        int is_dir=(p[12]&0x10)!=0;
        if(root ? (!is_dir||strcmp(e.name,"maps")) : (is_dir||len<4||strcmp(e.name+len-4,".map")))continue;
        e.sector=u32(p+4);e.size=u32(p+8);
        if(*count>=MAX_FILES){fail(i,"Too many disc maps.");goto done;}
        for(unsigned n=0;n<*count;n++)if(!strcmp(entries[n].name,e.name)){fail(i,"Duplicate disc map names.");goto done;}
        entries[(*count)++]=e;
    }
    result=1;
done: free(stack);free(visited);free(b);return result;
}
static int valid_map(Image *i,Entry e) {
    unsigned char b[SECTOR];uint64_t start=i->base+(uint64_t)e.sector*SECTOR;
    if(e.size<SECTOR || start>i->size || e.size>i->size-start || !read_at(i,start,b,sizeof(b)))
        return fail(i,"A disc map is truncated; no maps were installed.");
    if(u32(b)!=0x68656164||u32(b+4)!=5||u32(b+2044)!=0x666f6f74)
        return fail(i,"A disc map fails the Xbox cache v5 head/version/foot check. PC/MCC/Custom Edition maps are unsupported.");
    if(!memchr(b+0x20,0,32)||!memchr(b+0x40,0,32))return fail(i,"Invalid map header strings.");
    if(strcmp((char *)b+0x40,"01.10.12.2276") && strcmp((char *)b+0x40,"01.01.14.2342"))
        return fail(i,"Unsupported map build. Expected Xbox Halo CE NTSC 01.10.12.2276 or PAL 01.01.14.2342.");
    /* Disc maps can be compressed: file_length describes the expanded cache,
     * so do not compare it to the on-disc compressed length. */
    if(u32(b+8)>0x11600000)return fail(i,"Map expanded size exceeds the supported Xbox cache limit.");
    return 1;
}
int halo_xiso_extract(const char *path,const char *staging,halo_xiso_progress progress,
    void *context,char *error,unsigned error_size) {
    Image i={0};Entry root={0},dirs[MAX_FILES],files[MAX_FILES];unsigned nd=0,nf=0;int result=0;
    unsigned char *buffer=NULL;uint64_t total=0,done=0;int has_ui=0;
    i.error=error;i.error_size=error_size;i.progress=progress;i.context=context;
    if(error_size)error[0]=0;
    if(!path||!staging)return fail(&i,"Missing disc image or staging folder.");
    i.file=fopen(path,"rb");if(!i.file)return fail(&i,"Cannot open disc image. Download it in Files first.");
    if(seek64(i.file,0,SEEK_END)!=0 || tell64(i.file)<0){fail(&i,"Cannot determine disc image size.");goto end;}
    i.size=(uint64_t)tell64(i.file);
    if(!volume(&i,&root))goto end;
    result=directory(&i,root,dirs,&nd,1);if(result!=1)goto end;
    result=0;if(nd!=1){fail(&i,"Not an Xbox Halo CE image: no maps directory found.");goto end;}
    result=directory(&i,dirs[0],files,&nf,0);if(result!=1)goto end;
    result=0;
    for(unsigned n=0;n<nf;n++) {
        if(cancelled(&i,files[n].name,0,0)){result=-1;goto end;}
        if(!valid_map(&i,files[n]))goto end;
        has_ui|=!strcmp(files[n].name,"ui.map");total+=files[n].size;
    }
    if(!has_ui){fail(&i,"Not an Xbox Halo CE image: a supported ui.map is required.");goto end;}
    buffer=malloc(CHUNK);if(!buffer){fail(&i,"Not enough memory to extract maps.");goto end;}
    for(unsigned n=0;n<nf;n++) {
        char target[4096];Entry e=files[n];
        if(snprintf(target,sizeof(target),"%s/%s",staging,e.name)>=(int)sizeof(target)){fail(&i,"Staging path is too long.");goto end;}
        FILE *out=fopen(target,"wbx");if(!out){fail(&i,"Cannot create staged map; check free storage.");goto end;}
        uint32_t copied=0;
        while(copied<e.size) {
            if(cancelled(&i,e.name,done,total)){result=-1;break;}
            size_t amount=e.size-copied;if(amount>CHUNK)amount=CHUNK;
            if(!read_at(&i,i.base+(uint64_t)e.sector*SECTOR+copied,buffer,amount)||fwrite(buffer,1,amount,out)!=amount){fail(&i,"Failed to copy disc map; check free storage and the image.");break;}
            copied+=(uint32_t)amount;done+=amount;
        }
        int close_ok=fclose(out)==0;
        if(copied!=e.size||!close_ok){if(!close_ok&&result!=-1)fail(&i,"Cannot finish staged map.");goto end;}
    }
    if(cancelled(&i,"Maps validated",done,total)){result=-1;goto end;}
    result=1;
end: free(buffer);fclose(i.file);return result;
}
