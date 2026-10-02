#include "halo_log_classify.h"
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)
#define CAT(line, want) CHECK(halo_log_category(line) == (want), "'%s' is category %d, wanted %d", line, halo_log_category(line), want)

int main(void)
{
    /* lines copied from real device logs */
    CAT("### ERROR no DirectSound for bink", HALO_LOG_ERROR);
    CAT("### ERROR failed to open bink file ''", HALO_LOG_ERROR);
    CAT("Couldn't read map file 'd:\\cachebeta.map'", HALO_LOG_INFO);
    CAT("file_open('z:\\last_language.dat') error 0x00000002", HALO_LOG_INFO);
    CAT("checksum failed on persistent storage", HALO_LOG_ERROR);
    CAT("bind_endpoint() failed on telnet console endpoint", HALO_LOG_ERROR);
    CAT("unable to locate any movie for movie #3 (checked for all possible language variations)", HALO_LOG_ERROR);
    CAT("WARNING: object_create - 'cryotube_1' already exists", HALO_LOG_WARNING);
    CAT("local player 0, weapon (0x0), deleted unexpectedly", HALO_LOG_WARNING);
    CAT("winsock error #50: <unknown error>", HALO_LOG_NETWORK);
    CAT("starting precaching of map 'a10'", HALO_LOG_LOADING);
    CAT("[loading] done: Scripts (0.018 s)", HALO_LOG_LOADING);
    CAT("  MAP  a10.map          name=a10  build=01.10.12.2276  zlib 12345", HALO_LOG_LOADING);
    CAT("presentation rate: 28.63 FPS (299 successful drawable presents in 10.44 s; loading durations reported separately)", HALO_LOG_PERFORMANCE);
    CAT("timing render CPU (includes conversion/upload): 364 calls, 8.6 ms average, 13 thread pointer upgrades/call (overlapping categories)", HALO_LOG_PERFORMANCE);
    CAT("native scan indices: 88846 calls, 41908235 items, 31.1 ms total", HALO_LOG_PERFORMANCE);
    CAT("  fault hot spot:    33243  __emutls_get_address (0x8839fb20)", HALO_LOG_PERFORMANCE);
    CAT("pointer faults this interval by function (top 16 of 62190 total):", HALO_LOG_PERFORMANCE);
    CAT("[guest] frame 840: 267 draws, 212 immediate, 3 clears, 9 target changes; skipped 0", HALO_LOG_NOISE);
    CAT("scene: tick=517 cinematic=0 windows=1 player=0 camera=(-56.560 0.413 0.637)", HALO_LOG_NOISE);
    CAT("final back buffer: guest=0x07ed4000 texture=1 size=640x480", HALO_LOG_NOISE);
    CAT("screen fade: -1.000 (-1 disabled, 1 opaque black)", HALO_LOG_NOISE);
    CAT("FULL GUEST BLOCKED: pthread_create failed (11).", HALO_LOG_ERROR);
    CAT("Internet play: the invite link is on the clipboard", HALO_LOG_NETWORK);
    CAT("audio: could not open output (48000 Hz, 2 channels) - audio engine would not start: x (code -10868)", HALO_LOG_ERROR);
    CAT("network (system link): broadcast search failed: No route to host (errno 65). LOCAL NETWORK access may be off", HALO_LOG_ERROR);
    CAT("", HALO_LOG_INFO);
    CAT("starting main menu music", HALO_LOG_INFO);

    CHECK(fabs(halo_log_fps("presentation rate: 28.63 FPS (299 successful drawable presents in 10.44 s)") - 28.63) < 1e-9, "fps");
    CHECK(halo_log_fps("native bulk memory: 1 calls") < 0, "not an fps line");
    CHECK(fabs(halo_log_render_ms("timing render CPU (includes conversion/upload): 364 calls, 8.6 ms average, 13 thread pointer upgrades/call") - 8.6) < 1e-9, "old render line");
    CHECK(fabs(halo_log_render_ms("timing render CPU (includes conversion/upload): 364 calls, avg 8612 us, 13 thread pointer upgrades/call") - 8.612) < 1e-9, "new render line in us");
    CHECK(halo_log_render_ms("timing update: 368 calls, 0.0 ms average") < 0, "not the render line");
    CHECK(halo_log_number_after("x: abc", "x:") < 0, "no number gives -1");
    CHECK(halo_log_number_after("nothing here", "x:") < 0, "missing marker gives -1");

    CHECK(halo_log_expected("### ERROR no DirectSound for bink"), "bink is expected");
    CHECK(halo_log_expected("Couldn't read map file 'd:\\cachebeta.map'"), "cachebeta map is expected");
    CHECK(halo_log_expected("file_open('z:\\lastprof.txt') error 0x00000002"), "lastprof is expected");
    CHECK(halo_log_expected("winsock error #50: <unknown error>"), "winsock 50 is expected");
    CHECK(!halo_log_expected("checksum failed on persistent storage"), "a checksum failure is a real problem");
    CHECK(!halo_log_expected("FULL GUEST BLOCKED: pthread_create failed (11)."), "a blocked guest is a real problem");
    CHECK(!halo_log_expected(NULL) && !halo_log_expected(""), "empty input");

    if (!failures) printf("PASS: log classification and number extraction on lines from real device logs\n");
    return failures ? 1 : 0;
}
