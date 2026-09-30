#include "halo_ios_probe.h"

#include <inttypes.h>
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>

#define XBOX_BASE       0x80000000u
#define XBOX_SIZE       0x08000000u
#define IMAGE_BASE      0x88000000u
#define IMAGE_SIZE      0x02000000u
#define EXPECTED_PAGEZERO 0x00004000ULL

extern const struct mach_header_64 _mh_execute_header;

static void say(void (^line)(const char *), const char *fmt, ...)
{
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    line(buf);
}

static uint64_t pagezero_size(void)
{
    const struct mach_header_64 *mh = &_mh_execute_header;
    const uint8_t *p = (const uint8_t *)(mh + 1);

    for (uint32_t i = 0; i < mh->ncmds; ++i)
    {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmd == LC_SEGMENT_64)
        {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)p;
            if (strncmp(seg->segname, "__PAGEZERO", sizeof(seg->segname)) == 0)
                return seg->vmsize;
        }
        if (lc->cmdsize == 0)
            break;
        p += lc->cmdsize;
    }
    return UINT64_MAX;
}

static int fixed_allocate(uint32_t base, uint32_t size, void (^line)(const char *), const char *name)
{
    vm_address_t address = (vm_address_t)base;
    kern_return_t kr = vm_allocate(mach_task_self(), &address, (vm_size_t)size, FALSE);
    if (kr != KERN_SUCCESS)
    {
        say(line, "FAIL %-12s 0x%08x + 0x%08x: kr=%d (%s)",
            name, base, size, kr, mach_error_string(kr));
        return 0;
    }

    if ((uint64_t)address != (uint64_t)base)
    {
        say(line, "FAIL %-12s requested=0x%08x got=0x%llx",
            name, base, (unsigned long long)address);
        vm_deallocate(mach_task_self(), address, (vm_size_t)size);
        return 0;
    }

    say(line, "PASS %-12s 0x%08x + 0x%08x", name, base, size);
    vm_deallocate(mach_task_self(), address, (vm_size_t)size);
    return 1;
}

void halo_ios_run_m0_probe(void (^line)(const char *text))
{
    const long page = sysconf(_SC_PAGESIZE);
    const uint64_t pz = pagezero_size();
    int pass = 1;

    say(line, "pointer size: %zu-bit", sizeof(void *) * 8);
    say(line, "page size: %ld", page);

    line("");
    line("[1] Mach-O PAGEZERO:");
    if (pz == UINT64_MAX)
    {
        line("FAIL __PAGEZERO segment not found");
        pass = 0;
    }
    else
    {
        say(line, "%s __PAGEZERO vmsize=0x%llx (%llu KiB)",
            pz == EXPECTED_PAGEZERO ? "PASS" : "WARN",
            (unsigned long long)pz,
            (unsigned long long)(pz / 1024ULL));
        if (pz >= 0x100000000ULL)
        {
            line("FAIL low 4 GB is still covered by __PAGEZERO");
            pass = 0;
        }
    }

    line("");
    line("[2] Low-address fixed-page sanity:");
    pass &= fixed_allocate(0x10000000u, (uint32_t)page, line, "0x10000000");
    pass &= fixed_allocate(0x20000000u, (uint32_t)page, line, "0x20000000");
    pass &= fixed_allocate(0x40000000u, (uint32_t)page, line, "0x40000000");
    pass &= fixed_allocate(0x60000000u, (uint32_t)page, line, "0x60000000");

    line("");
    line("[3] Halo ranges independently:");
    int xbox_alone = fixed_allocate(XBOX_BASE, XBOX_SIZE, line, "Xbox window");
    int image_alone = fixed_allocate(IMAGE_BASE, IMAGE_SIZE, line, "Guest image");
    pass &= xbox_alone && image_alone;

    line("");
    line("[4] Halo ranges simultaneously:");
    vm_address_t xbox = XBOX_BASE;
    vm_address_t image = IMAGE_BASE;
    kern_return_t kr_xbox = vm_allocate(mach_task_self(), &xbox, XBOX_SIZE, FALSE);
    kern_return_t kr_image = KERN_FAILURE;
    if (kr_xbox == KERN_SUCCESS && xbox == XBOX_BASE)
        kr_image = vm_allocate(mach_task_self(), &image, IMAGE_SIZE, FALSE);

    int simultaneous = kr_xbox == KERN_SUCCESS && xbox == XBOX_BASE &&
                       kr_image == KERN_SUCCESS && image == IMAGE_BASE;
    if (simultaneous)
    {
        volatile uint32_t *x0 = (volatile uint32_t *)(uintptr_t)XBOX_BASE;
        volatile uint32_t *x1 = (volatile uint32_t *)(uintptr_t)(XBOX_BASE + XBOX_SIZE - sizeof(uint32_t));
        volatile uint32_t *g0 = (volatile uint32_t *)(uintptr_t)IMAGE_BASE;
        volatile uint32_t *g1 = (volatile uint32_t *)(uintptr_t)(IMAGE_BASE + IMAGE_SIZE - sizeof(uint32_t));
        *x0 = 0x48414c4fu;
        *x1 = 0x58424f58u;
        *g0 = 0x23422342u;
        *g1 = 0xdeadbeefu;
        simultaneous = (*x0 == 0x48414c4fu && *x1 == 0x58424f58u &&
                        *g0 == 0x23422342u && *g1 == 0xdeadbeefu);
        say(line, "%s simultaneous direct read/write at original addresses",
            simultaneous ? "PASS" : "FAIL");
    }
    else
    {
        say(line, "FAIL simultaneous map: xbox kr=%d addr=0x%llx, image kr=%d addr=0x%llx",
            kr_xbox, (unsigned long long)xbox,
            kr_image, (unsigned long long)image);
    }

    if (kr_image == KERN_SUCCESS && image == IMAGE_BASE)
        vm_deallocate(mach_task_self(), image, IMAGE_SIZE);
    if (kr_xbox == KERN_SUCCESS && xbox == XBOX_BASE)
        vm_deallocate(mach_task_self(), xbox, XBOX_SIZE);
    pass &= simultaneous;

    line("");
    if (pass)
    {
        line("M0.4 RESULT: PASS - shrinking __PAGEZERO restores Halo's original low-4GB mappings.");
        line("NEXT: prefer the Android ILP32 direct-address architecture for M1; relocation translation is no longer the primary path.");
    }
    else
    {
        line("M0.4 RESULT: FAIL - iOS still blocks one or more required low-4GB mappings after shrinking __PAGEZERO.");
        line("NEXT: keep the relocated-arena strategy and investigate instruction/data pointer rewriting.");
    }
}
