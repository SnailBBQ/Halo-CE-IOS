#include <stdio.h>
#include "halo_settings_search.h"

static int failures;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, m); failures++; } } while (0)

int main(void)
{
    int out[HSS_COUNT], n;

    CHECK(HSS_CATEGORY_COUNT == (int)(sizeof(hss_category_names) / sizeof(hss_category_names[0])), "category names");
    for (int i = 0; i < HSS_COUNT; i++)
        CHECK(hss_entries[i].category >= 0 && hss_entries[i].category < HSS_CATEGORY_COUNT && hss_entries[i].title[0], "every entry has a title and a real category");
    n = hss_suggestions(out, HSS_COUNT);
    CHECK(n >= 8 && n <= 20, "a sensible number of suggestions");
    CHECK(hss_search("", out, HSS_COUNT) == 0 && hss_search("   ", out, HSS_COUNT) == 0, "empty query matches nothing");
    n = hss_search("mic", out, HSS_COUNT);
    CHECK(n >= 1 && !strcmp(hss_entries[out[0]].title, "Your microphone"), "mic finds the microphone");
    n = hss_search("push to talk", out, HSS_COUNT);
    CHECK(n >= 1 && !strcmp(hss_entries[out[0]].title, "Your microphone") && hss_entries[out[0]].category == 3, "push to talk finds the voice chat setting");
    n = hss_search("REVERB", out, HSS_COUNT);
    CHECK(n == 1 && !strcmp(hss_entries[out[0]].title, "Reverb"), "case does not matter");
    n = hss_search("vehicle", out, HSS_COUNT);
    CHECK(n >= 1 && !strcmp(hss_entries[out[0]].title, "Vehicle Spawner"), "vehicle finds the spawner first");
    n = hss_search("emoji", out, HSS_COUNT);
    CHECK(n >= 1 && !strcmp(hss_entries[out[0]].title, "Choose icon"), "emoji finds the icon picker");
    n = hss_search("volume", out, HSS_COUNT);
    CHECK(n >= 3, "volume matches several options");
    {
        int first = -1;
        n = hss_search("volume", out, HSS_COUNT);
        for (int i = 0; i < n; i++)
            if (!strcmp(hss_entries[out[i]].title, "Master volume")) first = i;
        CHECK(first >= 0 && first < 2, "title matches rank above keyword matches");
    }
    CHECK(hss_search("zzzz", out, HSS_COUNT) == 0, "nonsense matches nothing");
    CHECK(hss_search("audio", out, HSS_COUNT) >= 8, "a category name lists its options");
    CHECK(hss_search("tal", out, 3) <= 3, "the limit is honoured");
    n = hss_search("a", out, HSS_COUNT);
    CHECK(n > 10 && n <= HSS_COUNT, "a one letter query is cheap and bounded");
    if (failures) return 1;
    puts("PASS: settings search index finds options by title, keyword and category");
    return 0;
}
