/* Builds the Summary and Problems report from real device logs (tools/tests/fixtures: lines cut from the
 * ios-boot.log and debug.txt a phone produced) and from hand-made edge cases. Run from the repository root:
 *   cc -Iport/ios/HaloIOS tools/tests/test_ios_log_report.c -o t && ./t */
#include "halo_log_report.h"
#include <math.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

static char *slurp(const char *path)
{
    FILE *f = fopen(path, "rb");
    char *data;
    long n;

    if (!f) { printf("cannot open %s (run from the repository root)\n", path); exit(2); }
    fseek(f, 0, SEEK_END); n = ftell(f); fseek(f, 0, SEEK_SET);
    data = malloc((size_t)n + 1);
    if (fread(data, 1, (size_t)n, f) != (size_t)n) { printf("short read\n"); exit(2); }
    data[n] = 0;
    fclose(f);
    return data;
}

static const HrProblem *find(const HaloReport *r, const char *title)
{
    for (int i = 0; i < r->problem_count; i++) if (!strcmp(r->problems[i].title, title)) return &r->problems[i];
    return NULL;
}

int main(void)
{
    char *boot = slurp("tools/tests/fixtures/ios-boot-sample.log");
    char *game = slurp("tools/tests/fixtures/debug-sample.txt");
    static HaloReport r;

    halo_report_build(&r, boot, game);

    /* ---- the real session: campaign a10 on an iPhone, sound on, 24 maps, 50-53 FPS */
    CHECK(r.engine_started && !r.stopped, "engine running (started %d, stopped %d)", r.engine_started, r.stopped);
    CHECK(!strcmp(r.app_version, "M2.6.36"), "app version '%s'", r.app_version);
    CHECK(r.maps_found == 24 && r.maps_total == 24, "maps %d/%d", r.maps_found, r.maps_total);
    CHECK(r.fps_samples >= 5 && r.fps_average > 55 && r.fps_average < 65, "typical fps %.1f (latest sample %.1f, which is a loading spike) of %d samples", r.fps_average, r.fps, r.fps_samples);
    CHECK(r.fps > 150, "the latest raw sample really is the 213 FPS loading spike in this log (%.1f), which is why the median is used", r.fps);
    CHECK(!strcmp(halo_report_verdict(r.fps_average), "Smooth"), "verdict %s", halo_report_verdict(r.fps_average));
    CHECK(r.waiting_percent > 50 && r.waiting_percent < 70, "the game thread is mostly waiting for the display: median of the last five reports (%.1f%%)", r.waiting_percent);
    CHECK(r.profile_samples > 1000, "profile samples %d", r.profile_samples);
    CHECK(r.top_count > 0 && strstr(r.top[0], "%"), "top game functions listed (%d)", r.top_count);
    CHECK(r.mem_used_mib == -1, "an older log with no memory lines reports none");
    CHECK(r.audio_open && strstr(r.audio_text, "speaker") && r.underruns == 0, "sound: open %d '%s' underruns %u", r.audio_open, r.audio_text, r.underruns);
    CHECK(!strcmp(r.build, "Halo CE (Xbox build 2342)"), "build '%s'", r.build);
    CHECK(!strcmp(r.map, "a10"), "last map '%s'", r.map);

    /* ---- problems: the harmless Xbox messages are counted, not listed; the real ones appear once with a count */
    CHECK(r.expected_count >= 8, "expected messages counted: %d", r.expected_count);
    CHECK(find(&r, "Videos are skipped") == NULL && find(&r, "Xbox disc files are not present") == NULL, "expected messages are not problems");
    const HrProblem *checksum = find(&r, "Saved profile check failed");
    CHECK(checksum && checksum->count == 1 && checksum->severity == 1 && strstr(checksum->detail, "Playing is not affected"), "checksum problem explained");
    const HrProblem *twice = find(&r, "A map object was created twice");
    CHECK(twice && twice->count == 2, "two 'already exists' lines are one problem with count 2 (got %d)", twice ? twice->count : -1);
    CHECK(find(&r, "A weapon was removed before it existed") != NULL, "the weapon message is explained");
    CHECK(r.problem_count == 3, "exactly three real problems in a healthy session, got %d", r.problem_count);
    for (int i = 0; i < r.problem_count; i++) CHECK(r.problems[i].severity == 1, "none of them is an error: %s", r.problems[i].title);

    /* ---- a stopped engine, a failed start, a network failure and a sound failure */
    static HaloReport bad;
    const char *bad_boot =
        "M2.6.37 breadcrumb: header start=0x883d11a0\n"
        "previous start: the app crashed (last step: guest image: mapping the image span)\n"
        "  previous crash: signal=10\n"
        "  previous crash: fault_address=0x388848000\n"
        "SAFE START: sound, internet play, smooth 60 FPS, hi-res HUD and text and the profiler are off because the last start did not finish.\n"
        "audio: could not open output (48000 Hz, 2 channels) - audio engine would not start: x (code -10868)\n"
        "network (system link): broadcast search failed: No route to host (errno 65). LOCAL NETWORK access may be off: iOS Settings\n"
        "network (system link): broadcast search failed: No route to host (errno 65). LOCAL NETWORK access may be off: iOS Settings\n"
        "FULL GUEST STOPPED: the guest aborted (reason 2)\n";
    halo_report_build(&bad, bad_boot, "");
    CHECK(bad.stopped && strstr(bad.stop_reason, "STOPPED"), "stopped engine reported");
    CHECK(bad.safe_start && strstr(bad.previous_start, "crashed") && bad.crash_count == 2, "failed start reported (%d crash lines)", bad.crash_count);
    CHECK(!bad.audio_open && strstr(bad.audio_text, "could not open"), "audio failure: '%s'", bad.audio_text);
    CHECK(bad.network_count == 2, "network lines kept for the summary (%d)", bad.network_count);
    const HrProblem *net = find(&bad, "Network problem");
    CHECK(net && net->count == 2 && net->severity == 0 && strstr(net->detail, "LOCAL NETWORK"), "network problem once with count 2");
    CHECK(find(&bad, "Sound could not start") && find(&bad, "The game engine stopped"), "sound and engine problems listed");
    static HaloReport loader;
    halo_report_build(&loader, "FULL GUEST: could not map the guest image (0x88000000..0x88a00000, 10 MiB).\nFULL GUEST IMAGE: 0x88000000-0x892ea038, start=0x883d11a0\nFULL GUEST STATUS: STILL RUNNING AFTER 5 SECONDS\n", "");
    CHECK(loader.problem_count == 1 && find(&loader, "The game engine could not start") && strstr(find(&loader, "The game engine could not start")->detail, "could not map"), "a loader failure is one problem; the IMAGE and STATUS lines are not problems");
    CHECK(find(&bad, "previous start") == NULL && find(&bad, "The last start crashed") == NULL, "last-start lines go to the Summary, not the list");

    /* ---- memory report lines are measurements, never problems; a real failure is */
    static HaloReport mem;
    halo_report_build(&mem,
        "guest memory: 212 of 768 MiB of the game's address space in use (highest 301 MiB, 14 MiB free in holes), 0 failed requests\n"
        "device memory: app footprint 1873 MiB, 1190 MiB left before iOS ends the app\n", "");
    CHECK(mem.mem_used_mib == 212 && mem.mem_region_mib == 768 && mem.mem_peak_mib == 301 && mem.mem_failures == 0, "guest memory parsed: %ld of %ld peak %ld failures %ld", mem.mem_used_mib, mem.mem_region_mib, mem.mem_peak_mib, mem.mem_failures);
    CHECK(mem.device_footprint_mib == 1873 && mem.device_left_mib == 1190, "device memory parsed: %ld / %ld", mem.device_footprint_mib, mem.device_left_mib);
    CHECK(mem.problem_count == 0, "the word 'failed requests' in a healthy memory line is not a problem (%d problems)", mem.problem_count);
    halo_report_build(&mem, "guest memory: out of address space (the game asked for 131072 KiB; 760 of 768 MiB in use, 3 MiB free in holes, the largest 1 MiB)\n"
                            "guest memory: 760 of 768 MiB of the game's address space in use (highest 768 MiB, 3 MiB free in holes), 7 failed requests\n", "");
    CHECK(mem.problem_count == 1 && find(&mem, "The game ran out of memory space") && mem.mem_failures == 7, "out-of-memory is one error problem (%d problems, %ld failures)", mem.problem_count, mem.mem_failures);
    CHECK(find(&mem, "The game ran out of memory space")->severity == 0, "and an error");
    static HaloReport none;
    halo_report_build(&none, "FULL GUEST STATUS: STILL RUNNING AFTER 5 SECONDS\n", "");
    CHECK(none.mem_used_mib == -1 && none.device_left_mib == -1, "no memory report in the log gives -1");

    /* ---- where a fatal fault happened */
    static HaloReport fault;
    halo_report_build(&fault,
        "EXECUTION FAULT: guestPC=0x883d3e30 fault=0x300000010 insn=0x00000000 Rn=x8\n"
        "FAULT FUNCTION (where the program counter was):\n"
        "  in prepare_draw+0x1c4 (guest address 0x8836e2f8)\n"
        "  called from (link register) D3DDevice_DrawIndexedVertices+0x88 (guest address 0x8835a110)\n"
        "  then rasterizer_draw+0x40 (guest address 0x88123450)\n"
        "M2.6.15 RESULT: FULL GUEST REACHED AN EXECUTION/HOST BOUNDARY ABOVE.\n", "");
    CHECK(fault.fault_count == 3 && !strncmp(fault.fault[0], "in prepare_draw", 15) && strstr(fault.fault[1], "called from") && strstr(fault.fault[2], "then rasterizer_draw"), "fault frames kept (%d)", fault.fault_count);
    CHECK(fault.fault_count == 3 && strstr(fault.fault[0], "0x8836e2f8"), "with their addresses");

    /* ---- the counters of the M2.6.42 build are measurements: the 21 "problems" that screen showed were all these */
    static HaloReport counters;
    halo_report_build(&counters,
        "native uniforms: 93744 comparisons, 2813 uploads, 3272 KiB compared, 21.0 ms total; invalid native inputs 0\n"
        "native scene invalid inputs: 0; datum diagnostic fallbacks: 0\n"
        "native uniforms: 218299 comparisons, 10227 uploads, 7698 KiB compared, 28.1 ms total; invalid native inputs 0\n", "");
    CHECK(counters.problem_count == 0, "counter lines are not problems (%d)", counters.problem_count);
    halo_report_build(&counters, "native uniforms: 5 comparisons, 1 uploads, 1 KiB compared, 1.0 ms total; invalid native inputs 4\n", "");
    CHECK(counters.problem_count == 1 && counters.problems[0].severity == 1, "a counter above zero is one warning");

    /* ---- empty and hostile input */
    static HaloReport empty;
    halo_report_build(&empty, "", "");
    CHECK(!empty.engine_started && empty.fps_samples == 0 && empty.problem_count == 0 && empty.render_ms < 0 && empty.waiting_percent < 0, "empty logs give an empty report");
    halo_report_build(&empty, NULL, NULL);
    CHECK(empty.problem_count == 0, "NULL logs are fine");
    char *junk = malloc(300000);
    memset(junk, 'x', 299999); junk[299999] = 0;
    for (int i = 0; i < 299999; i += 700) junk[i] = '\n';
    halo_report_build(&empty, junk, junk);
    CHECK(empty.problem_count <= HR_MAX_PROBLEMS, "junk cannot overflow the problem list");
    free(junk);
    /* more distinct problems than room: the list stops, nothing overflows */
    char *many = malloc(40000), *w = many;
    for (int i = 0; i < 100; i++) w += sprintf(w, "ERROR: problem number %d\n", i);
    halo_report_build(&empty, many, "");
    CHECK(empty.problem_count == HR_MAX_PROBLEMS, "capped at %d (got %d)", HR_MAX_PROBLEMS, empty.problem_count);
    free(many);

    /* the median of the last five ignores a spike, and handles short and even-sized histories */
    static HaloReport med;
    halo_report_build(&med, "presentation rate: 60.0 FPS (x)\npresentation rate: 213.0 FPS (x)\npresentation rate: 59.0 FPS (x)\n", "");
    CHECK(fabs(med.fps_average - 60.0) < 0.01, "three samples 60/213/59: median 60, got %.1f", med.fps_average);
    halo_report_build(&med, "presentation rate: 30.0 FPS (x)\npresentation rate: 60.0 FPS (x)\n", "");
    CHECK(fabs(med.fps_average - 45.0) < 0.01, "two samples: their mean, got %.1f", med.fps_average);
    halo_report_build(&med, "presentation rate: 42.0 FPS (x)\n", "");
    CHECK(fabs(med.fps_average - 42.0) < 0.01, "one sample");

    /* a profile report replaces the previous one's numbers rather than adding to them */
    static HaloReport two;
    halo_report_build(&two,
        "profile: 5000 samples of the game thread (every 2 ms): 5% in game code, 95% in iOS libraries\n"
        "  profile host     60.0%  libsystem_kernel.dylib  semaphore_timedwait_trap\n"
        "profile: 4000 samples of the game thread (every 2 ms): 4% in game code, 96% in iOS libraries\n"
        "  profile host     20.0%  libsystem_kernel.dylib  semaphore_timedwait_trap\n"
        "  profile host     10.0%  libsystem_kernel.dylib  __psynch_cvwait\n"
        "  profile host      9.0%  GLEngine  <redacted>\n", "");
    CHECK(fabs(two.waiting_percent - 45.0) < 0.01 && two.profile_samples == 4000, "two profile reports (60 and 30): median 45, and the latest report's sample count: waiting %.1f samples %d", two.waiting_percent, two.profile_samples);
    CHECK(!strcmp(halo_report_verdict(31), "Smooth") && !strcmp(halo_report_verdict(22), "Playable") && !strcmp(halo_report_verdict(14), "Choppy") && !strcmp(halo_report_verdict(5), "Slow"), "verdict words");

    free(boot); free(game);
    if (!failures) printf("PASS: log report from real device logs: status, speed, session, sound, last start, and %d real problems with %d normal messages counted apart\n", r.problem_count, r.expected_count);
    return failures ? 1 : 0;
}
