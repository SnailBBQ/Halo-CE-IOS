#include "halo_texture_check.h"
#include "halo_timing_sample.h"
#include "halo_frame_diagnostics.h"
#include "halo_map_name.h"
#include "halo_coop_input.h"
#import "halo_guest_runner.h"
#import "halo_ios_controls.h"

#import <Foundation/Foundation.h>

#include "halo_guest_exec_bridge.h"
#include "halo_guest_runtime.h"
#include "halo_ios_gl_host.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <mach/mach.h>
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#include <sched.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include "halo_ios_net.h"
#include "halo_sdl_events.h"
#include "halo_ios_audio.h"
#include "halo_ios_platform.h"
#include "halo_hash_native.h"
#include "halo_geometry_cache.h"
#include "halo_crash_report.h"
#include "halo_scancodes.h"
#include "halo_launch_state.h"
#import "HaloSettingsStore.h"
#import "HaloMods.h"
#include "../../include/halo_ios_campaign_options.h"
#include "halo_engine_settings.h"
#include <string.h>
#include <strings.h>
#include <zlib.h>
#include "halo_dxt_decode.h"
#include "halo_crc_native.h"
#include "halo_texel_native.h"
#include "halo_silent_native.h"
#include "halo_vertex_native.h"
#include <OpenGLES/ES3/gl.h>
#include "halo_attribute_native.h"
#include "halo_render_scan_native.h"
#include "halo_scene_scan_native.h"
#include "../../include/ios_scene_scan.h"
#include "../../include/ios_render_scan.h"
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define HALO_GUEST_IMAGE_BASE UINT32_C(0x88000000)
#define HALO_GUEST_MAGIC UINT32_C(0x4F4C4148)
#define HALO_GUEST_ABI_VERSION 1
#define FOUR_GB UINT64_C(0x100000000)

#define PT_LOAD 1
#define PF_X 1
#define PF_W 2
#define PF_R 4
#define SHT_SYMTAB 2

typedef struct
{
    unsigned char e_ident[16];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint64_t e_entry;
    uint64_t e_phoff;
    uint64_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
} Elf64_Ehdr;

typedef struct
{
    uint32_t p_type;
    uint32_t p_flags;
    uint64_t p_offset;
    uint64_t p_vaddr;
    uint64_t p_paddr;
    uint64_t p_filesz;
    uint64_t p_memsz;
    uint64_t p_align;
} Elf64_Phdr;

typedef struct
{
    uint32_t sh_name;
    uint32_t sh_type;
    uint64_t sh_flags;
    uint64_t sh_addr;
    uint64_t sh_offset;
    uint64_t sh_size;
    uint32_t sh_link;
    uint32_t sh_info;
    uint64_t sh_addralign;
    uint64_t sh_entsize;
} Elf64_Shdr;

typedef struct
{
    uint32_t st_name;
    unsigned char st_info;
    unsigned char st_other;
    uint16_t st_shndx;
    uint64_t st_value;
    uint64_t st_size;
} Elf64_Sym;

struct halo_guest_header
{
    uint32_t magic;
    uint32_t abi_version;
    uint32_t image_end;
    uint32_t import_table;
    uint32_t import_names;
    uint32_t import_count;
    uint32_t start;
    uint32_t thread_start;
    uint32_t thread_attach;
    uint32_t init_array_start;
    uint32_t init_array_end;
};

struct halo_guest_boot
{
    uint32_t argc;
    uint32_t argv;
    uint32_t environment;
    uint32_t page_size;
};

struct guest_timespec
{
    int32_t seconds;
    int32_t nanoseconds;
};

struct guest_iovec
{
    uint32_t base;
    uint32_t length;
};

struct guest_winsize
{
    uint16_t rows;
    uint16_t cols;
    uint16_t xpixel;
    uint16_t ypixel;
};

struct guest_kstat
{
    uint64_t st_dev;
    uint64_t st_ino;
    uint32_t st_mode;
    uint32_t st_nlink;
    uint32_t st_uid;
    uint32_t st_gid;
    uint64_t st_rdev;
    uint64_t pad;
    int64_t st_size;
    int32_t st_blksize;
    int32_t pad2;
    int64_t st_blocks;
    int64_t st_atime_sec;
    int64_t st_atime_nsec;
    int64_t st_mtime_sec;
    int64_t st_mtime_nsec;
    int64_t st_ctime_sec;
    int64_t st_ctime_nsec;
    uint32_t unused[2];
};

struct posix_file_information
{
    uint32_t flags;
    uint32_t size_low;
    uint32_t size_high;
    uint32_t modification_seconds;
    uint32_t modification_nanoseconds;
    uint32_t access_seconds;
    uint32_t access_nanoseconds;
    uint32_t creation_seconds;
    uint32_t creation_nanoseconds;
};

static NSData *g_elf;
static const Elf64_Ehdr *g_ehdr;
static struct halo_guest_header *g_header;
static void (^g_line)(const char *);
static NSString *g_data_root;
static NSString *g_save_root;

static _Thread_local uint32_t g_guest_tp;
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
static _Atomic int g_nonjb_first_host_import_logged;
#endif
static _Thread_local int g_guest_errno;

static uint32_t g_guest_writable_start;
static uint32_t g_main_thread_va;
static pthread_t g_main_host_thread;
static int g_main_host_thread_valid;
static int g_logged_ioctl;
static int g_logged_tp_repair;

static pthread_mutex_t g_futex_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_futex_cond = PTHREAD_COND_INITIALIZER;
static pthread_mutex_t g_alloc_lock = PTHREAD_MUTEX_INITIALIZER;
/* the guest's mmap region, 0xA0000000..0xD0000000: freed ranges are reused (halo_guest_vm.h) */
#include "halo_guest_vm.h"
#include <os/proc.h>
static HaloVm g_vm;
static unsigned g_memory_failures_logged;
static uint32_t g_thread_stack_next = UINT32_C(0xEC000000);

static atomic_int g_guest_finished;
static volatile int g_guest_reason;
static volatile int g_guest_exit_code;
static volatile uint64_t g_missing_lr;

static void say(const char *fmt, ...)
{
    if (!g_line)
        return;

    char buffer[1200];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, ap);
    va_end(ap);
    g_line(buffer);
}

static void *gp(uint64_t guest, size_t size)
{
    if (!guest || guest >= FOUR_GB)
        return NULL;
    return halo_guest_ptr((uint32_t)guest, size);
}


static _Atomic uint64_t g_bulk_calls, g_bulk_bytes;
static void ios_memory_copy(uint32_t dst, uint32_t src, uint32_t size, int move)
{
    if (!size) return;
    void *d = gp(dst, size);
    const void *s = gp(src, size);
    if (!d || !s) {
        say("native memory copy: invalid guest span dst=0x%08x src=0x%08x size=%u", dst, src, size);
        halo_guest_exec_abort(HALO_GUEST_ABORT_HOST);
        return;
    }
    if (move) memmove(d, s, size); else memcpy(d, s, size);
    atomic_fetch_add(&g_bulk_calls, 1);
    atomic_fetch_add(&g_bulk_bytes, size);
}
static void ios_memory_fill(uint32_t dst, int value, uint32_t size)
{
    if (!size) return;
    void *d = gp(dst, size);
    if (!d) {
        say("native memory fill: invalid guest span dst=0x%08x size=%u", dst, size);
        halo_guest_exec_abort(HALO_GUEST_ABORT_HOST);
        return;
    }
    memset(d, value, size);
    atomic_fetch_add(&g_bulk_calls, 1);
    atomic_fetch_add(&g_bulk_bytes, size);
}
static double loading_seconds(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

static _Atomic uint64_t g_crc_calls, g_crc_bytes, g_crc_ns, g_texel_calls, g_texel_bytes, g_texel_ns, g_texel_fallbacks;
static _Atomic uint64_t g_phase_ns[24], g_phase_calls[24], g_phase_upgrades[24],g_phase_samples[24];
static HaloTimingSampler g_phase_sampler[24];
static int g_phase_measured[24];
static _Atomic uint64_t g_vertex_calls, g_vertex_bytes, g_vertex_ns, g_vertex_fallbacks;
static double g_phase_started[24];
static uint64_t g_phase_upgrade_start[24];
static _Atomic int g_waiting_frame, g_frame_present_ok;
static _Atomic uint64_t g_presented_frames;
/* Actual successful-present spacing, not the ten-second average. Long gaps
 * (loading/background) are reported separately rather than hidden in FPS. */
static _Atomic uint64_t g_frame_interval_bins[6],g_frame_interval_max_us;
static double g_last_successful_present;
static uint64_t g_present_interval_ns,g_frame_work_ns[3];
static HaloSlowFrames g_slow_frames;
static void ios_record_frame(void);
static void ios_report_slow_frames(void);

static _Atomic uint32_t g_frame_draws;
static double g_last_candidate_report;
static pthread_mutex_t g_timing_lock = PTHREAD_MUTEX_INITIALIZER;
static double g_first_frame_started;
/* Native attribute cache is used only on the existing guest GL thread. */
static struct halo_attribute_cache g_attribute_cache;
static int g_attribute_initialized;
static _Atomic uint64_t g_attribute_pointer_calls,g_attribute_pointer_reused,g_attribute_value_calls,g_attribute_ns,g_attribute_samples;
static void ios_vertex_state_invalidate(void)
{
    halo_attribute_invalidate(&g_attribute_cache);g_attribute_initialized=1;
}
static int ios_vertex_attribute_pointer(uint32_t index,uint32_t buffer,int32_t size,uint32_t type,
    uint32_t flags,int32_t stride,uint32_t offset)
{
    if (!g_attribute_initialized) ios_vertex_state_invalidate();
    static _Thread_local HaloTimingSampler sampler;
    HaloTimedSample timing=halo_timing_begin(&sampler,10,loading_seconds);
    int result=halo_attribute_pointer(&g_attribute_cache,index,buffer,size,type,flags,stride,offset);
    if (result<0) { say("native vertex attribute: invalid index %u",index);halo_guest_exec_abort(HALO_GUEST_ABORT_HOST);return 0; }
    atomic_fetch_add_explicit(&g_attribute_pointer_calls,1,memory_order_relaxed);
    if (!result) atomic_fetch_add_explicit(&g_attribute_pointer_reused,1,memory_order_relaxed);
    if(timing.selected) {
        atomic_fetch_add_explicit(&g_attribute_ns,halo_timing_finish(timing,loading_seconds),memory_order_relaxed);
        atomic_fetch_add_explicit(&g_attribute_samples,1,memory_order_relaxed);
    }
    return result;
}
static void ios_vertex_attribute_value(uint32_t index,uint32_t value_va)
{
    const float *value=value_va?gp(value_va,16):NULL;
    if (index>=16 || (value_va && (!value || (value_va&3u)))) {
        say("native vertex value: invalid index/span %u 0x%08x",index,value_va);
        halo_guest_exec_abort(HALO_GUEST_ABORT_HOST);return;
    }
    if (!g_attribute_initialized) ios_vertex_state_invalidate();
    static _Thread_local HaloTimingSampler sampler;
    HaloTimedSample timing=halo_timing_begin(&sampler,10,loading_seconds);
    halo_attribute_value(&g_attribute_cache,index,value);
    atomic_fetch_add_explicit(&g_attribute_value_calls,1,memory_order_relaxed);
    if(timing.selected) {
        atomic_fetch_add_explicit(&g_attribute_ns,halo_timing_finish(timing,loading_seconds),memory_order_relaxed);
        atomic_fetch_add_explicit(&g_attribute_samples,1,memory_order_relaxed);
    }
}

/* No persistent cache: renderer/drop invalidation remains wholly guest-owned.
   Packet fields are snapshotted before any result write, including aliases. */
static _Atomic uint64_t g_scan_calls[5],g_scan_items[5],g_scan_ns[5],g_scan_samples[5],g_scan_invalid,g_native_loop_upgrades;
static _Atomic uint64_t g_uniform_calls,g_uniform_uploads,g_uniform_bytes,g_uniform_ns,g_uniform_samples;
static const void *ios_scan_resolve(void *context,uint32_t address,size_t size)
{ (void)context;return gp(address,size); }
static void ios_render_scan(uint32_t packet_va)
{
    static _Thread_local HaloTimingSampler sampler;
    HaloTimedSample timing=halo_timing_begin(&sampler,10,loading_seconds);
    uint64_t upgrades=halo_guest_exec_thread_pointer_upgrades();
    struct halo_render_scan_packet p;
    const void *packet=(packet_va&3u)?NULL:gp(packet_va,sizeof(p));
    if (!packet) goto invalid;
    memcpy(&p,packet,sizeof(p));
    uint32_t result[3]={0},visited=0,items=0;
    void *output=NULL;
    if (p.kind==HALO_SCAN_INDICES) {
        output=(p.result&3u)?NULL:gp(p.result,8);
        if (!output || p.size>UINT32_MAX/2u) goto invalid;
        const void *indices=p.size?gp(p.head,(size_t)p.size*2):NULL;
        if (p.size && !indices) goto invalid;
        halo_scan_indices(indices,p.size,result);items=p.size;
    } else if (p.kind==HALO_SCAN_PALETTE) {
        output=(p.result&3u)?NULL:gp(p.result,4);
        const void *palette=p.head?gp(p.head,1024):NULL;
        if (!output || (p.head && !palette)) goto invalid;
        result[0]=halo_scan_palette(palette);items=p.head?256:0;
    } else if (p.kind==HALO_SCAN_SHADER_HASH) {
        output=(p.result&3u)?NULL:gp(p.result,4);
        if (!output || p.size>4096 || (p.size&3u)) goto invalid;
        const void *key=p.size?gp(p.head,p.size):NULL;
        if (p.size && !key) goto invalid;
        result[0]=halo_scan_hash_words(key,p.size);items=p.size/4;
    } else if (p.kind==HALO_SCAN_SHADER) {
        output=(p.result&3u)?NULL:gp(p.result,4);
        const void *key=(p.key_size && p.key_size<=4096)?gp(p.key,p.key_size):NULL;
        if (!output || !halo_scan_shader(ios_scan_resolve,NULL,p.head,p.size,p.next,p.key_offset,p.key_size,
            key,p.hash_offset,p.hash,p.use_hash,result,&visited)) goto invalid;
        items=visited;
    } else if (p.kind==HALO_SCAN_TEXTURE) {
        output=(p.result&3u)?NULL:gp(p.result,12);
        uint32_t key[4];const void *source=gp(p.key,16);
        if (!output || !source) goto invalid;
        memcpy(key,source,sizeof(key));
        if (!halo_scan_texture(ios_scan_resolve,NULL,p.head,p.size,p.next,p.key_offset,p.hash_offset,p.hash,
            key,result,&visited)) goto invalid;
        items=visited;
    } else goto invalid;
    memcpy(output,result,p.kind==HALO_SCAN_INDICES?8:p.kind==HALO_SCAN_TEXTURE?12:4);
    unsigned kind=p.kind-1;
    atomic_fetch_add_explicit(&g_native_loop_upgrades,halo_guest_exec_thread_pointer_upgrades()-upgrades,memory_order_relaxed);
    atomic_fetch_add_explicit(&g_scan_calls[kind],1,memory_order_relaxed);atomic_fetch_add_explicit(&g_scan_items[kind],items,memory_order_relaxed);
    if(timing.selected) {
        atomic_fetch_add_explicit(&g_scan_ns[kind],halo_timing_finish(timing,loading_seconds),memory_order_relaxed);
        atomic_fetch_add_explicit(&g_scan_samples[kind],1,memory_order_relaxed);
    }return;
invalid:
    atomic_fetch_add_explicit(&g_scan_invalid,1,memory_order_relaxed);
    say("native render scan: invalid packet/span/list at 0x%08x",packet_va);
    halo_guest_exec_abort(HALO_GUEST_ABORT_HOST);
}
/* Comparison, shadow update and upload preserve the original order. No native
   uniform cache or guest pointer survives this call. Negative locations are
   ignored before pointer access, as in the original renderer. */
static void ios_uniform_apply(int32_t location,uint32_t shadow_va,uint32_t value_va,uint32_t count,uint32_t scalar)
{
    if (location<0 || !count) return;
    static _Thread_local HaloTimingSampler sampler;
    HaloTimedSample timing=halo_timing_begin(&sampler,10,loading_seconds);
    uint64_t upgrades=halo_guest_exec_thread_pointer_upgrades();
    if (scalar>1 || !count || count>256 || (scalar && count!=1) || ((shadow_va|value_va)&3u)) goto invalid;
    size_t size=(size_t)count*(scalar?4:16);
    void *shadow=gp(shadow_va,size);const void *value=gp(value_va,size);
    if (!shadow || !value) goto invalid;
    /* Partial overlap was never a valid memcpy input in the guest path. */
    if (shadow_va!=value_va && (uint64_t)shadow_va<(uint64_t)value_va+size &&
        (uint64_t)value_va<(uint64_t)shadow_va+size) goto invalid;
    atomic_fetch_add_explicit(&g_uniform_calls,1,memory_order_relaxed);atomic_fetch_add_explicit(&g_uniform_bytes,size,memory_order_relaxed);
    if (memcmp(shadow,value,size)) {
        memcpy(shadow,value,size);
        if (scalar) { float v;memcpy(&v,value,4);glUniform1f(location,v); }
        else glUniform4fv(location,(GLsizei)count,value);
        atomic_fetch_add_explicit(&g_uniform_uploads,1,memory_order_relaxed);
    }
    atomic_fetch_add_explicit(&g_native_loop_upgrades,halo_guest_exec_thread_pointer_upgrades()-upgrades,memory_order_relaxed);
    if(timing.selected) {
        atomic_fetch_add_explicit(&g_uniform_ns,halo_timing_finish(timing,loading_seconds),memory_order_relaxed);
        atomic_fetch_add_explicit(&g_uniform_samples,1,memory_order_relaxed);
    }return;
invalid:
    atomic_fetch_add_explicit(&g_scan_invalid,1,memory_order_relaxed);
    say("native uniform: invalid location/span/count %d %u",location,count);
    halo_guest_exec_abort(HALO_GUEST_ABORT_HOST);
}

static _Atomic uint64_t g_scene_calls[7],g_scene_items[7],g_scene_ns[7],g_scene_samples[7],g_scene_invalid,g_datum_fallbacks;
static _Atomic uint64_t g_object_filter_skipped,g_object_filter_fallbacks;
static const void *ios_scene_resolve(uint32_t va,size_t size) { return gp(va,size); }
static int ios_scene_datum(uint32_t kind,uint32_t data,uint32_t index,uint32_t result_va,uint32_t layout_va)
{
    static _Thread_local HaloTimingSampler sampler;
    HaloTimedSample timing=halo_timing_begin(&sampler,10,loading_seconds);
    uint64_t upgrades=halo_guest_exec_thread_pointer_upgrades(),visited=0;
    uint32_t l[13],out[3];
    const void *layout=gp(layout_va,sizeof(l));
    void *result=(result_va&3u)?NULL:gp(result_va,4);
    if (!layout || !result || (layout_va&3u)) goto fallback;
    memcpy(l,layout,sizeof(l));
    if (!halo_scene_datum(ios_scene_resolve,kind,data,index,l,out,&visited)) goto fallback;
    if(kind==2) {
        void *iterator=gp(data,16);
        if(!iterator)goto fallback;
        /* Only update the two fields the original iterator writes. */
        int16_t absolute=(int16_t)out[1];
        memcpy((unsigned char *)iterator+4,&absolute,2);
        memcpy((unsigned char *)iterator+8,&out[2],4);
    }
    memcpy(result,out,4);
    atomic_fetch_add_explicit(&g_scene_calls[0],1,memory_order_relaxed);
    atomic_fetch_add_explicit(&g_scene_items[0],visited,memory_order_relaxed);
    if(timing.selected) {
        atomic_fetch_add_explicit(&g_scene_ns[0],halo_timing_finish(timing,loading_seconds),memory_order_relaxed);
        atomic_fetch_add_explicit(&g_scene_samples[0],1,memory_order_relaxed);
    }
    atomic_fetch_add_explicit(&g_native_loop_upgrades,halo_guest_exec_thread_pointer_upgrades()-upgrades,memory_order_relaxed);
    return 1;
    fallback:
    atomic_fetch_add_explicit(&g_datum_fallbacks,1,memory_order_relaxed);
    return 0;
}

static int ios_scene_filter_objects(uint32_t header_data, uint32_t indices_va,
    uint32_t count, uint32_t filter_mask, uint32_t result_va, uint32_t layout_va)
{
    static _Thread_local HaloTimingSampler sampler;
    HaloTimedSample timing=halo_timing_begin(&sampler,10,loading_seconds);
    uint64_t upgrades=halo_guest_exec_thread_pointer_upgrades(),visited=0;
    uint32_t l[13], kept=0;
    const void *layout=gp(layout_va,sizeof(l));
    void *result=(result_va&3u)?NULL:gp(result_va,4);
    uint32_t *indices=(indices_va&3u || !count)?NULL:gp(indices_va,(size_t)count*4);
    if (!layout || !result || !indices || (layout_va&3u) || count>512 || (filter_mask&~2u)) goto fallback;
    memcpy(l,layout,sizeof(l));
    if (!halo_scene_filter_objects(ios_scene_resolve,header_data,l,indices,count,filter_mask,&kept,&visited))
        goto fallback;
    memcpy(result,&kept,4);
    atomic_fetch_add_explicit(&g_object_filter_skipped,count-kept,memory_order_relaxed);
    atomic_fetch_add_explicit(&g_scene_calls[6],1,memory_order_relaxed);
    atomic_fetch_add_explicit(&g_scene_items[6],visited,memory_order_relaxed);
    if(timing.selected) {
        atomic_fetch_add_explicit(&g_scene_ns[6],halo_timing_finish(timing,loading_seconds),memory_order_relaxed);
        atomic_fetch_add_explicit(&g_scene_samples[6],1,memory_order_relaxed);
    }
    atomic_fetch_add_explicit(&g_native_loop_upgrades,halo_guest_exec_thread_pointer_upgrades()-upgrades,memory_order_relaxed);
    return 1;
    fallback:
    atomic_fetch_add_explicit(&g_object_filter_fallbacks,1,memory_order_relaxed);
    return 0;
}
static int ios_scene_overlap(uint32_t a,size_t an,uint32_t b,size_t bn)
{ return an && bn && (uint64_t)a<(uint64_t)b+bn && (uint64_t)b<(uint64_t)a+an; }
static void ios_scene_scan(uint32_t packet_va)
{
    static _Thread_local HaloTimingSampler sampler;
    HaloTimedSample timing=halo_timing_begin(&sampler,10,loading_seconds);
    uint64_t upgrades=halo_guest_exec_thread_pointer_upgrades(),visited=0;
    struct halo_scene_scan_packet p;
    const void *packet=(packet_va&3u)?NULL:gp(packet_va,sizeof(p));
    if (!packet) goto invalid;
    memcpy(&p,packet,sizeof(p));
    uint32_t *a=p.a,result=0;
    void *output=NULL;
    if(p.kind==HALO_SCENE_TRIANGLES || p.kind==HALO_SCENE_BIT_TRIANGLES) {
        /* a: surfaces,total,indices,capacity,triangles,index-output,flags */
        if(a[1]>UINT32_MAX/6u || a[3]>32767)goto invalid;
        const void *surfaces=a[1]?gp(a[0],(size_t)a[1]*6):NULL;
        void *triangles=a[3]?gp(a[4],(size_t)a[3]*6):NULL;
        if((a[1]&&!surfaces)||(a[3]&&!triangles) ||
        ios_scene_overlap(a[4],(size_t)a[3]*6,a[0],(size_t)a[1]*6))goto invalid;
        if(p.kind==HALO_SCENE_TRIANGLES) {
            void *indices=a[3]?gp(a[2],(size_t)a[3]*4):NULL;
            if((a[3]&&!indices) || ios_scene_overlap(a[4],(size_t)a[3]*6,a[2],(size_t)a[3]*4))goto invalid;
            if(!halo_scene_sorted_triangles(surfaces,a[1],indices,a[3],triangles))goto invalid;
            visited=a[3];
        } else {
            const void *flags=a[1]?gp(a[6],(size_t)((a[1]+31u)/32u)*4):NULL;
            void *indices=a[3]?gp(a[5],(size_t)a[3]*4):NULL;
            if((a[1]&&!flags)||(a[3]&&!indices) ||
            ios_scene_overlap(a[5],(size_t)a[3]*4,a[0],(size_t)a[1]*6) ||
            ios_scene_overlap(a[5],(size_t)a[3]*4,a[6],(size_t)((a[1]+31u)/32u)*4) ||
            ios_scene_overlap(a[4],(size_t)a[3]*6,a[6],(size_t)((a[1]+31u)/32u)*4) ||
            ios_scene_overlap(a[4],(size_t)a[3]*6,a[5],(size_t)a[3]*4))goto invalid;
            if(!halo_scene_bit_triangles(surfaces,a[1],flags,a[3],indices,triangles,&result))goto invalid;
            visited=a[1];
        }
    } else if(p.kind==HALO_SCENE_MATERIAL_RUN) {
        /* a: remaining indices,count,signed material end,result-count */
        if(!a[1] || a[1]>32767)goto invalid;
        const void *indices=gp(a[0],(size_t)a[1]*4);output=gp(a[3],4);
        if(!indices || !output)goto invalid;
        result=halo_scene_material_run(indices,a[1],(int32_t)a[2]);visited=result;
    } else if(p.kind==HALO_SCENE_MARK_SURFACES) {
        /* a: indices,count,total,flags,current,maximum,result-count */
        if(a[1]>32767 || a[2]>UINT32_MAX/4u || a[4]>a[5])goto invalid;
        const void *indices=a[1]?gp(a[0],(size_t)a[1]*4):NULL;
        void *flags=a[2]?gp(a[3],(size_t)((a[2]+31u)/32u)*4):NULL;output=gp(a[6],4);
        if(!output || (a[1]&&!indices)||(a[2]&&!flags) ||
        ios_scene_overlap(a[0],(size_t)a[1]*4,a[3],(size_t)((a[2]+31u)/32u)*4))goto invalid;
        if(!halo_scene_mark(indices,a[1],a[2],flags,a[4],a[5],&result,&visited))goto invalid;
    } else if(p.kind==HALO_SCENE_LEAF_REFERENCES) {
        /* a: ref-base,total-refs,first,count,stride,surface-offset,total-surfaces,
           allowed-bits,seen-bits,index-output,maximum,result-count */
        if(!a[4] || a[4]>4096 || a[5]>a[4] || a[4]-a[5]<4 || a[2]>a[1] || a[3]>a[1]-a[2] ||
        a[6]>UINT32_MAX/4u || a[10]>32767 || (uint64_t)a[1]*a[4]>UINT32_MAX)goto invalid;
        const unsigned char *refs=a[1]?gp(a[0],(size_t)a[1]*a[4]):NULL;
        size_t words=(size_t)((a[6]+31u)/32u)*4;
        const void *allowed=a[6]?gp(a[7],words):NULL;
        void *seen=a[6]?gp(a[8],words):NULL;
        void *indices=a[10]?gp(a[9],(size_t)a[10]*4):NULL;output=gp(a[11],4);
        if(!output ||(a[1]&&!refs)||(a[6]&&(!allowed||!seen))||(a[10]&&!indices) ||
        ios_scene_overlap(a[8],words,a[0],(size_t)a[1]*a[4]) ||
        ios_scene_overlap(a[9],(size_t)a[10]*4,a[0],(size_t)a[1]*a[4]) ||
        ios_scene_overlap(a[9],(size_t)a[10]*4,a[7],words) ||
        ios_scene_overlap(a[9],(size_t)a[10]*4,a[8],words))goto invalid;
        if(!halo_scene_leaf(refs?refs+(size_t)a[2]*a[4]:NULL,a[3],a[4],a[5],a[6],allowed,seen,indices,a[10],&result,&visited))goto invalid;
    } else goto invalid;
    if(output)memcpy(output,&result,4);
    atomic_fetch_add_explicit(&g_scene_calls[p.kind],1,memory_order_relaxed);
    atomic_fetch_add_explicit(&g_scene_items[p.kind],visited,memory_order_relaxed);
    if(timing.selected) {
        atomic_fetch_add_explicit(&g_scene_ns[p.kind],halo_timing_finish(timing,loading_seconds),memory_order_relaxed);
        atomic_fetch_add_explicit(&g_scene_samples[p.kind],1,memory_order_relaxed);
    }
    atomic_fetch_add_explicit(&g_native_loop_upgrades,halo_guest_exec_thread_pointer_upgrades()-upgrades,memory_order_relaxed);
    return;
    invalid:
    atomic_fetch_add_explicit(&g_scene_invalid,1,memory_order_relaxed);
    say("native scene scan: invalid packet/span/index at 0x%08x",packet_va);
    halo_guest_exec_abort(HALO_GUEST_ABORT_HOST);
}

static int ios_vertex_color_swizzle(uint32_t dst, uint32_t src, uint32_t size,
    uint32_t stride, uint32_t offsets_va, uint32_t count)
{
    double started=loading_seconds();
    if (!dst || !src || !offsets_va || (offsets_va & 3u) || !size || !stride || !count || count>16) { atomic_fetch_add(&g_vertex_fallbacks,1); return 0; }
    unsigned char *d=gp(dst,size);
    const unsigned char *s=gp(src,size);
    const uint32_t *offsets=gp(offsets_va,count*sizeof(uint32_t));
    if (!d || !s || !offsets || !halo_vertex_color_swizzle(d,s,size,stride,offsets,count)) {
        atomic_fetch_add(&g_vertex_fallbacks,1); return 0;
    }
    atomic_fetch_add(&g_vertex_calls,1);atomic_fetch_add(&g_vertex_bytes,size);
    atomic_fetch_add(&g_vertex_ns,(uint64_t)((loading_seconds()-started)*1e9));
    return 1;
}

static void ios_crc_checksum(uint32_t crc_va, uint32_t buffer_va, int32_t size)
{
    uint32_t *crc = gp(crc_va, 4);
    const uint8_t *buffer = size > 0 ? gp(buffer_va, (uint32_t)size) : NULL;
    if (!crc || size < 0 || (size && !buffer)) {
        say("native CRC: invalid guest span size=%d", size);
        halo_guest_exec_abort(HALO_GUEST_ABORT_HOST);
        return;
    }
    double started = loading_seconds();
    *crc = halo_crc_native(*crc, buffer, (uint32_t)size);
    atomic_fetch_add(&g_crc_calls, 1);
    atomic_fetch_add(&g_crc_bytes, size);
    atomic_fetch_add(&g_crc_ns, (uint64_t)((loading_seconds() - started) * 1e9));
}
static int ios_texel_fallback(void)
{
    uint64_t count=atomic_fetch_add(&g_texel_fallbacks,1);
    if (count<3) say("native texels: layout not handled; using existing guest converter");
    return 0;
}
static int ios_texture_decode_texels(uint32_t packet_va)
{
    const uint32_t *packet = gp(packet_va, 40);
    if (!packet) return ios_texel_fallback();
    uint32_t p[10]; memcpy(p, packet, sizeof(p));
    uint32_t kind=p[0], bytes=p[1], linear=p[2], w=p[3], h=p[4], d=p[5], pitch=p[6];
    if (!w || !h || !d || w>16384 || h>16384 || d>2048 || linear>1 || kind<1 || kind>_texel_d16) return ios_texel_fallback();
    uint32_t expected = 4;
    switch (kind) {
    case _texel_l8: case _texel_al8: case _texel_a8: case _texel_p8: expected=1; break;
    case _texel_r5g6b5: case _texel_a1r5g5b5: case _texel_x1r5g5b5: case _texel_a4r4g4b4:
    case _texel_a8l8: case _texel_g8b8: case _texel_r8b8: case _texel_r6g5b5: case _texel_l16:
    case _texel_r5g5b5a1: case _texel_r4g4b4a4: case _texel_yuy2: case _texel_uyvy: case _texel_d16: expected=2; break;
    }
    if (bytes != expected) return ios_texel_fallback();
    int yuv = kind==_texel_yuy2 || kind==_texel_uyvy;
    uint64_t row=(uint64_t)(yuv ? ((w+1)&~1u) : w)*bytes;
    if (linear && (d!=1 || pitch<row)) return ios_texel_fallback();
    if (!linear && (yuv || (w&(w-1)) || (h&(h-1)) || (d&(d-1)))) return ios_texel_fallback();
    uint64_t input = linear ? (uint64_t)(h-1)*pitch+row : (uint64_t)w*h*d*bytes;
    uint64_t output = (uint64_t)w*h*d*4;
    if (input>UINT32_MAX || output>UINT32_MAX) return ios_texel_fallback();
    const uint8_t *src=gp(p[7], (size_t)input);
    uint32_t *dst=gp(p[8], (size_t)output);
    const uint32_t *palette=p[9] ? gp(p[9], 1024) : NULL;
    if (!src || !dst || (p[9] && !palette)) {
        say("native texels: invalid guest span");
        halo_guest_exec_abort(HALO_GUEST_ABORT_HOST); return ios_texel_fallback();
    }
    double started=loading_seconds();
    int result=halo_texel_native(kind,bytes,linear,w,h,d,pitch,src,palette,dst);
    atomic_fetch_add(&g_texel_calls, 1);
    atomic_fetch_add(&g_texel_bytes, output);
    atomic_fetch_add(&g_texel_ns, (uint64_t)((loading_seconds()-started)*1e9));
    return result;
}
static void ios_frame_counts(uint32_t draws, uint32_t skipped, uint32_t clears, uint32_t targets)
{
    g_frame_draws=draws;
    if (g_waiting_frame && loading_seconds()-g_last_candidate_report>=5) {
        g_last_candidate_report=loading_seconds();
        say("first frame candidate: %u draws, %u skipped, %u clears, %u target changes", draws, skipped, clears, targets);
    }
}
static void ios_frame_phase(int phase, int done)
{
    if (phase<0 || phase>=24) return;
    if (!done) {
        /* Whole update/render/present/upload phases stay fully measured. */
        g_phase_measured[phase]=phase<4 || halo_timing_select(&g_phase_sampler[phase],6);
        if(g_phase_measured[phase])g_phase_started[phase]=loading_seconds();
        g_phase_upgrade_start[phase]=halo_guest_exec_thread_pointer_upgrades();
        if (phase==2) g_frame_present_ok=0;
    } else {
        uint64_t ns=g_phase_measured[phase]?(uint64_t)((loading_seconds()-g_phase_started[phase])*1e9):0;
        pthread_mutex_lock(&g_timing_lock);
        atomic_fetch_add_explicit(&g_phase_ns[phase],ns,memory_order_relaxed);
        atomic_fetch_add_explicit(&g_phase_calls[phase],1,memory_order_relaxed);
        atomic_fetch_add_explicit(&g_phase_samples[phase],g_phase_measured[phase],memory_order_relaxed);
        atomic_fetch_add_explicit(&g_phase_upgrades[phase],halo_guest_exec_thread_pointer_upgrades()-g_phase_upgrade_start[phase],memory_order_relaxed);
        pthread_mutex_unlock(&g_timing_lock);
        if(phase<3)g_frame_work_ns[phase]+=ns;
        if(phase==2)ios_record_frame();
        if (phase==2 && g_waiting_frame && g_frame_draws && g_frame_present_ok) {
            say("[loading] done: First game frame (%.3f s; draw calls submitted and drawable presented; visual correctness unverified)", loading_seconds()-g_first_frame_started);
            g_waiting_frame=0;
        }
    }
}


static _Atomic uint64_t g_silent_calls, g_silent_ns;
static void ios_silent_advance(uint32_t packet_va)
{
    uint32_t *header=gp(packet_va,24);
    if (!header || header[5]>64 || header[4]>48000) {
        say("native silent clock: invalid packet");
        halo_guest_exec_abort(HALO_GUEST_ABORT_HOST); return;
    }
    uint32_t count=header[5], frames=header[4];
    uint32_t *packet=gp(packet_va,24+(size_t)count*8);
    if (!packet) { halo_guest_exec_abort(HALO_GUEST_ABORT_HOST); return; }
    double cursor,step;
    memcpy(&cursor,packet,8); memcpy(&step,packet+2,8);
    double started=loading_seconds();
    halo_silent_native(&cursor,step,frames,count,(uint32_t (*)[2])(packet+6));
    memcpy(packet,&cursor,8);
    atomic_fetch_add(&g_silent_calls,1);
    atomic_fetch_add(&g_silent_ns,(uint64_t)((loading_seconds()-started)*1e9));
}
void halo_ios_quit_app(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        halo_ios_campaign_state(0);
        halo_ios_set_hosted_invite(NULL); /* async provider cleanup; next launch remains necessary */
        halo_ios_menu_reset();
        halo_crash_phase(HALO_PHASE_EXITED);
        fflush(NULL);
        exit(EXIT_SUCCESS); /* explicit user Quit; all guest threads end with the process */
    });
}
static _Atomic int g_campaign_active;
static pthread_mutex_t g_campaign_lock=PTHREAD_MUTEX_INITIALIZER;
static uint32_t g_campaign_queue[16],g_campaign_head,g_campaign_count;
void halo_ios_campaign_state(int active) {
    int previous=atomic_exchange(&g_campaign_active,!!active);
    if (!active) { pthread_mutex_lock(&g_campaign_lock);g_campaign_count=g_campaign_head=0;pthread_mutex_unlock(&g_campaign_lock); }
    if (previous!=!!active) [[HaloSettingsStore shared] setCampaignActive:!!active];
}
static void ios_campaign_state(uint32_t active) { halo_ios_campaign_state((int)active); }
static uint32_t ios_campaign_take_action(void) {
    pthread_mutex_lock(&g_campaign_lock);
    uint32_t action=0;
    if (g_campaign_count) { action=g_campaign_queue[g_campaign_head];g_campaign_head=(g_campaign_head+1)%16;--g_campaign_count; }
    pthread_mutex_unlock(&g_campaign_lock);return action;
}
int halo_ios_queue_campaign_action(uint32_t action)
{
    pthread_mutex_lock(&g_campaign_lock);
    int ok=action && atomic_load(&g_campaign_active) && g_campaign_count<16;
    if (ok) { g_campaign_queue[(g_campaign_head+g_campaign_count)%16]=action;++g_campaign_count; }
    pthread_mutex_unlock(&g_campaign_lock);return ok;
}
/* Scalar audio controls are atomic: no Objective-C lock on a mixing hot path. */
static _Atomic float g_music_gain=1.f,g_dialogue_gain=1.f,g_effects_gain=1.f,g_ambient_gain=1.f;
void halo_ios_set_ambient_gain(float gain) { atomic_store(&g_ambient_gain,gain<0.f?0.f:gain>1.f?1.f:gain); }
void halo_ios_set_channel_gains(float music,float dialogue,float effects) {
 atomic_store(&g_music_gain,music);atomic_store(&g_dialogue_gain,dialogue);atomic_store(&g_effects_gain,effects);
}
static pthread_mutex_t g_settings_sync_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned g_settings_pending;
static unsigned g_settings_generation[HE_COUNT];
static uint32_t g_settings_profile=UINT32_MAX;
static HsSettings g_settings_wanted;
void halo_ios_engine_settings_changed(const void *before, const void *after) {
    const HsSettings *old=before,*next=after;
    if(!next)return;
    pthread_mutex_lock(&g_settings_sync_lock);
    for(int i=0;i<HE_COUNT;i++) {
        if(he_is_profile(i) && (!old || !next->game_profile_ready))continue;
        char a[64],b[64];he_text(next,i,b);if(old)he_text(old,i,a);
        if(!old || strcmp(a,b)){g_settings_pending|=1u<<i;g_settings_generation[i]++;}
    }
    g_settings_wanted=*next;
    pthread_mutex_unlock(&g_settings_sync_lock);
}
/* Each slot is a 64-byte text value; validate before reading or writing. */
static _Atomic int g_local_coop;
static _Atomic int g_phys_present[2];
static _Atomic(int32_t) g_phys_axis[2][6];
static _Atomic(uint32_t) g_phys_held[2];
static _Atomic int g_coop_primary = -1, g_coop_secondary = 0;
int halo_ios_coop_touch_primary(void) { return atomic_load(&g_local_coop) && atomic_load(&g_coop_primary)<0; }
static int physical_slot(uint32_t pad) {
    if(pad!=1 && pad!=2)return -1;
    if(atomic_load(&g_local_coop))return atomic_load(pad==1?&g_coop_primary:&g_coop_secondary);
    return pad==1?(atomic_load(&g_phys_present[0])?0:atomic_load(&g_phys_present[1])?1:-1):-1;
}
static int ios_settings_value(uint32_t index,uint32_t address,uint32_t profile) {
    if(index==UINT32_MAX-1) {
        int coop=profile>=2;
        if(coop!=atomic_load(&g_local_coop)) {
            uint32_t held[2];int32_t axes[2][6];
            for(int pad=0;pad<2;pad++) {
                held[pad]=atomic_load(&g_phys_held[pad]);
                for(int axis=0;axis<6;axis++)axes[pad][axis]=atomic_load(&g_phys_axis[pad][axis]);
            }
            if(!halo_coop_switch_ready(held,axes))return 0;
            int a=atomic_load(&g_phys_present[0]),b=atomic_load(&g_phys_present[1]);
            int primary,secondary;halo_coop_route(a,b,&primary,&secondary);
            atomic_store(&g_coop_primary,primary);
            atomic_store(&g_coop_secondary,secondary);
            atomic_store(&g_local_coop,coop);
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:@"HaloCoopInputChanged" object:nil];
            });
        }
        return 0;
    }
    if(index==UINT32_MAX) {
        pthread_mutex_lock(&g_settings_sync_lock);
        BOOL changed=profile!=g_settings_profile;
        if(changed) {
            g_settings_profile=profile;
            for(int i=HE_PROFILE;i<19;i++) {
                g_settings_pending &= ~(1u<<i);
                g_settings_generation[i]++;
            }
        }
        pthread_mutex_unlock(&g_settings_sync_lock);
        if(changed && profile==UINT32_MAX)dispatch_async(dispatch_get_main_queue(), ^{
            [HaloSettingsStore.shared update:^(HsSettings *s){s->game_profile_ready=0;}];
        });
        return 0;
    }
    if(index>=HE_COUNT)return 0;
    /* Recovery launch overrides remain temporary, and must neither be undone
     * by synchronization nor written back as the player's normal preference. */
    if(halo_ios_safe_level() && (index==4 || index==5 || index==8))return 0;
    char *guest=gp(address,64);if(!guest || !memchr(guest,0,64))return 0;
    char incoming[64];memcpy(incoming,guest,64);
    pthread_mutex_lock(&g_settings_sync_lock);
    if(he_is_profile((int)index) && (profile==UINT32_MAX || profile!=g_settings_profile)) {
        pthread_mutex_unlock(&g_settings_sync_lock);return 0;
    }
    if(g_settings_pending & (1u<<index)) {
        he_text(&g_settings_wanted,(int)index,guest);
        g_settings_pending &= ~(1u<<index);
        pthread_mutex_unlock(&g_settings_sync_lock);return 1;
    }
    unsigned generation=g_settings_generation[index];
    pthread_mutex_unlock(&g_settings_sync_lock);
    NSString *value=[NSString stringWithUTF8String:incoming];if(!value)return 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        pthread_mutex_lock(&g_settings_sync_lock);
        BOOL current=generation==g_settings_generation[index];
        pthread_mutex_unlock(&g_settings_sync_lock);
        if(!current)return;
        [HaloSettingsStore.shared acceptEngineValue:value index:(int)index];
    });
    return 0;
}
static float ios_audio_class_gain(uint32_t category) {
 return atomic_load(category==32?&g_music_gain:(category==19 || category==44 || category==46 || category==47)?&g_dialogue_gain:(category==28 || category==29 || category==30 || (category>=33 && category<=35))?&g_ambient_gain:&g_effects_gain);
}
/* HUD packet is copied once per screen draw, with no guest pointers retained. */
static void ios_hud_options(uint32_t packet) {
 HsHud *out=gp(packet,sizeof(HsHud)*HS_HUD_COUNT);if(!out)return;
 HsSettings s=[[HaloSettingsStore shared] snapshot];memcpy(out,s.hud,sizeof(s.hud));
}
static _Atomic uint32_t g_network_role,g_network_peers,g_network_ping;
static void ios_network_status(uint32_t role,uint32_t peers,uint32_t ping) {
 atomic_store(&g_network_role,role);atomic_store(&g_network_peers,peers);atomic_store(&g_network_ping,ping);
}
/* The last map file the game opened (through the syscall bridge). It names the campaign map in the diagnostics when the
 * network layer has no map details, which it never has outside multiplayer. It is a hint, not proof: the menus can open other
 * map files too. Host strings only; no guest pointers are kept. */
static pthread_mutex_t g_last_map_lock = PTHREAD_MUTEX_INITIALIZER;
static char g_last_map[32];
static CFAbsoluteTime g_last_map_time;
static void ios_note_opened_path(const char *path)
{
    char name[32];
    if (!halo_map_name_from_path(path, name, sizeof(name)))
        return;
    pthread_mutex_lock(&g_last_map_lock);
    strlcpy(g_last_map, name, sizeof(g_last_map));
    g_last_map_time = CFAbsoluteTimeGetCurrent();
    pthread_mutex_unlock(&g_last_map_lock);
}
static int ios_last_map_copy(char *out, size_t size, double *age_seconds)
{
    int have;
    pthread_mutex_lock(&g_last_map_lock);
    have = g_last_map[0] != 0;
    if (have)
    {
        strlcpy(out, g_last_map, size);
        if (age_seconds)
            *age_seconds = CFAbsoluteTimeGetCurrent() - g_last_map_time;
    }
    pthread_mutex_unlock(&g_last_map_lock);
    return have;
}
static NSLock *NetworkDetailsLock(void) { static NSLock *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=[NSLock new];});return lock; }
static NSString *g_network_map;
static unsigned g_network_mode;
static CFTimeInterval g_network_details_time;
/* Game-thread input is copied, never retained. Limit work to twice a second;
 * Settings reads only immutable strings and scalar tunnel counters. */
static void ios_network_details(uint32_t map,uint32_t mode) {
    static CFTimeInterval next;CFTimeInterval now=CACurrentMediaTime();if(now<next)return;next=now+.5;
    NSString *name=nil;const char *bytes=map?gp(map,128):NULL;
    if(bytes){const char *end=memchr(bytes,0,128);if(end){name=[[NSString alloc] initWithBytes:bytes length:(NSUInteger)(end-bytes) encoding:NSUTF8StringEncoding];name=[[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] lastPathComponent];}}
    [NetworkDetailsLock() lock];g_network_map=name;g_network_mode=mode;g_network_details_time=now;[NetworkDetailsLock() unlock];
}
/* The existing game-thread phase hooks retain no game addresses. Capture only
 * the worst eight active gaps; monitor logging never runs on the render thread. */
static _Atomic uint64_t g_cap_wait_ns,g_drawable_present_ns,g_present_timing_calls;
static void ios_record_frame(void) {
    if(g_frame_present_ok) {
        HaloPresentTiming display=halo_ios_gl_last_present_timing();
        atomic_fetch_add_explicit(&g_cap_wait_ns,display.cap_wait_ns,memory_order_relaxed);
        atomic_fetch_add_explicit(&g_drawable_present_ns,display.drawable_ns,memory_order_relaxed);
        atomic_fetch_add_explicit(&g_present_timing_calls,1,memory_order_relaxed);
        pthread_mutex_lock(&g_timing_lock);
        int slot=halo_slow_frame_slot(&g_slow_frames,g_present_interval_ns);
        if(slot>=0) {
            HaloSlowFrame *frame=&g_slow_frames.frames[slot];memset(frame,0,sizeof(*frame));
            frame->number=atomic_load_explicit(&g_presented_frames,memory_order_relaxed);
            frame->interval_ns=g_present_interval_ns;frame->update_ns=g_frame_work_ns[0];
            frame->render_ns=g_frame_work_ns[1];frame->present_ns=g_frame_work_ns[2];frame->display=display;
            frame->role=atomic_load(&g_network_role);frame->peers=atomic_load(&g_network_peers);frame->ping=atomic_load(&g_network_ping);
            [NetworkDetailsLock() lock];
            if(g_network_map && CACurrentMediaTime()-g_network_details_time<5) {
                strlcpy(frame->map,g_network_map.UTF8String,sizeof(frame->map));frame->mode=g_network_mode;
            }
            [NetworkDetailsLock() unlock];
            if(frame->map[0])frame->map_source=1;
            else if(ios_last_map_copy(frame->map,sizeof(frame->map),NULL))frame->map_source=2;
        }
        pthread_mutex_unlock(&g_timing_lock);
    }
    memset(g_frame_work_ns,0,sizeof(g_frame_work_ns));
}
static void ios_report_slow_frames(void) {
    HaloSlowFrames frames;
    pthread_mutex_lock(&g_timing_lock);halo_slow_frames_take(&g_slow_frames,&frames);pthread_mutex_unlock(&g_timing_lock);
    uint64_t calls=atomic_exchange(&g_present_timing_calls,0),cap=atomic_exchange(&g_cap_wait_ns,0),drawable=atomic_exchange(&g_drawable_present_ns,0);
    if(calls)say("presentation wall-time breakdown: %llu calls, avg intentional cap wait %.3f ms, avg drawable present %.3f ms (driver/display wait included; not GPU time)",(unsigned long long)calls,cap/1e6/calls,drawable/1e6/calls);
    say("slow frames: %llu intervals >25ms and <=250ms; %llu longer gaps excluded; retained worst %u",(unsigned long long)frames.slow_count,(unsigned long long)frames.long_gaps,frames.count);
    for(unsigned i=0;i<frames.count;i++) {
        HaloSlowFrame *f=&frames.frames[i];
        say("slow frame #%llu: interval %.3f ms; update %.3f ms; render %.3f ms; present %.3f ms; cap wait %.3f ms; drawable %.3f ms; map=%s mode=%u role=%u peers=%u reported ping=%u ms; map source=%s",
            (unsigned long long)f->number,f->interval_ns/1e6,f->update_ns/1e6,f->render_ns/1e6,f->present_ns/1e6,f->display.cap_wait_ns/1e6,f->display.drawable_ns/1e6,
            f->map[0]?f->map:"unknown",f->mode,f->role,f->peers,f->ping,f->map_source==1?"network":f->map_source==2?"last map file opened":"none");
    }
}
static void ios_report_gl_waits(void) {
    HaloGlWaitSnapshot waits;
    int any = 0;
    halo_ios_gl_wait_stats_take(&waits);
    say("gl wall time by call type this window (calls are counted exactly; rare calls are timed every time, draws and buffer data on ~1 call in 64):");
    for(int c=0;c<HALO_GLW_COUNT;c++) {
        if(!waits.calls[c])continue;
        any=1;
        if(halo_glw_exact(c))
            say("  gl %-20s %8llu calls, %9.2f ms total, worst %7.3f ms, %llu calls over 2 ms",halo_glw_name(c),(unsigned long long)waits.calls[c],halo_gl_wait_total_ms(&waits,c),waits.max_ns[c]/1e6,(unsigned long long)waits.long_calls[c]);
        else
            say("  gl %-20s %8llu calls, %9.2f ms estimated from %llu samples, worst sampled %7.3f ms, %llu sampled calls over 2 ms",halo_glw_name(c),(unsigned long long)waits.calls[c],halo_gl_wait_total_ms(&waits,c),(unsigned long long)waits.samples[c],waits.max_ns[c]/1e6,(unsigned long long)waits.long_calls[c]);
    }
    if(!any)say("  gl no calls timed this window");
}
NSString *HaloNetworkSummary(void) {
 unsigned role=atomic_load(&g_network_role),peers=atomic_load(&g_network_peers),ping=atomic_load(&g_network_ping);
 NSString *status=role==1?@"Hosting":role==2?@"Client connected":role==3?@"Connecting":@"No active internet connection";
 [NetworkDetailsLock() lock];NSString *map=CACurrentMediaTime()-g_network_details_time<5?g_network_map:nil;unsigned mode=g_network_mode;[NetworkDetailsLock() unlock];
 NSArray *modes=@[@"—",@"Capture the Flag",@"Slayer",@"Oddball",@"King of the Hill",@"Race"];
 return [NSString stringWithFormat:@"%@ · %@ · %u peers\nMap: %@ · Mode: %@",status,ping?[NSString stringWithFormat:@"%u ms",ping]:@"Ping —",peers,map.length?map:@"—",map.length && mode<modes.count?modes[mode]:@"—"];

}
static void ios_campaign_options(uint32_t packet)
{
    HaloCampaignOptions *out = (packet & 3u) ? NULL : gp(packet, sizeof(*out));
    if (!out) return;
    HsSettings s = [[HaloSettingsStore shared] snapshot];
    HaloCampaignOptions result = { hs_cheat_mask(&s), 0, s.cheat_jump, s.cheat_speed, s.cheat_fov };
    if (s.cheat_one_hit) result.flags |= IOS_CHEAT_ONE_HIT;
    if (s.cheat_flashlight) result.flags |= IOS_CHEAT_FLASHLIGHT;
    if (s.cheat_no_fall) result.flags |= IOS_CHEAT_NO_FALL;
    if (s.cheat_rapid) result.flags |= IOS_CHEAT_RAPID;
    if (s.cheat_no_recoil) result.flags |= IOS_CHEAT_NO_RECOIL;
    if (s.cheat_third_person) result.flags |= IOS_CHEAT_THIRD_PERSON;
    if (s.cheat_noclip) result.flags |= IOS_CHEAT_NOCLIP;
    if (s.cheat_jetpack) result.flags |= IOS_CHEAT_JETPACK;
    if (s.cheat_ai_ignore) result.flags |= IOS_CHEAT_AI_IGNORE;
    result.flags |= ((uint32_t)hs_clampi(s.cheat_slow, 0, 7) << IOS_CHEAT_SLOW_SHIFT) & IOS_CHEAT_SLOW_MASK;
    result.flags|=(uint32_t)hs_clampi(s.cheat_alliance,0,4)<<IOS_CHEAT_ALLIANCE_SHIFT;
    result.flags|=(uint32_t)hs_clampi(s.cheat_projectile,0,6)<<IOS_CHEAT_PROJECTILE_SHIFT;
    if(s.cheat_detach_camera)result.flags|=IOS_CHEAT_DETACH_CAMERA;
    if(s.cheat_wireframe)result.flags|=IOS_CHEAT_WIREFRAME;
    if(s.cheat_hijack_vehicle)result.flags|=IOS_CHEAT_HIJACK_VEHICLE;
    if(s.cheat_medusa)result.flags|=IOS_CHEAT_MEDUSA;
    if(s.cheat_low_gravity)result.flags|=IOS_CHEAT_LOW_GRAVITY;
    if(s.cheat_hijack_npc)result.flags|=IOS_CHEAT_HIJACK_NPC;
    if(s.cheat_vehicle_health)result.flags|=IOS_CHEAT_VEHICLE_HEALTH;
    if (s.cheat_camo) result.flags |= IOS_CHEAT_CAMO;
    if (s.cheat_overshield) result.flags |= IOS_CHEAT_OVERSHIELD;
    result.action = ios_campaign_take_action();
    memcpy(out, &result, sizeof(result));
}
static _Atomic int g_touch_auto_fire, g_touch_controller_connected;
void halo_ios_set_touch_auto_fire(int enabled) { atomic_store(&g_touch_auto_fire, !!enabled); }
void halo_ios_set_touch_controller_connected(int connected) { atomic_store(&g_touch_controller_connected, !!connected); }
static int ios_touch_auto_fire(void) { return atomic_load(&g_touch_auto_fire) && (!atomic_load(&g_touch_controller_connected) || halo_ios_coop_touch_primary()); }
static _Atomic uint32_t g_viewmodel_flags = 3;
void halo_ios_set_viewmodel_flags(uint32_t flags) { atomic_store_explicit(&g_viewmodel_flags, flags & 3u, memory_order_relaxed); }
static uint32_t ios_viewmodel_flags(void) { return atomic_load_explicit(&g_viewmodel_flags, memory_order_relaxed); }
static _Atomic uint32_t g_cheat_flags;
void halo_ios_set_cheat_flags(uint32_t flags) { atomic_store_explicit(&g_cheat_flags, flags & 15u, memory_order_relaxed); }
static uint32_t ios_cheat_flags(void) { return atomic_load_explicit(&g_cheat_flags, memory_order_relaxed); }

static int ios_audio_open(uint32_t rate, uint32_t channels)
{
    int ok = halo_ios_audio_open(rate, channels);
    say("audio: %s (%u Hz, %u channels) - %s", ok ? "output opened" : "could not open output", rate, channels, halo_ios_audio_status());
    return ok;
}
static uint32_t ios_audio_fill(void)
{
    return halo_ios_audio_fill();
}
static uint32_t ios_audio_push(uint32_t buffer_va, uint32_t frames)
{
    if (!frames || frames > 48000) return 0;
    const float *samples = gp(buffer_va, (size_t)frames * 2 * sizeof(float));
    if (!samples) { halo_guest_exec_abort(HALO_GUEST_ABORT_HOST); return 0; }
    return halo_ios_audio_push(samples, frames);
}
static void ios_debug_state(int kind, uint32_t packet_va)
{
    static double previous[3];
    if (kind<0 || kind>2) return;
    double now=loading_seconds();
    if (now-previous[kind]<5) return;
    previous[kind]=now;
    const uint32_t *p=gp(packet_va,kind==0 ? 56 : kind==1 ? 4 : 16);
    if (!p) return;
    if (kind==0) {
        float f[6]; memcpy(f,p+4,sizeof(f));
        say("scene: tick=%d cinematic=%u windows=%u player=%d camera=(%.3f %.3f %.3f) near=%.3f far=%.3f fov=%.3f viewport=(%d %d %d %d)",
            (int32_t)p[0],p[1],p[2],(int32_t)p[3],f[0],f[1],f[2],f[3],f[4],f[5],(int32_t)p[10],(int32_t)p[11],(int32_t)p[12],(int32_t)p[13]);
    } else if (kind==1) {
        float fade; memcpy(&fade,p,4);
        say("screen fade: %.3f (-1 disabled, 1 opaque black)",fade);
    } else {
        say("final back buffer: guest=0x%08x texture=%u size=%ux%u",p[0],p[1],p[2],p[3]);
    }
}

static void ios_loading_stage(uint32_t name_va, int done)
{
    /* These calls are sequential on the game thread; no nested stages. */
    static double started;
    const char *name = gp(name_va, 1);
    if (!name) return;
    if (!done) {
        started = loading_seconds();
        if (!strcmp(name, "First game frame")) { g_frame_draws=0; g_frame_present_ok=0; g_first_frame_started=started; g_last_candidate_report=0; g_waiting_frame=1; }
        say("[loading] begin: %s", name);
    } else {
        say("[loading] done: %s (%.3f s)", name, loading_seconds() - started);
    }
}

/* the first few failures are written to the log; the game retries and would otherwise flood it */
static void report_memory_failure(const char *what, uint32_t size)
{
    if (g_memory_failures_logged++ >= 6)
        return;
    pthread_mutex_lock(&g_alloc_lock);
    uint64_t used = g_vm.used >> 20, holes = halo_vm_hole_bytes(&g_vm) >> 20, largest = halo_vm_largest_hole(&g_vm) >> 20;
    uint64_t region = ((uint64_t)g_vm.limit - g_vm.base) >> 20;
    pthread_mutex_unlock(&g_alloc_lock);
    say("guest memory: %s (the game asked for %u KiB; %llu of %llu MiB in use, %llu MiB free in holes, the largest %llu MiB)",
        what, size >> 10, (unsigned long long)used, (unsigned long long)region, (unsigned long long)holes, (unsigned long long)largest);
}

static uint32_t guest_alloc(uint32_t size, uint32_t alignment)
{
    if (alignment < 0x4000)
        alignment = 0x4000;

    pthread_mutex_lock(&g_alloc_lock);
    uint32_t va = halo_vm_alloc(&g_vm, size, alignment);
    pthread_mutex_unlock(&g_alloc_lock);
    if (!va)
    {
        report_memory_failure("out of address space", size);
        return 0;
    }
    if (!halo_guest_commit(va, size))
    {
        pthread_mutex_lock(&g_alloc_lock);
        halo_vm_free(&g_vm, va, size);
        pthread_mutex_unlock(&g_alloc_lock);
        report_memory_failure("could not map the memory", size);
        return 0;
    }
    return va;
}

/* defined further down; the backtrace below needs it first */
static const char *symbol_name_nearest(uint32_t value, uint32_t *symbol_va);

/* One line of a guest backtrace: the function and offset an address in the guest's code is in. */
static void say_guest_frame(const char *label, uint64_t host_address, uint64_t arena)
{
    if (host_address < arena || host_address - arena >= FOUR_GB)
        return;
    uint32_t va = (uint32_t)(host_address - arena), symbol_va = 0;
    const char *name = symbol_name_nearest(va, &symbol_va);
    say("  %s %s+0x%x (guest address 0x%08x)", label, name ? name : "unknown", name ? va - symbol_va : 0, va);
}

/* Where a fatal fault happened, and who called it: the function the program counter is in (the bridge's own "last
 * guest pc" is only the last indirect call it translated, a neighbour), the link register, then the frame-pointer chain
 * on the guest's stack. The chain is read only inside the guest stack area and only while it climbs. */
static void say_fault_backtrace(const halo_guest_exec_stats *stats)
{
    uint64_t arena = (uint64_t)(uintptr_t)halo_guest_base_address();

    if (!arena)
        return;
    say("FAULT FUNCTION (where the program counter was):");
    say_guest_frame("in", stats->last_host_pc, arena);
    say_guest_frame("called from (link register)", stats->last_lr, arena);
    uint64_t fp = stats->last_fp, previous = 0;
    for (int depth = 0; depth < 10; depth++)
    {
        if (fp < arena || fp - arena >= FOUR_GB)
            break;
        uint32_t fp_va = (uint32_t)(fp - arena);
        if (fp_va < UINT32_C(0xD0000000) || fp_va > UINT32_C(0xEFFFFFF0) || (fp_va & 15u) || fp <= previous)
            break;
        const uint64_t *record = halo_guest_ptr(fp_va, 16);
        if (!record)
            break;
        say_guest_frame("then", record[1], arena);
        previous = fp;
        fp = record[0];
    }
}

/* "guest memory: ..." and "device memory: ..." lines for the heartbeat */
static void report_memory(void)
{
    pthread_mutex_lock(&g_alloc_lock);
    uint64_t used = g_vm.used >> 20, peak = ((uint64_t)g_vm.peak - g_vm.base) >> 20, holes = halo_vm_hole_bytes(&g_vm) >> 20;
    uint64_t region = ((uint64_t)g_vm.limit - g_vm.base) >> 20, lost = g_vm.lost >> 20, failures = g_vm.failures;
    pthread_mutex_unlock(&g_alloc_lock);
    say("guest memory: %llu of %llu MiB of the game's address space in use (highest %llu MiB, %llu MiB free in holes%s), %llu failed requests",
        (unsigned long long)used, (unsigned long long)region, (unsigned long long)peak, (unsigned long long)holes,
        lost ? ", some space lost" : "", (unsigned long long)failures);

    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS)
    {
        unsigned long long left = (unsigned long long)os_proc_available_memory() >> 20;
        say("device memory: app footprint %llu MiB, %llu MiB left before iOS ends the app",
            (unsigned long long)info.phys_footprint >> 20, left);
    }
}

static const char *symbol_name_exact(uint32_t value)
{
    if (!g_elf || !g_ehdr || !g_ehdr->e_shoff || !g_ehdr->e_shnum)
        return NULL;

    const uint8_t *file = g_elf.bytes;
    size_t file_size = g_elf.length;

    if (g_ehdr->e_shoff + (uint64_t)g_ehdr->e_shnum * g_ehdr->e_shentsize > file_size)
        return NULL;

    const Elf64_Shdr *sections = (const Elf64_Shdr *)(file + g_ehdr->e_shoff);
    for (uint16_t i = 0; i < g_ehdr->e_shnum; ++i)
    {
        const Elf64_Shdr *sh = &sections[i];
        if (sh->sh_type != SHT_SYMTAB || sh->sh_entsize != sizeof(Elf64_Sym))
            continue;
        if (sh->sh_offset + sh->sh_size > file_size || sh->sh_link >= g_ehdr->e_shnum)
            continue;

        const Elf64_Shdr *strsh = &sections[sh->sh_link];
        if (strsh->sh_offset + strsh->sh_size > file_size)
            continue;

        const char *strings = (const char *)(file + strsh->sh_offset);
        const Elf64_Sym *symbols = (const Elf64_Sym *)(file + sh->sh_offset);
        uint64_t count = sh->sh_size / sizeof(Elf64_Sym);

        for (uint64_t n = 0; n < count; ++n)
        {
            if ((uint32_t)symbols[n].st_value == value &&
                symbols[n].st_name < strsh->sh_size)
                return strings + symbols[n].st_name;
        }
    }
    return NULL;
}


static uint32_t symbol_value_named(const char *wanted)
{
    if (!wanted || !g_elf || !g_ehdr || !g_ehdr->e_shoff || !g_ehdr->e_shnum)
        return 0;

    const uint8_t *file = g_elf.bytes;
    size_t file_size = g_elf.length;
    if (g_ehdr->e_shoff + (uint64_t)g_ehdr->e_shnum * g_ehdr->e_shentsize > file_size)
        return 0;

    const Elf64_Shdr *sections = (const Elf64_Shdr *)(file + g_ehdr->e_shoff);
    for (uint16_t i = 0; i < g_ehdr->e_shnum; ++i)
    {
        const Elf64_Shdr *sh = &sections[i];
        if (sh->sh_type != SHT_SYMTAB || sh->sh_entsize != sizeof(Elf64_Sym))
            continue;
        if (sh->sh_offset + sh->sh_size > file_size || sh->sh_link >= g_ehdr->e_shnum)
            continue;

        const Elf64_Shdr *strsh = &sections[sh->sh_link];
        if (strsh->sh_offset + strsh->sh_size > file_size)
            continue;

        const char *strings = (const char *)(file + strsh->sh_offset);
        const Elf64_Sym *symbols = (const Elf64_Sym *)(file + sh->sh_offset);
        uint64_t count = sh->sh_size / sizeof(Elf64_Sym);

        for (uint64_t n = 0; n < count; ++n)
        {
            if (symbols[n].st_name >= strsh->sh_size)
                continue;
            const char *name = strings + symbols[n].st_name;
            if (!strcmp(name, wanted))
                return (uint32_t)symbols[n].st_value;
        }
    }
    return 0;
}

static const char *symbol_name_nearest(uint32_t value, uint32_t *symbol_va)
{
    if (!g_elf || !g_ehdr || !g_ehdr->e_shoff || !g_ehdr->e_shnum)
        return NULL;

    const uint8_t *file = g_elf.bytes;
    size_t file_size = g_elf.length;
    if (g_ehdr->e_shoff + (uint64_t)g_ehdr->e_shnum * g_ehdr->e_shentsize > file_size)
        return NULL;

    const char *best_name = NULL;
    uint32_t best_value = 0;

    const Elf64_Shdr *sections = (const Elf64_Shdr *)(file + g_ehdr->e_shoff);
    for (uint16_t i = 0; i < g_ehdr->e_shnum; ++i)
    {
        const Elf64_Shdr *sh = &sections[i];
        if (sh->sh_type != SHT_SYMTAB || sh->sh_entsize != sizeof(Elf64_Sym))
            continue;
        if (sh->sh_offset + sh->sh_size > file_size || sh->sh_link >= g_ehdr->e_shnum)
            continue;

        const Elf64_Shdr *strsh = &sections[sh->sh_link];
        if (strsh->sh_offset + strsh->sh_size > file_size)
            continue;

        const char *strings = (const char *)(file + strsh->sh_offset);
        const Elf64_Sym *symbols = (const Elf64_Sym *)(file + sh->sh_offset);
        uint64_t count = sh->sh_size / sizeof(Elf64_Sym);

        for (uint64_t n = 0; n < count; ++n)
        {
            uint64_t sv = symbols[n].st_value;
            if (!sv || sv > value || sv > UINT32_MAX || symbols[n].st_name >= strsh->sh_size)
                continue;
            if ((uint32_t)sv >= best_value)
            {
                best_value = (uint32_t)sv;
                best_name = strings + symbols[n].st_name;
            }
        }
    }

    if (symbol_va)
        *symbol_va = best_value;
    return best_name;
}

static const char *missing_import_from_lr(uint64_t lr)
{
    uint64_t base = (uint64_t)(uintptr_t)halo_guest_base_address();
    if (!base || lr < base + 4)
        return NULL;

    uint32_t *call = (uint32_t *)(uintptr_t)(lr - 4);
    uint32_t instruction = *call;
    if ((instruction & UINT32_C(0xFC000000)) != UINT32_C(0x94000000))
        return NULL;

    int32_t imm26 = (int32_t)(instruction & 0x03FFFFFFu);
    if (imm26 & 0x02000000)
        imm26 |= (int32_t)0xFC000000;
    int64_t delta = ((int64_t)imm26) << 2;
    uint64_t target_host = (lr - 4) + delta;
    if (target_host < base || target_host - base >= FOUR_GB)
        return NULL;

    return symbol_name_exact((uint32_t)(target_host - base));
}

static uint32_t linux_to_darwin_open_flags(uint32_t flags)
{
    uint32_t result = 0;
    switch (flags & 3u)
    {
        case 1: result |= O_WRONLY; break;
        case 2: result |= O_RDWR; break;
        default: result |= O_RDONLY; break;
    }
    if (flags & 0x40u) result |= O_CREAT;
    if (flags & 0x80u) result |= O_EXCL;
    if (flags & 0x200u) result |= O_TRUNC;
    if (flags & 0x400u) result |= O_APPEND;
#ifdef O_CLOEXEC
    if (flags & 0x80000u) result |= O_CLOEXEC;
#endif
    return result;
}

static void fill_guest_kstat(struct guest_kstat *out, const struct stat *st)
{
    memset(out, 0, sizeof(*out));
    out->st_dev = (uint64_t)st->st_dev;
    out->st_ino = (uint64_t)st->st_ino;
    out->st_mode = (uint32_t)st->st_mode;
    out->st_nlink = (uint32_t)st->st_nlink;
    out->st_uid = (uint32_t)st->st_uid;
    out->st_gid = (uint32_t)st->st_gid;
    out->st_rdev = (uint64_t)st->st_rdev;
    out->st_size = (int64_t)st->st_size;
    out->st_blksize = (int32_t)st->st_blksize;
    out->st_blocks = (int64_t)st->st_blocks;
#if defined(__APPLE__)
    out->st_atime_sec = st->st_atimespec.tv_sec;
    out->st_atime_nsec = st->st_atimespec.tv_nsec;
    out->st_mtime_sec = st->st_mtimespec.tv_sec;
    out->st_mtime_nsec = st->st_mtimespec.tv_nsec;
    out->st_ctime_sec = st->st_ctimespec.tv_sec;
    out->st_ctime_nsec = st->st_ctimespec.tv_nsec;
#else
    out->st_atime_sec = st->st_atim.tv_sec;
    out->st_atime_nsec = st->st_atim.tv_nsec;
    out->st_mtime_sec = st->st_mtim.tv_sec;
    out->st_mtime_nsec = st->st_mtim.tv_nsec;
    out->st_ctime_sec = st->st_ctim.tv_sec;
    out->st_ctime_nsec = st->st_ctim.tv_nsec;
#endif
}

static int guest_timespec_in(uint32_t va, struct timespec *out)
{
    struct guest_timespec *g = gp(va, sizeof(*g));
    if (!g)
        return 0;
    out->tv_sec = g->seconds;
    out->tv_nsec = g->nanoseconds;
    return 1;
}

static void guest_timespec_out(uint32_t va, const struct timespec *value)
{
    struct guest_timespec *g = gp(va, sizeof(*g));
    if (!g)
        return;
    g->seconds = (int32_t)value->tv_sec;
    g->nanoseconds = (int32_t)value->tv_nsec;
}

static void guest_log_bytes(const void *bytes, size_t size)
{
    if (!bytes || !size)
        return;
    const char *p = bytes;
    char line[1024];
    size_t length = 0;
    for (size_t i = 0; i < size; ++i)
    {
        char c = p[i];
        if (c == '\n' || length == sizeof(line) - 1)
        {
            line[length] = 0;
            if (length)
                say("[guest] %s", line);
            length = 0;
            if (c == '\n')
                continue;
        }
        line[length++] = c;
    }
    if (length)
    {
        line[length] = 0;
        say("[guest] %s", line);
    }
}

/* Convert Linux futex timeouts to the realtime deadline Darwin expects. */
static int guest_futex_deadline(int operation, int flags,
                                const struct timespec *timeout, struct timespec *deadline)
{
    if (timeout->tv_sec < 0 || timeout->tv_nsec < 0 || timeout->tv_nsec >= 1000000000L)
        return EINVAL;
    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now)) return errno;
    if (operation == 9 && (flags & 256)) /* WAIT_BITSET | CLOCK_REALTIME */
        *deadline = *timeout;
    else
    {
        deadline->tv_sec = now.tv_sec + timeout->tv_sec;
        deadline->tv_nsec = now.tv_nsec + timeout->tv_nsec;
        if (operation == 9) /* WAIT_BITSET is absolute in the monotonic clock */
        {
            struct timespec monotonic;
            if (clock_gettime(CLOCK_MONOTONIC, &monotonic)) return errno;
            deadline->tv_sec -= monotonic.tv_sec;
            deadline->tv_nsec -= monotonic.tv_nsec;
        }
        if (deadline->tv_nsec >= 1000000000L)
        {
            deadline->tv_sec++;
            deadline->tv_nsec -= 1000000000L;
        }
        else if (deadline->tv_nsec < 0)
        {
            deadline->tv_sec--;
            deadline->tv_nsec += 1000000000L;
        }
    }
    return 0;
}

/* The cache worker is the sole owner of this native decompressor. */
struct guest_z_stream
{
    uint32_t next_in, avail_in, total_in;
    uint32_t next_out, avail_out, total_out;
    uint32_t msg, state, zalloc, zfree, opaque;
    int32_t data_type;
    uint32_t adler, reserved;
};
_Static_assert(sizeof(struct guest_z_stream) == 56, "guest z_stream must stay ILP32");
static z_stream g_cache_inflate;
static uint32_t g_cache_inflate_va;

static int ios_texture_decode_dxt(uint32_t kind, uint32_t source, uint32_t width,
    uint32_t height, uint32_t depth, uint32_t destination)
{
    if ((kind != 1 && kind != 3 && kind != 5) || !width || !height || !depth ||
        width > 16384 || height > 16384 || depth > 2048) return 0;
    uint64_t input_size = (((uint64_t)width + 3) / 4) * (((uint64_t)height + 3) / 4) * depth * (kind == 1 ? 8 : 16);
    uint64_t output_size = (uint64_t)width * height * depth * 4;
    if (input_size > UINT32_MAX || output_size > UINT32_MAX) return 0;
    const unsigned char *input = gp(source, (size_t)input_size);
    uint32_t *output = gp(destination, (size_t)output_size);
    if (!input || !output) return 0;
    halo_dxt_decode_level((unsigned char)kind, input, width, height, depth, output);
    static atomic_flag reported = ATOMIC_FLAG_INIT;
    if (!atomic_flag_test_and_set(&reported)) say("native DXT texture decoder ready");
    return 1;
}

static HtCache g_texture_checks;
static pthread_mutex_t g_texture_check_lock=PTHREAD_MUTEX_INITIALIZER;
static _Atomic uint64_t g_texture_check_calls,g_texture_check_hits,g_texture_check_compared,g_texture_check_hashed;
static void ios_texture_checks_reset(void) {
    pthread_mutex_lock(&g_texture_check_lock);ht_reset(&g_texture_checks);pthread_mutex_unlock(&g_texture_check_lock);
}
static uint32_t ios_texture_hash(uint32_t source, uint32_t size)
{
    const unsigned char *bytes = gp(source, size);
    if (!bytes) return 1;
    pthread_mutex_lock(&g_texture_check_lock);
    uint64_t hits=g_texture_checks.hits,compared=g_texture_checks.compared,hashed=g_texture_checks.hashed;
    uint32_t hash=ht_hash(&g_texture_checks,source,bytes,size);
    atomic_fetch_add_explicit(&g_texture_check_calls,1,memory_order_relaxed);
    atomic_fetch_add_explicit(&g_texture_check_hits,g_texture_checks.hits-hits,memory_order_relaxed);
    atomic_fetch_add_explicit(&g_texture_check_compared,g_texture_checks.compared-compared,memory_order_relaxed);
    atomic_fetch_add_explicit(&g_texture_check_hashed,g_texture_checks.hashed-hashed,memory_order_relaxed);
    pthread_mutex_unlock(&g_texture_check_lock);
    return hash;
}

static int ios_cache_inflate_init(uint32_t va)
{
    struct guest_z_stream *guest = gp(va, sizeof(*guest));
    if (!va || !guest || g_cache_inflate_va) return Z_STREAM_ERROR;
    memset(&g_cache_inflate, 0, sizeof(g_cache_inflate));
    int result = inflateInit(&g_cache_inflate);
    if (result == Z_OK)
    {
        g_cache_inflate_va = va;
        guest->total_in = guest->total_out = guest->msg = 0;
        guest->data_type = g_cache_inflate.data_type;
        guest->adler = (uint32_t)g_cache_inflate.adler;
        say("native cache decompressor ready: guest stream=0x%08x", va);
    }
    return result;
}

static int ios_cache_inflate_step(uint32_t va, int flush)
{
    struct guest_z_stream *guest = gp(va, sizeof(*guest));
    if (!va || va != g_cache_inflate_va || !guest) return Z_STREAM_ERROR;
    Bytef *input = guest->avail_in ? gp(guest->next_in, guest->avail_in) : NULL;
    Bytef *output = guest->avail_out ? gp(guest->next_out, guest->avail_out) : NULL;
    if ((guest->avail_in && !input) || (guest->avail_out && !output))
        return Z_STREAM_ERROR;
    uint32_t input_size = guest->avail_in, output_size = guest->avail_out;
    g_cache_inflate.next_in = input;
    g_cache_inflate.avail_in = input_size;
    g_cache_inflate.next_out = output;
    g_cache_inflate.avail_out = output_size;
    int result = inflate(&g_cache_inflate, flush);
    guest->next_in += input_size - g_cache_inflate.avail_in;
    guest->next_out += output_size - g_cache_inflate.avail_out;
    guest->avail_in = g_cache_inflate.avail_in;
    guest->avail_out = g_cache_inflate.avail_out;
    guest->total_in = (uint32_t)g_cache_inflate.total_in;
    guest->total_out = (uint32_t)g_cache_inflate.total_out;
    guest->data_type = g_cache_inflate.data_type;
    guest->adler = (uint32_t)g_cache_inflate.adler;
    /* A native zlib error string must never escape as a guest pointer. */
    guest->msg = 0;
    if (result != Z_OK && result != Z_STREAM_END)
        say("native cache decompression result=%d input=%u output=%u: %s",
            result, guest->total_in, guest->total_out,
            g_cache_inflate.msg ? g_cache_inflate.msg : "no error message");
    return result;
}

static int ios_cache_inflate_end(uint32_t va)
{
    if (!va || va != g_cache_inflate_va) return Z_STREAM_ERROR;
    say("native cache decompressor finished: input=%lu output=%lu",
        (unsigned long)g_cache_inflate.total_in, (unsigned long)g_cache_inflate.total_out);
    int result = inflateEnd(&g_cache_inflate);
    g_cache_inflate_va = 0;
    memset(&g_cache_inflate, 0, sizeof(g_cache_inflate));
    return result;
}

/* Linux ILP32 sysinfo uses 32-bit words, not the native iOS long layout. */
struct guest_sysinfo
{
    int32_t uptime;
    uint32_t loads[3];
    uint32_t totalram, freeram, sharedram, bufferram, totalswap, freeswap;
    uint16_t procs, pad;
    uint32_t totalhigh, freehigh, mem_unit;
    uint8_t reserved[8];
};
_Static_assert(sizeof(struct guest_sysinfo) == 64, "guest sysinfo must stay ILP32");
_Static_assert(offsetof(struct guest_sysinfo, mem_unit) == 52, "guest sysinfo memory unit offset");

static long long ios_guest_sysinfo(uint32_t va)
{
    struct guest_sysinfo *out = gp(va, sizeof(*out));
    if (!out) return -EFAULT;
    memset(out, 0, sizeof(*out));
    struct timespec uptime;
    if (clock_gettime(CLOCK_MONOTONIC, &uptime)) return -errno;
    out->uptime = uptime.tv_sec > INT32_MAX ? INT32_MAX : (int32_t)uptime.tv_sec;
    /* Page units keep physical-memory totals representable on >4 GB devices. */
    out->mem_unit = 4096;
    uint64_t total = NSProcessInfo.processInfo.physicalMemory;
    uint64_t total_units = total / out->mem_unit;
    out->totalram = total_units > UINT32_MAX ? UINT32_MAX : (uint32_t)total_units;
    mach_port_t host = mach_host_self();
    vm_size_t page_size = 0;
    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_page_size(host, &page_size) == KERN_SUCCESS &&
        host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS)
    {
        uint64_t available = ((uint64_t)vm.free_count + vm.inactive_count) * page_size;
        if (available > total) available = total;
        uint64_t units = available / out->mem_unit;
        out->freeram = units > out->totalram ? out->totalram : (uint32_t)units;
    }
    mach_port_deallocate(mach_task_self(), host);
    out->procs = 1; /* one hosted guest process; no guest swap or high-memory zone */
    static atomic_flag reported = ATOMIC_FLAG_INIT;
    if (!atomic_flag_test_and_set(&reported))
        say("guest memory query ready: total=%u MiB available=%u MiB unit=%u",
            out->totalram / 256, out->freeram / 256, out->mem_unit);
    return 0;
}

/* ---------- guest Linux syscall service ---------- */

static long long ios_host_syscall(long long number, long long a, long long b, long long c,
                                  long long d, long long e, long long f)
{
    (void)e; (void)f;
    errno = 0;

    switch (number)
    {
        case 17: /* getcwd */
        {
            char *buffer = gp((uint32_t)a, (size_t)(uint32_t)b);
            if (!buffer)
                return -EFAULT;
            if (!getcwd(buffer, (size_t)(uint32_t)b))
                return -errno;
            return (long long)strlen(buffer) + 1;
        }

        case 23: /* dup */
        {
            int r = dup((int)a);
            return r < 0 ? -errno : r;
        }

        case 25: /* fcntl */
        {
            int r = fcntl((int)a, (int)b, (int)c);
            return r < 0 ? -errno : r;
        }

        case 29: /* ioctl */
        {
            uint32_t request = (uint32_t)b;
            uint32_t argument = (uint32_t)c;

            if (!g_logged_ioctl)
            {
                say("[guest-ioctl] first request fd=%lld request=0x%08x arg=0x%08x",
                    a, request, argument);
                g_logged_ioctl = 1;
            }

            /*
             * The arm64_32 musl startup uses Linux ioctl request numbers.
             * Handle the terminal/stdio probes it performs instead of returning
             * ENOSYS, which immediately sends musl through its errno/TLS path.
             */
            switch (request)
            {
                case UINT32_C(0x5413): /* TIOCGWINSZ */
                {
                    struct guest_winsize *ws = gp(argument, sizeof(*ws));
                    if (!ws)
                        return -EFAULT;
                    ws->rows = 24;
                    ws->cols = 80;
                    ws->xpixel = 0;
                    ws->ypixel = 0;
                    return 0;
                }

                case UINT32_C(0x5401): /* TCGETS */
                {
                    void *termios = gp(argument, 64);
                    if (!termios)
                        return -EFAULT;
                    memset(termios, 0, 64);
                    return 0;
                }

                case UINT32_C(0x541B): /* FIONREAD */
                {
                    int32_t *available = gp(argument, sizeof(*available));
                    if (!available)
                        return -EFAULT;
                    *available = 0;
                    return 0;
                }

                case UINT32_C(0x5421): /* FIONBIO */
                    return 0;

                default:
                    return -ENOTTY;
            }
        }

        case 34: /* mkdirat */
        {
            const char *path = gp((uint32_t)b, 1);
            if (!path)
                return -EFAULT;
            int r = mkdir(path, (mode_t)c);
            return r < 0 ? -errno : r;
        }

        case 35: /* unlinkat */
        {
            const char *path = gp((uint32_t)b, 1);
            if (!path)
                return -EFAULT;
            int r = ((int)c & 0x200) ? rmdir(path) : unlink(path);
            return r < 0 ? -errno : r;
        }

        case 38: /* renameat */
        {
            const char *oldp = gp((uint32_t)b, 1);
            const char *newp = gp((uint32_t)d, 1);
            if (!oldp || !newp)
                return -EFAULT;
            int r = rename(oldp, newp);
            return r < 0 ? -errno : r;
        }

        case 46: /* ftruncate */
        {
            int r = ftruncate((int)a, (off_t)b);
            return r < 0 ? -errno : r;
        }

        case 49: /* chdir */
        {
            const char *path = gp((uint32_t)a, 1);
            if (!path)
                return -EFAULT;
            int r = chdir(path);
            return r < 0 ? -errno : r;
        }

        case 56: /* openat */
        {
            const char *path = gp((uint32_t)b, 1);
            if (!path)
                return -EFAULT;
            int flags = (int)linux_to_darwin_open_flags((uint32_t)c);
            int fd = open(path, flags, (mode_t)d);
            if (fd >= 0)
                ios_note_opened_path(path);
            return fd < 0 ? -errno : fd;
        }

        case 57: /* close */
        {
            int r = close((int)a);
            return r < 0 ? -errno : r;
        }

        case 62: /* lseek */
        {
            off_t r = lseek((int)a, (off_t)b, (int)c);
            return r < 0 ? -errno : r;
        }

        case 63: /* read */
        {
            void *buffer = gp((uint32_t)b, (size_t)(uint32_t)c);
            if (!buffer)
                return -EFAULT;
            ssize_t r = read((int)a, buffer, (size_t)(uint32_t)c);
            return r < 0 ? -errno : r;
        }

        case 64: /* write */
        {
            const void *buffer = gp((uint32_t)b, (size_t)(uint32_t)c);
            if (!buffer)
                return -EFAULT;
            if ((int)a == 1 || (int)a == 2)
            {
                guest_log_bytes(buffer, (size_t)(uint32_t)c);
                return (uint32_t)c;
            }
            ssize_t r = write((int)a, buffer, (size_t)(uint32_t)c);
            return r < 0 ? -errno : r;
        }

        case 65: /* readv */
        case 66: /* writev */
        {
            struct guest_iovec *vectors = gp((uint32_t)b, (size_t)(uint32_t)c * sizeof(*vectors));
            if (!vectors || c < 0 || c > 64)
                return -EFAULT;
            long long total = 0;
            for (int i = 0; i < (int)c; ++i)
            {
                void *buffer = gp(vectors[i].base, vectors[i].length);
                if (!buffer)
                    return -EFAULT;
                ssize_t r;
                if (number == 65)
                    r = read((int)a, buffer, vectors[i].length);
                else if ((int)a == 1 || (int)a == 2)
                {
                    guest_log_bytes(buffer, vectors[i].length);
                    r = vectors[i].length;
                }
                else
                    r = write((int)a, buffer, vectors[i].length);
                if (r < 0)
                    return -errno;
                total += r;
                if ((uint32_t)r != vectors[i].length)
                    break;
            }
            return total;
        }

        case 67: /* pread64 */
        {
            void *buffer = gp((uint32_t)b, (size_t)(uint32_t)c);
            if (!buffer)
                return -EFAULT;
            ssize_t r = pread((int)a, buffer, (size_t)(uint32_t)c, (off_t)d);
            return r < 0 ? -errno : r;
        }

        case 68: /* pwrite64 */
        {
            const void *buffer = gp((uint32_t)b, (size_t)(uint32_t)c);
            if (!buffer)
                return -EFAULT;
            ssize_t r = pwrite((int)a, buffer, (size_t)(uint32_t)c, (off_t)d);
            return r < 0 ? -errno : r;
        }

        case 79: /* newfstatat */
        {
            const char *path = gp((uint32_t)b, 1);
            struct guest_kstat *out = gp((uint32_t)c, sizeof(*out));
            if (!path || !out)
                return -EFAULT;
            struct stat st;
            if (stat(path, &st) != 0)
                return -errno;
            fill_guest_kstat(out, &st);
            return 0;
        }

        case 80: /* fstat */
        {
            struct guest_kstat *out = gp((uint32_t)b, sizeof(*out));
            if (!out)
                return -EFAULT;
            struct stat st;
            if (fstat((int)a, &st) != 0)
                return -errno;
            fill_guest_kstat(out, &st);
            return 0;
        }

        case 82: /* fsync */
        {
            int r = fsync((int)a);
            return r < 0 ? -errno : r;
        }

        case 83: /* fdatasync */
        {
            int r = fsync((int)a);
            return r < 0 ? -errno : r;
        }

        case 93: /* exit */
        case 94: /* exit_group */
            g_guest_exit_code = (int)a;
            halo_guest_exec_abort(HALO_GUEST_ABORT_EXIT);
            return 0;

        case 96: /* set_tid_address */
        case 178: /* gettid */
            return (long long)(uint32_t)pthread_mach_thread_np(pthread_self());

        case 98: /* futex */
        {
            uint32_t *address = gp((uint32_t)a, sizeof(uint32_t));
            if (!address)
                return -EFAULT;
            int operation = (int)b & 0x7F;
            uint32_t expected = (uint32_t)c;

            if (operation == 0 || operation == 9) /* WAIT / WAIT_BITSET */
            {
                pthread_mutex_lock(&g_futex_lock);
                if (*address != expected)
                {
                    pthread_mutex_unlock(&g_futex_lock);
                    return -EAGAIN;
                }

                int r = 0;
                if (d)
                {
                    struct timespec timeout, deadline;
                    if (!guest_timespec_in((uint32_t)d, &timeout))
                    {
                        pthread_mutex_unlock(&g_futex_lock);
                        return -EFAULT;
                    }
                    r = guest_futex_deadline(operation, (int)b, &timeout, &deadline);
                    if (r)
                    {
                        pthread_mutex_unlock(&g_futex_lock);
                        return -r;
                    }
                    r = pthread_cond_timedwait(&g_futex_cond, &g_futex_lock, &deadline);
                }
                else
                    r = pthread_cond_wait(&g_futex_cond, &g_futex_lock);

                pthread_mutex_unlock(&g_futex_lock);
                return r ? -r : 0;
            }
            if (operation == 1 || operation == 10) /* WAKE / WAKE_BITSET */
            {
                pthread_mutex_lock(&g_futex_lock);
                pthread_cond_broadcast(&g_futex_cond);
                pthread_mutex_unlock(&g_futex_lock);
                return (int)c;
            }
            return -ENOSYS;
        }

        case 101: /* nanosleep */
        {
            struct timespec request, remaining;
            if (!guest_timespec_in((uint32_t)a, &request))
                return -EFAULT;
            int r = nanosleep(&request, &remaining);
            if (r && b)
                guest_timespec_out((uint32_t)b, &remaining);
            return r ? -errno : 0;
        }

        case 115: /* clock_nanosleep */
        {
            struct timespec request;
            struct timespec remaining = {0};
            struct timespec now = {0};
            struct timespec sleep_for = {0};

            if (!guest_timespec_in((uint32_t)c, &request))
                return -EFAULT;

            clockid_t host_clock;
            switch ((int)a)
            {
                case 0: host_clock = CLOCK_REALTIME; break;
                case 1: host_clock = CLOCK_MONOTONIC; break;
#ifdef CLOCK_MONOTONIC_RAW
                case 4: host_clock = CLOCK_MONOTONIC_RAW; break;
#endif
                default: host_clock = CLOCK_MONOTONIC; break;
            }

            /*
             * Linux clock_nanosleep flags bit 0 is TIMER_ABSTIME.
             * Darwin/iOS does not expose Linux's syscall ABI, so translate
             * absolute sleeps into a relative nanosleep.
             */
            if (((int)b & 1) != 0)
            {
                if (clock_gettime(host_clock, &now) != 0)
                    return -errno;

                sleep_for.tv_sec = request.tv_sec - now.tv_sec;
                sleep_for.tv_nsec = request.tv_nsec - now.tv_nsec;
                if (sleep_for.tv_nsec < 0)
                {
                    sleep_for.tv_sec--;
                    sleep_for.tv_nsec += 1000000000L;
                }

                if (sleep_for.tv_sec < 0 ||
                    (sleep_for.tv_sec == 0 && sleep_for.tv_nsec <= 0))
                    return 0;
            }
            else
                sleep_for = request;

            int r = nanosleep(&sleep_for, &remaining);
            if (r != 0)
            {
                if (errno == EINTR && d && (((int)b & 1) == 0))
                    guest_timespec_out((uint32_t)d, &remaining);
                return -errno;
            }
            return 0;
        }

        case 113: /* clock_gettime */
        case 114: /* clock_getres */
        {
            struct timespec value;
            clockid_t host_clock;
            switch ((int)a)
            {
                case 0: host_clock = CLOCK_REALTIME; break;
                case 1: host_clock = CLOCK_MONOTONIC; break;
#ifdef CLOCK_MONOTONIC_RAW
                case 4: host_clock = CLOCK_MONOTONIC_RAW; break;
#endif
                default: host_clock = CLOCK_MONOTONIC; break;
            }
            int r = number == 113
                ? clock_gettime(host_clock, &value)
                : clock_getres(host_clock, &value);
            if (r)
                return -errno;
            guest_timespec_out((uint32_t)b, &value);
            return 0;
        }

        case 179: /* sysinfo */
            return ios_guest_sysinfo((uint32_t)a);

        case 124: /* sched_yield */
            sched_yield();
            return 0;

        case 132: /* sigaltstack */
        case 134: /* rt_sigaction */
        case 135: /* rt_sigprocmask */
            return 0;

        case 160: /* uname */
        {
            char *out = gp((uint32_t)a, 65 * 6);
            if (!out)
                return -EFAULT;
            memset(out, 0, 65 * 6);
            strlcpy(out + 0 * 65, "Linux", 65);
            strlcpy(out + 1 * 65, "halo-ios", 65);
            strlcpy(out + 2 * 65, "1", 65);
            strlcpy(out + 3 * 65, "Halo iOS", 65);
            strlcpy(out + 4 * 65, "aarch64", 65);
            return 0;
        }

        case 169: /* gettimeofday */
        {
            struct timeval tv;
            gettimeofday(&tv, NULL);
            struct guest_timespec *out = gp((uint32_t)a, sizeof(*out));
            if (out)
            {
                out->seconds = (int32_t)tv.tv_sec;
                out->nanoseconds = (int32_t)tv.tv_usec;
            }
            return 0;
        }

        case 172: return getpid();
        case 173: return getppid();
        case 174: return getuid();
        case 175: return geteuid();
        case 176: return getgid();
        case 177: return getegid();

        case 214: /* brk */
            return -ENOMEM;

        case 215: /* munmap */
            if (!halo_guest_decommit((uint32_t)a, (size_t)b))
                return -EINVAL;
            pthread_mutex_lock(&g_alloc_lock);
            halo_vm_free(&g_vm, (uint32_t)a, (uint32_t)b);
            pthread_mutex_unlock(&g_alloc_lock);
            return 0;

        case 222: /* mmap */
        {
            uint32_t va = (uint32_t)a;
            uint32_t size = (uint32_t)b;
            if (!size)
                return -EINVAL;
            if (!va)
                va = guest_alloc(size, 0x4000);
            else if (!halo_guest_commit(va, size))
                return -ENOMEM;
            if (!va)
                return -ENOMEM;
            return va;
        }

        case 226: /* mprotect */
        {
            int protection = 0;
            if (c & 1) protection |= PROT_READ;
            if (c & 2) protection |= PROT_WRITE;
            if (c & 4) protection |= PROT_EXEC;
            return halo_guest_protect((uint32_t)a, (size_t)b, protection) ? 0 : -EINVAL;
        }

        case 233: /* madvise */
            return 0;

        case 261: /* prlimit64 */
            return -ENOSYS;

        case 278: /* getrandom */
        {
            void *buffer = gp((uint32_t)a, (size_t)(uint32_t)b);
            if (!buffer)
                return -EFAULT;
            arc4random_buf(buffer, (size_t)(uint32_t)b);
            return (uint32_t)b;
        }

        case 283: /* membarrier */
            __sync_synchronize();
            return 0;

        default:
            say("[guest-syscall] unsupported Linux syscall %lld", number);
            return -ENOSYS;
    }
}

/* ---------- direct host imports ---------- */

static void ios_host_log(int priority, uint32_t text)
{
    (void)priority;
    const char *s = gp(text, 1);
    if (s)
        say("[guest] %s", s);
}

static void ios_host_abort(uint32_t reason)
{
    const char *s = gp(reason, 1);
    say("GUEST ABORT: %s", s ? s : "<no reason>");
    halo_guest_exec_abort(HALO_GUEST_ABORT_HOST);
}

static void ios_host_exit(int code)
{
    g_guest_exit_code = code;
    halo_guest_exec_abort(HALO_GUEST_ABORT_EXIT);
}

static int ios_host_errno(void)
{
    return g_guest_errno ? g_guest_errno : errno;
}

static uint32_t ios_host_get_tp(void)
{
    if (g_guest_tp &&
        g_guest_writable_start &&
        g_guest_tp < g_guest_writable_start)
    {
        if (g_main_host_thread_valid &&
            pthread_equal(pthread_self(), g_main_host_thread) &&
            g_main_thread_va)
        {
            if (!g_logged_tp_repair)
            {
                say("[guest-tls] repaired invalid main TP 0x%08x -> 0x%08x",
                    g_guest_tp, g_main_thread_va);
                g_logged_tp_repair = 1;
            }
            g_guest_tp = g_main_thread_va;
        }
    }

    return g_guest_tp;
}

static void ios_host_set_tp(uint32_t thread)
{
    if (thread &&
        g_guest_writable_start &&
        thread < g_guest_writable_start &&
        g_main_host_thread_valid &&
        pthread_equal(pthread_self(), g_main_host_thread) &&
        g_main_thread_va)
    {
        say("[guest-tls] rejected non-writable TP 0x%08x; using main_thread 0x%08x",
            thread, g_main_thread_va);
        thread = g_main_thread_va;
    }

    g_guest_tp = thread;
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
    if (g_main_host_thread_valid &&
        pthread_equal(pthread_self(), g_main_host_thread) &&
        atomic_exchange_explicit(&g_nonjb_first_host_import_logged, 1, memory_order_relaxed) == 0)
    {
        say("NON-JB EXECUTION TRACE: [416] first guest host import reached: host_set_tp(0x%08x)", thread);
        halo_crash_phase("nonjb 416 first host import host_set_tp");
    }
#endif
}

static HgCache g_geometry_cache;
static _Atomic uint64_t g_geometry_calls, g_geometry_changed, g_geometry_bytes;
static const void *ios_geometry_resolve(void *context, uint32_t address, size_t size) {
    (void)context; return gp(address,size);
}
static uint32_t ios_geometry_pages(uint32_t first,uint32_t count,uint32_t dirty_va) {
    if (!count && first==UINT32_MAX) { hg_reset(&g_geometry_cache);ios_texture_checks_reset();return 1; }
    if (!count || count>256 || first>=HG_PAGE_COUNT || count>HG_PAGE_COUNT-first) return 0;
    uint64_t source=0x80000000ull+(uint64_t)first*HG_PAGE_SIZE, end=source+(uint64_t)count*HG_PAGE_SIZE;
    if ((uint64_t)dirty_va<end && (uint64_t)dirty_va+count>source) return 0;
    unsigned char *dirty=gp(dirty_va,count);
    uint64_t changed=g_geometry_cache.changed, bytes=g_geometry_cache.compared;
    int ok=dirty && hg_compare(&g_geometry_cache,ios_geometry_resolve,NULL,first,count,dirty);
    atomic_fetch_add(&g_geometry_calls,1);
    atomic_fetch_add(&g_geometry_changed,g_geometry_cache.changed-changed);
    atomic_fetch_add(&g_geometry_bytes,g_geometry_cache.compared-bytes);
    return ok;
}
static void ios_memory_watch_initialize(void) {ios_texture_checks_reset();}
static void ios_memory_watch_protect(uint32_t a, uint32_t b) { (void)a; (void)b; }
static uint32_t ios_memory_watch_generation(uint32_t a, uint32_t b) { (void)a; (void)b; return 0; }
static uint32_t ios_memory_watch_serial(void) { return 1; }
static void ios_memory_watch_prepare_write(uint32_t a, uint32_t b) { (void)a; (void)b; }
static void ios_memory_watch_forget(uint32_t a,uint32_t b) {
    pthread_mutex_lock(&g_texture_check_lock);ht_forget(&g_texture_checks,a,b);pthread_mutex_unlock(&g_texture_check_lock);
}

static void ios_host_android_path(int which, uint32_t buffer_va, uint32_t size)
{
    char *buffer = gp(buffer_va, size);
    if (!buffer || !size)
        return;
    NSString *root = which ? g_save_root : g_data_root;
    snprintf(buffer, size, "%s", root.fileSystemRepresentation);
}

/* ---------- iOS SDL / OpenGL ES service ---------- */

static int ios_sdl_init(uint32_t flags)
{
    return halo_ios_gl_sdl_init(flags);
}

static int ios_sdl_set_hint(uint32_t name_va, uint32_t value_va)
{
    const char *name = gp(name_va, 1);
    const char *value = gp(value_va, 1);
    return halo_ios_gl_set_hint(name, value);
}

static void ios_sdl_get_error(uint32_t buffer_va, uint32_t size)
{
    char *buffer = gp(buffer_va, size);
    if (buffer)
        halo_ios_gl_get_error(buffer, size);
}

static int64_t ios_sdl_ticks(void)
{
    static mach_timebase_info_data_t tb;
    if (!tb.denom)
        mach_timebase_info(&tb);
    uint64_t now = mach_absolute_time();
    long double ns = (long double)now * tb.numer / tb.denom;
    return (int64_t)(ns / 1000000.0L);
}

static int64_t ios_sdl_thread_id(void)
{
    return (int64_t)pthread_mach_thread_np(pthread_self());
}

static uint32_t ios_sdl_create_window(uint32_t title_va, int width, int height, int64_t flags)
{
    const char *title = gp(title_va, 1);
    return halo_ios_gl_create_window(title, width, height, flags);
}

static void ios_sdl_window_size(uint32_t window, uint32_t w_va, uint32_t h_va)
{
    (void)window;
    int width = 0, height = 0;
    halo_ios_gl_window_size(&width, &height);
    int *w = gp(w_va, sizeof(int));
    int *h = gp(h_va, sizeof(int));
    if (w) *w = width;
    if (h) *h = height;
}

static int ios_sdl_set_relative_mouse(uint32_t window, int enabled)
{
    return halo_ios_gl_set_relative_mouse(window, enabled);
}

static int ios_sdl_gl_set_attribute(int attribute, int value)
{
    return halo_ios_gl_set_attribute(attribute, value);
}

static uint32_t ios_sdl_gl_create_context(uint32_t window)
{
    return halo_ios_gl_create_context(window);
}

static int ios_sdl_gl_make_current(uint32_t window, uint32_t context)
{
    return halo_ios_gl_make_current(window, context);
}

static int ios_sdl_gl_set_swap_interval(int interval)
{
    return halo_ios_gl_set_swap_interval(interval);
}

static int ios_sdl_gl_swap_window(uint32_t window)
{
    int ok=halo_ios_gl_swap_window(window);
    g_frame_present_ok=ok;
    if(ok) {
        double now=loading_seconds();
        g_present_interval_ns=0;
        if(g_last_successful_present>0) {
            double ms=(now-g_last_successful_present)*1000.;
            g_present_interval_ns=(uint64_t)(ms*1e6);
            unsigned bin=ms<=18.?0:ms<=25.?1:ms<=33.4?2:ms<=50.?3:ms<=250.?4:5;
            atomic_fetch_add_explicit(&g_frame_interval_bins[bin],1,memory_order_relaxed);
            if(bin<5) {
                uint64_t us=(uint64_t)(ms*1000.),old=atomic_load(&g_frame_interval_max_us);
                while(us>old && !atomic_compare_exchange_weak(&g_frame_interval_max_us,&old,us)){}
            }
        }
        g_last_successful_present=now;
        atomic_fetch_add_explicit(&g_presented_frames,1,memory_order_relaxed);
    }
    return ok;
}

static pthread_mutex_t g_event_lock = PTHREAD_MUTEX_INITIALIZER;
static HaloLookAccumulator g_look;
static int g_focus_event_pending;

uint64_t halo_ios_presented_frames(void)
{
    return atomic_load_explicit(&g_presented_frames, memory_order_relaxed);
}

void halo_ios_touch_look(float dx, float dy)
{
    pthread_mutex_lock(&g_event_lock);
    halo_look_add(&g_look, dx, dy);
    pthread_mutex_unlock(&g_event_lock);
}

/* The game looks at the clipboard (for an invite link) when its window gains focus. */
void halo_ios_post_focus_event(void)
{
    pthread_mutex_lock(&g_event_lock);
    g_focus_event_pending = 1;
    pthread_mutex_unlock(&g_event_lock);
}

static int ios_sdl_poll_event(uint32_t event)
{
    uint8_t *out = gp(event, HALO_SDL_EVENT_SIZE);
    float dx = 0, dy = 0;
    int have_motion = 0, have_focus = 0;

    if (!out)
        return 0;
    pthread_mutex_lock(&g_event_lock);
    if (g_focus_event_pending) { g_focus_event_pending = 0; have_focus = 1; }
    else have_motion = halo_look_take(&g_look, &dx, &dy);
    pthread_mutex_unlock(&g_event_lock);
    uint64_t now = (uint64_t)(loading_seconds() * 1e9);
    if (have_focus) { halo_sdl_event_focus_gained(out, now); return 1; }
    if (have_motion) { halo_sdl_event_mouse_motion(out, dx, dy, now); return 1; }
    return 0;
}

static void ios_active_invite(uint32_t text)
{
    halo_ios_campaign_state(0);
    /* The guest invite is small. Resolve every byte through the arena validator;
     * never let Foundation read an unterminated guest string. */
    char copy[256];
    if (!text) { halo_ios_set_hosted_invite(NULL); return; }
    for (size_t i = 0; i < sizeof(copy); ++i) {
        const char *ch = gp((uint64_t)text + i, 1);
        if (!ch) { halo_ios_set_hosted_invite(NULL); return; }
        copy[i] = *ch;
        if (!copy[i]) { halo_ios_set_hosted_invite(copy); return; }
    }
    halo_ios_set_hosted_invite(NULL);
}

static int ios_copy_guest_string(uint32_t address, char *out, size_t capacity)
{
    if (!out || capacity < 2 || !address) return 0;
    for (size_t index = 0; index < capacity; ++index) {
        const char *ch = gp((uint64_t)address + index, 1);
        if (!ch) { out[0] = 0; return 0; }
        out[index] = *ch;
        if (!out[index]) return 1;
    }
    out[0] = 0;
    return 0;
}

static int ios_host_movie_available(uint32_t path)
{
    char text[512];
    if (!ios_copy_guest_string(path, text, sizeof(text))) return 0;
    int available = HaloMovieAvailablePath(text) ? 1 : 0;
    if (available) say("MOVIE: MP4 fallback available for %s", text);
    return available;
}

static int ios_host_movie_start(uint32_t path, unsigned long flags)
{
    char text[512];
    if (!ios_copy_guest_string(path, text, sizeof(text))) return 0;
    int started = HaloMovieStartPath(text, flags) ? 1 : 0;
    say("MOVIE: guest requested %s -> MP4 %s", text, started ? "started" : "missing/failed");
    return started;
}

static int ios_host_movie_active(void)
{
    return HaloMovieIsActive() ? 1 : 0;
}

static void ios_host_movie_stop(void)
{
    say("MOVIE: stop/complete");
    HaloMovieStop();
}

static int ios_sdl_set_clipboard_text(uint32_t text)
{
    const char *string = gp(text, 1);
    if (string) halo_ios_clipboard_set(string);
    return 1;
}

/* The game's key bindings ask for a key's name and for a name's key (halo_scancodes.h). */
static void ios_sdl_scancode_name(int32_t scancode, uint32_t buffer_va, uint32_t size)
{
    char *buffer = gp(buffer_va, size);
    if (!buffer || !size) return;
    const char *name = hsc_name(scancode);
    size_t length = strlen(name);
    if (length >= size) length = size - 1;
    memcpy(buffer, name, length);
    buffer[length] = 0;
}

static int32_t ios_sdl_scancode_from_name(uint32_t name_va)
{
    char copy[64];
    for (size_t i = 0; i < sizeof(copy); ++i) {
        const char *ch = gp((uint64_t)name_va + i, 1);
        if (!ch) return 0;
        copy[i] = *ch;
        if (!copy[i]) return hsc_from_name(copy);
    }
    return 0;
}

static void ios_sdl_get_clipboard_text(uint32_t buffer_va, uint32_t size)
{
    char *buffer = gp(buffer_va, size);
    if (buffer && size) {
        buffer[0] = 0;
        halo_ios_clipboard_get(buffer, size);
    }
}

static int ios_sdl_show_toast(uint32_t message, int duration, int gravity, int x, int y)
{
    (void)duration; (void)gravity; (void)x; (void)y;
    const char *text = gp(message, 1);
    if (text) halo_ios_toast(text);
    return 1;
}

static int ios_sdl_show_simple_message_box(uint32_t flags, uint32_t title, uint32_t message)
{
    (void)flags; (void)title; (void)message;
    return 1;
}

static _Atomic(uint32_t) g_menu_held;
static _Atomic(uint32_t) g_menu_pending;
static _Atomic(int32_t) g_touch_axis[6];

static int32_t clamp_axis(int32_t value, int axis)
{
    int32_t low = axis >= 4 ? 0 : -32768;
    if (value < low) return low;
    if (value > 32767) return 32767;
    return value;
}

void halo_ios_menu_button(int button, int pressed)
{
    if (button < 0 || button >= 32) return;
    uint32_t bit = UINT32_C(1) << button;
    if (pressed) {
        atomic_fetch_or(&g_menu_held, bit);
        atomic_fetch_or(&g_menu_pending, bit);
    } else atomic_fetch_and(&g_menu_held, ~bit);
}

void halo_ios_pad_axis(int axis, int value)
{
    if (axis < 0 || axis >= 6) return;
    atomic_store(&g_touch_axis[axis], clamp_axis(value, axis));
}

void halo_ios_touch_reset(void)
{
    halo_ios_set_touch_auto_fire(0);
    atomic_store(&g_menu_held, 0);
    atomic_store(&g_menu_pending, 0);
    for (int i = 0; i < 6; i++) atomic_store(&g_touch_axis[i], 0);
}

void halo_ios_menu_reset(void)
{
    halo_ios_touch_reset();
    for(int slot=0;slot<2;slot++){atomic_store(&g_phys_held[slot],0);for(int i=0;i<6;i++)atomic_store(&g_phys_axis[slot][i],0);}
}

void halo_ios_physical_pad_state(uint32_t buttons, const int32_t axes[6])
{
    halo_ios_physical_pad_state_at(0,1,buttons,axes);
}
void halo_ios_physical_pad_state_at(int slot,int connected,uint32_t buttons,const int32_t axes[6]) {
    if(slot<0 || slot>=2)return;
    atomic_store(&g_phys_present[slot],connected!=0);
    atomic_store(&g_phys_held[slot],connected?buttons:0);
    for(int i=0;i<6;i++)atomic_store(&g_phys_axis[slot][i],connected&&axes?clamp_axis(axes[i],i):0);
}

static int ios_sdl_get_gamepads(uint32_t ids, int capacity)
{
    if (capacity < 1) return 0;
    int second=physical_slot(2);
    int count=capacity>=2 && second>=0 && atomic_load(&g_phys_present[second])?2:1;
    uint32_t *out=gp(ids,(size_t)count*sizeof(*out));
    if(!out)return 0;
    out[0]=1; /* Touch always owns logical port zero. */
    if(count==2)out[1]=2;
    return count;
}

static uint32_t ios_sdl_open_gamepad(uint32_t id)
{
    return id==1 || (id==2 && atomic_load(&g_local_coop))?id:0;
}

static int ios_sdl_gamepad_axis(uint32_t gamepad, int axis)
{
    if ((gamepad != 1 && gamepad != 2) || axis < 0 || axis >= 6) return 0;
    /* Touch and a physical controller are merged: the larger deflection wins. */
    int slot=physical_slot(gamepad);
    int32_t touch=gamepad==1?atomic_load(&g_touch_axis[axis]):0;
    int32_t physical=slot>=0?atomic_load(&g_phys_axis[slot][axis]):0;
    int32_t value = abs(touch) >= abs(physical) ? touch : physical;
    return (int)clamp_axis(value, axis);
}

static int ios_sdl_gamepad_button(uint32_t gamepad, int button)
{
    if ((gamepad != 1 && gamepad != 2) || button < 0 || button >= 32) return 0;
    uint32_t bit = UINT32_C(1) << button;
    /* A quick tap is delivered at least once even between slow frames. */
    int slot=physical_slot(gamepad);
    uint32_t pending=gamepad==1?atomic_fetch_and(&g_menu_pending,~bit):0;
    uint32_t touch=gamepad==1?atomic_load(&g_menu_held):0;
    return ((touch|pending|(slot>=0?atomic_load(&g_phys_held[slot]):0))&bit)!=0;
}

static int ios_sdl_gamepad_type(uint32_t gamepad)
{
    return gamepad==1 || gamepad==2?1:0; /* SDL_GAMEPAD_TYPE_STANDARD */
}

static int ios_sdl_rumble(uint32_t gamepad, uint32_t low, uint32_t high, uint32_t milliseconds)
{
    int slot=physical_slot(gamepad);
    if(slot<0)return 0;
    halo_ios_controller_rumble_at(slot,low,high,milliseconds);
    return 1;
}

static uint32_t ios_sdl_open_audio(uint32_t device, uint32_t spec,
                                   uint32_t callback, uint32_t userdata)
{
    (void)device; (void)spec; (void)callback; (void)userdata;
    return 0;
}

static int ios_sdl_audio_data(uint32_t stream, uint32_t data, int length)
{
    (void)stream; (void)data; (void)length;
    return 0;
}

static int ios_sdl_audio_resume(uint32_t stream)
{
    (void)stream;
    return 0;
}

static void ios_gl_get_string(uint32_t name, int index, uint32_t buffer_va, uint32_t size)
{
    char *buffer = gp(buffer_va, size);
    if (buffer)
        halo_ios_gl_get_string(name, index, buffer, size);
}

static int ios_gl_has_extension(uint32_t name_va)
{
    const char *name = gp(name_va, 1);
    return halo_ios_gl_has_extension(name);
}

static uint32_t ios_gl_read_word(uint32_t buffer, uint32_t offset)
{
    return halo_ios_gl_read_buffer_word(buffer, offset);
}

static void ios_gl_buffer_write(uint32_t target, uint32_t offset,
                                uint32_t size, uint32_t data_va)
{
    const void *data = data_va ? gp(data_va, size) : NULL;
    halo_ios_gl_buffer_write(target, offset, size, data);
}

static void ios_gl_fence(uint32_t slot)
{
    halo_ios_gl_fence_frame(slot);
}

static void ios_gl_wait(uint32_t slot)
{
    halo_ios_gl_wait_frame(slot);
}

/*
 * The iOS-specific generated guest GL wrappers call this before native GL
 * imports. It converts a 32-bit guest address into the real 64-bit address
 * inside the aligned guest arena while preserving NULL.
 */
static uint64_t ios_host_guest_pointer(uint32_t guest)
{
    if (!guest)
        return 0;
    return (uint64_t)(uintptr_t)halo_guest_ptr(guest, 1);
}

/* ---------- hostposix file helpers ---------- */

static void split64(uint64_t value, uint32_t *lo, uint32_t *hi)
{
    if (lo) *lo = (uint32_t)value;
    if (hi) *hi = (uint32_t)(value >> 32);
}

static void fill_posix_info(const struct stat *st, struct posix_file_information *out)
{
    memset(out, 0, sizeof(*out));
    if (S_ISDIR(st->st_mode)) out->flags |= 1;
    if (!(st->st_mode & S_IWUSR)) out->flags |= 2;
    split64((uint64_t)st->st_size, &out->size_low, &out->size_high);
#if defined(__APPLE__)
    out->modification_seconds = (uint32_t)st->st_mtimespec.tv_sec;
    out->modification_nanoseconds = (uint32_t)st->st_mtimespec.tv_nsec;
    out->access_seconds = (uint32_t)st->st_atimespec.tv_sec;
    out->access_nanoseconds = (uint32_t)st->st_atimespec.tv_nsec;
    out->creation_seconds = (uint32_t)st->st_birthtimespec.tv_sec;
    out->creation_nanoseconds = (uint32_t)st->st_birthtimespec.tv_nsec;
#endif
}

static int ios_posix_stat(uint32_t path_va, uint32_t info_va)
{
    const char *path = gp(path_va, 1);
    struct posix_file_information *info = gp(info_va, sizeof(*info));
    struct stat st;
    if (!path || !info) { errno = EFAULT; return -1; }
    if (stat(path, &st)) return -1;
    fill_posix_info(&st, info);
    return 0;
}

static int ios_posix_fstat(int fd, uint32_t info_va)
{
    struct posix_file_information *info = gp(info_va, sizeof(*info));
    struct stat st;
    if (!info) { errno = EFAULT; return -1; }
    if (fstat(fd, &st)) return -1;
    fill_posix_info(&st, info);
    return 0;
}

static int ios_posix_set_file_times(uint32_t path_va,
                                    uint32_t access_seconds, uint32_t access_nanoseconds,
                                    uint32_t modification_seconds, uint32_t modification_nanoseconds)
{
    const char *path = gp(path_va, 1);
    if (!path) { errno = EFAULT; return -1; }
    struct timespec times[2];
    times[0].tv_sec = (time_t)access_seconds;
    times[0].tv_nsec = access_seconds ? (long)access_nanoseconds : UTIME_OMIT;
    times[1].tv_sec = (time_t)modification_seconds;
    times[1].tv_nsec = modification_seconds ? (long)modification_nanoseconds : UTIME_OMIT;
    return utimensat(AT_FDCWD, path, times, 0);
}

static int ios_posix_seek(int fd, int32_t low, int32_t high, int whence,
                          uint32_t out_low_va, uint32_t out_high_va)
{
    uint64_t raw = ((uint64_t)(uint32_t)high << 32) | (uint32_t)low;
    off_t r = lseek(fd, (off_t)raw, whence);
    if (r < 0) return -1;
    uint32_t *olo = gp(out_low_va, 4);
    uint32_t *ohi = gp(out_high_va, 4);
    split64((uint64_t)r, olo, ohi);
    return 0;
}

static int ios_posix_truncate(int fd, uint32_t lo, uint32_t hi)
{
    return ftruncate(fd, (off_t)(((uint64_t)hi << 32) | lo));
}

static int ios_posix_make_directory(uint32_t path_va)
{
    const char *path = gp(path_va, 1);
    if (!path) { errno = EFAULT; return -1; }
    if (mkdir(path, 0755) == 0 || errno == EEXIST) return 0;
    return -1;
}

static int ios_posix_set_read_only(uint32_t path_va, int ro)
{
    const char *path = gp(path_va, 1);
    struct stat st;
    if (!path || stat(path,&st)) return -1;
    mode_t mode = st.st_mode & 07777;
    mode = ro ? (mode & ~(mode_t)0222) : (mode | S_IWUSR);
    return chmod(path, mode);
}

static int ios_posix_disk_space(uint32_t path_va,
                                uint32_t free_lo_va,uint32_t free_hi_va,
                                uint32_t total_lo_va,uint32_t total_hi_va)
{
    const char *path = gp(path_va,1);
    if (!path) return -1;
    struct statvfs s;
    if (statvfs(path,&s)) return -1;
    split64((uint64_t)s.f_bavail*s.f_frsize, gp(free_lo_va,4), gp(free_hi_va,4));
    split64((uint64_t)s.f_blocks*s.f_frsize, gp(total_lo_va,4), gp(total_hi_va,4));
    return 0;
}

#define DIR_HANDLES 64
static DIR *g_dirs[DIR_HANDLES];
static pthread_mutex_t g_dir_lock=PTHREAD_MUTEX_INITIALIZER;

static uint32_t ios_posix_directory_open(uint32_t path_va)
{
    const char *path=gp(path_va,1);
    if(!path) return 0;
    DIR *d=opendir(path);
    if(!d) return 0;
    pthread_mutex_lock(&g_dir_lock);
    for(uint32_t i=0;i<DIR_HANDLES;i++) if(!g_dirs[i]) {
        g_dirs[i]=d; pthread_mutex_unlock(&g_dir_lock); return i+1;
    }
    pthread_mutex_unlock(&g_dir_lock); closedir(d); return 0;
}

static int ios_posix_directory_next(uint32_t handle,uint32_t name_va,uint32_t name_size)
{
    if(!handle||handle>DIR_HANDLES) return 0;
    char *name=gp(name_va,name_size);
    if(!name) return 0;
    pthread_mutex_lock(&g_dir_lock);
    DIR *d=g_dirs[handle-1];
    if(!d){pthread_mutex_unlock(&g_dir_lock);return 0;}
    struct dirent *e;
    while((e=readdir(d))) {
        if(!strcmp(e->d_name,".")||!strcmp(e->d_name,"..")) continue;
        if(strlen(e->d_name)+1<=name_size){strlcpy(name,e->d_name,name_size);pthread_mutex_unlock(&g_dir_lock);return 1;}
    }
    pthread_mutex_unlock(&g_dir_lock); return 0;
}

static void ios_posix_directory_close(uint32_t handle)
{
    if(!handle||handle>DIR_HANDLES) return;
    pthread_mutex_lock(&g_dir_lock);
    DIR *d=g_dirs[handle-1]; g_dirs[handle-1]=NULL;
    pthread_mutex_unlock(&g_dir_lock);
    if(d) closedir(d);
}

static int ios_posix_find_case(uint32_t dir_va,uint32_t name_va,uint32_t result_va,uint32_t result_size)
{
    const char *dir=gp(dir_va,1), *name=gp(name_va,1);
    char *result=gp(result_va,result_size);
    if(!dir||!name||!result) return 0;
    DIR *d=opendir(*dir?dir:"."); if(!d) return 0;
    struct dirent *e; int found=0;
    while((e=readdir(d))) if(!strcasecmp(e->d_name,name)&&strlen(e->d_name)+1<=result_size){
        strlcpy(result,e->d_name,result_size); found=1; break;
    }
    closedir(d); return found;
}

static int ios_posix_command_line(int index,uint32_t buffer_va,uint32_t size)
{
    if(index!=0) return 0;
    char *b=gp(buffer_va,size); if(!b||!size) return 0;
    strlcpy(b,"halo",size); return 1;
}

static uint32_t ios_posix_process_id(void){return (uint32_t)getpid();}
static int ios_posix_register_url(uint32_t s,uint32_t d){(void)s;(void)d;return 0;}
static void *ios_net_resolver(uint32_t va, size_t size) { return gp(va, size); }
static void ios_net_log(const char *line)
{
    say("%s", line);
    if (strstr(line, "LOCAL NETWORK"))
        halo_ios_toast("Local Network access is off for Halo CE - turn it on in iOS Settings");
}
static int ios_posix_socket_last_error(void){return halo_net_last_error();}
static int ios_posix_minus_one(void){return -1;}
static int ios_posix_zero_int(void){return 0;}
/* UPnP needs a router library the iOS build does not carry; internet play falls back to STUN. */
static int ios_posix_upnp_forward(uint32_t port, uint32_t preferred_port, uint32_t external_address, uint32_t external_port, uint32_t error_va, int32_t error_size)
{
    (void)port; (void)preferred_port; (void)external_address; (void)external_port;
    char *error = gp(error_va, error_size > 0 ? (size_t)error_size : 1);
    if (error && error_size > 0) snprintf(error, (size_t)error_size, "UPnP is not available on iOS");
    return 0;
}
static uint32_t ios_posix_zero_u32(void){return 0;}
static void ios_posix_random(uint32_t buffer_va,uint32_t size){void*b=gp(buffer_va,size);if(b)arc4random_buf(b,size);}

static void missing_import(void)
{
    g_missing_lr = (uint64_t)(uintptr_t)__builtin_return_address(0);
    halo_guest_exec_abort(HALO_GUEST_ABORT_MISSING_IMPORT);
}

/* ---------- secondary guest threads ---------- */

struct guest_thread_start
{
    uint32_t handle;
    uint32_t stack_va;
    uint32_t stack_size;
};

static void *guest_secondary_thread(void *opaque)
{
    struct guest_thread_start start = *(struct guest_thread_start *)opaque;
    free(opaque);

    sigjmp_buf *env = halo_guest_exec_guard_buffer();
    int reason = sigsetjmp(*env, 1);
    if (reason == 0)
    {
        halo_guest_exec_guard_set_active(1);
        void (*entry)(uint32_t) =
            (void (*)(uint32_t))halo_guest_ptr(g_header->thread_start, 1);
        entry(start.handle);
        halo_guest_exec_guard_set_active(0);
    }
    else
    {
        halo_guest_exec_guard_set_active(0);
        say("secondary guest thread aborted, reason=%d", reason);
    }
    return NULL;
}

static int ios_host_thread_create(uint32_t handle, uint32_t stack_size)
{
    if (stack_size < 1024*1024) stack_size=1024*1024;
    stack_size=(stack_size+0x3FFF)&~0x3FFFu;

    pthread_mutex_lock(&g_alloc_lock);
    if(g_thread_stack_next < stack_size + UINT32_C(0xD2000000)){
        pthread_mutex_unlock(&g_alloc_lock); return EAGAIN;
    }
    g_thread_stack_next -= stack_size;
    uint32_t va=g_thread_stack_next;
    pthread_mutex_unlock(&g_alloc_lock);

    if(!halo_guest_commit(va,stack_size)) return EAGAIN;

    struct guest_thread_start *s=calloc(1,sizeof(*s));
    if(!s) return ENOMEM;
    s->handle=handle;s->stack_va=va;s->stack_size=stack_size;

    pthread_attr_t attr; pthread_t thread;
    pthread_attr_init(&attr);
    pthread_attr_setstack(&attr,halo_guest_ptr(va,stack_size),stack_size);
    int r=pthread_create(&thread,&attr,guest_secondary_thread,s);
    pthread_attr_destroy(&attr);
    if(r){free(s);return r;}
    pthread_detach(thread);
    return 0;
}

/* ---------- import resolver ---------- */

static void *resolve_host_import(const char *name)
{
#define MAP(n,f) if(!strcmp(name,n)) return (void *)(f)
    MAP("host_syscall", ios_host_syscall);
    MAP("host_log", ios_host_log);
    MAP("host_abort", ios_host_abort);
    MAP("host_exit", ios_host_exit);
    MAP("host_errno", ios_host_errno);
    MAP("host_get_tp", ios_host_get_tp);
    MAP("host_set_tp", ios_host_set_tp);
    MAP("host_thread_create", ios_host_thread_create);
    MAP("host_cache_inflate_init", ios_cache_inflate_init);
    MAP("host_texture_decode_dxt", ios_texture_decode_dxt);
    MAP("host_texture_hash", ios_texture_hash);
    MAP("host_vertex_color_swizzle", ios_vertex_color_swizzle);
    MAP("host_vertex_attribute_pointer", ios_vertex_attribute_pointer);
    MAP("host_vertex_attribute_value", ios_vertex_attribute_value);
    MAP("host_vertex_state_invalidate", ios_vertex_state_invalidate);
    MAP("host_render_scan", ios_render_scan);
    MAP("host_uniform_apply", ios_uniform_apply);
    MAP("host_scene_scan", ios_scene_scan);
    MAP("host_scene_datum", ios_scene_datum);
    MAP("host_scene_filter_objects", ios_scene_filter_objects);
    MAP("host_memory_copy", ios_memory_copy);
    MAP("host_memory_fill", ios_memory_fill);
    MAP("host_loading_stage", ios_loading_stage);
    MAP("host_crc_checksum", ios_crc_checksum);
    MAP("host_texture_decode_texels", ios_texture_decode_texels);
    MAP("host_frame_phase", ios_frame_phase);
    MAP("host_frame_counts", ios_frame_counts);
    MAP("host_silent_advance", ios_silent_advance);
    MAP("host_audio_open", ios_audio_open);
    MAP("host_audio_fill", ios_audio_fill);
    MAP("host_audio_push", ios_audio_push);
    MAP("host_movie_available", ios_host_movie_available);
    MAP("host_movie_start", ios_host_movie_start);
    MAP("host_movie_active", ios_host_movie_active);
    MAP("host_movie_stop", ios_host_movie_stop);
    MAP("host_cheat_flags", ios_cheat_flags);
    MAP("host_viewmodel_flags", ios_viewmodel_flags);
    MAP("host_touch_auto_fire", ios_touch_auto_fire);
    MAP("host_active_invite", ios_active_invite);
    MAP("host_campaign_options", ios_campaign_options);
    MAP("host_settings_value", ios_settings_value);
    MAP("host_audio_class_gain",ios_audio_class_gain);
    MAP("host_hud_options",ios_hud_options);
    MAP("host_network_status",ios_network_status);
    MAP("host_network_details",ios_network_details);
    MAP("host_campaign_state", ios_campaign_state);
    MAP("host_debug_state", ios_debug_state);
    MAP("host_cache_inflate", ios_cache_inflate_step);
    MAP("host_cache_inflate_end", ios_cache_inflate_end);
    MAP("host_guest_pointer", ios_host_guest_pointer);

    MAP("host_geometry_pages", ios_geometry_pages);
    MAP("host_memory_watch_initialize", ios_memory_watch_initialize);
    MAP("host_memory_watch_protect", ios_memory_watch_protect);
    MAP("host_memory_watch_generation", ios_memory_watch_generation);
    MAP("host_memory_watch_serial", ios_memory_watch_serial);
    MAP("host_memory_watch_prepare_write", ios_memory_watch_prepare_write);
    MAP("host_memory_watch_forget", ios_memory_watch_forget);

    MAP("host_sdl_init", ios_sdl_init);
    MAP("host_sdl_set_hint", ios_sdl_set_hint);
    MAP("host_sdl_get_error", ios_sdl_get_error);
    MAP("host_sdl_ticks", ios_sdl_ticks);
    MAP("host_sdl_thread_id", ios_sdl_thread_id);
    MAP("host_sdl_create_window", ios_sdl_create_window);
    MAP("host_sdl_window_size_in_pixels", ios_sdl_window_size);
    MAP("host_sdl_set_relative_mouse", ios_sdl_set_relative_mouse);
    MAP("host_sdl_gl_set_attribute", ios_sdl_gl_set_attribute);
    MAP("host_sdl_gl_create_context", ios_sdl_gl_create_context);
    MAP("host_sdl_gl_make_current", ios_sdl_gl_make_current);
    MAP("host_sdl_gl_set_swap_interval", ios_sdl_gl_set_swap_interval);
    MAP("host_sdl_gl_swap_window", ios_sdl_gl_swap_window);
    MAP("host_sdl_poll_event", ios_sdl_poll_event);
    MAP("host_sdl_set_clipboard_text", ios_sdl_set_clipboard_text);
    MAP("host_sdl_get_clipboard_text", ios_sdl_get_clipboard_text);
    MAP("host_sdl_scancode_name", ios_sdl_scancode_name);
    MAP("host_sdl_scancode_from_name", ios_sdl_scancode_from_name);
    MAP("host_sdl_show_toast", ios_sdl_show_toast);
    MAP("host_sdl_show_simple_message_box", ios_sdl_show_simple_message_box);
    MAP("host_sdl_get_gamepads", ios_sdl_get_gamepads);
    MAP("host_sdl_open_gamepad", ios_sdl_open_gamepad);
    MAP("host_sdl_gamepad_from_id", ios_sdl_open_gamepad);
    MAP("host_sdl_gamepad_axis", ios_sdl_gamepad_axis);
    MAP("host_sdl_gamepad_button", ios_sdl_gamepad_button);
    MAP("host_sdl_gamepad_type", ios_sdl_gamepad_type);
    MAP("host_sdl_rumble_gamepad", ios_sdl_rumble);
    MAP("host_sdl_open_audio_stream", ios_sdl_open_audio);
    MAP("host_sdl_put_audio_stream_data", ios_sdl_audio_data);
    MAP("host_sdl_resume_audio_stream_device", ios_sdl_audio_resume);

    MAP("host_gl_get_string", ios_gl_get_string);
    MAP("host_gl_has_extension", ios_gl_has_extension);
    MAP("host_gl_read_buffer_word", ios_gl_read_word);
    MAP("host_gl_buffer_write", ios_gl_buffer_write);
    MAP("host_gl_fence_frame", ios_gl_fence);
    MAP("host_gl_wait_frame", ios_gl_wait);
    MAP("host_android_path", ios_host_android_path);

    if(!strncmp(name,"hostgl_",7))
    {
        void *gl = halo_ios_gl_resolve_import(name);
        return gl ? gl : (void *)missing_import;
    }

    if(!strncmp(name,"hostposix_",10))
    {
        const char *n=name+10;
#define PMAP(s,f) if(!strcmp(n,s)) return (void *)(f)
        PMAP("stat", ios_posix_stat);
        PMAP("fstat", ios_posix_fstat);
        PMAP("set_file_times", ios_posix_set_file_times);
        PMAP("seek", ios_posix_seek);
        PMAP("truncate", ios_posix_truncate);
        PMAP("make_directory", ios_posix_make_directory);
        PMAP("set_read_only", ios_posix_set_read_only);
        PMAP("disk_space", ios_posix_disk_space);
        PMAP("directory_open", ios_posix_directory_open);
        PMAP("directory_next", ios_posix_directory_next);
        PMAP("directory_close", ios_posix_directory_close);
        PMAP("find_entry_case_insensitive", ios_posix_find_case);
        PMAP("command_line_argument", ios_posix_command_line);
        PMAP("process_id", ios_posix_process_id);
        PMAP("register_url_scheme", ios_posix_register_url);
        PMAP("socket_last_error", ios_posix_socket_last_error);
        PMAP("local_ipv4_address", halo_net_local_ipv4);
        PMAP("resolve_ipv4", halo_net_resolve_ipv4);
        PMAP("socket", halo_net_socket);
        PMAP("socket_close", halo_net_close);
        PMAP("socket_bind", halo_net_bind);
        PMAP("socket_connect", halo_net_connect);
        PMAP("socket_listen", halo_net_listen);
        PMAP("socket_accept", halo_net_accept);
        PMAP("socket_send", halo_net_send);
        PMAP("socket_sendto", halo_net_sendto);
        PMAP("socket_recv", halo_net_recv);
        PMAP("socket_recvfrom", halo_net_recvfrom);
        PMAP("socket_shutdown", halo_net_shutdown);
        PMAP("socket_set_nonblocking", halo_net_set_nonblocking);
        PMAP("socket_bytes_available", halo_net_bytes_available);
        PMAP("socket_set_nodelay", halo_net_set_nodelay);
        PMAP("socket_setsockopt", halo_net_setsockopt);
        PMAP("socket_getsockopt", halo_net_getsockopt);
        PMAP("socket_getsockname", halo_net_getsockname);
        PMAP("socket_getpeername", halo_net_getpeername);
        PMAP("socket_select", halo_net_select);
        PMAP("upnp_forward_udp", ios_posix_upnp_forward);
        PMAP("user_secret", ios_posix_zero_int); /* none, as on Android: the game then makes its own */
        PMAP("upnp_stop_forwarding_udp", ios_posix_zero_int);
        PMAP("discord_connect", ios_posix_minus_one);
        PMAP("discord_write", ios_posix_minus_one);
        PMAP("discord_read", ios_posix_minus_one);
        PMAP("discord_close", ios_posix_zero_int);
        PMAP("random_bytes", ios_posix_random);
#undef PMAP
        if(!strncmp(n,"socket",6) || !strncmp(n,"discord",7) || !strncmp(n,"upnp",4))
            return (void *)ios_posix_minus_one;
    }
#undef MAP
    return (void *)missing_import;
}

/* ---------- ELF image ---------- */

static int load_guest_image(NSString *path)
{
    NSError *error=nil;
    g_elf=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error];
    if(!g_elf){
        say("FULL GUEST: cannot read halo_guest.elf: %s",
            error.localizedDescription.UTF8String ?: "unknown");
        return 0;
    }
    if(g_elf.length < sizeof(Elf64_Ehdr)){ say("FULL GUEST: halo_guest.elf is too small (%lu bytes).",(unsigned long)g_elf.length); return 0; }

    g_ehdr=(const Elf64_Ehdr *)g_elf.bytes;
    if(g_ehdr->e_ident[0]!=0x7F || g_ehdr->e_ident[1]!='E' ||
       g_ehdr->e_ident[2]!='L' || g_ehdr->e_ident[3]!='F' ||
       g_ehdr->e_ident[4]!=2 || g_ehdr->e_machine!=183 ||
       g_ehdr->e_phentsize!=sizeof(Elf64_Phdr))
    {
        say("FULL GUEST: bundled image is not the expected AArch64 ELF.");
        return 0;
    }

    if(g_ehdr->e_phoff + (uint64_t)g_ehdr->e_phnum*sizeof(Elf64_Phdr) > g_elf.length){ say("FULL GUEST: the ELF program headers run past the end of the file."); return 0; }

    const uint8_t *file=g_elf.bytes;
    const Elf64_Phdr *ph=(const Elf64_Phdr *)(file+g_ehdr->e_phoff);

    halo_guest_exec_bridge_reset_ranges();

    /* The linker script (port/android/guest/guest.ld) aligns .data to 64 KiB, so a gap of whole 16 KiB pages can
       sit between the read-only and writable segments. Those pages belong to no segment; if they stay unmapped,
       anything that sweeps the image from its first byte to its last (the instruction-cache maintenance below did)
       takes a bus error on the first gap page. The image span is therefore mapped as one range first. */
    uint32_t span_low=UINT32_MAX, span_high=0;
    unsigned segments=0;
    for(uint16_t i=0;i<g_ehdr->e_phnum;i++)
    {
        if(ph[i].p_type!=PT_LOAD) continue;
        if(ph[i].p_vaddr>=FOUR_GB || ph[i].p_vaddr+ph[i].p_memsz>FOUR_GB ||
           ph[i].p_offset+ph[i].p_filesz>g_elf.length || ph[i].p_filesz>ph[i].p_memsz)
        {
            say("FULL GUEST: segment %u of halo_guest.elf is outside the 4 GiB guest space or the file (va=0x%llx mem=0x%llx file=0x%llx).",
                (unsigned)i,(unsigned long long)ph[i].p_vaddr,(unsigned long long)ph[i].p_memsz,(unsigned long long)ph[i].p_filesz);
            return 0;
        }
        uint32_t va=(uint32_t)ph[i].p_vaddr, mem=(uint32_t)ph[i].p_memsz;
        if(va<span_low) span_low=va;
        if((uint64_t)va+mem>span_high) span_high=va+mem;
        say("guest image: segment %u at 0x%08x, 0x%x bytes in memory, 0x%llx from the file, %c%c%c",
            segments++,va,mem,(unsigned long long)ph[i].p_filesz,
            (ph[i].p_flags&PF_R)?'r':'-',(ph[i].p_flags&PF_W)?'w':'-',(ph[i].p_flags&PF_X)?'x':'-');
    }
    if(!segments || span_high<=span_low){ say("FULL GUEST: halo_guest.elf has nothing to load."); return 0; }
    halo_crash_phase("guest image: mapping the image span");
    if(!halo_guest_commit(span_low,span_high-span_low))
    {
#if defined(HALO_MOD_TEST) || defined(HALO_NON_JAILBREAK)
        int memory_error=errno;
        say("Startup memory detail: RW commit errno=%d (%s)",memory_error,strerror(memory_error));
        say("STARTUP BLOCKED: GUEST IMAGE COMMIT");
#endif
        say("FULL GUEST: could not map the guest image (0x%08x..0x%08x, %u MiB).",span_low,span_high,(span_high-span_low)>>20);
        return 0;
    }
    uint32_t low=UINT32_MAX, high=0;
    for(uint16_t i=0;i<g_ehdr->e_phnum;i++)
    {
        if(ph[i].p_type!=PT_LOAD) continue;

        uint32_t va=(uint32_t)ph[i].p_vaddr;
        uint32_t mem=(uint32_t)ph[i].p_memsz;
        void *dst=halo_guest_ptr(va,mem);
        if(!dst){ say("FULL GUEST: segment %u has no host address.",(unsigned)i); return 0; }
        halo_crash_phase("guest image: copying segments");
        memset(dst,0,mem);
        memcpy(dst,file+ph[i].p_offset,(size_t)ph[i].p_filesz);

        if(va<low)low=va;
        if((uint64_t)va+mem>high)high=va+mem;
    }

    /* Only the executable segments need it, each over its own bytes. */
    halo_crash_phase("guest image: instruction cache");
    for(uint16_t i=0;i<g_ehdr->e_phnum;i++)
    {
        if(ph[i].p_type!=PT_LOAD || !(ph[i].p_flags&PF_X)) continue;
        void *code=halo_guest_ptr((uint32_t)ph[i].p_vaddr,(size_t)ph[i].p_memsz);
        if(code && ph[i].p_memsz) sys_icache_invalidate(code,(size_t)ph[i].p_memsz);
    }

    g_guest_writable_start = UINT32_MAX;

    for(uint16_t i=0;i<g_ehdr->e_phnum;i++)
    {
        if(ph[i].p_type!=PT_LOAD) continue;
        uint32_t va=(uint32_t)ph[i].p_vaddr;
        uint32_t mem=(uint32_t)ph[i].p_memsz;

        if(ph[i].p_flags&PF_X)
            halo_guest_exec_bridge_register_code(va,va+mem);
        if((ph[i].p_flags&PF_W) && va < g_guest_writable_start)
            g_guest_writable_start = va;
    }

    /*
     * iPhones use 16 KiB VM pages. The ELF's text/rodata boundaries can fall
     * inside one of those pages, so protecting PT_LOAD segments one by one can
     * accidentally remove execute permission from the tail of .text.
     * Apply the union of all overlapping segment permissions per host page.
     */
    const uint64_t page_size = halo_guest_page_size();
    const uint64_t page_mask = page_size - 1;
    uint64_t first_page = ((uint64_t)low) & ~page_mask;
    uint64_t last_page = (((uint64_t)high + page_mask) & ~page_mask);

    for(uint64_t page=first_page; page<last_page; page+=page_size)
    {
        int prot=0;
        uint64_t page_end=page+page_size;

        for(uint16_t i=0;i<g_ehdr->e_phnum;i++)
        {
            if(ph[i].p_type!=PT_LOAD) continue;
            uint64_t seg_start=ph[i].p_vaddr;
            uint64_t seg_end=seg_start+ph[i].p_memsz;
            if(page>=seg_end || page_end<=seg_start)
                continue;

            if(ph[i].p_flags&PF_R)prot|=PROT_READ;
            if(ph[i].p_flags&PF_W)prot|=PROT_WRITE;
            if(ph[i].p_flags&PF_X)prot|=PROT_EXEC;
        }

        if(prot && !halo_guest_protect((uint32_t)page,(size_t)page_size,prot))
        {
            int error=errno;
            say("FULL GUEST: could not set memory protection at 0x%08x, flags=0x%x, errno=%d (%s).",(uint32_t)page,prot,error,strerror(error));
            if(prot&PROT_EXEC) {
                say("Guest execution authorization may be missing; memory-limit capabilities alone do not authorize executable code.");
                say("STARTUP BLOCKED: EXECUTABLE MEMORY");
            }
            return 0;
        }
    }
    halo_crash_phase("guest image: protected");
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
    halo_crash_phase("nonjb 405 real guest image protected");
    say("NON-JB EXECUTION TRACE: [405] real halo_guest.elf executable pages are mapped and RX-protected");
#endif

    g_header=(struct halo_guest_header *)halo_guest_ptr(HALO_GUEST_IMAGE_BASE,sizeof(*g_header));
    if(!g_header || g_header->magic!=HALO_GUEST_MAGIC || g_header->abi_version!=HALO_GUEST_ABI_VERSION){
        say("FULL GUEST: image header mismatch.");
        return 0;
    }

    uint32_t *countp=gp(g_header->import_count,4);
    uint64_t *table=gp(g_header->import_table,(*countp)*sizeof(uint64_t));
    const char *name=gp(g_header->import_names,1);
    if(!countp||!table||!name){ say("FULL GUEST: the import table is outside the image."); return 0; }
    halo_crash_phase("guest image: resolving imports");

    uint32_t count=*countp;
    uint32_t resolved=0, fallback=0;
    for(uint32_t i=0;i<count;i++)
    {
        void *fn=resolve_host_import(name);
        if(fn==(void *)missing_import) fallback++; else resolved++;
        table[i]=(uint64_t)(uintptr_t)fn;
        name+=strlen(name)+1;
    }

    g_main_thread_va = symbol_value_named("main_thread");

    say("FULL GUEST IMAGE: 0x%08x-0x%08x, start=0x%08x",
        low,high,g_header->start);
    say("GUEST TLS: writable_start=0x%08x main_thread=0x%08x",
        g_guest_writable_start, g_main_thread_va);
    say("HOST IMPORTS: %u resolved, %u guarded fallback",
        resolved,fallback);
    return 1;
}

/* ---------- boot environment and main guest thread ---------- */

struct main_guest_context
{
    uint32_t boot_va;
};

/* ---------- safe start: what is switched off after a start that did not finish ---------- */
static int g_safe_level;
static char *g_launch_note, *g_launch_crash;
static NSString *const kSafeLevelKey = @"HaloSafeLevel";

void halo_ios_set_safe_level(int level) { g_safe_level = level; }
int halo_ios_safe_level(void) { return g_safe_level; }

void halo_ios_set_launch_notes(const char *note, const char *crash)
{
    free(g_launch_note); free(g_launch_crash);
    g_launch_note = note && *note ? strdup(note) : NULL;
    g_launch_crash = crash && *crash ? strdup(crash) : NULL;
}

/* "Leave safe mode": the next start is a normal one. */
void halo_ios_leave_safe_mode(void)
{
    [[NSUserDefaults standardUserDefaults] setInteger:HALO_SAFE_NORMAL forKey:kSafeLevelKey];
    halo_crash_phase(HALO_PHASE_EXITED);
    g_safe_level = HALO_SAFE_NORMAL;
}

static NSString *HaloDataFolder(void)
{
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Halo"];
}

/* The first moment the guest has presented a frame, and the moment it has run long enough to count as a good start. */
static void note_run_progress(uint64_t presented, double now)
{
    static double first_frame_time;
    static int stage;

    if (stage == 0 && presented > 0) {
        stage = 1; first_frame_time = now;
        halo_crash_phase("first frame presented");
    } else if (stage == 1 && now - first_frame_time >= 15.0) {
        stage = 2;
        halo_crash_phase(HALO_PHASE_RUNNING_OK);
        halo_crash_clear(HaloDataFolder().fileSystemRepresentation);
        [[NSUserDefaults standardUserDefaults] setInteger:HALO_SAFE_NORMAL forKey:kSafeLevelKey];
        say("this start ran for 15 seconds after its first frame: it counts as a good start");
    }
}

/* Back from the background: the phase file says which state the app is really in. */
void halo_ios_phase_foreground(void)
{
    uint64_t presented = atomic_load_explicit(&g_presented_frames, memory_order_relaxed);
    if (presented > 0 && g_guest_finished == 0) halo_crash_phase(HALO_PHASE_RUNNING_OK);
}

static uint32_t build_boot(void)
{
    const uint32_t base=UINT32_C(0xE0000000);
    const uint32_t size=0x20000;
    if(!halo_guest_commit(base,size)) return 0;

    uint8_t *m=halo_guest_ptr(base,size);
    memset(m,0,size);

    struct halo_guest_boot *boot=(struct halo_guest_boot *)m;
    uint32_t argv_va=base+sizeof(*boot);
    uint32_t env_va=argv_va+8;
    uint32_t strings_va=env_va+64*4;
    uint32_t *argv=halo_guest_ptr(argv_va,8);
    uint32_t *env=halo_guest_ptr(env_va,64*4);
    char *strings=halo_guest_ptr(strings_va,size-(strings_va-base));

    uint32_t cursor=strings_va;
#define PUT_STRING(value, outva) do { \
    size_t _n=strlen(value)+1; \
    strcpy((char *)halo_guest_ptr(cursor,_n),value); \
    outva=cursor; cursor+=(uint32_t)_n; \
} while(0)

    uint32_t halo_va;
    PUT_STRING("halo",halo_va);
    argv[0]=halo_va; argv[1]=0;

    char data[1024], save[1024];
    snprintf(data,sizeof(data),"HALO_DATA_ROOT=%s",g_data_root.fileSystemRepresentation);
    snprintf(save,sizeof(save),"HALO_SAVE_ROOT=%s",g_save_root.fileSystemRepresentation);

    /* Sound and internet play are on (they used to be switched off here, which is why neither worked).
       Smooth 60 FPS is a setting; it is read once at launch. UPnP is not available on iOS. */
    HsSettings launch_settings=[[HaloSettingsStore shared] snapshot];
    char interpolation[40];
    snprintf(interpolation,sizeof(interpolation),"HALO_INTERPOLATION=%s",launch_settings.fps_mode!=0?"true":"false");
    char hires_hud[32], hires_text[32];
    snprintf(hires_hud,sizeof(hires_hud),"HALO_HIGH_RES_HUD=%s",launch_settings.hires_hud?"true":"false");
    snprintf(hires_text,sizeof(hires_text),"HALO_HIGH_RES_TEXT=%s",launch_settings.hires_text?"true":"false");
    char menus[32];
    snprintf(menus,sizeof(menus),"HALO_MENUS=%s",launch_settings.menu_style?"xbox":"pc");
    /* Capture screen shape on the UI thread; the guest boot runs on its own thread. */
    __block CGSize display_size;
    dispatch_sync(dispatch_get_main_queue(), ^{ display_size = UIScreen.mainScreen.bounds.size; });
    int picture_width = hs_display_width(launch_settings.display_mode, display_size.width, display_size.height);
    char picture[48], detail[48];
    snprintf(picture,sizeof(picture),"HALO_DISPLAY_WIDTH=%d",g_safe_level?640:picture_width);
    snprintf(detail,sizeof(detail),"HALO_RENDER_SCALE=%.2f",g_safe_level?1.0:hs_render_scale(launch_settings.render_quality));
    const char *values[20]; unsigned count=0;
    values[count++]=data;
    values[count++]=save;
    say("picture: logical=%dx480, target scale=%.2f; touch aiming options are opt-in", g_safe_level?640:picture_width, g_safe_level?1.0:hs_render_scale(launch_settings.render_quality));
    values[count++]=picture;
    values[count++]=detail;
    values[count++]="HALO_GPU_STATS=1";
    values[count++]=g_safe_level?"HALO_NET_ONLINE=false":"HALO_NET_ONLINE=true";
    values[count++]="HALO_NET_ALLOW_UPNP=false";
    values[count++]="HALO_UPDATE_AUTO=false";
    values[count++]=g_safe_level?"HALO_INTERPOLATION=false":interpolation;
    values[count++]=g_safe_level?"HALO_HIGH_RES_HUD=false":hires_hud;
    values[count++]=g_safe_level?"HALO_HIGH_RES_TEXT=false":hires_text;
    values[count++]=g_safe_level?"HALO_MENUS=xbox":menus;   /* a safe start uses the menus known to work */
    if(g_safe_level) values[count++]="HALO_NO_AUDIO=1";
    values[count++]="HOME=/tmp";
    values[count++]="TZ=UTC0";
    values[count]=NULL;
    unsigned ec=0;
    for(;values[ec]&&ec<63;ec++){
        uint32_t va;PUT_STRING(values[ec],va);env[ec]=va;
    }
    env[ec]=0;

    boot->argc=1;
    boot->argv=argv_va;
    boot->environment=env_va;
    boot->page_size=(uint32_t)halo_guest_page_size();
#undef PUT_STRING
    return base;
}


/* ---------- sampling profiler for the thread that runs the game ----------
 * Every 2 ms a helper thread suspends the guest main thread, reads its program counter and
 * resumes it. Each 10-second heartbeat then reports where the time went: guest functions by
 * name, and the iOS graphics driver and system libraries by module. The helper touches only
 * static memory while the target is suspended, so it cannot deadlock on a lock the target holds. */
#define PROFILE_SAMPLES 16384
static mach_port_t g_profile_target;
static _Atomic int g_profiler_enabled = 1;
void halo_ios_set_profiler_enabled(int enabled) { atomic_store_explicit(&g_profiler_enabled, enabled ? 1 : 0, memory_order_relaxed); }
static pthread_mutex_t g_profile_lock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t g_profile_pc[PROFILE_SAMPLES];
static uint32_t g_profile_count;

static void *profiler_thread(void *unused)
{
    (void)unused;
    pthread_setname_np("halo-profiler");
    for (;;)
    {
        usleep(2000);
        mach_port_t target = g_profile_target;
        if (!target || !atomic_load_explicit(&g_profiler_enabled, memory_order_relaxed)) continue;
        pthread_mutex_lock(&g_profile_lock);
        if (g_profile_count < PROFILE_SAMPLES && thread_suspend(target) == KERN_SUCCESS)
        {
            arm_thread_state64_t state;
            mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
            kern_return_t result = thread_get_state(target, ARM_THREAD_STATE64, (thread_state_t)&state, &count);
            thread_resume(target);
            if (result == KERN_SUCCESS)
                g_profile_pc[g_profile_count++] = (uint64_t)arm_thread_state64_get_pc(state);
        }
        pthread_mutex_unlock(&g_profile_lock);
    }
    return NULL;
}

static void profiler_start_for_current_thread(void)
{
    static dispatch_once_t once;
    g_profile_target = mach_thread_self();
    dispatch_once(&once, ^{
        pthread_t thread;
        if (pthread_create(&thread, NULL, profiler_thread, NULL) == 0) pthread_detach(thread);
    });
}

static int compare_u64(const void *a, const void *b)
{
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return x < y ? -1 : (x > y);
}

struct profile_row { char name[120]; uint32_t samples; };

static void profile_add(struct profile_row *rows, unsigned *count, unsigned capacity, const char *name, uint32_t samples)
{
    for (unsigned i = 0; i < *count; i++)
        if (!strcmp(rows[i].name, name)) { rows[i].samples += samples; return; }
    if (*count < capacity) { snprintf(rows[*count].name, sizeof(rows[0].name), "%s", name); rows[(*count)++].samples = samples; }
}

static int compare_rows(const void *a, const void *b)
{
    uint32_t x = ((const struct profile_row *)a)->samples, y = ((const struct profile_row *)b)->samples;
    return x < y ? 1 : (x > y ? -1 : 0);
}

static void report_profile(void)
{
    report_memory();    /* every heartbeat, with or without profile samples */
    static uint64_t pcs[PROFILE_SAMPLES];
    static struct profile_row guest[512], host[512], modules[64];
    unsigned guest_count = 0, host_count = 0, module_count = 0;
    uint32_t total, guest_samples = 0;

    pthread_mutex_lock(&g_profile_lock);
    total = g_profile_count;
    memcpy(pcs, g_profile_pc, (size_t)total * sizeof(pcs[0]));
    g_profile_count = 0;
    pthread_mutex_unlock(&g_profile_lock);
    if (total < 20) return;

    qsort(pcs, total, sizeof(pcs[0]), compare_u64);
    uint64_t base = (uint64_t)(uintptr_t)halo_guest_base_address();
    for (uint32_t i = 0; i < total; )
    {
        uint32_t j = i;
        while (j < total && pcs[j] == pcs[i]) j++;
        uint32_t samples = j - i;
        uint64_t pc = pcs[i];
        char name[120];

        if (base && pc >= base && pc - base < FOUR_GB)
        {
            uint32_t symbol_va = 0;
            const char *symbol = symbol_name_nearest((uint32_t)(pc - base), &symbol_va);
            snprintf(name, sizeof(name), "%s", symbol ? symbol : "unknown guest code");
            profile_add(guest, &guest_count, 512, name, samples);
            guest_samples += samples;
        }
        else
        {
            Dl_info info;
            const char *module = "unknown";
            const char *symbol = NULL;
            if (dladdr((void *)(uintptr_t)pc, &info))
            {
                if (info.dli_fname) { const char *slash = strrchr(info.dli_fname, '/'); module = slash ? slash + 1 : info.dli_fname; }
                symbol = info.dli_sname;
            }
            snprintf(name, sizeof(name), "%s  %s", module, symbol ? symbol : "?");
            profile_add(host, &host_count, 512, name, samples);
            profile_add(modules, &module_count, 64, module, samples);
        }
        i = j;
    }
    qsort(guest, guest_count, sizeof(guest[0]), compare_rows);
    qsort(host, host_count, sizeof(host[0]), compare_rows);
    qsort(modules, module_count, sizeof(modules[0]), compare_rows);

    say("profile: %u samples of the game thread (every 2 ms): %.0f%% in game code, %.0f%% in iOS libraries",
        total, 100.0 * guest_samples / total, 100.0 * (total - guest_samples) / total);
    for (unsigned i = 0; i < module_count && i < 6; i++)
        say("  profile library %5.1f%%  %s", 100.0 * modules[i].samples / total, modules[i].name);
    for (unsigned i = 0; i < guest_count && i < 12; i++)
        say("  profile game    %5.1f%%  %s", 100.0 * guest[i].samples / total, guest[i].name);
    for (unsigned i = 0; i < host_count && i < 10; i++)
        say("  profile host    %5.1f%%  %s", 100.0 * host[i].samples / total, host[i].name);
}

#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
/*
 * Execute two known AArch64 instructions from a temporary page inside the real
 * guest arena.  The page uses the same RW commit -> instruction-cache flush ->
 * RX protection path as halo_guest.elf.  It is diagnostic only and is released
 * before the real guest starts.  If iOS terminates the process on instruction
 * fetch, launch-phase.txt remains at step 403 for the next launch to report.
 */
static int nonjb_guest_arena_exec_canary(void)
{
    enum { CANARY_GUEST_VA = 0x0FFF0000u, CANARY_MAGIC = 0x4841u };
    const uint32_t code[] = {
        0x52890820u, /* movz w0, #0x4841 */
        0xD65F03C0u  /* ret */
    };
    size_t page = halo_guest_page_size();
    void *host;
    uint32_t (*entry)(void);
    uint32_t result;

    halo_crash_phase("nonjb 402 exec canary mapping");
    say("NON-JB EXECUTION TRACE: [402] preparing guest-arena executable canary at guest 0x%08x", CANARY_GUEST_VA);
    if (!page || !halo_guest_commit(CANARY_GUEST_VA, page))
    {
        say("NON-JB EXECUTION TRACE: canary RW commit FAILED (errno=%d: %s)", errno, strerror(errno));
        halo_crash_phase("nonjb 402 exec canary commit failed");
        return 0;
    }

    host = halo_guest_ptr(CANARY_GUEST_VA, sizeof(code));
    if (!host)
    {
        say("NON-JB EXECUTION TRACE: canary host pointer lookup FAILED");
        halo_guest_decommit(CANARY_GUEST_VA, page);
        halo_crash_phase("nonjb 402 exec canary pointer failed");
        return 0;
    }
    memcpy(host, code, sizeof(code));
    sys_icache_invalidate(host, sizeof(code));
    if (!halo_guest_protect(CANARY_GUEST_VA, page, PROT_READ | PROT_EXEC))
    {
        say("NON-JB EXECUTION TRACE: canary RX protection FAILED (errno=%d: %s)", errno, strerror(errno));
        halo_guest_decommit(CANARY_GUEST_VA, page);
        halo_crash_phase("nonjb 402 exec canary protect failed");
        return 0;
    }

    halo_crash_phase("nonjb 403 exec canary entering");
    say("NON-JB EXECUTION TRACE: [403] executing canary from host %p; if the process vanishes here, instruction fetch from guest-arena RX memory is the boundary", host);
    entry = (uint32_t (*)(void))host;
    result = entry();
    halo_crash_phase("nonjb 404 exec canary returned");
    say("NON-JB EXECUTION TRACE: [404] canary returned 0x%04x (expected 0x%04x): %s", result, CANARY_MAGIC, result == CANARY_MAGIC ? "PASS" : "FAIL");
    halo_guest_decommit(CANARY_GUEST_VA, page);
    return result == CANARY_MAGIC;
}
#endif

static void *main_guest_thread(void *opaque)
{
    struct main_guest_context context=*(struct main_guest_context *)opaque;
    free(opaque);

    g_main_host_thread = pthread_self();
    g_main_host_thread_valid = 1;
    profiler_start_for_current_thread();
    if (g_main_thread_va)
        g_guest_tp = g_main_thread_va;
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
    halo_crash_phase("nonjb 410 main guest thread entered");
    say("NON-JB EXECUTION TRACE: [410] main guest host thread entered on guest stack");
#endif

    halo_ios_net_set_resolver(ios_net_resolver);
    halo_ios_net_set_logger(ios_net_log);
    signal(SIGPIPE, SIG_IGN); /* a peer closing a socket must not kill the app */
    say("M2.6.51: arena fast path (PC-derived base, x15 scratch) when built with it; signal bridge stays active as fallback.");
    say("Performance defaults: smooth 60 FPS follows the Settings switch; draw tracing and GL polling follow config.toml (off by default).");
    say("M2.6.51: independent first-person meshes and bounded pose diagnostics; coordinated iCloud invite file support.");
    say("M2.6.51: timed campaign power-ups, independent audio channels, HUD groups, map library and staged backups.");
    say("M2.6.51 visible-render runtime: null renderer disabled; iOS EAGL/OpenGL ES 3 + real guest GL bridge");
    say("M2.6.51 breadcrumb: header start=0x%08x boot_va=0x%08x arena_aligned=%s",
        g_header ? g_header->start : 0u,
        context.boot_va,
        halo_guest_base_is_4gb_aligned() ? "YES" : "NO");

    sigjmp_buf *env=halo_guest_exec_guard_buffer();
    int reason=sigsetjmp(*env,1);
    if(reason==0)
    {
        halo_guest_exec_guard_set_active(1);
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
        halo_crash_phase("nonjb 411 execution guard armed");
        say("NON-JB EXECUTION TRACE: [411] guest execution guard armed");
#endif
        void (*start)(uint32_t)=(void (*)(uint32_t))halo_guest_ptr(g_header->start,1);
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
        halo_crash_phase("nonjb 412 guest start pointer resolved");
        say("NON-JB EXECUTION TRACE: [412] __guest_start pointer resolved: host=%p guest=0x%08x boot=0x%08x", (void *)start, g_header->start, context.boot_va);
#endif
        say("ENTERING REAL arm64_32 __guest_start()... (PC host=%p guest VA=0x%08x)",
            (void *)start, g_header->start);
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
        halo_crash_phase("nonjb 413 calling __guest_start");
        say("NON-JB EXECUTION TRACE: [413] branching into real __guest_start now");
#else
        halo_crash_phase("guest entering __guest_start");
#endif
        start(context.boot_va);
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
        halo_crash_phase("nonjb 418 __guest_start returned");
        say("NON-JB EXECUTION TRACE: [418] __guest_start returned to the host unexpectedly");
#endif
        halo_guest_exec_guard_set_active(0);
        reason=HALO_GUEST_ABORT_HOST;
    }
    else
    {
        halo_guest_exec_guard_set_active(0);
        halo_guest_exec_stats st;
        halo_guest_exec_stats_get(&st);
        say("M2.6.51 abort breadcrumb: reason=%d upgrades=%llu faults=%llu last_fault=0x%llx last_guest_pc=0x%08x last_host_pc=0x%llx insn=0x%08x",
            reason,
            (unsigned long long)st.pointer_upgrades,
            (unsigned long long)st.handled_faults,
            (unsigned long long)st.last_fault_address,
            st.last_guest_pc,
            (unsigned long long)st.last_host_pc,
            st.last_instruction);
    }

    halo_ios_set_hosted_invite(NULL); /* also clear on a guarded guest exit */
    g_guest_reason=reason;
    g_guest_finished=1;
    return NULL;
}

int halo_ios_run_full_guest(void (^line)(const char *text))
{
    g_line=[line copy];
    /* Build 98 reads the default broker list beside config.toml. Atomic write
     * prevents partial lists; custom network.brokers_file paths are untouched. */
    NSString *brokerSource=[NSBundle.mainBundle pathForResource:@"brokers" ofType:@"txt"];
    NSData *brokers=brokerSource?[NSData dataWithContentsOfFile:brokerSource]:nil;
    NSError *brokerError=nil;
    if(!brokers || ![brokers writeToFile:[HaloDataFolder() stringByAppendingPathComponent:@"brokers.txt"] options:NSDataWritingAtomic error:&brokerError])
        say("Internet play: cannot install bundled brokers.txt: %s",brokerError.localizedDescription.UTF8String ?: "missing bundled resource");
    halo_ios_gl_set_logger(g_line);
    g_guest_finished=0;
    g_guest_reason=0;
    g_guest_exit_code=0;
    g_missing_lr=0;
    g_guest_writable_start=0;
    g_main_thread_va=0;
    g_main_host_thread_valid=0;
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
    atomic_store_explicit(&g_nonjb_first_host_import_logged, 0, memory_order_relaxed);
#endif
    g_logged_ioctl=0;
    g_logged_tp_repair=0;
    halo_vm_init(&g_vm, UINT32_C(0xA0000000), UINT32_C(0xD0000000), 0x4000u);
    g_memory_failures_logged=0;
    g_thread_stack_next=UINT32_C(0xEC000000);

    halo_crash_phase("guest start");
    if (g_launch_note) say("%s", g_launch_note);
    if (g_launch_crash) {
        char copy[700]; snprintf(copy, sizeof(copy), "%s", g_launch_crash);
        for (char *l = strtok(copy, "\n"); l; l = strtok(NULL, "\n")) say("  previous crash: %s", l);
    }
    if (g_safe_level) {
        halo_ios_set_profiler_enabled(0);
        say("SAFE START: sound, internet play, smooth 60 FPS, hi-res HUD and text and the profiler are off because the last start did not finish. Settings > Diagnostics > Leave safe mode returns to a normal start.");
    }

    if(!halo_guest_base_is_4gb_aligned())
    {
        say("FULL GUEST BLOCKED: guest arena is not 4-GiB aligned.");
        return 0;
    }
    if(!halo_guest_exec_bridge_install())
    {
        say("FULL GUEST BLOCKED: could not install the PAGEZERO execution bridge.");
        return 0;
    }
    halo_guest_exec_stats_reset();
    halo_crash_phase("guest bridge installed");
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
    halo_crash_phase("nonjb 401 guest bridge installed");
    say("NON-JB EXECUTION TRACE: [401] PAGEZERO execution bridge installed; testing executable code in the actual guest arena next");
    if (!nonjb_guest_arena_exec_canary())
        say("NON-JB EXECUTION TRACE: canary did not pass; continuing into the real guest so the next boundary can still be observed if iOS allows it");
#endif

    NSString *elf=[[NSBundle mainBundle] pathForResource:@"halo_guest" ofType:@"elf"];
    if(!elf)
    {
        say("FULL GUEST BLOCKED: halo_guest.elf is missing from the IPA.");
        return 0;
    }

    NSString *home=NSHomeDirectory() ?: @"";
    g_data_root=[[home stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"Halo"];
    g_save_root=[g_data_root stringByAppendingPathComponent:@"save"];
    [[NSFileManager defaultManager] createDirectoryAtPath:g_save_root
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    if(!load_guest_image(elf))
        return 0;
    halo_crash_phase("guest image loaded");
    if (g_launch_crash) {
        const char *at = strstr(g_launch_crash, "guest_pc=0x");
        if (at) {
            uint32_t pc = (uint32_t)strtoul(at + 9, NULL, 16), symbol_va = 0;
            const char *symbol = symbol_name_nearest(pc, &symbol_va);
            say("  previous crash was in game code: %s+0x%x (guest address 0x%08x)", symbol ? symbol : "unknown", symbol ? pc - symbol_va : 0, pc);
        }
    }

    uint32_t boot=build_boot();
    halo_crash_phase("guest boot environment built");
    if(!boot)
    {
        say("FULL GUEST BLOCKED: boot environment allocation failed.");
        return 0;
    }

    const uint32_t stack_va=UINT32_C(0xED000000);
    const uint32_t stack_size=16*1024*1024;
    if(!halo_guest_commit(stack_va,stack_size))
    {
#if defined(HALO_MOD_TEST) || defined(HALO_NON_JAILBREAK)
        int memory_error=errno;
        say("Startup memory detail: RW commit errno=%d (%s)",memory_error,strerror(memory_error));
        say("STARTUP BLOCKED: GUEST STACK COMMIT");
#endif
        say("FULL GUEST BLOCKED: guest main stack allocation failed.");
        return 0;
    }

#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
    halo_crash_phase("nonjb 408 guest main stack ready");
    say("NON-JB EXECUTION TRACE: [408] 16 MiB guest main stack committed at 0x%08x", stack_va);
#endif

    struct main_guest_context *context=calloc(1,sizeof(*context));
    context->boot_va=boot;

    pthread_attr_t attr; pthread_t thread;
    pthread_attr_init(&attr);
    pthread_attr_setstack(&attr,halo_guest_ptr(stack_va,stack_size),stack_size);
    int error=pthread_create(&thread,&attr,main_guest_thread,context);
    pthread_attr_destroy(&attr);
    if(error)
    {
        free(context);
        say("FULL GUEST BLOCKED: pthread_create failed (%d).",error);
        return 0;
    }
    pthread_detach(thread);
    halo_crash_phase("guest thread started");

    for(int i=0;i<50 && !g_guest_finished;i++)
        usleep(100000);

    halo_guest_exec_stats stats;
    halo_guest_exec_stats_get(&stats);

    if(!g_guest_finished)
    {
        say("");
        say("FULL GUEST STATUS: STILL RUNNING AFTER 5 SECONDS");
        say("PAGEZERO bridge: %llu pointer upgrades, %llu indirect-PC translations",
            (unsigned long long)stats.pointer_upgrades,
            (unsigned long long)stats.pc_translations);
        say("The guest remains active; monitoring for a later exit or execution fault.");
        unsigned monitor_ticks = 0;
        uint64_t previous_upgrades = stats.pointer_upgrades;
        uint64_t previous_presented = atomic_load_explicit(&g_presented_frames,memory_order_relaxed);
        double previous_frame_sample = loading_seconds();
        while (!g_guest_finished)
        {
            usleep(100000);
            if (monitor_ticks % 10 == 0) note_run_progress(atomic_load_explicit(&g_presented_frames,memory_order_relaxed), loading_seconds());
            if (++monitor_ticks % 100 == 0 && !g_guest_finished)
            {
                double frame_sample = loading_seconds();
                uint64_t presented = atomic_load_explicit(&g_presented_frames,memory_order_relaxed);
                double interval = frame_sample-previous_frame_sample;
                if (interval > 0) say("presentation rate: %.2f FPS (%llu successful drawable presents in %.2f s; loading durations reported separately)",
                    (double)(presented-previous_presented)/interval,
                    (unsigned long long)(presented-previous_presented),interval);
                uint64_t bins[6];
                for(int b=0;b<6;b++)bins[b]=atomic_exchange(&g_frame_interval_bins[b],0);
                say("frame intervals: <=18ms %llu, 18-25ms %llu, 25-33ms %llu, 33-50ms %llu, 50-250ms %llu; long gaps >250ms %llu; longest active %.2fms",
                    (unsigned long long)bins[0],(unsigned long long)bins[1],(unsigned long long)bins[2],
                    (unsigned long long)bins[3],(unsigned long long)bins[4],(unsigned long long)bins[5],
                    atomic_exchange(&g_frame_interval_max_us,0)/1000.);
                ios_report_slow_frames();
                say("timing policy: exact call/item/fault counters; native helper clocks ~1/1024, overlapping sub-phase clocks ~1/64; full update/render/upload/present clocks");
                say("device thermal state: %ld; low power mode: %s",(long)NSProcessInfo.processInfo.thermalState,NSProcessInfo.processInfo.isLowPowerModeEnabled?"on":"off");
                {
                    char last_map[32];double map_age=0;
                    if(ios_last_map_copy(last_map,sizeof(last_map),&map_age))say("map file last opened by the game: %s (%.1f s ago); fresh network map details are used instead when there are any",last_map,map_age);
                    else say("map file last opened by the game: none seen yet");
                }
                ios_report_gl_waits();
                previous_presented=presented;
                previous_frame_sample=frame_sample;
                halo_guest_exec_stats_get(&stats);
                uint32_t symbol_va = 0;
                const char *symbol = symbol_name_nearest(stats.last_guest_pc, &symbol_va);
                say("guest heartbeat: elapsed~%u seconds, bridge upgrades +%llu; last bridge PC=0x%08x %s+0x%x",
                    5 + monitor_ticks / 10,
                    (unsigned long long)(stats.pointer_upgrades - previous_upgrades),
                    stats.last_guest_pc, symbol ? symbol : "unknown",
                    symbol ? stats.last_guest_pc - symbol_va : 0);
                {
                    /* Where the remaining pointer faults come from, by function. */
                    enum { HIST_MAX = 4096, TOP = 16 };
                    static halo_fault_hist_entry hist[HIST_MAX];
                    unsigned count = halo_guest_fault_hist_take(hist, HIST_MAX);
                    struct { uint32_t symbol; uint64_t faults; uint32_t sample_pc; } top[TOP];
                    unsigned top_count = 0; uint64_t total = 0;
                    for (unsigned i = 0; i < count; i++) {
                        uint32_t va = 0;
                        const char *name = symbol_name_nearest(hist[i].pc, &va);
                        uint32_t key = name ? va : hist[i].pc;
                        total += hist[i].count;
                        unsigned j = 0;
                        while (j < top_count && top[j].symbol != key) j++;
                        if (j == top_count && top_count < TOP) { top[j].symbol = key; top[j].faults = 0; top[j].sample_pc = hist[i].pc; top_count++; }
                        if (j < top_count) top[j].faults += hist[i].count;
                    }
                    for (unsigned a = 0; a < top_count; a++)
                        for (unsigned b = a + 1; b < top_count; b++)
                            if (top[b].faults > top[a].faults) { __typeof__(top[0]) t = top[a]; top[a] = top[b]; top[b] = t; }
                    say("pointer faults this interval by function (top %u of %llu total):", top_count, (unsigned long long)total);
                    for (unsigned a = 0; a < top_count; a++) {
                        uint32_t va = 0;
                        const char *name = symbol_name_nearest(top[a].sample_pc, &va);
                        say("  fault hot spot: %8llu  %s (0x%08x)", (unsigned long long)top[a].faults, name ? name : "unknown", top[a].symbol);
                    }
                }
                report_profile();
                say("audio: %s; %u buffer underruns so far (an underrun is a tiny gap in the sound)",
                    halo_ios_audio_is_open() ? "playing through the speaker" : halo_ios_audio_status(), halo_ios_audio_underruns());
                say("native bulk memory: %llu calls, %llu MiB total",
                    (unsigned long long)atomic_load(&g_bulk_calls),
                    (unsigned long long)(atomic_load(&g_bulk_bytes) / (1024 * 1024)));
                say("native CRC: %llu calls, %llu MiB, %.1f ms total; texels: %llu levels, %llu MiB, %.1f ms total, %llu guest fallbacks",
                    (unsigned long long)atomic_load(&g_crc_calls), (unsigned long long)(atomic_load(&g_crc_bytes)/1048576), atomic_load(&g_crc_ns)/1e6,
                    (unsigned long long)atomic_load(&g_texel_calls), (unsigned long long)(atomic_load(&g_texel_bytes)/1048576), atomic_load(&g_texel_ns)/1e6, (unsigned long long)atomic_load(&g_texel_fallbacks));
                say("native silent clock: %llu calls, %.1f ms total",
                    (unsigned long long)atomic_load(&g_silent_calls),atomic_load(&g_silent_ns)/1e6);
                say("native vertex colors: %llu calls, %llu KiB, %.1f ms total, %llu guest fallbacks",
                    (unsigned long long)atomic_load(&g_vertex_calls), (unsigned long long)(atomic_load(&g_vertex_bytes)/1024),
                    atomic_load(&g_vertex_ns)/1e6, (unsigned long long)atomic_load(&g_vertex_fallbacks));
                say("native vertex attributes: %llu pointer calls, %llu pointer descriptors reused, %llu value calls, %.1f ms estimated (sampled)",
                    (unsigned long long)atomic_load(&g_attribute_pointer_calls),(unsigned long long)atomic_load(&g_attribute_pointer_reused),
                    (unsigned long long)atomic_load(&g_attribute_value_calls),halo_timing_estimated_ms(atomic_load(&g_attribute_pointer_calls)+atomic_load(&g_attribute_value_calls),atomic_load(&g_attribute_samples),atomic_load(&g_attribute_ns)));
                say("native attribute timing: %llu samples, %.3f ms observed; estimated duration above",(unsigned long long)atomic_load(&g_attribute_samples),atomic_load(&g_attribute_ns)/1e6);
                static const char *scan_names[]={"indices","palette","shader cache","texture cache","shader hash"};
                for (unsigned kind=0;kind<5;kind++)
                    say("native scan %s: %llu calls, %llu items, %.1f ms estimated (sampled); %llu timing samples",scan_names[kind],
                        (unsigned long long)atomic_load(&g_scan_calls[kind]),(unsigned long long)atomic_load(&g_scan_items[kind]),halo_timing_estimated_ms(atomic_load(&g_scan_calls[kind]),atomic_load(&g_scan_samples[kind]),atomic_load(&g_scan_ns[kind])),(unsigned long long)atomic_load(&g_scan_samples[kind]));
                say("native uniforms: %llu comparisons, %llu uploads, %llu KiB compared, %.1f ms estimated (sampled); invalid native inputs %llu",
                    (unsigned long long)atomic_load(&g_uniform_calls),(unsigned long long)atomic_load(&g_uniform_uploads),
                    (unsigned long long)(atomic_load(&g_uniform_bytes)/1024),halo_timing_estimated_ms(atomic_load(&g_uniform_calls),atomic_load(&g_uniform_samples),atomic_load(&g_uniform_ns)),(unsigned long long)atomic_load(&g_scan_invalid));
                say("native uniform timing samples: %llu",(unsigned long long)atomic_load(&g_uniform_samples));
                say("native renderer helper thread upgrades: %llu",(unsigned long long)atomic_load(&g_native_loop_upgrades));
                static const char *scene_names[]={"datum lookup/iteration","BSP index triangles","BSP bit triangles","material ranges","visibility surface lists","visibility leaf references","object list filter"};
                for(unsigned kind=0;kind<7;kind++)say("native scene %s: %llu calls, %llu items, %.1f ms estimated (sampled); %llu timing samples",scene_names[kind],
                    (unsigned long long)atomic_load(&g_scene_calls[kind]),(unsigned long long)atomic_load(&g_scene_items[kind]),halo_timing_estimated_ms(atomic_load(&g_scene_calls[kind]),atomic_load(&g_scene_samples[kind]),atomic_load(&g_scene_ns[kind])),(unsigned long long)atomic_load(&g_scene_samples[kind]));
                say("texture content checks: %llu calls, %llu exact reuse hits, %llu MiB compared, %llu MiB hashed; snapshot budget 8 MiB",
                    (unsigned long long)atomic_load(&g_texture_check_calls),(unsigned long long)atomic_load(&g_texture_check_hits),
                    (unsigned long long)(atomic_load(&g_texture_check_compared)>>20),(unsigned long long)(atomic_load(&g_texture_check_hashed)>>20));
                say("geometry cache: %llu comparisons, %llu KiB checked, %llu changed pages (exact byte comparison)",
                    (unsigned long long)atomic_load(&g_geometry_calls),
                    (unsigned long long)(atomic_load(&g_geometry_bytes)/1024),
                    (unsigned long long)atomic_load(&g_geometry_changed));
                say("native scene invalid inputs: %llu; datum diagnostic fallbacks: %llu",(unsigned long long)atomic_load(&g_scene_invalid),(unsigned long long)atomic_load(&g_datum_fallbacks));
                say("native shadow filter: %llu skipped; %llu diagnostic fallbacks",(unsigned long long)atomic_load(&g_object_filter_skipped),(unsigned long long)atomic_load(&g_object_filter_fallbacks));
                for (int phase=0; phase<24; phase++) {
                    pthread_mutex_lock(&g_timing_lock);
                    uint64_t calls=atomic_exchange(&g_phase_calls[phase],0), ns=atomic_exchange(&g_phase_ns[phase],0), upgrades=atomic_exchange(&g_phase_upgrades[phase],0), samples=atomic_exchange(&g_phase_samples[phase],0);
                    pthread_mutex_unlock(&g_timing_lock);
                    static const char *names[]={"update", "render CPU (includes conversion/upload)", "present CPU", "GL upload CPU", "draw setup total", "texture binding/cache", "shader lookup/link", "vertex preparation", "uniform/state setup", "vertex color conversion/upload", "index bounds/cache", "texture lookup/upload", "scene visibility", "scene objects/shadows", "scene structure passes", "scene particles/transparency", "scene lights", "scene interface", "object discovery", "object render callbacks", "object lighting/cache", "object lighting refresh", "object model/widget traversal", "object simulation update"};
                    if (calls && phase<4) say("timing %s: %llu calls, avg %.0f us, %.0f ms total, %.0f thread pointer upgrades/call (overlapping categories)", names[phase], (unsigned long long)calls, ns/1e3/calls, ns/1e6, (double)upgrades/calls);
                    else if(calls && samples) say("timing %s: %llu calls, sampled avg %.0f us, %.0f ms estimated, %llu samples, %.0f thread pointer upgrades/call (overlapping categories)",names[phase],(unsigned long long)calls,ns/1e3/samples,halo_timing_estimated_ms(calls,samples,ns),(unsigned long long)samples,(double)upgrades/calls);
                    else if(calls)say("timing %s: %llu calls, duration not sampled, %.0f thread pointer upgrades/call",names[phase],(unsigned long long)calls,(double)upgrades/calls);
                }
                previous_upgrades = stats.pointer_upgrades;
            }
        }
        halo_guest_exec_stats_get(&stats);
    }

    say("");
    say("FULL GUEST STOPPED: reason=%d exit=%d",g_guest_reason,g_guest_exit_code);
    say("PAGEZERO bridge: %llu pointer upgrades, %llu indirect-PC translations",
        (unsigned long long)stats.pointer_upgrades,
        (unsigned long long)stats.pc_translations);

    if(g_guest_reason==HALO_GUEST_ABORT_MISSING_IMPORT)
    {
        const char *name=missing_import_from_lr(g_missing_lr);
        say("NEXT HOST BOUNDARY: %s",name ? name : "<could not resolve import stub>");
    }
    else if(g_guest_reason==HALO_GUEST_ABORT_SIGNAL)
    {
        say("EXECUTION FAULT: guestPC=0x%08x fault=0x%llx insn=0x%08x Rn=x%u",
            stats.last_guest_pc,
            (unsigned long long)stats.last_fault_address,
            stats.last_instruction,
            stats.last_base_register);

        uint32_t symbol_va=0;
        const char *symbol=symbol_name_nearest(stats.last_guest_pc,&symbol_va);
        if(symbol)
            say("FAULT PC SYMBOL: %s+0x%x",symbol,stats.last_guest_pc-symbol_va);
        say_fault_backtrace(&stats);

        uint64_t base=(uint64_t)(uintptr_t)halo_guest_base_address();
        if(stats.last_fault_address>=base &&
           stats.last_fault_address-base<FOUR_GB)
        {
            uint32_t fault_va=(uint32_t)(stats.last_fault_address-base);
            uint32_t fault_symbol_va=0;
            const char *fault_symbol=symbol_name_nearest(fault_va,&fault_symbol_va);
            say("FAULT GUEST VA: 0x%08x",fault_va);
            if(fault_symbol)
                say("FAULT ADDRESS SYMBOL: %s+0x%x",
                    fault_symbol,fault_va-fault_symbol_va);
        }
    }
    else if(g_guest_reason==HALO_GUEST_ABORT_EXIT)
    {
        say("REAL GUEST EXITED THROUGH ITS NORMAL EXIT PATH.");
        if(g_guest_exit_code==0)halo_ios_quit_app();
        return g_guest_exit_code==0;
    }

    return 0;
}
