/* The map name a path gives for diagnostics (halo_map_name.h). */
#include <stdio.h>
#include <string.h>
#include "halo_map_name.h"
static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)
static void accept(const char *path, const char *expected) { char out[32] = "untouched"; int ok = halo_map_name_from_path(path, out, sizeof(out)); CHECK(ok && !strcmp(out, expected), "%s -> %s (expected %s)", path, ok ? out : "refused", expected); }
static void refuse(const char *path) { char out[32] = "untouched"; int ok = halo_map_name_from_path(path, out, sizeof(out)); CHECK(!ok && !strcmp(out, "untouched"), "%s was taken as %s", path ? path : "NULL", out); }
int main(void) {
    char tiny[4], big[1300], out[32];
    accept("/var/mobile/Containers/Data/Application/X/Documents/Halo/maps/a50.map", "a50");
    accept("d:\\maps\\Bloodgulch.MAP", "bloodgulch"); accept("maps/ui.map", "ui"); accept("a10.map", "a10"); accept("x.Map", "x");
    accept("c:/halo/maps/boardingaction.map", "boardingaction"); accept("maps/my-custom_map2.map", "my-custom_map2");
    refuse(NULL); refuse(""); refuse(".map"); refuse("maps/.map"); refuse("maps/a50"); refuse("maps/a50.map.bak"); refuse("maps/a.b.map"); refuse("maps/bad name.map");
    refuse("maps/a50.mapx"); refuse("maps/a50.mp"); refuse("maps/dir/"); refuse("maps\\a50.txt"); refuse("a%0d.map"); refuse("maps/a\xc3\xa9.map");
    refuse("maps/thisnameisfarlongerthanthirtyoneletters.map");
    memset(big, 'a', sizeof(big) - 1); big[sizeof(big) - 1] = 0; memcpy(big + sizeof(big) - 5, ".map", 5);
    CHECK(!halo_map_name_from_path(big, out, sizeof(out)), "an over-long path is refused");
    CHECK(!halo_map_name_from_path("maps/a50.map", tiny, 0) && !halo_map_name_from_path("maps/a50.map", NULL, 32) && !halo_map_name_from_path("maps/a50.map", tiny, 1), "bad output buffers");
    CHECK(halo_map_name_from_path("maps/abc.map", tiny, 4) && !strcmp(tiny, "abc") && !halo_map_name_from_path("maps/abcd.map", tiny, 4), "the output buffer is never overrun");
    if (!failures) printf("PASS: map names from paths accept plain .map names in any case and refuse everything else\n");
    return failures ? 1 : 0;
}
