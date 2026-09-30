#import "halo_boot_integration.h"

#import "halo_cache_runtime.h"
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
    line("Halo iOS - M2.3 Compressed Cache Boot");
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
    line("Starting real Halo cache bootstrap...");

    halo_ios_cache_boot_result result;
    int ok = halo_ios_cache_bootstrap(line, &result);

    line("");
    if (ok)
    {
        line("M2.3 BOOT RESULT: REAL CONTENT LOADED");
        say(line, "Maps indexed: %u valid / %u discovered",
            result.valid_maps, result.discovered_maps);
        say(line, "ui.map tags: %u", result.selected_tag_count);
        say(line, "scenario datum: 0x%08x", result.selected_scenario_tag_index);
        line("");
        line("Halo iOS has crossed from file discovery into real cache/tag loading.");
        line("The next update will connect this loaded ui.map state to the recovered");
        line("scenario/game initialization path instead of returning to probe code.");
    }
    else
    {
        line("M2.3 BOOT RESULT: BLOCKED");
        line("The cache loader stopped at the first real content/format boundary above.");
    }

    /*
     * Keep the guest reservation alive for the process lifetime. Later engine
     * startup code will continue from the loaded tag cache instead of rebuilding it.
     */
}
