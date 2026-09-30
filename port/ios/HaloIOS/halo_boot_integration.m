#import "halo_boot_integration.h"

#import "halo_cache_runtime.h"
#import "halo_engine_boot.h"
#import "halo_guest_runner.h"
#import "halo_guest_runtime.h"

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

void halo_ios_start_game_boot(void (^line)(const char *text))
{
    line("Halo iOS - M2.6.6 Visible Renderer Startup");
    line("");

    if (!halo_guest_runtime_init())
    {
        line("FATAL: 4-GiB-aligned original-address guest runtime failed.");
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
    line("Mode: real engine execution + iOS OpenGL ES renderer; audio disabled.");
    line("The guest receives Documents/Halo as its data root and runs its own main().");
    line("");

    int success = halo_ios_run_full_guest(line);

    line("");
    if (success)
        line("M2.6.6 RESULT: FULL GUEST EXITED CLEANLY.");
    else
        line("M2.6.6 RESULT: FULL GUEST REACHED AN EXECUTION/HOST BOUNDARY ABOVE.");
}
