from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
runner=(r/'port/ios/HaloIOS/halo_guest_runner.m').read_text(encoding='utf-8')
body='static _Atomic uint64_t g_scene_calls'+runner.split('static _Atomic uint64_t g_scene_calls',1)[1].split('static int ios_vertex_color_swizzle',1)[0]
prefix=r"""#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>
#include "halo_timing_sample.h"
#include "ios_scene_scan.h"
#include "halo_scene_scan_native.h"
static unsigned char arena[65536];
static unsigned aborted;
static _Atomic uint64_t g_native_loop_upgrades;
static uint64_t halo_guest_exec_thread_pointer_upgrades(void){return 9;}
static unsigned clock_reads; static double loading_seconds(void){clock_reads++;return 1;}
static void *gp(uint64_t va,size_t size){return va && va<=sizeof(arena) && size<=sizeof(arena)-va?arena+va:NULL;}
#define HALO_GUEST_ABORT_HOST 5
static void halo_guest_exec_abort(int reason){assert(reason==5);aborted++;}
static void say(const char *format,...){(void)format;}
"""
suffix=r"""
static void packet(struct halo_scene_scan_packet p){memcpy(arena+32,&p,sizeof(p));ios_scene_scan(32);}
static uint32_t word(unsigned va){return halo_scene_u32(arena,va);}
int main(void){
    _Static_assert(sizeof(struct halo_scene_scan_packet)==56,"packet ABI");
    struct halo_scene_scan_packet p={HALO_SCENE_TRIANGLES,{128,3,256,2,512}};
    uint16_t surfaces[3][3]={{1,2,3},{7,8,9},{11,12,13}};uint32_t indices[2]={2,0};
    memcpy(arena+128,surfaces,18);memcpy(arena+256,indices,8);packet(p);assert(!memcmp(arena+512,surfaces[0],6) && halo_scene_u32(arena,256)==0);
    p.a[0]=65530;packet(p);assert(aborted==1);
    p.a[0]=128;p.a[4]=256;packet(p);assert(aborted==2);
    p.kind=HALO_SCENE_BIT_TRIANGLES;p.a[4]=512;p.a[5]=768;p.a[6]=384;halo_scene_write32(arena,384,5);packet(p);
    assert(word(768)==0 && word(772)==2);
    p.kind=HALO_SCENE_MATERIAL_RUN;memset(p.a,0,sizeof(p.a));p.a[0]=256;p.a[1]=2;p.a[2]=4;p.a[3]=1024;packet(p);assert(word(1024)==2);
    p.kind=HALO_SCENE_MARK_SURFACES;memset(p.a,0,sizeof(p.a));p.a[0]=256;p.a[1]=2;p.a[2]=3;p.a[3]=384;p.a[5]=3;p.a[6]=1024;
    halo_scene_write32(arena,384,0);packet(p);assert(word(1024)==2 && word(384)==5);
    p.kind=HALO_SCENE_LEAF_REFERENCES;memset(p.a,0,sizeof(p.a));p.a[0]=256;p.a[1]=2;p.a[3]=2;p.a[4]=4;p.a[6]=3;p.a[7]=384;p.a[8]=400;p.a[9]=768;p.a[10]=1;p.a[11]=1024;
    packet(p);assert(word(1024)==1 && word(768)==0);
    p.a[2]=3;packet(p);assert(aborted==3);
    uint32_t layout[13]={56,32,34,36,37,40,44,46,48,52,50,0x64407440u,0x69746572u};
    memcpy(arena+2048,layout,52);int16_t maximum=3,stride=8,count=3,salt=-123;
    memcpy(arena+1536+32,&maximum,2);memcpy(arena+1536+34,&stride,2);arena[1536+36]=1;
    memcpy(arena+1536+46,&count,2);halo_scene_write32(arena,1536+40,layout[11]);halo_scene_write32(arena,1536+52,4096);memcpy(arena+4104,&salt,2);
    assert(ios_scene_datum(1,1536,UINT32_MAX,1024,2048) && word(1024)==(((uint32_t)(uint16_t)salt<<16)|1));
    halo_scene_write32(arena,3072,1536);halo_scene_write32(arena,3080,99);halo_scene_write32(arena,3084,1536^layout[12]);
    assert(ios_scene_datum(2,3072,0,1024,2048) && word(1024)==4104 && halo_scene_i16(arena,3076)==2);
    assert(word(3080)==(((uint32_t)(uint16_t)salt<<16)|1));
    halo_scene_write32(arena,1536+40,0);assert(!ios_scene_datum(1,1536,0,1024,2048) && atomic_load(&g_datum_fallbacks)==1);
    assert(atomic_load(&g_native_loop_upgrades)==0 && atomic_load(&g_scene_invalid)==3);

    /* Object header array: 12-byte rows, object flags at object+4. */
    stride=12;count=3;maximum=3;
    memcpy(arena+1536+32,&maximum,2);memcpy(arena+1536+34,&stride,2);
    memcpy(arena+1536+46,&count,2);halo_scene_write32(arena,1536+40,layout[11]);
    halo_scene_write32(arena,4096,1);halo_scene_write32(arena,4108,1);halo_scene_write32(arena,4120,1);
    halo_scene_write32(arena,4104,8192);halo_scene_write32(arena,4116,8208);halo_scene_write32(arena,4128,8224);
    halo_scene_write32(arena,8196,1); /* invisible parent/widgets: keep */
    halo_scene_write32(arena,8212,1u<<18); /* shadowless */
    halo_scene_write32(arena,8228,0);
    uint32_t original[3]={0x10000,0x10001,0x10002};
    memcpy(arena+9000,original,12);
    assert(ios_scene_filter_objects(1536,9000,3,0,1024,2048) && word(1024)==3);
    assert(!memcmp(arena+9000,original,12));
    /* Shadow output is scratch, not the shared list used by normal passes. */
    uint32_t scratch[3];memcpy(scratch,original,12);memcpy(arena+9000,scratch,12);
    assert(ios_scene_filter_objects(1536,9000,3,2,1024,2048) && word(1024)==2);
    assert(word(9000)==original[0] && word(9004)==original[2]);
    /* Fail after a would-be compaction: input/result must remain untouched. */
    memcpy(arena+9000,original,12);halo_scene_write32(arena,8196,1u<<18);
    halo_scene_write32(arena,4128,65535);halo_scene_write32(arena,1024,77);
    assert(!ios_scene_filter_objects(1536,9000,3,2,1024,2048));
    assert(!memcmp(arena+9000,original,12) && word(1024)==77);
    halo_scene_write32(arena,4128,8224);
    uint32_t bad_offset=layout[9];halo_scene_write32(arena,2048+9*4,UINT32_MAX);
    assert(!ios_scene_filter_objects(1536,9000,3,2,1024,2048));
    halo_scene_write32(arena,2048+9*4,bad_offset);
    /* Fresh single-entry queries observe callbacks changing later flags. */
    halo_scene_write32(arena,9000,original[2]);
    assert(ios_scene_filter_objects(1536,9000,1,2,1024,2048) && word(1024)==1);
    halo_scene_write32(arena,8228,1u<<18);
    assert(ios_scene_filter_objects(1536,9000,1,2,1024,2048) && word(1024)==0);
    memcpy(arena+9000,original,12);
    assert(!ios_scene_filter_objects(1536,9000,3,1,1024,2048));
    assert(!memcmp(arena+9000,original,12));
    assert(atomic_load(&g_native_loop_upgrades)==0);
    uint64_t calls_before=atomic_load(&g_scene_calls[6]), samples_before=atomic_load(&g_scene_samples[6]);
    unsigned reads_before=clock_reads;
    for(unsigned i=0;i<65536;i++)assert(ios_scene_filter_objects(1536,9000,1,2,1024,2048));
    uint64_t samples=atomic_load(&g_scene_samples[6])-samples_before;
    assert(atomic_load(&g_scene_calls[6])-calls_before==65536);
    assert(samples>30 && samples<100 && clock_reads-reads_before==samples*2);
    assert(atomic_load(&g_native_loop_upgrades)==0);
    puts("PASS: actual scene adapters, full spans, overlap rejection, packet ABI, iterator writeback, diagnostic fallback and zero helper upgrades");return 0;
}
"""
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'scene.c';source.write_bytes((prefix+body+suffix).encode());binary=Path(tmp)/'scene'
 subprocess.run([os.environ.get('CC','cc'),'-std=c11','-Wall','-Wextra','-Werror','-I'+str(r/'port/include'),'-I'+str(r/'port/ios/HaloIOS'),str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
