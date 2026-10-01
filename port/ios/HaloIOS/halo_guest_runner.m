#import "halo_guest_runner.h"

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
#include <string.h>
#include <strings.h>
#include <zlib.h>
#include "halo_dxt_decode.h"
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
static uint32_t g_heap_next = UINT32_C(0xA0000000);
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
static void ios_loading_stage(uint32_t name_va, int done)
{
    /* These calls are sequential on the game thread; no nested stages. */
    static double started;
    const char *name = gp(name_va, 1);
    if (!name) return;
    if (!done) {
        started = loading_seconds();
        say("[loading] begin: %s", name);
    } else {
        say("[loading] done: %s (%.3f s)", name, loading_seconds() - started);
    }
}

static uint32_t guest_alloc(uint32_t size, uint32_t alignment)
{
    if (alignment < 0x4000)
        alignment = 0x4000;

    pthread_mutex_lock(&g_alloc_lock);
    uint32_t aligned = (g_heap_next + alignment - 1) & ~(alignment - 1);
    uint64_t end = (uint64_t)aligned + size;
    if (end >= UINT32_C(0xD0000000))
    {
        pthread_mutex_unlock(&g_alloc_lock);
        return 0;
    }
    g_heap_next = (uint32_t)((end + 0x3FFF) & ~UINT64_C(0x3FFF));
    pthread_mutex_unlock(&g_alloc_lock);

    if (!halo_guest_commit(aligned, size))
        return 0;
    return aligned;
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

static uint32_t ios_texture_hash(uint32_t source, uint32_t size)
{
    const unsigned char *bytes = gp(source, size);
    if (!bytes) return 1;
    uint32_t hash = 2166136261u;
    for (uint32_t i = 0; i < size; ++i) hash = (hash ^ bytes[i]) * 16777619u;
    return hash ? hash : 1;
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
            return halo_guest_decommit((uint32_t)a, (size_t)b) ? 0 : -EINVAL;

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
}

static void ios_memory_watch_initialize(void) {}
static void ios_memory_watch_protect(uint32_t a, uint32_t b) { (void)a; (void)b; }
static uint32_t ios_memory_watch_generation(uint32_t a, uint32_t b) { (void)a; (void)b; return 0; }
static uint32_t ios_memory_watch_serial(void) { return 1; }
static void ios_memory_watch_prepare_write(uint32_t a, uint32_t b) { (void)a; (void)b; }
static void ios_memory_watch_forget(uint32_t a, uint32_t b) { (void)a; (void)b; }

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
    return halo_ios_gl_swap_window(window);
}

static int ios_sdl_poll_event(uint32_t event)
{
    (void)event;
    return 0;
}

static int ios_sdl_set_clipboard_text(uint32_t text)
{
    (void)text;
    return 1;
}

static void ios_sdl_get_clipboard_text(uint32_t buffer_va, uint32_t size)
{
    char *buffer = gp(buffer_va, size);
    if (buffer && size)
        buffer[0] = 0;
}

static int ios_sdl_show_toast(uint32_t message, int duration, int gravity, int x, int y)
{
    (void)message; (void)duration; (void)gravity; (void)x; (void)y;
    return 1;
}

static int ios_sdl_show_simple_message_box(uint32_t flags, uint32_t title, uint32_t message)
{
    (void)flags; (void)title; (void)message;
    return 1;
}

static _Atomic(uint32_t) g_menu_held;
static _Atomic(uint32_t) g_menu_pending;

void halo_ios_menu_button(int button, int pressed)
{
    if (button < 0 || button >= 32) return;
    uint32_t bit = UINT32_C(1) << button;
    if (pressed) {
        atomic_fetch_or(&g_menu_held, bit);
        atomic_fetch_or(&g_menu_pending, bit);
    } else atomic_fetch_and(&g_menu_held, ~bit);
}

void halo_ios_menu_reset(void)
{
    atomic_store(&g_menu_held, 0);
    atomic_store(&g_menu_pending, 0);
}

static int ios_sdl_get_gamepads(uint32_t ids, int capacity)
{
    if (capacity < 1) return 0;
    uint32_t *out = gp(ids, sizeof(*out));
    if (!out) return 0;
    out[0] = 1; /* the native menu pad */
    return 1;
}

static uint32_t ios_sdl_open_gamepad(uint32_t id)
{
    return id == 1 ? 1 : 0;
}

static int ios_sdl_gamepad_axis(uint32_t gamepad, int axis)
{
    (void)gamepad; (void)axis;
    return 0;
}

static int ios_sdl_gamepad_button(uint32_t gamepad, int button)
{
    if (gamepad != 1 || button < 0 || button >= 32) return 0;
    uint32_t bit = UINT32_C(1) << button;
    /* A quick tap is delivered at least once even between slow frames. */
    uint32_t pending = atomic_fetch_and(&g_menu_pending, ~bit);
    return ((atomic_load(&g_menu_held) | pending) & bit) != 0;
}

static int ios_sdl_gamepad_type(uint32_t gamepad)
{
    return gamepad == 1 ? 1 : 0; /* SDL_GAMEPAD_TYPE_STANDARD */
}

static int ios_sdl_rumble(uint32_t gamepad, uint32_t low, uint32_t high, uint32_t milliseconds)
{
    (void)gamepad; (void)low; (void)high; (void)milliseconds;
    return 0;
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
static int ios_posix_socket_last_error(void){return ENETDOWN;}
static int ios_posix_socket_fail(void){errno=ENETDOWN;return -1;}
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
    MAP("host_memory_copy", ios_memory_copy);
    MAP("host_memory_fill", ios_memory_fill);
    MAP("host_loading_stage", ios_loading_stage);
    MAP("host_cache_inflate", ios_cache_inflate_step);
    MAP("host_cache_inflate_end", ios_cache_inflate_end);
    MAP("host_guest_pointer", ios_host_guest_pointer);

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
        PMAP("local_ipv4_address", ios_posix_zero_u32);
        PMAP("resolve_ipv4", ios_posix_zero_u32);
        PMAP("random_bytes", ios_posix_random);
#undef PMAP
        if(!strncmp(n,"socket",6) || !strncmp(n,"discord",7) || !strncmp(n,"upnp",4))
            return (void *)ios_posix_socket_fail;
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
    if(g_elf.length < sizeof(Elf64_Ehdr)) return 0;

    g_ehdr=(const Elf64_Ehdr *)g_elf.bytes;
    if(g_ehdr->e_ident[0]!=0x7F || g_ehdr->e_ident[1]!='E' ||
       g_ehdr->e_ident[2]!='L' || g_ehdr->e_ident[3]!='F' ||
       g_ehdr->e_ident[4]!=2 || g_ehdr->e_machine!=183 ||
       g_ehdr->e_phentsize!=sizeof(Elf64_Phdr))
    {
        say("FULL GUEST: bundled image is not the expected AArch64 ELF.");
        return 0;
    }

    if(g_ehdr->e_phoff + (uint64_t)g_ehdr->e_phnum*sizeof(Elf64_Phdr) > g_elf.length)
        return 0;

    const uint8_t *file=g_elf.bytes;
    const Elf64_Phdr *ph=(const Elf64_Phdr *)(file+g_ehdr->e_phoff);

    halo_guest_exec_bridge_reset_ranges();

    uint32_t low=UINT32_MAX, high=0;
    for(uint16_t i=0;i<g_ehdr->e_phnum;i++)
    {
        if(ph[i].p_type!=PT_LOAD) continue;
        if(ph[i].p_vaddr>=FOUR_GB || ph[i].p_vaddr+ph[i].p_memsz>FOUR_GB ||
           ph[i].p_offset+ph[i].p_filesz>g_elf.length)
            return 0;

        uint32_t va=(uint32_t)ph[i].p_vaddr;
        uint32_t mem=(uint32_t)ph[i].p_memsz;
        if(!halo_guest_commit(va,mem)) return 0;
        void *dst=halo_guest_ptr(va,mem);
        memset(dst,0,mem);
        memcpy(dst,file+ph[i].p_offset,(size_t)ph[i].p_filesz);

        if(va<low)low=va;
        if((uint64_t)va+mem>high)high=va+mem;
    }

    void *code_start = halo_guest_ptr(low, 1);
    size_t code_size = (size_t)((uint64_t)high - low);
    if (!code_start || !code_size)
        return 0;
    sys_icache_invalidate(code_start, code_size);

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
            return 0;
    }

    g_header=(struct halo_guest_header *)halo_guest_ptr(HALO_GUEST_IMAGE_BASE,sizeof(*g_header));
    if(!g_header || g_header->magic!=HALO_GUEST_MAGIC || g_header->abi_version!=HALO_GUEST_ABI_VERSION){
        say("FULL GUEST: image header mismatch.");
        return 0;
    }

    uint32_t *countp=gp(g_header->import_count,4);
    uint64_t *table=gp(g_header->import_table,(*countp)*sizeof(uint64_t));
    const char *name=gp(g_header->import_names,1);
    if(!countp||!table||!name)return 0;

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

    const char *values[]={
        data,
        save,
        "HALO_NO_AUDIO=1",
        "HALO_GL_DEBUG=1",
        "HALO_GPU_STATS=1",
        "HALO_GPU_TRACE=0",
        "HALO_NET_ONLINE=false",
        "HALO_NET_ALLOW_UPNP=false",
        "HALO_UPDATE_AUTO=false",
        "HALO_INTERPOLATION=false",
        "HOME=/tmp",
        "TZ=UTC0",
        NULL
    };
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

static void *main_guest_thread(void *opaque)
{
    struct main_guest_context context=*(struct main_guest_context *)opaque;
    free(opaque);

    g_main_host_thread = pthread_self();
    g_main_host_thread_valid = 1;
    if (g_main_thread_va)
        g_guest_tp = g_main_thread_va;

    say("M2.6.17 visible-render runtime: null renderer disabled; iOS EAGL/OpenGL ES 3 + real guest GL bridge");

    sigjmp_buf *env=halo_guest_exec_guard_buffer();
    int reason=sigsetjmp(*env,1);
    if(reason==0)
    {
        halo_guest_exec_guard_set_active(1);
        void (*start)(uint32_t)=(void (*)(uint32_t))halo_guest_ptr(g_header->start,1);
        say("ENTERING REAL arm64_32 __guest_start()...");
        start(context.boot_va);
        halo_guest_exec_guard_set_active(0);
        reason=HALO_GUEST_ABORT_HOST;
    }
    else
        halo_guest_exec_guard_set_active(0);

    g_guest_reason=reason;
    g_guest_finished=1;
    return NULL;
}

int halo_ios_run_full_guest(void (^line)(const char *text))
{
    g_line=[line copy];
    halo_ios_gl_set_logger(g_line);
    g_guest_finished=0;
    g_guest_reason=0;
    g_guest_exit_code=0;
    g_missing_lr=0;
    g_guest_writable_start=0;
    g_main_thread_va=0;
    g_main_host_thread_valid=0;
    g_logged_ioctl=0;
    g_logged_tp_repair=0;
    g_heap_next=UINT32_C(0xA0000000);
    g_thread_stack_next=UINT32_C(0xEC000000);

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

    uint32_t boot=build_boot();
    if(!boot)
    {
        say("FULL GUEST BLOCKED: boot environment allocation failed.");
        return 0;
    }

    const uint32_t stack_va=UINT32_C(0xED000000);
    const uint32_t stack_size=16*1024*1024;
    if(!halo_guest_commit(stack_va,stack_size))
    {
        say("FULL GUEST BLOCKED: guest main stack allocation failed.");
        return 0;
    }

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
        while (!g_guest_finished)
        {
            usleep(100000);
            if (++monitor_ticks % 100 == 0 && !g_guest_finished)
            {
                halo_guest_exec_stats_get(&stats);
                uint32_t symbol_va = 0;
                const char *symbol = symbol_name_nearest(stats.last_guest_pc, &symbol_va);
                say("guest heartbeat: elapsed~%u seconds, bridge upgrades +%llu; last bridge PC=0x%08x %s+0x%x",
                    5 + monitor_ticks / 10,
                    (unsigned long long)(stats.pointer_upgrades - previous_upgrades),
                    stats.last_guest_pc, symbol ? symbol : "unknown",
                    symbol ? stats.last_guest_pc - symbol_va : 0);
                say("native bulk memory: %llu calls, %llu MiB total",
                    (unsigned long long)atomic_load(&g_bulk_calls),
                    (unsigned long long)(atomic_load(&g_bulk_bytes) / (1024 * 1024)));
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
        return g_guest_exit_code==0;
    }

    return 0;
}
