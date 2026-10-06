#ifndef HALO_VA_MAP_H
#define HALO_VA_MAP_H
/*
 * Non-Jailbreak Version (HALO_NON_JAILBREAK builds only): turns the process's list of mapped address ranges into what matters for the
 * guest arena: how much address space the process may use, where the free gaps are, and whether any whole 4 GiB-aligned 4 GiB
 * window is free. Plain C with no system calls, so tools/tests/test_ios_va_map.c checks it against made-up maps. The runtime
 * supplies the ranges (a walk of the task's memory map) and the lowest and highest addresses the system reports.
 */
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define HALO_VA_REGION_MAX 768
#define HALO_VA_GAPS 6
#define HALO_VA_MAP_WINDOW (UINT64_C(1) << 32)
#define HALO_VA_MAP_GIB ((double)(UINT64_C(1) << 30))

typedef struct HaloVaRegion { uint64_t start, size; } HaloVaRegion;
typedef struct HaloVaGap { uint64_t start, size; } HaloVaGap;

typedef struct HaloVaMapStats {
    unsigned regions;              /* mapped ranges inside the process range, after neighbours are merged */
    unsigned beyond;               /* ranges that reach above the process range (the system maps things there; they are ignored) */
    unsigned big_gaps;             /* free blocks of at least 4 GiB with any alignment */
    int truncated;                 /* the list given was cut short */
    int range_known;               /* the system reported a usable address range */
    uint64_t low, high;
    uint64_t mapped_bytes, first_start, last_end;
    HaloVaGap gaps[HALO_VA_GAPS];  /* the largest free gaps, largest first */
    unsigned gap_count;
    uint64_t free_above;           /* free space between the last mapped byte and the top of the range */
    unsigned free_windows;         /* whole 4 GiB-aligned 4 GiB windows that are free */
    uint64_t first_free_window;
} HaloVaMapStats;

static inline void halo_va_map_add_gap(HaloVaMapStats *s, uint64_t start, uint64_t end) {
    HaloVaGap gap;
    uint64_t base;
    unsigned guard = 0;
    if (end <= start) return;
    gap.start = start; gap.size = end - start;
    if (gap.size >= HALO_VA_MAP_WINDOW) s->big_gaps++;
    if (start <= UINT64_MAX - HALO_VA_MAP_WINDOW) {
        for (base = (start + HALO_VA_MAP_WINDOW - 1) & ~(HALO_VA_MAP_WINDOW - 1); base + HALO_VA_MAP_WINDOW > base && base + HALO_VA_MAP_WINDOW <= end && guard < 4096; base += HALO_VA_MAP_WINDOW, guard++) {
            if (!s->free_windows) s->first_free_window = base;
            s->free_windows++;
        }
    }
    {
        unsigned at = s->gap_count;
        if (at == HALO_VA_GAPS && gap.size <= s->gaps[HALO_VA_GAPS - 1].size) return;
        if (at == HALO_VA_GAPS) at--; else s->gap_count++;
        while (at > 0 && s->gaps[at - 1].size < gap.size) { s->gaps[at] = s->gaps[at - 1]; at--; }
        s->gaps[at] = gap;
    }
}

/* regions may be unsorted and overlapping. low and high are the lowest and highest addresses the system reports (0, 0 when it does not). */
static inline void halo_va_map_analyze(const HaloVaRegion *regions, unsigned count, int truncated, uint64_t low, uint64_t high, HaloVaMapStats *out) {
    HaloVaRegion sorted[HALO_VA_REGION_MAX], merged[HALO_VA_REGION_MAX];
    unsigned n = 0, m = 0;
    uint64_t cursor;
    memset(out, 0, sizeof(*out));
    out->truncated = truncated;
    out->range_known = high > low;
    out->low = low; out->high = high;
    for (unsigned i = 0; i < count && n < HALO_VA_REGION_MAX; i++) {
        if (!regions[i].size || regions[i].start + regions[i].size < regions[i].start) continue;      /* empty, or wraps around */
        unsigned at = n++;
        while (at > 0 && sorted[at - 1].start > regions[i].start) { sorted[at] = sorted[at - 1]; at--; }
        sorted[at] = regions[i];
    }
    for (unsigned i = 0; i < n; i++) {
        uint64_t end = sorted[i].start + sorted[i].size;
        if (m && sorted[i].start <= merged[m - 1].start + merged[m - 1].size) {
            uint64_t previous_end = merged[m - 1].start + merged[m - 1].size;
            if (end > previous_end) merged[m - 1].size = end - merged[m - 1].start;
        } else { merged[m].start = sorted[i].start; merged[m].size = sorted[i].size; m++; }
    }
    /* Only the process's own range is address space it can use. The system also maps things far above it, and a gap there is not free
       to this process: counting it once made a device that cannot hold the window report twelve of them. */
    if (out->range_known) {
        unsigned kept = 0;
        for (unsigned i = 0; i < m; i++) {
            uint64_t start = merged[i].start, end = merged[i].start + merged[i].size;
            if (end > high) out->beyond++;
            if (start < low) start = low;
            if (end > high) end = high;
            if (end <= start) continue;
            merged[kept].start = start; merged[kept].size = end - start; kept++;
        }
        m = kept;
    }
    out->regions = m;
    if (m) { out->first_start = merged[0].start; out->last_end = merged[m - 1].start + merged[m - 1].size; }
    cursor = out->range_known ? low : (m ? merged[0].start : 0);
    for (unsigned i = 0; i < m; i++) {
        out->mapped_bytes += merged[i].size;
        if (merged[i].start > cursor) halo_va_map_add_gap(out, cursor, merged[i].start);
        if (merged[i].start + merged[i].size > cursor) cursor = merged[i].start + merged[i].size;
    }
    if (out->range_known && high > cursor) { out->free_above = high - cursor; halo_va_map_add_gap(out, cursor, high); }
}

static inline void halo_va_map_text(char *out, size_t size, size_t *used, const char *fmt, ...) {
    va_list ap;
    int n;
    if (!size || *used >= size - 1) return;
    va_start(ap, fmt);
    n = vsnprintf(out + *used, size - *used, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    *used += ((size_t)n < size - *used) ? (size_t)n : size - *used - 1;
}

static inline void halo_va_map_format(const HaloVaMapStats *s, char *out, size_t size) {
    size_t used = 0;
    if (!size) return;
    out[0] = 0;
    halo_va_map_text(out, size, &used, "Address space before the game reserves anything:\n");
    if (s->range_known) halo_va_map_text(out, size, &used, "  process address range: 0x%llx to 0x%llx (%.2f GiB)\n", (unsigned long long)s->low, (unsigned long long)s->high, (double)(s->high - s->low) / HALO_VA_MAP_GIB);
    else halo_va_map_text(out, size, &used, "  process address range: not reported by the system\n");
    halo_va_map_text(out, size, &used, "  %u mapped ranges%s, %.1f MiB mapped", s->regions, s->truncated ? " (the list was cut short)" : "", (double)s->mapped_bytes / (1024.0 * 1024.0));
    if (s->beyond) halo_va_map_text(out, size, &used, " (%u more reach above the process range and are ignored)", s->beyond);
    if (s->regions) halo_va_map_text(out, size, &used, "; first at 0x%llx, last ends at 0x%llx", (unsigned long long)s->first_start, (unsigned long long)s->last_end);
    halo_va_map_text(out, size, &used, "\n");
    if (s->range_known) halo_va_map_text(out, size, &used, "  free above the highest mapped address: %.2f GiB\n", (double)s->free_above / HALO_VA_MAP_GIB);
    halo_va_map_text(out, size, &used, "  largest free gaps:");
    if (!s->gap_count) halo_va_map_text(out, size, &used, " none");
    for (unsigned i = 0; i < s->gap_count; i++)
        halo_va_map_text(out, size, &used, "%s 0x%llx (%.2f GiB)", i ? ";" : "", (unsigned long long)s->gaps[i].start, (double)s->gaps[i].size / HALO_VA_MAP_GIB);
    halo_va_map_text(out, size, &used, "\n  completely free 4 GiB-aligned 4 GiB windows: %u", s->free_windows);
    if (s->free_windows) halo_va_map_text(out, size, &used, " (first at 0x%llx)", (unsigned long long)s->first_free_window);
    halo_va_map_text(out, size, &used, "\n  free blocks of at least 4 GiB, any alignment: %u\n", s->big_gaps);
}
#endif
