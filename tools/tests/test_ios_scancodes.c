#include "halo_scancodes.h"
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

int main(void)
{
    /* SDL3's numbers and names for the keys the game binds by default */
    struct { int code; const char *name; } known[] = { {4,"A"},{22,"S"},{26,"W"},{7,"D"},{29,"Z"},{30,"1"},{39,"0"},{40,"Return"},{41,"Escape"},{43,"Tab"},{44,"Space"},
        {58,"F1"},{69,"F12"},{79,"Right"},{80,"Left"},{81,"Down"},{82,"Up"},{224,"Left Ctrl"},{225,"Left Shift"},{226,"Left Alt"},{228,"Right Ctrl"},{231,"Right GUI"} };
    for (unsigned i = 0; i < sizeof(known) / sizeof(known[0]); i++)
        CHECK(!strcmp(hsc_name(known[i].code), known[i].name) && hsc_from_name(known[i].name) == known[i].code, "%s", known[i].name);

    /* every key round-trips, and no two keys share a number or a name */
    for (int i = 0; i < HSC_COUNT; i++)
    {
        CHECK(hsc_from_name(hsc_keys[i].name) == hsc_keys[i].code, "round trip of %s", hsc_keys[i].name);
        for (int j = i + 1; j < HSC_COUNT; j++)
            CHECK(hsc_keys[i].code != hsc_keys[j].code && !hsc_equal_nocase(hsc_keys[i].name, hsc_keys[j].name), "%s and %s clash", hsc_keys[i].name, hsc_keys[j].name);
    }
    /* names are matched without regard to case, as SDL does */
    CHECK(hsc_from_name("w") == 26 && hsc_from_name("SPACE") == 44 && hsc_from_name("left ctrl") == 224 && hsc_from_name("PAGEDOWN") == 78 && hsc_from_name("keypad enter") == 88, "case");
    /* not keys: empty, unknown, near misses, silly numbers */
    CHECK(hsc_from_name(NULL) == 0 && hsc_from_name("") == 0 && hsc_from_name("Banana") == 0 && hsc_from_name("Space ") == 0 && hsc_from_name("Left") == 80 && hsc_from_name("Lef") == 0, "unknown names give 0");
    CHECK(!strcmp(hsc_name(0), "") && !strcmp(hsc_name(-1), "") && !strcmp(hsc_name(3), "") && !strcmp(hsc_name(232), "") && !strcmp(hsc_name(100000), ""), "unknown numbers give an empty name");
    char longname[300]; memset(longname, 'a', sizeof longname); longname[299] = 0;
    CHECK(hsc_from_name(longname) == 0, "a very long name is not a key");
    /* the table is sorted into SDL's order by number is not required, but the letters are the contiguous run 4..29 */
    for (int c = 4; c <= 29; c++) CHECK(strlen(hsc_name(c)) == 1 && hsc_name(c)[0] == 'A' + (c - 4), "letter %d", c);
    for (int c = 58; c <= 69; c++) CHECK(hsc_name(c)[0] == 'F', "function key %d", c);
    if (!failures) printf("PASS: key names: SDL3 numbers and names, round trip of every key, any-case lookup, unknown input\n");
    return failures ? 1 : 0;
}
