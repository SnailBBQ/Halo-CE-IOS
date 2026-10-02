#ifndef HALO_LOG_CLASSIFY_H
#define HALO_LOG_CLASSIFY_H

/*
 * Sorts the engine's log lines so the log screen can colour and filter them, and pulls the few
 * numbers a player wants (frame rate, frame time) out of the periodic diagnostics. Plain C so
 * tools/tests/test_ios_log_classify.c can check it against lines from real device logs.
 */

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

enum
{
    HALO_LOG_INFO = 0,    /* ordinary progress */
    HALO_LOG_ERROR,       /* something failed */
    HALO_LOG_WARNING,     /* something odd but not fatal */
    HALO_LOG_PERFORMANCE, /* frame rate, timings, fault and profile reports */
    HALO_LOG_LOADING,     /* map and engine start-up steps */
    HALO_LOG_NETWORK,     /* internet play and system link */
    HALO_LOG_NOISE        /* the guest renderer's per-frame chatter */
};

static inline int halo_log_contains(const char *line, const char *needle)
{
    return strstr(line, needle) != NULL;
}

static inline int halo_log_contains_nocase(const char *line, const char *needle)
{
    size_t length = strlen(needle);

    for (; *line; line++)
    {
        size_t i = 0;
        while (i < length && line[i] && tolower((unsigned char)line[i]) == tolower((unsigned char)needle[i])) i++;
        if (i == length)
            return 1;
    }
    return 0;
}

static inline int halo_log_category(const char *line)
{
    if (!line || !*line)
        return HALO_LOG_INFO;
    /* the renderer's frame summaries and state dumps repeat every second; keep them out of the way */
    if (!strncmp(line, "[guest] ", 8) || !strncmp(line, "final back buffer", 17) || !strncmp(line, "screen fade", 11) ||
        !strncmp(line, "scene: tick=", 12))
        return HALO_LOG_NOISE;
    if (halo_log_contains(line, "ERROR") || halo_log_contains(line, "BLOCKED") || halo_log_contains(line, "STOPPED") ||
        halo_log_contains_nocase(line, "failed") || halo_log_contains_nocase(line, "cannot ") ||
        halo_log_contains_nocase(line, "unable to") || halo_log_contains_nocase(line, "could not") ||
        halo_log_contains_nocase(line, "would not"))
        return HALO_LOG_ERROR;
    if (halo_log_contains(line, "WARNING") || halo_log_contains_nocase(line, "unexpectedly") ||
        halo_log_contains_nocase(line, "invalid"))
        return HALO_LOG_WARNING;
    if (halo_log_contains(line, "Internet play") || halo_log_contains(line, "invite") || halo_log_contains(line, "system link") ||
        halo_log_contains(line, "winsock") || halo_log_contains(line, "STUN") || halo_log_contains(line, "p2p"))
        return HALO_LOG_NETWORK;
    if (!strncmp(line, "presentation rate", 17) || !strncmp(line, "timing ", 7) || !strncmp(line, "native ", 7) ||
        !strncmp(line, "guest heartbeat", 15) || !strncmp(line, "pointer faults", 14) || !strncmp(line, "  fault hot spot", 16) ||
        !strncmp(line, "profile", 7) || !strncmp(line, "  profile", 9) || !strncmp(line, "audio:", 6))
        return HALO_LOG_PERFORMANCE;
    if (!strncmp(line, "[loading]", 9) || halo_log_contains(line, "precaching") || halo_log_contains(line, "MAP ") ||
        halo_log_contains(line, "CACHE"))
        return HALO_LOG_LOADING;
    return HALO_LOG_INFO;
}


/* Messages the Xbox engine prints on iOS that mean nothing for the player: videos and some
 * console services are not implemented, and files from an Xbox hard disk do not exist. */
static inline int halo_log_expected(const char *line)
{
    static const char *const known[] = {
        "failed to open bink file", "no DirectSound for bink", "unable to locate any movie",
        "Couldn't read map file 'd:\\cachebeta.map'", "last_language.dat", "lastprof.txt",
        "bind_endpoint() failed on telnet console endpoint", "winsock error #50", "xbox ethernet link is not connected",
        "loading.tga unavailable", "event handler function failed", "reference function:", "reference address:",
        "unlocking all solo levels"
    };

    if (!line)
        return 0;
    for (unsigned i = 0; i < sizeof(known) / sizeof(known[0]); i++)
        if (strstr(line, known[i]))
            return 1;
    return 0;
}

/* The number that follows `marker` in `line`, or -1 if the marker is missing or no number follows. */
static inline double halo_log_number_after(const char *line, const char *marker)
{
    const char *at = strstr(line, marker);
    char *end;
    double value;

    if (!at)
        return -1.0;
    at += strlen(marker);
    while (*at == ' ' || *at == ':')
        at++;
    if (!isdigit((unsigned char)*at) && *at != '-')
        return -1.0;
    value = strtod(at, &end);
    return end == at ? -1.0 : value;
}

/* Player-facing performance: "presentation rate: 28.63 FPS (...)" gives 28.63. */
static inline double halo_log_fps(const char *line)
{
    return strncmp(line, "presentation rate", 17) ? -1.0 : halo_log_number_after(line, "presentation rate:");
}

/* "timing render CPU (...): 364 calls, 8.6 ms average, ..." gives 8.6 (older logs) or the new
 * "avg 8612 us" form (in milliseconds). */
static inline double halo_log_render_ms(const char *line)
{
    double value;

    if (strncmp(line, "timing render CPU", 17))
        return -1.0;
    value = halo_log_number_after(line, "avg ");
    if (value >= 0.0 && halo_log_contains(line, " us"))
        return value / 1000.0;
    return halo_log_number_after(line, "calls, ");
}

#endif
