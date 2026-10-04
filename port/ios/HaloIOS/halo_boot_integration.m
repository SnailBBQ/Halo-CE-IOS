#import "halo_boot_integration.h"

#import "halo_cache_runtime.h"
#import "halo_engine_boot.h"
#import "halo_guest_runner.h"
#import "halo_guest_runtime.h"

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <sys/utsname.h>
#include <stdarg.h>
#include <stdio.h>

static void say(void (^line)(const char *), const char *fmt, ...)
{
    char buffer[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, ap);
    va_end(ap);
    line(buffer);
}

/* Optional introspection, never a dependency or permission bypass. Some
 * signing environments do not expose SecTask's symbols; report unknown then. */
static void boot_signing_diagnostics(void (^line)(const char *)) {
    struct utsname machine;const char *model=uname(&machine)==0?machine.machine:"unknown";
    NSDictionary *info=NSBundle.mainBundle.infoDictionary;
    say(line,"Runtime environment: app=%s (%s), OS=%s, device=%s, physical RAM=%llu MiB",
        [info[@"CFBundleShortVersionString"] UTF8String] ?: "unknown",
        [info[@"CFBundleVersion"] UTF8String] ?: "unknown",
        NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String,model,
        (unsigned long long)(NSProcessInfo.processInfo.physicalMemory>>20));
    size_t (*available)(void)=dlsym(RTLD_DEFAULT,"os_proc_available_memory");
    if(available)say(line,"Process memory allowance remaining: %llu MiB (not virtual address space)",(unsigned long long)(available()>>20));
    void *security=dlopen("/System/Library/Frameworks/Security.framework/Security",RTLD_LAZY|RTLD_LOCAL);
    CFTypeRef (*create)(CFAllocatorRef)=security?dlsym(security,"SecTaskCreateFromSelf"):NULL;
    CFTypeRef (*value)(CFTypeRef,CFStringRef,CFErrorRef *)=security?dlsym(security,"SecTaskCopyValueForEntitlement"):NULL;
    CFTypeRef task=create&&value?create(kCFAllocatorDefault):NULL;
    for(NSString *key in @[@"com.apple.developer.kernel.extended-virtual-addressing",@"com.apple.developer.kernel.increased-memory-limit",@"get-task-allow"]) {
        const char *state="unknown (inspection unavailable)";
        CFErrorRef error=NULL;CFTypeRef result=task?value(task,(__bridge CFStringRef)key,&error):NULL;
        if(task && !error)state=!result?"absent":CFGetTypeID(result)==CFBooleanGetTypeID()?(CFBooleanGetValue((CFBooleanRef)result)?"true":"false"):"present, non-boolean";
        say(line,"Signing capability %s: %s",key.UTF8String,state);
        if(result)CFRelease(result);if(error)CFRelease(error);
    }
    if(task)CFRelease(task);if(security)dlclose(security);
    line("Capability inspection does not confirm authorization to execute loaded guest code.");
}

void halo_ios_start_game_boot(void (^line)(const char *text))
{
    line("Halo CE iOS — starting engine");
    line("");
    boot_signing_diagnostics(line);

    if (!halo_guest_runtime_init())
    {
        line("FATAL: 4-GiB-aligned original-address guest runtime failed.");
        say(line,"Runtime initialization detail: %s",halo_guest_runtime_last_error());
        line("Check the installed app's signing capabilities. This failure occurs before map loading; it is not a Jetsam termination report.");
        return;
    }

    say(line, "Guest arena: base=%p span=0x%llx page=%zu aligned4G=%s",
        halo_guest_base_address(),
        (unsigned long long)halo_guest_span(),
        halo_guest_page_size(),
        halo_guest_base_is_4gb_aligned() ? "YES" : "NO");

    line("");
    line("[1/3] Loading real ui.map cache and original-address tag state...");

    halo_ios_cache_boot_result cacheResult;
    if (!halo_ios_cache_bootstrap(line, &cacheResult))
    {
        line("M2.5 BOOT RESULT: BLOCKED IN CACHE STARTUP");
        return;
    }

    line("");
    line("[2/3] Binding recovered scenario/BSP/game-global engine state...");

    halo_ios_engine_boot_result engineResult;
    if (!halo_ios_engine_boot_main_menu(line, &engineResult))
    {
        line("M2.5 BOOT RESULT: BLOCKED IN ENGINE DATA ENTRY");
        return;
    }

    line("");
    line("[3/3] Launching the full recovered arm64_32 Halo guest image...");
    line("Mode: real engine execution + iOS OpenGL ES renderer; audio follows Settings.");
    line("The guest receives Documents/Halo as its data root and runs its own main().");
    line("");

    int success = halo_ios_run_full_guest(line);

    line("");
    if (success)
        line("M2.6.15 RESULT: FULL GUEST EXITED CLEANLY.");
    else
        line("M2.6.15 RESULT: FULL GUEST REACHED AN EXECUTION/HOST BOUNDARY ABOVE.");
}
