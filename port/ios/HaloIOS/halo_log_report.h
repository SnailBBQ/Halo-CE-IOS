#ifndef HALO_LOG_REPORT_H
#define HALO_LOG_REPORT_H

/*
 * Turns the two raw logs (ios-boot.log from the app, debug.txt from the game) into the two screens the
 * player sees, in plain C so tools/tests/test_ios_log_report.c can run it on real device logs:
 *
 *   Summary  - is it running, how fast, where the time goes, which map, sound, multiplayer, how the last start went
 *   Problems - what went wrong, in plain words, once each with a count; the messages that are normal on iOS
 *              are counted separately and never shown as problems
 */

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "halo_log_classify.h"

#define HR_MAX_PROBLEMS 24
#define HR_MAX_TOP 6
#define HR_TEXT 200

typedef struct
{
    int severity;             /* 0 error, 1 warning */
    int count;
    char title[96];
    char detail[HR_TEXT];
} HrProblem;

typedef struct
{
    /* status */
    int engine_started;
    int stopped;
    char stop_reason[HR_TEXT];
    char app_version[24];     /* "M2.6.37" */

    /* speed */
    int fps_samples;
    double fps;               /* the latest */
    double fps_average;       /* the median of the latest five intervals: one loading spike does not move it */
    double render_ms;         /* CPU time to draw a frame, -1 if not reported */
    double waiting_percent;   /* share of the game thread's samples spent waiting (idle), -1 if no profile */
    int profile_samples;
    char top[HR_MAX_TOP][100];
    int top_count;

    /* session */
    char build[48];           /* "Halo CE (Xbox build 2342)" */
    char map[48];             /* the last map the game loaded */
    int maps_found, maps_total;

    /* sound and network */
    int audio_open;
    char audio_text[HR_TEXT];
    unsigned underruns;
    char network[4][HR_TEXT];
    int network_count;

    /* how the last start went */
    char previous_start[HR_TEXT];
    char crash[3][100];
    int crash_count;
    int safe_start;

    /* problems */
    HrProblem problems[HR_MAX_PROBLEMS];
    int problem_count;
    int expected_count;       /* messages that are normal on iOS */
} HaloReport;

static inline void hr_copy(char *out, size_t size, const char *text)
{
    size_t n = 0;

    while (text && text[n] && n + 1 < size)
    {
        out[n] = text[n];
        n++;
    }
    out[n] = 0;
}

/* the line without a leading game-log time stamp ("10.02.26 22:00:15  ") or leading blanks */
static inline const char *hr_message(const char *line)
{
    const char *p = line;

    if (strlen(p) > 19 && isdigit((unsigned char)p[0]) && p[2] == '.' && p[5] == '.' && p[8] == ' ' && p[11] == ':' && p[14] == ':')
        p += 17;
    while (*p == ' ' || *p == '\t')
        p++;
    return p;
}

/* known messages: a plain title, what it means, whether it is normal on iOS */
typedef struct { const char *match; const char *title; const char *detail; int expected; int severity; } HrKnown;

static const HrKnown hr_known[] = {
    { "failed to open bink file", "Videos are skipped", "This port has no video player, so intro and cutscene videos are skipped.", 1, 1 },
    { "no DirectSound for bink", "Videos are skipped", "This port has no video player, so intro and cutscene videos are skipped.", 1, 1 },
    { "unable to locate any movie", "Videos are skipped", "This port has no video player, so intro and cutscene videos are skipped.", 1, 1 },
    { "cachebeta.map", "Xbox disc files are not present", "The game looks for files that only exist on an Xbox hard disk; it carries on without them.", 1, 1 },
    { "last_language.dat", "Xbox disc files are not present", "The game looks for files that only exist on an Xbox hard disk; it carries on without them.", 1, 1 },
    { "lastprof.txt", "Xbox disc files are not present", "The game looks for files that only exist on an Xbox hard disk; it carries on without them.", 1, 1 },
    { "telnet console endpoint", "Xbox console services are not available", "Developer console networking from the original game is off on iOS.", 1, 1 },
    { "winsock error #50", "Xbox console services are not available", "Developer console networking from the original game is off on iOS.", 1, 1 },
    { "xbox ethernet link is not connected", "Xbox console services are not available", "Developer console networking from the original game is off on iOS.", 1, 1 },
    { "loading.tga unavailable", "Loading screen texture missing", "The game uses a plain loading texture instead.", 1, 1 },
    { "event handler function failed", "A menu action reported failure", "Seen once while a profile is created; the menu carries on.", 1, 1 },
    { "reference function:", "Diagnostic header", "", 1, 1 },
    { "reference address:", "Diagnostic header", "", 1, 1 },
    { "unlocking all solo levels", "Diagnostic message", "", 1, 1 },
    { "checksum failed on persistent storage", "Saved profile check failed",
      "The game could not verify the profile data it saved on this device. Playing is not affected, but a profile or progress may not carry over.", 0, 1 },
    { "already exists", "A map object was created twice",
      "The campaign tried to create an object that already exists. The original game logs the same; it is harmless.", 0, 1 },
    { "deleted unexpectedly", "A weapon was removed before it existed",
      "Appears at the menu or map start when the player has no weapon yet. Harmless.", 0, 1 },
};

static inline int hr_add_problem(HaloReport *r, int severity, const char *title, const char *detail, int expected)
{
    if (expected)
    {
        r->expected_count++;
        return 0;
    }
    for (int i = 0; i < r->problem_count; i++)
        if (!strcmp(r->problems[i].title, title))
        {
            r->problems[i].count++;
            return 1;
        }
    if (r->problem_count >= HR_MAX_PROBLEMS)
        return 0;
    HrProblem *p = &r->problems[r->problem_count++];
    p->severity = severity;
    p->count = 1;
    hr_copy(p->title, sizeof(p->title), title);
    hr_copy(p->detail, sizeof(p->detail), detail);
    return 1;
}

/* classifies one message into the problem list (or the expected count) */
static inline void hr_classify(HaloReport *r, const char *raw)
{
    const char *message = hr_message(raw);
    int category = halo_log_category(message);
    char title[96];

    for (unsigned i = 0; i < sizeof(hr_known) / sizeof(hr_known[0]); i++)
        if (strstr(message, hr_known[i].match))
        {
            hr_add_problem(r, hr_known[i].severity, hr_known[i].title, hr_known[i].detail, hr_known[i].expected);
            return;
        }
    if (category != HALO_LOG_ERROR && category != HALO_LOG_WARNING)
        return;
    if (!strncmp(message, "FULL GUEST:", 11))
        hr_add_problem(r, 0, "The game engine could not start", message + 11 + (message[11] == ' '), 0);
    else if (!strncmp(message, "FULL GUEST STOPPED", 18) || !strncmp(message, "FULL GUEST BLOCKED", 18))
        hr_add_problem(r, 0, "The game engine stopped", message, 0);
    else if (!strncmp(message, "audio:", 6))
        hr_add_problem(r, 0, "Sound could not start", message + 6 + (message[6] == ' '), 0);
    else if (!strncmp(message, "network (system link):", 22))
        hr_add_problem(r, 0, "Network problem", message + 22 + (message[22] == ' '), 0);
    else if (!strncmp(message, "previous start:", 15) || !strncmp(message, "  previous crash", 16))
        return; /* shown on the Summary */
    else
    {
        hr_copy(title, sizeof(title), message);
        hr_add_problem(r, category == HALO_LOG_ERROR ? 0 : 1, title, "", 0);
    }
}

/* the number after `marker` as an integer, or -1 */
static inline long hr_int_after(const char *line, const char *marker)
{
    return (long)halo_log_number_after(line, marker);
}

static inline int hr_is_waiting_symbol(const char *line)
{
    static const char *const waits[] = { "semaphore_timedwait_trap", "semaphore_wait_trap", "__semwait_signal", "__psynch_cvwait",
                                         "__ulock_wait", "mach_msg2_trap", "mach_msg_trap", "usleep", "nanosleep", "__select", "kevent" };

    for (unsigned i = 0; i < sizeof(waits) / sizeof(waits[0]); i++)
        if (strstr(line, waits[i]))
            return 1;
    return 0;
}

static inline void hr_each_line(const char *text, void (*visit)(void *, const char *), void *context)
{
    char line[512];

    while (text && *text)
    {
        const char *end = strchr(text, '\n');
        size_t length = end ? (size_t)(end - text) : strlen(text);

        if (length >= sizeof(line))
            length = sizeof(line) - 1;
        memcpy(line, text, length);
        line[length] = 0;
        while (length && (line[length - 1] == '\r' || line[length - 1] == ' '))
            line[--length] = 0;
        if (length)
            visit(context, line);
        if (!end)
            break;
        text = end + 1;
    }
}

struct hr_state { HaloReport *report; double fps_history[5]; int fps_count; double waiting; int in_profile; double wait_history[5]; int wait_count; int have_block; };

static inline double hr_median(const double *values, int count)
{
    double sorted[5];
    int n = count < 5 ? count : 5;

    if (n <= 0)
        return -1.0;
    memcpy(sorted, values, sizeof(double) * (size_t)n);
    for (int i = 1; i < n; i++)
        for (int j = i; j > 0 && sorted[j] < sorted[j - 1]; j--)
        {
            double t = sorted[j]; sorted[j] = sorted[j - 1]; sorted[j - 1] = t;
        }
    return n % 2 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
}

static inline void hr_visit_boot(void *context, const char *line)
{
    struct hr_state *state = context;
    HaloReport *r = state->report;
    double v;

    if (!strncmp(line, "M2.6.", 5) && strstr(line, "breadcrumb") && !r->app_version[0])
    {
        size_t n = 0;
        while (line[n] && line[n] != ' ' && line[n] != ':' && n < sizeof(r->app_version) - 1) { r->app_version[n] = line[n]; n++; }
        r->app_version[n] = 0;
    }
    if (strstr(line, "ENTERING REAL arm64_32") || !strncmp(line, "[3/3] Launching", 15))
        r->engine_started = 1;
    if (!strncmp(line, "VALID CACHE FILES:", 18))
    {
        r->maps_found = (int)hr_int_after(line, "FILES:");
        const char *slash = strchr(line, '/');
        if (slash) r->maps_total = atoi(slash + 1);
    }
    if (!strncmp(line, "FULL GUEST STOPPED", 18) || !strncmp(line, "FULL GUEST BLOCKED", 18))
    {
        r->stopped = 1;
        hr_copy(r->stop_reason, sizeof(r->stop_reason), line);
    }
    v = halo_log_fps(line);
    if (v >= 0)
    {
        r->fps = v;
        r->fps_samples++;
        state->fps_history[state->fps_count++ % 5] = v;
    }
    v = halo_log_render_ms(line);
    if (v >= 0)
        r->render_ms = v;
    if (!strncmp(line, "profile:", 8))
    {
        /* a new profile report: keep the last one's waiting share, start counting again */
        if (state->have_block)
            state->wait_history[state->wait_count++ % 5] = state->waiting;
        state->have_block = 1;
        r->profile_samples = (int)hr_int_after(line, "profile:");
        state->waiting = 0;
        state->in_profile = 1;
        r->top_count = 0;
    }
    else if (state->in_profile && !strncmp(line, "  profile ", 10))
    {
        const char *after = line + 10;
        double percent;

        while (*after && *after != ' ') after++;           /* library | game | host */
        while (*after == ' ') after++;
        percent = strtod(after, NULL);
        if (!strncmp(line, "  profile host", 14) && hr_is_waiting_symbol(line))
            state->waiting += percent;
        if (!strncmp(line, "  profile game", 14) && r->top_count < HR_MAX_TOP)
        {
            const char *name = strchr(after, '%');
            if (name) { name++; while (*name == ' ') name++; }
            snprintf(r->top[r->top_count++], sizeof(r->top[0]), "%.1f%%  %s", percent, name ? name : "");
        }
    }
    else if (strncmp(line, "  profile", 9))
        state->in_profile = 0;
    if (!strncmp(line, "audio: output opened", 20))
    {
        r->audio_open = 1;
        hr_copy(r->audio_text, sizeof(r->audio_text), "Playing through the speaker");
    }
    else if (!strncmp(line, "audio: playing through the speaker", 34))
    {
        r->audio_open = 1;
        hr_copy(r->audio_text, sizeof(r->audio_text), "Playing through the speaker");
        r->underruns = (unsigned)hr_int_after(line, "speaker;");
    }
    else if (!strncmp(line, "audio: could not open", 21) || !strncmp(line, "audio: not playing", 18))
    {
        r->audio_open = 0;
        hr_copy(r->audio_text, sizeof(r->audio_text), line + 7);
    }
    if ((!strncmp(line, "network (system link)", 21) || strstr(line, "Internet play") || strstr(line, "invite link")) && r->network_count < 4)
        hr_copy(r->network[r->network_count++], HR_TEXT, line);
    if (!strncmp(line, "previous start:", 15))
        hr_copy(r->previous_start, sizeof(r->previous_start), line + 16);
    if (!strncmp(line, "  previous crash", 16) && r->crash_count < 3)
        hr_copy(r->crash[r->crash_count++], sizeof(r->crash[0]), line + 18);
    if (!strncmp(line, "SAFE START", 10))
        r->safe_start = 1;
    hr_classify(r, line);
}

static inline void hr_visit_game(void *context, const char *line)
{
    struct hr_state *state = context;
    HaloReport *r = state->report;
    const char *message = hr_message(line);
    const char *at;

    if (!r->build[0] && (at = strstr(message, "xbox 01.01.14.")) != NULL)
    {
        int build = atoi(at + 14);
        snprintf(r->build, sizeof(r->build), "Halo CE (Xbox build %d)", build);
    }
    if ((at = strstr(message, "starting precaching of map '")) != NULL)
    {
        const char *name = at + 28;
        size_t n = 0;
        while (name[n] && name[n] != '\'' && n < sizeof(r->map) - 1) { r->map[n] = name[n]; n++; }
        r->map[n] = 0;
    }
    hr_classify(r, line);
}

static inline void halo_report_build(HaloReport *r, const char *boot_log, const char *game_log)
{
    struct hr_state state;

    memset(r, 0, sizeof(*r));
    memset(&state, 0, sizeof(state));
    state.report = r;
    r->render_ms = -1.0;
    r->waiting_percent = -1.0;
    hr_each_line(boot_log, hr_visit_boot, &state);
    hr_each_line(game_log, hr_visit_game, &state);
    if (state.fps_count)
        r->fps_average = hr_median(state.fps_history, state.fps_count);
    if (state.have_block)
    {
        state.wait_history[state.wait_count++ % 5] = state.waiting;
        r->waiting_percent = hr_median(state.wait_history, state.wait_count);   /* the median of the last five reports */
    }
    /* an engine that never started has no frame rate to judge */
    if (!boot_log || !*boot_log)
        r->engine_started = 0;
}

/* "smooth", "playable", ... for the frame rate */
static inline const char *halo_report_verdict(double fps)
{
    return fps >= 28 ? "Smooth" : fps >= 20 ? "Playable" : fps >= 12 ? "Choppy" : "Slow";
}

#endif
