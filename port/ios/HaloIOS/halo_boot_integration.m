#import "halo_boot_integration.h"

#import "halo_cache_runtime.h"
#import "halo_engine_boot.h"
#import "halo_guest_runner.h"
#import "halo_guest_runtime.h"
#import "HaloBackupArchive.h"

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <sys/utsname.h>
#include <stdarg.h>
#include <stdio.h>
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
#include <errno.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>
#endif

static void say(void (^line)(const char *), const char *fmt, ...)
{
    char buffer[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, ap);
    va_end(ap);
    line(buffer);
}

static void boot_build_identity(void (^line)(const char *))
{
    for (NSString *part in [HaloBuildIdentityText() componentsSeparatedByString:@"\n"])
        line(part.UTF8String ?: "");
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

#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
/* Non-Jailbreak Version only. Observation and reporting; nothing here attaches a debugger or changes what the game does. */
static void say_block(void (^line)(const char *), const char *text)
{
    char buffer[1024];
    const char *start = text;
    while (start && *start)
    {
        const char *end = strchr(start, '\n');
        size_t length = end ? (size_t)(end - start) : strlen(start);
        if (length >= sizeof(buffer))
            length = sizeof(buffer) - 1;
        memcpy(buffer, start, length);
        buffer[length] = 0;
        line(buffer);
        start = end ? end + 1 : NULL;
    }
}

static void boot_non_jailbreak_diagnostics(void (^line)(const char *))
{
    char text[640];
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    struct kinfo_proc process;
    size_t process_size = sizeof(process);
    memset(&process, 0, sizeof(process));
    line("Non-Jailbreak Version (diagnostics): the official app plus address-space and JIT diagnostics. Nothing changes when the normal reservation works.");
    say(line, "Host compiled: %s %s; bundle=%s", __DATE__, __TIME__, NSBundle.mainBundle.bundleIdentifier.UTF8String ?: "unknown");
    if (sysctl(mib, 4, &process, &process_size, NULL, 0) == 0 && process_size == sizeof(process))
        say(line, "Debugger attached at boot: %s (does not prove JIT authorization)", (process.kp_proc.p_flag & P_TRACED) ? "yes" : "no");
    else
        say(line, "Debugger attached at boot: unknown (sysctl errno=%d)", errno);
    halo_guest_runtime_exec_report(text, sizeof(text));
    line(text);
    {
        char map[2048];
        halo_guest_runtime_vm_report(map, sizeof(map));
        say_block(line, map);
    }
}
#endif

void halo_ios_start_game_boot(void (^line)(const char *text))
{
    line("Halo CE iOS — starting engine");
    boot_build_identity(line);
#if defined(HALO_MOD_TEST)
    line("Mod Test build: separate app for large campaign maps. Not a PC or Master Chief Collection loader.");
#endif
    line("");
#if defined(HALO_ALIGNED_ARENA_TEST) && HALO_ALIGNED_ARENA_TEST
    line("Allocator mode: compatibility test, direct aligned 4 GiB Mach reservation");
#else
    line("Allocator mode: production, 8 GiB mmap reservation with aligned 4 GiB window");
#endif
    boot_signing_diagnostics(line);

#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
    boot_non_jailbreak_diagnostics(line);
#endif

    if (!halo_guest_runtime_init())
    {
        line("FATAL: 4-GiB-aligned original-address guest runtime failed.");
        say(line,"Runtime initialization detail: %s",halo_guest_runtime_last_error());
#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
        say_block(line, halo_guest_runtime_nonjb_report());
        line("Non-Jailbreak Version: the current guest still requires a 4-GiB-aligned arena, so startup remains blocked when no aligned window exists. M2.6.80 also tests one exact 4 GiB reservation at ANY address. If 'Flexible 4 GiB ANYWHERE' succeeds above, this install has enough contiguous virtual space for the planned flexible-base guest even though that architecture is not enabled yet.");
#endif
        line("Check the installed app's signing capabilities. This failure occurs before map loading; it is not a Jetsam termination report.");
        line("STARTUP BLOCKED: ADDRESS SPACE");
        return;
    }

#if defined(HALO_NON_JAILBREAK) && HALO_NON_JAILBREAK
    if (halo_guest_runtime_nonjb_report()[0])
        say_block(line, halo_guest_runtime_nonjb_report());
#endif
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
    {
        line("M2.6.15 RESULT: FULL GUEST REACHED AN EXECUTION/HOST BOUNDARY ABOVE.");
        line("STARTUP BLOCKED: ENGINE STARTUP");
    }
}
