#include "halo_ios_probe.h"
#include "halo_guest_runtime.h"
#include "halo_math_slice.h"
#include "halo_gameplay_slice.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

#define VA_VEC_A       UINT32_C(0x80010000)
#define VA_VEC_B       UINT32_C(0x80010020)
#define VA_VEC_MID     UINT32_C(0x80010040)
#define VA_VEC_PERP    UINT32_C(0x80010060)
#define VA_POINT_A     UINT32_C(0x80010100)
#define VA_POINT_B     UINT32_C(0x80010120)
#define VA_POINT_OUT   UINT32_C(0x80010140)
#define VA_RECT_A      UINT32_C(0x80010200)
#define VA_RECT_B      UINT32_C(0x80010210)
#define VA_RECT_OUT    UINT32_C(0x80010220)
#define VA_GAMEPLAY    UINT32_C(0x81000000)

static void say(void (^line)(const char *), const char *fmt, ...)
{
    char buf[768];
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

void halo_ios_run_combined_m12_m13_probe(void (^line)(const char *text))
{
    int pass = 1;

    line("Combined milestone: M1.2 runtime/math + M1.3 gameplay data cluster");
    line("");

    line("[1] Reusable 4 GiB original-address guest runtime:");
    if (!halo_guest_runtime_init())
    {
        line("FAIL halo_guest_runtime_init()");
        line("COMBINED RESULT: FAIL - M1.0 memory model regressed.");
        return;
    }

    say(line, "PASS base=%p span=0x%llx page=%zu",
        halo_guest_base_address(),
        (unsigned long long)halo_guest_span(),
        halo_guest_page_size());

    pass &= halo_guest_commit(VA_VEC_A, 0x400);
    pass &= halo_guest_commit(VA_GAMEPLAY, sizeof(halo_game_allegiance_globals));
    say(line, "%s guest region commits", pass ? "PASS" : "FAIL");

    line("");
    line("[2] M1.2 real_math multi-function call chain:");
    halo_real_vector3d *a = halo_guest_ptr(VA_VEC_A, sizeof(*a));
    halo_real_vector3d *b = halo_guest_ptr(VA_VEC_B, sizeof(*b));
    halo_real_vector3d *mid = halo_guest_ptr(VA_VEC_MID, sizeof(*mid));
    halo_real_vector3d *perp = halo_guest_ptr(VA_VEC_PERP, sizeof(*perp));

    if (!a || !b || !mid || !perp)
        pass = 0;
    else
    {
        *a = (halo_real_vector3d){1.f, 2.f, 3.f};
        *b = (halo_real_vector3d){9.f, 6.f, -1.f};
        halo_vectors_interpolate(a, b, 0.25f, mid);
        halo_perpendicular3d(mid, perp);

        int ok_mid = feq(mid->i, 3.f) && feq(mid->j, 3.f) && feq(mid->k, 2.f);
        int ok_perp = feq(perp->i, 3.f) && feq(perp->j, -3.f) && feq(perp->k, 0.f);
        say(line, "%s vectors_interpolate -> {%g,%g,%g}",
            ok_mid ? "PASS" : "FAIL", mid->i, mid->j, mid->k);
        say(line, "%s perpendicular3d -> {%g,%g,%g}",
            ok_perp ? "PASS" : "FAIL", perp->i, perp->j, perp->k);
        pass &= ok_mid && ok_perp;
    }

    halo_real_point3d *pa = halo_guest_ptr(VA_POINT_A, sizeof(*pa));
    halo_real_point3d *pb = halo_guest_ptr(VA_POINT_B, sizeof(*pb));
    halo_real_point3d *po = halo_guest_ptr(VA_POINT_OUT, sizeof(*po));
    if (!pa || !pb || !po)
        pass = 0;
    else
    {
        *pa = (halo_real_point3d){10.f, -2.f, 4.f};
        *pb = (halo_real_point3d){14.f, 6.f, 8.f};
        halo_points_interpolate(pa, pb, 0.5f, po);
        int ok = feq(po->x, 12.f) && feq(po->y, 2.f) && feq(po->z, 6.f);
        say(line, "%s points_interpolate -> {%g,%g,%g}",
            ok ? "PASS" : "FAIL", po->x, po->y, po->z);
        pass &= ok;
    }

    line("");
    line("[3] M1.2 real integer_math group:");
    halo_rectangle2d *ra = halo_guest_ptr(VA_RECT_A, sizeof(*ra));
    halo_rectangle2d *rb = halo_guest_ptr(VA_RECT_B, sizeof(*rb));
    halo_rectangle2d *ri = halo_guest_ptr(VA_RECT_OUT, sizeof(*ri));
    if (!ra || !rb || !ri)
        pass = 0;
    else
    {
        *ra = (halo_rectangle2d){0, 100, 0, 80};
        *rb = (halo_rectangle2d){50, 140, 20, 60};
        uint8_t hit = halo_intersect_rectangles2d(ra, rb, ri);
        halo_point2d p = {75, 40};

        int ok =
            halo_rectangle2d_width(ra) == 100 &&
            halo_rectangle2d_height(ra) == 80 &&
            hit &&
            ri->x0 == 50 && ri->x1 == 100 &&
            ri->y0 == 20 && ri->y1 == 60 &&
            halo_point2d_in_rectangle2d(ri, &p) &&
            halo_floor_log2(1024) == 10 &&
            halo_integer_square_root(144) == 12;

        say(line, "%s rect/intersection/point/log2/isqrt cluster", ok ? "PASS" : "FAIL");
        pass &= ok;
    }

    line("");
    line("[4] Guest runtime cross-page + read/write API:");
    size_t page = halo_guest_page_size();
    halo_guest_va_t cross_va = UINT32_C(0x82000000) + (uint32_t)page - 8;
    uint8_t pattern[32], copy[32];
    for (unsigned i = 0; i < sizeof(pattern); ++i)
        pattern[i] = (uint8_t)(i ^ 0xA5);
    memset(copy, 0, sizeof(copy));

    int cross_ok =
        halo_guest_commit(cross_va, sizeof(pattern)) &&
        halo_guest_write(cross_va, pattern, sizeof(pattern)) &&
        halo_guest_read(cross_va, copy, sizeof(copy)) &&
        memcmp(pattern, copy, sizeof(pattern)) == 0;
    say(line, "%s 32-byte guest transfer crossing a %zu-byte page boundary",
        cross_ok ? "PASS" : "FAIL", page);
    pass &= cross_ok;

    line("");
    line("[5] M1.3 recovered game_allegiance data layout:");
    halo_game_allegiance_globals *gg =
        halo_guest_ptr(VA_GAMEPLAY, sizeof(*gg));
    if (!gg)
        pass = 0;
    else
    {
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
        pass &= layout_ok;
    }

    line("");
    line("[6] M1.3 gameplay allegiance state-machine chain:");
    if (gg)
    {
        uint8_t initially_enemy = halo_game_team_is_enemy(gg, 1, 3);
        uint8_t initially_ally = halo_game_team_is_ally(gg, 1, 3);
        uint8_t notify = 0;

        uint8_t broke1 = halo_game_allegiance_incident(
            gg, 1, 3, HALO_INCIDENT_ACCIDENT, &notify);
        uint8_t broke2 = halo_game_allegiance_incident(
            gg, 1, 3, HALO_INCIDENT_BETRAYAL, &notify);

        int16_t threshold = -1;
        int16_t incidents = halo_game_allegiance_get_incidents(
            gg, 1, 3, &threshold);
        uint8_t now_enemy = halo_game_team_is_enemy(gg, 1, 3);
        uint8_t still_ally = halo_game_team_is_ally(gg, 1, 3);
        uint8_t changed = halo_game_team_ally_status_changed(gg, 1, 3);

        halo_game_allegiance_provoke(gg, 1, 3);
        int16_t decay = gg->allegiances[0].current_incident_decay_time;
        halo_game_allegiance_notify_change(gg, 1, 3);
        uint8_t changed_after_ack =
            halo_game_team_ally_status_changed(gg, 1, 3);

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
        pass &= gameplay_ok;
    }

    line("");
    line("[7] Combined stress pass:");
    int stress_ok = 1;
    if (a && b && mid && perp && gg)
    {
        for (int i = 0; i < 100000; ++i)
        {
            float t = (float)(i & 255) / 255.f;
            halo_vectors_interpolate(a, b, t, mid);
            halo_perpendicular3d(mid, perp);
            if (!isfinite(mid->i) || !isfinite(perp->j))
            {
                stress_ok = 0;
                break;
            }
        }
    }
    else
        stress_ok = 0;

    say(line, "%s 100000 real-math call-chain iterations", stress_ok ? "PASS" : "FAIL");
    pass &= stress_ok;

    line("");
    line("[8] Integration boundary summary:");
    line("PASS guest memory is now a reusable runtime module rather than probe-local code.");
    line("PASS several recovered real_math/integer_math routines execute in one native build.");
    line("PASS a recovered gameplay state structure lives and mutates inside original-address guest memory.");
    line("INFO the gameplay slice omits the original AI notification callback on purpose.");
    line("INFO full-game boot still requires wiring real globals, allocators, platform services, and larger source dependency graphs.");

    line("");
    if (pass)
    {
        line("M1.2 RESULT: PASS");
        line("M1.3 RESULT: PASS");
        line("COMBINED RESULT: PASS - reusable guest runtime + math cluster + gameplay state cluster are viable.");
        line("NEXT: begin a real startup/boot integration build instead of another isolated feasibility slice.");
    }
    else
    {
        line("COMBINED RESULT: FAIL - inspect the first failed subsystem above.");
    }

    halo_guest_runtime_shutdown();
}
