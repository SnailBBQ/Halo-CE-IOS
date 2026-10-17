#include <stdio.h>
#include <stdlib.h>
#include "halo_mods_state.h"

static int failures;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, m); failures++; } } while (0)

static char list[16][HMS_TEXT];

int main(void)
{
    int n;
    char one[64];

    n = hms_strings("order = [\"german\", \"hd_audio\",\n  \"hd_textures\"]\ndisabled = [\"hd_textures\"]\n", "order", list, 16);
    CHECK(n == 3 && !strcmp(list[0], "german") && !strcmp(list[2], "hd_textures"), "a list over two lines");
    n = hms_strings("order = []\ndisabled = [\"a\"]\n", "disabled", list, 16);
    CHECK(n == 1 && !strcmp(list[0], "a"), "an empty list before it does not matter");
    CHECK(hms_strings("order = []\n", "order", list, 16) == 0, "an empty list");
    CHECK(hms_strings("name = \"x\"\n", "order", list, 16) == 0, "a missing key");
    n = hms_strings("# comment\nname = \"High-res \\\"audio\\\"\"   # trailing\nversion='1.0'\n", "name", list, 16);
    CHECK(n == 1 && !strcmp(list[0], "High-res \"audio\""), "escapes and a trailing comment");
    n = hms_strings("version='1.0'\n", "version", list, 16);
    CHECK(n == 1 && !strcmp(list[0], "1.0"), "a literal string");
    n = hms_strings("name = \"caf\\u00e9 \xe2\x9c\x93\"\n", "name", list, 16);
    CHECK(n == 1 && !strcmp(list[0], "caf\xc3\xa9 \xe2\x9c\x93"), "\\u escapes become UTF-8 and raw UTF-8 passes");
    CHECK(hms_strings("[extra]\nname = \"x\"\n", "name", list, 16) == 0, "keys under a table header are not top level");
    n = hms_strings("authors = [\"A\", \"B\"] # two\nname=\"n\"\n", "authors", list, 16);
    CHECK(n == 2 && !strcmp(list[1], "B"), "a list with a comment after it");
    n = hms_strings("namespace = \"no\"\nname = \"yes\"\n", "name", list, 16);
    CHECK(n == 1 && !strcmp(list[0], "yes"), "a key that merely starts the same is skipped");
    hms_string("format = 1\n", "name", one, sizeof(one), "fallback");
    CHECK(!strcmp(one, "fallback"), "a fallback");
    n = hms_strings("order = [\"a\", \"b\"]\n", "order", list, 1);
    CHECK(n == 1, "the limit holds");

    CHECK(hms_folder_ok("hd_audio") && !hms_folder_ok("") && !hms_folder_ok("..") && !hms_folder_ok("a/b") && !hms_folder_ok("a\\b"), "folder names");
    {
        char name[80];
        memset(name, 'a', 63); name[63] = 0;
        CHECK(hms_folder_ok(name), "63 bytes is allowed");
        name[63] = 'a'; name[64] = 0;
        CHECK(!hms_folder_ok(name), "64 bytes is not");
    }

    {
        char folders[5][HMS_NAME] = { "hd_textures", "German", "fixes", "hd_audio", "zeta" };
        char kept[2][HMS_TEXT] = { "hd_audio", "GERMAN" };
        int order[8];
        n = hms_order(folders, 5, kept, 2, order);
        /* kept first: hd_audio, German; fixes has nothing placed before it so goes first; hd_textures and zeta go right
         * after hd_audio, the placed mod before them in alphabetical order (German is later in the file) */
        CHECK(n == 5, "every mod is placed once");
        {
            const char *want[5] = { "fixes", "hd_audio", "hd_textures", "zeta", "German" };
            int ok = 1;
            for (int i = 0; i < 5; i++) if (strcmp(folders[order[i]], want[i])) ok = 0;
            if (!ok) { for (int i = 0; i < 5; i++) printf(" %s", folders[order[i]]); printf("\n"); }
            CHECK(ok, "unlisted mods go after the mod before them in the default order");
        }
        n = hms_order(folders, 5, kept, 0, order);
        CHECK(n == 5 && !strcmp(folders[order[0]], "fixes") && !strcmp(folders[order[1]], "German") && !strcmp(folders[order[4]], "zeta"), "no file: alphabetical, not case-sensitive");
        {
            char dup[3][HMS_TEXT] = { "fixes", "fixes", "gone" };
            n = hms_order(folders, 5, dup, 3, order);
            CHECK(n == 5, "a repeated or missing name in the file changes nothing");
        }
    }

    {
        char names[3][HMS_NAME] = { "german", "hd \"audio\"", "z" };
        int off[3] = { 0, 1, 1 };
        char text[1024], back[3][HMS_TEXT];
        size_t length = hms_serialize(text, sizeof(text), names, off, 3);
        CHECK(length > 0 && strstr(text, "order = [\"german\", \"hd \\\"audio\\\"\", \"z\"]\n") && strstr(text, "disabled = [\"hd \\\"audio\\\"\", \"z\"]\n"), "load_order.toml as the game writes it");
        n = hms_strings(text, "order", back, 3);
        CHECK(n == 3 && !strcmp(back[1], "hd \"audio\""), "what is written reads back");
        n = hms_strings(text, "disabled", back, 3);
        CHECK(n == 2 && !strcmp(back[1], "z"), "the disabled list reads back");
        CHECK(hms_serialize(text, 20, names, off, 3) == 0, "a buffer too small is refused");
        {
            int none[3] = { 0, 0, 0 };
            hms_serialize(text, sizeof(text), names, none, 3);
            CHECK(strstr(text, "disabled = []\n") != NULL, "nothing off");
        }
    }
    if (failures) return 1;
    puts("PASS: mods state reads mod.toml and load_order.toml and writes the load order the game's own Mods menu writes");
    return 0;
}
