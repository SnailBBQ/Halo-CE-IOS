#ifndef HALO_LAUNCH_STATE_H
#define HALO_LAUNCH_STATE_H

/*
 * Did the last start fail? The app writes a phase name to a small file as it starts the game and
 * marks it "running ok" once the game has been up for a while; a crash handler writes crash.txt. At
 * the next launch this decides, in plain C so tools/tests/test_ios_launch_state.c can check it:
 * was the last start a failure, and which start mode (normal or safe) to use now.
 *
 * Safe start turns off what can be switched off at run time and has never been proved on a device:
 * sound, internet play, smooth 60 FPS, hi-res HUD and text, and the profiler.
 */

#include <string.h>

enum { HALO_SAFE_NORMAL = 0, HALO_SAFE_ON = 1 };

/* Phases written by the app. Anything else (including an empty or missing file) is "no information". */
#define HALO_PHASE_RUNNING_OK "running ok"
#define HALO_PHASE_BACKGROUND "backgrounded"
#define HALO_PHASE_EXITED "exited"

/* Phases from the first moment of a start until the game has run for a while; being stopped while in one
 * of these, without having gone to the background, means the start failed. */
static inline int halo_phase_is_startup(const char *phase)
{
    static const char *const startup[] = {
        "app launched", "engine boot", "guest start", "guest bridge", "guest image",
        "guest boot environment", "guest thread", "guest entering", "first frame"
    };

    if (!phase || !*phase)
        return 0;
    for (unsigned i = 0; i < sizeof(startup) / sizeof(startup[0]); i++)
        if (!strncmp(phase, startup[i], strlen(startup[i])))
            return 1;
    return 0;
}

/* `phase`: the last phase file's text (NULL if there was none); `crash_file`: a crash report from the last
 * run exists; `level`: the safe level the last start used. Returns the level for this start. */
static inline int halo_launch_next_level(const char *phase, int crash_file, int level)
{
    if (crash_file)
        return HALO_SAFE_ON;
    if (phase && !strncmp(phase, HALO_PHASE_RUNNING_OK, strlen(HALO_PHASE_RUNNING_OK)))
        return HALO_SAFE_NORMAL;
    if (halo_phase_is_startup(phase))
        return HALO_SAFE_ON;
    /* backgrounded, exited, or nothing known: the last start did not fail, keep the mode */
    return level == HALO_SAFE_ON ? HALO_SAFE_ON : HALO_SAFE_NORMAL;
}

/* One line for the log: what happened last time. Writes into `out` (never overflows) and returns 1 if
 * there is something worth showing. */
static inline int halo_launch_describe(const char *phase, int crash_file, char *out, size_t size)
{
    if (!size)
        return 0;
    out[0] = 0;
    if (crash_file)
        return snprintf(out, size, "previous start: the app crashed (last step: %s)", phase && *phase ? phase : "unknown") > 0;
    if (halo_phase_is_startup(phase))
        return snprintf(out, size, "previous start: stopped without a report during '%s' (the system may have ended it)", phase) > 0;
    return 0;
}

#endif
