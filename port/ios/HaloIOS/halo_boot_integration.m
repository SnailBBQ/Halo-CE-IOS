#import "halo_boot_integration.h"

#import "halo_cache_runtime.h"
#import "halo_engine_boot.h"
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
    line("Halo iOS - M2.4 Engine Boot Entry");
    line("");

    if (!halo_guest_runtime_init())
    {
        line("FATAL: original-address guest runtime failed to initialize.");
        return;
    }

    say(line, "Guest runtime online: base=%p span=0x%llx page=%zu",
        halo_guest_base_address(),
        (unsigned long long)halo_guest_span(),
        halo_guest_page_size());

    line("");
    line("[1/2] Loading the real Halo ui.map cache...");

    halo_ios_cache_boot_result cacheResult;
    if (!halo_ios_cache_bootstrap(line, &cacheResult))
    {
        line("");
        line("M2.4 BOOT RESULT: BLOCKED IN CACHE STARTUP");
        return;
    }

    line("");
    line("[2/2] Entering recovered scenario/game startup data path...");

    halo_ios_engine_boot_result engineResult;
    if (!halo_ios_engine_boot_main_menu(line, &engineResult))
    {
        line("");
        line("M2.4 BOOT RESULT: BLOCKED IN ENGINE ENTRY");
        return;
    }

    line("");
    line("M2.4 BOOT RESULT: RECOVERED ENGINE ENTRY REACHED");
    say(line, "scenario      : guest 0x%08x", engineResult.scenario_base_va);
    say(line, "structure BSP : guest 0x%08x", engineResult.bsp_definition_va);
    say(line, "game globals  : guest 0x%08x", engineResult.game_globals_base_va);
    line("");
    line("This build intentionally stops before calling LP64-incompatible recovered");
    line("engine functions. The next port layer must make their 32-bit pointer ABI");
    line("executable on iOS, then game_initialize_for_new_map()/main_menu_load can run.");
}
