#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <string.h>
#undef NDEBUG
#include <assert.h>
static long test_page=16384;
static int fail_map=1,map_error=ENOMEM,unmaps;
static long runtime_page(int name){(void)name;return test_page;}
static void *runtime_map(void *a,size_t size,int prot,int flags,int fd,off_t off){
    (void)a;(void)prot;(void)flags;(void)fd;(void)off;
    assert(size==((size_t)2<<32));
    if(fail_map){errno=map_error;return MAP_FAILED;}return (void *)(uintptr_t)0x310000000ULL;
}
static int runtime_unmap(void *a,size_t size){(void)a;(void)size;++unmaps;return 0;}
#define sysconf runtime_page
#define mmap runtime_map
#define munmap runtime_unmap
#include "halo_guest_runtime.c"
int main(void){
    assert(!halo_guest_runtime_init());assert(strstr(halo_guest_runtime_last_error(),"mmap errno="));
    map_error=EACCES;assert(!halo_guest_runtime_init());assert(strstr(halo_guest_runtime_last_error(),strerror(EACCES)));
    test_page=3;assert(!halo_guest_runtime_init());assert(strstr(halo_guest_runtime_last_error(),"page size: 3"));
    test_page=16384;fail_map=0;assert(halo_guest_runtime_init());assert(halo_guest_base_is_4gb_aligned());
    assert(halo_guest_runtime_last_error()[0]==0);assert(halo_guest_runtime_init());halo_guest_runtime_shutdown();assert(unmaps==3);
    return 0;
}
