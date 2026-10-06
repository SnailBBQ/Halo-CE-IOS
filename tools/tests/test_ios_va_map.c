/* The Non-Jailbreak Version's address-space map analysis (halo_va_map.h) against made-up memory maps: merging, gaps, whole free 4 GiB
   windows, an unknown range, hostile input and safe formatting. */
#include <stdlib.h>
#include "halo_va_map.h"

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)
#define G UINT64_C(0x40000000)      /* 1 GiB */
static HaloVaRegion R(uint64_t start, uint64_t size) { HaloVaRegion r = { start, size }; return r; }

static void test_empty_and_open(void) {
    HaloVaMapStats s;
    halo_va_map_analyze(NULL, 0, 0, 0x4000, 16 * G, &s);
    CHECK(s.regions == 0 && s.range_known && s.free_above == 16 * G - 0x4000 && s.gap_count == 1 && s.gaps[0].start == 0x4000, "an empty map is one gap (%u regions)", s.regions);
    CHECK(s.free_windows == 3 && s.first_free_window == 4 * G, "windows in a gap from 0x4000 to 16 GiB: %u first 0x%llx", s.free_windows, (unsigned long long)s.first_free_window);
    halo_va_map_analyze(NULL, 0, 0, 0, 0, &s);
    CHECK(!s.range_known && s.gap_count == 0 && s.free_windows == 0 && s.mapped_bytes == 0, "no map and no range: nothing to report");
}

static void test_typical_stock_install(void) {
    /* page zero, the app image, and the system's shared libraries; the process may use up to 12 GiB */
    HaloVaRegion list[] = { R(0, 4 * G), R(4 * G, 0x400000), R(6 * G, 4 * G) };
    HaloVaMapStats s;
    halo_va_map_analyze(list, 3, 0, 0x4000, 12 * G, &s);
    CHECK(s.regions == 2 && s.mapped_bytes == (4 * G - 0x4000) + 0x400000 + 4 * G, "page zero and the app image are adjacent, so they merge, and only the part inside the range counts: %u ranges, mapped %llu", s.regions, (unsigned long long)s.mapped_bytes);
    CHECK(s.free_above == 2 * G && s.free_windows == 0, "nothing aligned and free: above=%llu windows=%u", (unsigned long long)s.free_above, s.free_windows);
    CHECK(s.gap_count == 2 && s.gaps[0].size == 2 * G && s.gaps[0].start == 10 * G && s.gaps[1].start == 4 * G + 0x400000 && s.gaps[1].size == 2 * G - 0x400000, "gaps largest first (%u)", s.gap_count);
}

static void test_free_window(void) {
    HaloVaRegion list[] = { R(0, 4 * G), R(4 * G, 0x400000) };
    HaloVaMapStats s;
    halo_va_map_analyze(list, 2, 0, 0x4000, 16 * G, &s);
    CHECK(s.free_windows == 2 && s.first_free_window == 8 * G, "free windows at 8 and 12 GiB: %u first 0x%llx", s.free_windows, (unsigned long long)s.first_free_window);
    halo_va_map_analyze(list, 2, 0, 0x4000, 12 * G, &s);
    CHECK(s.free_windows == 1 && s.first_free_window == 8 * G, "one window fits below 12 GiB: %u", s.free_windows);
    halo_va_map_analyze(list, 2, 0, 0x4000, 11 * G, &s);
    CHECK(s.free_windows == 0, "a gap one GiB short holds none");
}

static void test_merging_and_hostile_input(void) {
    HaloVaMapStats sorted_stats, messy_stats;
    HaloVaRegion tidy[] = { R(0, 4 * G), R(4 * G, 3 * G), R(9 * G, G) };
    HaloVaRegion messy[] = { R(9 * G, G), R(5 * G, 2 * G), R(0, 4 * G), R(4 * G, 2 * G), R(0, 0), R(UINT64_MAX - 100, 4096), R(9 * G + 0x1000, 0x2000) };
    halo_va_map_analyze(tidy, 3, 0, 0x4000, 16 * G, &sorted_stats);
    halo_va_map_analyze(messy, 7, 0, 0x4000, 16 * G, &messy_stats);
    CHECK(sorted_stats.regions == 2 && messy_stats.regions == sorted_stats.regions, "overlapping and adjacent ranges merge (%u vs %u)", messy_stats.regions, sorted_stats.regions);
    CHECK(messy_stats.mapped_bytes == sorted_stats.mapped_bytes && messy_stats.free_above == sorted_stats.free_above && messy_stats.free_windows == sorted_stats.free_windows, "unsorted, overlapping, empty and wrapping ranges give the same answer");
    CHECK(messy_stats.first_start == 0x4000 && messy_stats.last_end == 10 * G, "extents 0x%llx..0x%llx", (unsigned long long)messy_stats.first_start, (unsigned long long)messy_stats.last_end);
    {   /* far more ranges than the limit are cut without overrunning anything */
        HaloVaRegion* many = malloc(sizeof(HaloVaRegion) * (HALO_VA_REGION_MAX + 50)); HaloVaMapStats s;
        for (unsigned i = 0; i < HALO_VA_REGION_MAX + 50; i++) many[i] = R((uint64_t)i * 0x10000, 0x8000);
        halo_va_map_analyze(many, HALO_VA_REGION_MAX + 50, 1, 0, 0, &s);
        CHECK(s.regions == HALO_VA_REGION_MAX && s.truncated, "a full list is cut at %d (%u)", HALO_VA_REGION_MAX, s.regions);
        free(many);
    }
}

static void test_unknown_range(void) {
    HaloVaRegion list[] = { R(0, 4 * G), R(12 * G, G) };
    HaloVaMapStats s;
    halo_va_map_analyze(list, 2, 0, 0, 0, &s);
    CHECK(!s.range_known && s.free_above == 0 && s.gap_count == 1 && s.gaps[0].start == 4 * G && s.gaps[0].size == 8 * G && s.free_windows == 2, "only the gap between mapped ranges counts when the top is unknown (%u windows)", s.free_windows);
}

static void test_gap_ranking(void) {
    HaloVaRegion list[10]; HaloVaMapStats s;
    for (unsigned i = 0; i < 10; i++) list[i] = R((uint64_t)i * 4 * G, G / 2);
    /* gaps are 3.5 GiB each: all equal; make one larger and one tiny */
    list[5].start += G; list[6].start += 2 * G;
    halo_va_map_analyze(list, 10, 0, 0, 0, &s);
    CHECK(s.gap_count == HALO_VA_GAPS, "only the largest %d gaps are kept (%u)", HALO_VA_GAPS, s.gap_count);
    for (unsigned i = 1; i < s.gap_count; i++) CHECK(s.gaps[i - 1].size >= s.gaps[i].size, "gaps are ordered largest first");
}

static void test_the_process_range_limits_what_is_free(void) {
    /* the shape of a real log: iPhone 14 Plus, iOS 16.2, signed with a free account. The process may use 4.007 to 15.375 GiB; the system also
       maps things far above that, and the gap between those is not free address space for the process. */
    uint64_t low = 4 * G + 0x76c000, high = 15 * G + 3 * G / 8;
    HaloVaRegion list[] = { R(low, 4 * G + G / 4 - low), R(5 * G + 3 * G / 4, 4 * G + 3 * G / 4), R(16 * G + G / 2, G / 4), R(96 * G, 16 * G) };
    HaloVaMapStats s; char text[1536];
    halo_va_map_analyze(list, 4, 0, low, high, &s);
    CHECK(s.regions == 2 && s.beyond == 2, "only the two ranges inside the process range count (%u, %u beyond)", s.regions, s.beyond);
    CHECK(s.mapped_bytes == (4 * G + G / 4 - low) + 4 * G + 3 * G / 4, "mapped bytes leave out what lies above the range (%llu)", (unsigned long long)s.mapped_bytes);
    CHECK(s.free_windows == 0, "no aligned window fits: [12, 16) GiB runs past the limit at 15.375 GiB (%u windows)", s.free_windows);
    CHECK(s.big_gaps == 1 && s.gaps[0].start == 10 * G + G / 2 && s.gaps[0].size == high - (10 * G + G / 2), "one free block of at least 4 GiB, from 10.5 GiB to the limit (%u blocks, first 0x%llx, %.3f GiB)", s.big_gaps, (unsigned long long)s.gaps[0].start, (double)s.gaps[0].size / G);
    CHECK(s.free_above == high - (10 * G + G / 2), "the free space above the highest mapped range stops at the limit (%llu)", (unsigned long long)s.free_above);
    halo_va_map_format(&s, text, sizeof(text));
    CHECK(strstr(text, "completely free 4 GiB-aligned 4 GiB windows: 0") && strstr(text, "free blocks of at least 4 GiB, any alignment: 1") && strstr(text, "2 more reach above the process range and are ignored") && !strstr(text, "windows: 0 (first at"), "report:\n%s", text);
    /* the same device with a process range that reached 16 GiB would have its window */
    halo_va_map_analyze(list, 4, 0, low, 16 * G, &s);
    CHECK(s.free_windows == 1 && s.first_free_window == 12 * G, "with the limit at 16 GiB the window at 12 GiB is whole (%u windows, first 0x%llx)", s.free_windows, (unsigned long long)s.first_free_window);
    /* a free block of 4.5 GiB is a block of at least 4 GiB, but it holds an aligned window only if one fits inside it */
    halo_va_map_analyze(list, 4, 0, low, 15 * G, &s);
    CHECK(s.free_windows == 0 && s.big_gaps == 1 && s.gaps[0].size == 15 * G - (10 * G + G / 2), "a limit of 15 GiB leaves a 4.5 GiB block with no aligned window in it (%u blocks, %u windows)", s.big_gaps, s.free_windows);
}

static void test_format(void) {
    HaloVaRegion list[] = { R(0, 4 * G), R(4 * G, 0x400000), R(6 * G, 4 * G) };
    HaloVaMapStats s; char text[1024];
    halo_va_map_analyze(list, 3, 0, 0x4000, 12 * G, &s);
    halo_va_map_format(&s, text, sizeof(text));
    CHECK(strstr(text, "process address range: 0x4000 to 0x300000000 (12.00 GiB)") && strstr(text, "2 mapped ranges") && strstr(text, "free above the highest mapped address: 2.00 GiB") && strstr(text, "completely free 4 GiB-aligned 4 GiB windows: 0"), "report:\n%s", text);
    halo_va_map_analyze(list, 3, 1, 0, 0, &s); halo_va_map_format(&s, text, sizeof(text));
    CHECK(strstr(text, "not reported by the system") && strstr(text, "(the list was cut short)"), "report for an unknown range:\n%s", text);
    halo_va_map_analyze(NULL, 0, 0, 0x4000, 16 * G, &s); halo_va_map_format(&s, text, sizeof(text));
    CHECK(strstr(text, "windows: 3 (first at 0x100000000)"), "report with free windows:\n%s", text);
    for (size_t size = 0; size <= 200; size += (size < 8 ? 1 : 29)) {
        unsigned char guarded[300];
        memset(guarded, 0xA5, sizeof(guarded));
        halo_va_map_format(&s, (char *)guarded, size);
        for (size_t i = size; i < sizeof(guarded); i++) if (guarded[i] != 0xA5) { CHECK(0, "buffer of %zu bytes was overrun at %zu", size, i); break; }
        if (size) CHECK(memchr(guarded, 0, size) != NULL, "buffer of %zu bytes is not terminated", size);
    }
}

int main(void) {
    test_empty_and_open(); test_typical_stock_install(); test_free_window(); test_merging_and_hostile_input(); test_unknown_range(); test_gap_ranking(); test_the_process_range_limits_what_is_free(); test_format();
    if (!failures) printf("PASS: the address-space map analysis merges ranges, finds the largest free gaps and whole free 4 GiB-aligned windows, copes with an unknown range and hostile input, and formats safely\n");
    return failures ? 1 : 0;
}
