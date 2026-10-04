from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
runner=(r/'port/ios/HaloIOS/halo_guest_runner.m').read_text(encoding='utf-8')
adapter=runner.split('/* No persistent cache:',1)[1].split('static _Atomic uint64_t g_scene_calls',1)[0].split('*/',1)[1]
prefix=r"""#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>
#include "halo_timing_sample.h"
#include "ios_render_scan.h"
#include "halo_render_scan_native.h"
typedef int GLsizei;
static unsigned char arena[8192];
static unsigned aborted,uploads;
static float uploaded;
static void *gp(uint64_t va,size_t size) { return va && va<=sizeof(arena) && size<=sizeof(arena)-va?arena+va:NULL; }
static uint64_t halo_guest_exec_thread_pointer_upgrades(void) { return 17; }
static unsigned clock_reads; static double loading_seconds(void) { clock_reads++;return 1; }
#define HALO_GUEST_ABORT_HOST 5
static void say(const char *format,...) { (void)format; }
static void halo_guest_exec_abort(int reason) { assert(reason==5);aborted++; }
static void glUniform4fv(int location,int count,const void *value) { assert(location==3 && count==1);uploads++;memcpy(&uploaded,value,4);assert(!memcmp(arena+256,value,16)); }
static void glUniform1f(int location,float value) { assert(location==3);uploads++;uploaded=value;assert(!memcmp(arena+256,&value,4)); }
"""
suffix=r"""
static void packet(struct halo_render_scan_packet p) { memcpy(arena+32,&p,sizeof(p));ios_render_scan(32); }
static uint32_t result(unsigned offset) { uint32_t v;memcpy(&v,arena+offset,4);return v; }
int main(void) {
    _Static_assert(sizeof(struct halo_render_scan_packet)==44,"packet ABI");
    struct halo_render_scan_packet p={0};
    p.kind=HALO_SCAN_INDICES;p.head=128;p.size=3;p.result=512;
    uint16_t indices[3]={7,4,12};memcpy(arena+128,indices,6);packet(p);
    assert(result(512)==4 && result(516)==12 && atomic_load(&g_scan_items[0])==3);
    indices[0]=25;memcpy(arena+128,indices,6);packet(p);assert(result(516)==25);
    unsigned before=aborted;p.size=UINT32_MAX;packet(p);assert(aborted==before+1 && result(516)==25);
    p.size=2;p.head=8190;packet(p);assert(aborted==before+2 && result(516)==25);
    p.kind=HALO_SCAN_PALETTE;p.head=0;packet(p);assert(result(512)==0);
    p.head=8190;packet(p);assert(aborted==before+3);
    p.kind=HALO_SCAN_SHADER_HASH;p.head=128;p.size=0;packet(p);assert(result(512)==2166136261u);
    p.size=5;packet(p);assert(aborted==before+4);
    p.kind=HALO_SCAN_SHADER;p.head=0;p.size=32;p.next=0;p.key_offset=4;p.key_size=8;p.key=128;p.use_hash=0;
    packet(p);assert(result(512)==0);
    p.head=8190;packet(p);assert(aborted==before+5);
    p.kind=HALO_SCAN_TEXTURE;p.head=0;p.size=32;p.key_offset=4;p.hash_offset=16;p.hash=20;
    packet(p);assert(result(512)==0 && result(516)==0 && result(520)==0);
    before=aborted;ios_render_scan(8190);assert(aborted==before+1);
    float value[4]={1,2,3,4};memcpy(arena+128,value,16);memset(arena+256,0,16);
    ios_uniform_apply(3,256,128,1,0);assert(uploads==1 && uploaded==1);
    ios_uniform_apply(3,256,128,1,0);assert(uploads==1);
    value[0]=-0.0f;memcpy(arena+128,value,16);ios_uniform_apply(3,256,128,1,1);assert(uploads==2);
    value[0]=0.0f;memcpy(arena+128,value,16);ios_uniform_apply(3,256,128,1,1);assert(uploads==3);
    ios_uniform_apply(3,0,0,0,0);
    assert(atomic_load(&g_native_loop_upgrades)==0);
    before=aborted;ios_uniform_apply(-1,0,0,UINT32_MAX,9);assert(aborted==before);
    ios_uniform_apply(3,256,8190,1,0);assert(aborted==before+1 && uploads==3);
    ios_uniform_apply(3,256,128,257,0);assert(aborted==before+2);
    ios_uniform_apply(3,256,260,1,0);assert(aborted==before+3 && uploads==3);
    assert(atomic_load(&g_uniform_calls)==4 && atomic_load(&g_uniform_uploads)==3);
    uint64_t calls_before=atomic_load(&g_uniform_calls), samples_before=atomic_load(&g_uniform_samples);
    unsigned reads_before=clock_reads, uploads_before=uploads;
    for(unsigned i=0;i<65536;i++)ios_uniform_apply(3,256,256,1,1);
    uint64_t samples=atomic_load(&g_uniform_samples)-samples_before;
    assert(atomic_load(&g_uniform_calls)-calls_before==65536 && uploads==uploads_before);
    assert(samples>30 && samples<100 && clock_reads-reads_before==samples*2);
    puts("PASS: actual renderer adapters, changed index data, complete spans, packet ABI, invalid inputs, uniform shadow-before-upload order and telemetry");
    return 0;
}
"""
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'adapters.c';source.write_bytes((prefix+adapter+suffix).encode())
 binary=Path(tmp)/'adapters'
 cc=os.environ.get('CC','cc')
 subprocess.run([cc,'-std=c11','-Wall','-Wextra','-Werror','-I'+str(r/'port/include'),'-I'+str(r/'port/ios/HaloIOS'),str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
