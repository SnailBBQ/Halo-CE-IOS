#import "halo_boot_integration.h"

#import <Foundation/Foundation.h>

#import "halo_guest_runtime.h"
#import "halo_math_slice.h"
#import "halo_gameplay_slice.h"

#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define VA_VEC_A        UINT32_C(0x80010000)
#define VA_VEC_B        UINT32_C(0x80010020)
#define VA_VEC_MID      UINT32_C(0x80010040)
#define VA_VEC_PERP     UINT32_C(0x80010060)
#define VA_POINT_A      UINT32_C(0x80010100)
#define VA_POINT_B      UINT32_C(0x80010120)
#define VA_POINT_OUT    UINT32_C(0x80010140)
#define VA_RECT_A       UINT32_C(0x80010200)
#define VA_RECT_B       UINT32_C(0x80010210)
#define VA_RECT_OUT     UINT32_C(0x80010220)
#define VA_GAMEPLAY     UINT32_C(0x81000000)
#define VA_BOOT_SCRATCH UINT32_C(0x82000000)

typedef struct halo_boot_result {
    int runtime_ok;
    int math_ok;
    int gameplay_ok;
    int content_ok;
    int committed_regions;
    unsigned map_count;
} halo_boot_result;

static void say(void (^line)(const char *), const char *fmt, ...)
{
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    line(buf);
}

static int feq(float a, float b)
{
    return fabsf(a - b) < 0.00001f;
}

static int run_math_cluster(void (^line)(const char *))
{
    int pass = 1;

    halo_real_vector3d *a = halo_guest_ptr(VA_VEC_A, sizeof(*a));
    halo_real_vector3d *b = halo_guest_ptr(VA_VEC_B, sizeof(*b));
    halo_real_vector3d *mid = halo_guest_ptr(VA_VEC_MID, sizeof(*mid));
    halo_real_vector3d *perp = halo_guest_ptr(VA_VEC_PERP, sizeof(*perp));
    halo_real_point3d *pa = halo_guest_ptr(VA_POINT_A, sizeof(*pa));
    halo_real_point3d *pb = halo_guest_ptr(VA_POINT_B, sizeof(*pb));
    halo_real_point3d *po = halo_guest_ptr(VA_POINT_OUT, sizeof(*po));
    halo_rectangle2d *ra = halo_guest_ptr(VA_RECT_A, sizeof(*ra));
    halo_rectangle2d *rb = halo_guest_ptr(VA_RECT_B, sizeof(*rb));
    halo_rectangle2d *ri = halo_guest_ptr(VA_RECT_OUT, sizeof(*ri));

    if (!a || !b || !mid || !perp || !pa || !pb || !po || !ra || !rb || !ri)
    {
        line("FAIL guest pointer resolution for math/input regions");
        return 0;
    }

    *a = (halo_real_vector3d){1.f, 2.f, 3.f};
    *b = (halo_real_vector3d){9.f, 6.f, -1.f};
    halo_vectors_interpolate(a, b, 0.25f, mid);
    halo_perpendicular3d(mid, perp);

    int ok_mid = feq(mid->i, 3.f) && feq(mid->j, 3.f) && feq(mid->k, 2.f);
    int ok_perp = feq(perp->i, 3.f) && feq(perp->j, -3.f) && feq(perp->k, 0.f);
    say(line, "%s vectors_interpolate -> {%g,%g,%g}", ok_mid ? "PASS" : "FAIL", mid->i, mid->j, mid->k);
    say(line, "%s perpendicular3d -> {%g,%g,%g}", ok_perp ? "PASS" : "FAIL", perp->i, perp->j, perp->k);
    pass &= ok_mid && ok_perp;

    *pa = (halo_real_point3d){10.f, -2.f, 4.f};
    *pb = (halo_real_point3d){14.f, 6.f, 8.f};
    halo_points_interpolate(pa, pb, 0.5f, po);
    int ok_points = feq(po->x, 12.f) && feq(po->y, 2.f) && feq(po->z, 6.f);
    say(line, "%s points_interpolate -> {%g,%g,%g}", ok_points ? "PASS" : "FAIL", po->x, po->y, po->z);
    pass &= ok_points;

    *ra = (halo_rectangle2d){0, 100, 0, 80};
    *rb = (halo_rectangle2d){50, 140, 20, 60};
    uint8_t hit = halo_intersect_rectangles2d(ra, rb, ri);
    halo_point2d p = {75, 40};
    int ok_int =
        halo_rectangle2d_width(ra) == 100 &&
        halo_rectangle2d_height(ra) == 80 &&
        hit &&
        ri->x0 == 50 && ri->x1 == 100 &&
        ri->y0 == 20 && ri->y1 == 60 &&
        halo_point2d_in_rectangle2d(ri, &p) &&
        halo_floor_log2(1024) == 10 &&
        halo_integer_square_root(144) == 12;
    say(line, "%s rect/intersection/point/log2/isqrt cluster", ok_int ? "PASS" : "FAIL");
    pass &= ok_int;

    return pass;
}

static int run_gameplay_cluster(void (^line)(const char *))
{
    halo_game_allegiance_globals *gg = halo_guest_ptr(VA_GAMEPLAY, sizeof(*gg));
    if (!gg)
    {
        line("FAIL guest pointer resolution for gameplay globals");
        return 0;
    }

    halo_gameplay_initialize_fixture(gg);
    int layout_ok =
        sizeof(halo_game_allegiance_record) == 0x12 &&
        sizeof(halo_game_allegiance_globals) == 0xB4 &&
        gg->allegiance_count == 1;
    say(line, "%s record=0x%zx globals=0x%zx guestVA=0x%08x host=%p",
        layout_ok ? "PASS" : "FAIL",
        sizeof(halo_game_allegiance_record),
        sizeof(halo_game_allegiance_globals),
        VA_GAMEPLAY, gg);

    uint8_t initially_enemy = halo_game_team_is_enemy(gg, 1, 3);
    uint8_t initially_ally = halo_game_team_is_ally(gg, 1, 3);
    uint8_t notify = 0;

    uint8_t broke1 = halo_game_allegiance_incident(
        gg, 1, 3, HALO_INCIDENT_ACCIDENT, &notify);
    uint8_t broke2 = halo_game_allegiance_incident(
        gg, 1, 3, HALO_INCIDENT_BETRAYAL, &notify);

    int16_t threshold = -1;
    int16_t incidents = halo_game_allegiance_get_incidents(gg, 1, 3, &threshold);
    uint8_t now_enemy = halo_game_team_is_enemy(gg, 1, 3);
    uint8_t still_ally = halo_game_team_is_ally(gg, 1, 3);
    uint8_t changed = halo_game_team_ally_status_changed(gg, 1, 3);

    halo_game_allegiance_provoke(gg, 1, 3);
    int16_t decay = gg->allegiances[0].current_incident_decay_time;
    halo_game_allegiance_notify_change(gg, 1, 3);
    uint8_t changed_after_ack = halo_game_team_ally_status_changed(gg, 1, 3);

    int gameplay_ok =
        !initially_enemy && initially_ally &&
        !broke1 && broke2 &&
        incidents == 4 && threshold == 3 &&
        now_enemy && still_ally &&
        changed && notify &&
        decay == 10 &&
        !changed_after_ack;

    say(line, "%s friendly->incident->betrayal->broken chain", gameplay_ok ? "PASS" : "FAIL");
    say(line, "INFO incidents=%d threshold=%d enemy=%u ally=%u decay=%d notify=%u",
        incidents, threshold, now_enemy, still_ally, decay, notify);

    return layout_ok && gameplay_ok;
}

static unsigned inspect_map_directory(NSString *path, void (^line)(const char *))
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir)
    {
        say(line, "MISS %s", path.UTF8String);
        return 0;
    }

    NSError *error = nil;
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:path error:&error];
    if (!items)
    {
        say(line, "FAIL %s (enumeration error: %s)", path.UTF8String,
            error.localizedDescription.UTF8String ?: "unknown");
        return 0;
    }

    unsigned count = 0;
    for (NSString *item in items)
    {
        if ([[item.pathExtension lowercaseString] isEqualToString:@"map"])
            ++count;
    }

    say(line, "%s %s (%u .map file%s)",
        count ? "FOUND" : "EMPTY",
        path.UTF8String,
        count,
        count == 1 ? "" : "s");
    return count;
}

static unsigned inspect_content_locations(void (^line)(const char *))
{
    NSString *bundle = [[NSBundle mainBundle] resourcePath] ?: @"";
    NSString *home = NSHomeDirectory() ?: @"";
    NSString *docs = [home stringByAppendingPathComponent:@"Documents"];

    NSArray<NSString *> *candidates = @[
        [bundle stringByAppendingPathComponent:@"maps"],
        [bundle stringByAppendingPathComponent:@"data/maps"],
        [bundle stringByAppendingPathComponent:@"Halo/maps"],
        [docs stringByAppendingPathComponent:@"Halo"],
        [docs stringByAppendingPathComponent:@"Halo/maps"],
        [docs stringByAppendingPathComponent:@"halo"],
        [docs stringByAppendingPathComponent:@"halo/maps"],
    ];

    unsigned total = 0;
    for (NSString *path in candidates)
        total += inspect_map_directory(path, line);
    return total;
}

void halo_ios_run_m20_boot_integration(void (^line)(const char *text))
{
    halo_boot_result result = {0};

    line("Halo iOS - M2.0 First Boot Integration");
    line("");
    line("Boot goal: move beyond isolated feasibility slices and push into a real startup path.");
    line("This build wires the reusable guest runtime, recovered math/gameplay slices,");
    line("and the first content-discovery gate a real boot will need.");
    line("");

    line("[1] Bring up reusable original-address guest runtime:");
    result.runtime_ok = halo_guest_runtime_init();
    if (!result.runtime_ok)
    {
        line("FAIL halo_guest_runtime_init()");
        line("");
        line("M2.0 RESULT: FAIL - original-address runtime did not initialize.");
        return;
    }

    say(line, "PASS base=%p span=0x%llx page=%zu",
        halo_guest_base_address(),
        (unsigned long long)halo_guest_span(),
        halo_guest_page_size());
    say(line, "PASS guest-visible 32-bit VA window remains original-address based");

    line("");
    line("[2] Commit boot-critical guest regions:");
    int commit_math = halo_guest_commit(VA_VEC_A, 0x400);
    int commit_gameplay = halo_guest_commit(VA_GAMEPLAY, sizeof(halo_game_allegiance_globals));
    int commit_scratch = halo_guest_commit(VA_BOOT_SCRATCH, halo_guest_page_size() * 2u);
    say(line, "%s math/input region @ 0x%08x", commit_math ? "PASS" : "FAIL", VA_VEC_A);
    say(line, "%s gameplay globals @ 0x%08x", commit_gameplay ? "PASS" : "FAIL", VA_GAMEPLAY);
    say(line, "%s boot scratch @ 0x%08x", commit_scratch ? "PASS" : "FAIL", VA_BOOT_SCRATCH);
    result.committed_regions = commit_math + commit_gameplay + commit_scratch;

    line("");
    line("[3] Recovered runtime dependency chain - math cluster:");
    result.math_ok = run_math_cluster(line);

    line("");
    line("[4] Recovered gameplay dependency chain - allegiance cluster:");
    result.gameplay_ok = run_gameplay_cluster(line);

    line("");
    line("[5] First real boot gate - content discovery:");
    line("Checking likely app-bundle and Documents locations for Halo .map content...");
    result.map_count = inspect_content_locations(line);
    result.content_ok = result.map_count > 0;
    say(line, "%s aggregate content discovery (%u total .map file%s seen)",
        result.content_ok ? "PASS" : "BLOCKED",
        result.map_count,
        result.map_count == 1 ? "" : "s");

    line("");
    line("[6] Startup integration summary:");
    say(line, "%s reusable guest runtime", result.runtime_ok ? "PASS" : "FAIL");
    say(line, "%s recovered math slice cluster", result.math_ok ? "PASS" : "FAIL");
    say(line, "%s recovered gameplay slice cluster", result.gameplay_ok ? "PASS" : "FAIL");
    say(line, "%s content discovery gate", result.content_ok ? "PASS" : "BLOCKED");

    line("");
    if (result.runtime_ok && result.math_ok && result.gameplay_ok && result.content_ok)
    {
        line("M2.0 RESULT: PASS - the project is ready to step into cache/filesystem + boot-sequence wiring.");
        line("NEXT: begin M2.1 real cache/filesystem bootstrap and startup-call-chain integration.");
    }
    else if (result.runtime_ok && result.math_ok && result.gameplay_ok)
    {
        line("M2.0 RESULT: PARTIAL PASS - core runtime slices are ready, but real boot is now blocked on content discovery.");
        line("NEXT: either package actual Halo assets for iOS bundle/Documents loading or wire the cache/filesystem layer against an existing content drop.");
    }
    else
    {
        line("M2.0 RESULT: FAIL - inspect the first failed boot stage above.");
    }

    halo_guest_runtime_shutdown();
}
