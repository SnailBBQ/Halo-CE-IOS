#include "halo_map_order.h"
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

static int alphabetical;
static int cmp(const void *a, const void *b) { return hm_compare(*(const char *const *)a, *(const char *const *)b, alphabetical); }

static void sort_names(const char **names, int n, int alpha) { alphabetical = alpha; qsort(names, (size_t)n, sizeof(*names), cmp); }

static int joined_matches(const char **names, int n, const char *expected)
{
    char buffer[1024] = "";
    for (int i = 0; i < n; i++) { if (i) strcat(buffer, ","); strcat(buffer, names[i]); }
    if (strcmp(buffer, expected)) { printf("  got      %s\n  expected %s\n", buffer, expected); return 0; }
    return 1;
}

int main(void)
{
    /* the files in your Documents/Halo/maps, in scrambled order */
    const char *stock[] = { "wizard", "ui", "d40", "bloodgulch", "a30", "longest", "damnation", "c10", "beavercreek", "putput", "a10", "ratrace",
                            "boardingaction", "b40", "carousel", "c20", "prisoner", "a50", "b30", "chillout", "hangemhigh", "d20", "sidewinder", "c40" };
    int n = (int)(sizeof(stock) / sizeof(stock[0]));
    CHECK(n == 24, "24 stock files");

    /* campaign in mission order, then the menu order you listed, then ui */
    sort_names(stock, n, 0);
    CHECK(joined_matches(stock, n, "a10,a30,a50,b30,b40,c10,c20,c40,d20,d40,beavercreek,sidewinder,damnation,ratrace,prisoner,hangemhigh,chillout,carousel,boardingaction,bloodgulch,wizard,putput,longest,ui"),
          "in-game order");

    /* alphabetical multiplayer: campaign unaffected and still on top */
    sort_names(stock, n, 1);
    CHECK(joined_matches(stock, n, "a10,a30,a50,b30,b40,c10,c20,c40,d20,d40,beavercreek,bloodgulch,boardingaction,chillout,putput,damnation,carousel,hangemhigh,longest,prisoner,ratrace,sidewinder,wizard,ui"),
          "alphabetical order of the names shown (Battle Creek, Blood Gulch, Boarding Action, Chill Out, Chiron TL-34, Damnation, Derelict, Hang 'Em High, Longest, Prisoner, Rat Race, Sidewinder, Wizard)");

    /* custom maps: after the stock multiplayer maps in game order, alphabetically; mixed in when alphabetical */
    const char *mixed[] = { "zebra_run", "ui", "a10", "Aardvark", "beavercreek", "longest", "d40", "mymap" };
    int m = (int)(sizeof(mixed) / sizeof(mixed[0]));
    sort_names(mixed, m, 0);
    CHECK(joined_matches(mixed, m, "a10,d40,beavercreek,longest,Aardvark,mymap,zebra_run,ui"), "custom maps follow the stock multiplayer maps");
    sort_names(mixed, m, 1);
    CHECK(joined_matches(mixed, m, "a10,d40,Aardvark,beavercreek,longest,mymap,zebra_run,ui"), "custom maps are mixed in alphabetically when sorting A-Z");

    /* names */
    CHECK(!strcmp(hm_title("beavercreek"), "Battle Creek") && !strcmp(hm_title("CARouSEL"), "Derelict") && !strcmp(hm_title("putput"), "Chiron TL-34") &&
          !strcmp(hm_title("a10"), "The Pillar of Autumn") && !strcmp(hm_title("ui"), "Main menu") && !strcmp(hm_title("mymap"), "mymap"), "titles");
    CHECK(!strcmp(hm_title("hangemhigh"), "Hang 'Em High") && !strcmp(hm_title("bloodgulch"), "Blood Gulch") && !strcmp(hm_title("d40"), "The Maw"), "more titles");

    /* multiplayer only hides the campaign maps and nothing else */
    int visible = 0;
    for (int i = 0; i < n; i++) visible += hm_visible(stock[i], 1);
    CHECK(visible == 14, "multiplayer only leaves 13 multiplayer maps and ui (%d)", visible);
    CHECK(hm_visible_mode("a10", 2) == 1 && hm_visible_mode("longest", 2) == 0 && hm_visible_mode("custom", 2) == 0 && hm_visible_mode("longest", 1) == 1 && hm_visible_mode("d40", 1) == 0 && hm_visible_mode("d40", 0) == 1, "campaign-only and multiplayer-only are opposites");
    CHECK(hm_custom_visible(0, 2) && !hm_custom_visible(1, 2) && !hm_custom_visible(0, 1) && hm_custom_visible(1, 1) && hm_custom_visible(2, 1) && hm_custom_visible(0, 0) && hm_custom_visible(1, 0), "custom map filters follow the scenario type");
    CHECK(hm_visible("a10", 1) == 0 && hm_visible("ui", 1) == 1 && hm_visible("longest", 1) == 1 && hm_visible("custom", 1) == 1 && hm_visible("a10", 0) == 1, "visibility rules");

    /* hostile input */
    CHECK(hm_index(NULL) == -1 && hm_index("") == -1 && hm_group("") == 2 && !hm_is_ui("uix") && !hm_is_ui("u"), "empty and near-miss names");
    char longname[200]; memset(longname, 'a', sizeof longname); longname[199] = 0;
    CHECK(hm_index(longname) == -1 && hm_compare(longname, "a10", 0) > 0, "a very long name is not a stock map");
    CHECK(hm_compare("a10", "a10", 0) == 0 && hm_compare("x", "x", 1) == 0, "equal names compare equal");

    if (!failures) printf("PASS: installed game files: campaign in mission order, multiplayer in menu order or A-Z, custom maps after, ui last, multiplayer-only hides campaign\n");
    return failures ? 1 : 0;
}
