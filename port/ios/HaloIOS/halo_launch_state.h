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

#include <stdio.h>
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
        "guest boot environment", "guest thread", "guest entering", "nonjb ", "first frame"
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

/* A short history of runs that ended badly, kept in Documents/Halo/start-history.txt. Each launch reads what the run before it left
 * behind, and the launch itself then overwrites that, so without a history the step where a run stopped is lost as soon as the app
 * is opened again. Only endings worth knowing about are recorded: a crash, a start that stopped without a report, and a run that was
 * going normally when it stopped without a report. Going to the background and a normal exit are not.
 * `stamp` is the launch time as text. Returns 1 if a line was written, 0 if there is nothing to record. */
static inline int halo_launch_history_line(const char *stamp, const char *phase, int crash_file, char *out, size_t size)
{
    const char *what;
    int n;

    if (!size)
        return 0;
    out[0] = 0;
    if (crash_file)
        what = "the app crashed and wrote a crash report";
    else if (halo_phase_is_startup(phase))
        what = "stopped without a report (the system may have ended it)";
    else if (phase && !strncmp(phase, HALO_PHASE_RUNNING_OK, strlen(HALO_PHASE_RUNNING_OK)))
        what = "was running normally, then stopped without a report (the system may have ended it)";
    else
        return 0;
    n = snprintf(out, size, "%s  launch: the previous run's last step was '%s' - %s\n",
                 stamp && *stamp ? stamp : "?", phase && *phase ? phase : "unknown", what);
    return n > 0;
}

/* `existing` followed by `line`, keeping only the newest `max_lines` lines. Never overflows `out`; returns the length written. */
static inline size_t halo_launch_history_append(const char *existing, const char *line, int max_lines, char *out, size_t size)
{
    const char *start = existing ? existing : "";
    size_t used, n;
    int lines = 0;

    if (!size)
        return 0;
    for (const char *p = start; *p; p++)
        if (*p == '\n')
            lines++;
    if (*start && start[strlen(start) - 1] != '\n')
        lines++;
    while (lines > max_lines - 1 && *start)
    {
        const char *newline = strchr(start, '\n');
        start = newline ? newline + 1 : start + strlen(start);
        lines--;
    }
    n = strlen(start);
    if (n > size - 1)
    {
        start += n - (size - 1);
        n = size - 1;
    }
    memcpy(out, start, n);
    used = n;
    if (used && out[used - 1] != '\n' && used + 1 < size)
        out[used++] = '\n';
    n = line ? strlen(line) : 0;
    if (n > size - 1 - used)
        n = size - 1 - used;
    memcpy(out + used, line, n);
    used += n;
    out[used] = 0;
    return used;
}

#endif
