#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>
#undef NDEBUG
#include <assert.h>

static kern_return_t map_result=KERN_NO_SPACE;
static mach_vm_address_t chosen=UINT64_C(0x400000000);
static int reservations,invalid_releases,unmaps;
static kern_return_t direct_map(vm_map_t target,mach_vm_address_t *address,
    mach_vm_size_t size,mach_vm_offset_t mask,int flags,mem_entry_name_port_t object,
    mach_vm_offset_t offset,boolean_t copy,vm_prot_t current,vm_prot_t maximum,vm_inherit_t inherit)
{
    (void)target;
    assert(size==UINT64_C(0x100000000) && mask==UINT64_C(0xffffffff));
    assert(flags==VM_FLAGS_ANYWHERE && object==MEMORY_OBJECT_NULL);
    assert(!offset && !copy && current==VM_PROT_NONE && maximum==VM_PROT_ALL && inherit==VM_INHERIT_NONE);
    ++reservations;if(map_result==KERN_SUCCESS)*address=chosen;return map_result;
}
static kern_return_t direct_release(vm_map_t target,mach_vm_address_t address,mach_vm_size_t size)
{(void)target;assert(address==chosen && size==UINT64_C(0x100000000));++invalid_releases;return KERN_SUCCESS;}
static int direct_unmap(void *address,size_t size)
{assert((uintptr_t)address==chosen && size==UINT64_C(0x100000000));++unmaps;return 0;}
static long direct_page(int name){(void)name;return 16384;}
#define HALO_ALIGNED_ARENA_TEST 1
#define mach_vm_map direct_map
#define mach_vm_deallocate direct_release
#define munmap direct_unmap
#define sysconf direct_page
#include "halo_guest_runtime.c"

int main(void)
{
    assert(!halo_guest_runtime_init());assert(strstr(halo_guest_runtime_last_error(),"Mach error="));
    assert(!halo_guest_base_address() && !invalid_releases);
    map_result=KERN_SUCCESS;chosen=UINT64_C(0x400004000);
    assert(!halo_guest_runtime_init());assert(invalid_releases==1);
    chosen=UINT64_C(0x400000000);
    assert(halo_guest_runtime_init() && halo_guest_base_is_4gb_aligned());
    assert(halo_guest_page_size()==16384 && !halo_guest_runtime_last_error()[0]);
    assert((uint32_t)(uintptr_t)halo_guest_ptr(0x12345678,4)==0x12345678);
    assert(!halo_guest_ptr(UINT32_MAX,2));
    assert(halo_guest_runtime_init() && reservations==3);
    halo_guest_runtime_shutdown();assert(unmaps==1 && !halo_guest_base_address());
    return 0;
}
