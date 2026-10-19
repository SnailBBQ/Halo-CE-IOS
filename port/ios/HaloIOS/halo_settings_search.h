#ifndef HALO_SETTINGS_SEARCH_H
#define HALO_SETTINGS_SEARCH_H

/*
 * The index behind the magnifier next to "Settings". Plain C so tools/tests/test_ios_settings_search.c can check it.
 * Every entry names the option as the Settings screen shows it, the category it lives in (the order of HaloCategory in
 * HaloSettingsViewController.m) and some extra words people might type. "popular" entries are the suggestions shown
 * before anything is typed. A query matches when every word in it appears at the start of a word in the title,
 * the keywords or the category name; matches in the title rank above matches in the keywords.
 */

#include <string.h>

typedef struct { int category; const char *title; const char *keywords; int popular; } HssEntry;

static const char *const hss_category_names[] = {
    "Multiplayer", "Controls", "Display", "Audio", "Cheats", "Profiles", "Options", "Mods", "Advanced"
};
#define HSS_CATEGORY_COUNT 9

static const HssEntry hss_entries[] = {
    /* Multiplayer */
    { 0, "Join the invite on the clipboard", "link paste join game friend invite", 1 },
    { 0, "Show QR code", "invite share scan friend", 0 },
    { 0, "Join links on the clipboard automatically", "auto paste invite", 0 },
    { 0, "Choose iCloud Drive folder", "invite file game_invite icloud", 0 },
    { 0, "Check Local Network access", "wifi lan permission bonjour", 0 },
    { 0, "Clear recent games", "history servers", 0 },
    { 0, "Internet play", "online multiplayer network", 0 },
    { 0, "UPnP port forwarding", "router port open nat", 0 },
    { 0, "Share maps with other players", "map download upload", 0 },
    { 0, "Streamer mode", "slurs swearing insults filter offensive words stream record", 0 },
    /* Controls */
    { 1, "Edit button layout", "touch buttons move resize place hud scheme", 1 },
    { 1, "Look speed", "sensitivity aim camera turn", 1 },
    { 1, "Look acceleration", "sensitivity aim camera curve", 0 },
    { 1, "Invert look", "inverted y axis flip", 0 },
    { 1, "Auto-fire on enemies", "aim assist shoot automatically", 0 },
    { 1, "Floating sticks", "joystick thumbstick follow", 0 },
    { 1, "Haptic feedback", "vibration rumble", 0 },
    { 1, "Left-handed layout", "mirror swap hand", 0 },
    { 1, "Toggle crouch", "hold press", 0 },
    { 1, "Aim by turning the device", "gyro motion tilt", 1 },
    { 1, "Dead zone", "stick drift controller", 0 },
    { 1, "Reset to the standard layout", "default restore controls", 0 },
    { 1, "Game HUD preset", "interface layout", 0 },
    /* Display */
    { 2, "Show FPS", "frame rate counter performance", 1 },
    { 2, "Aspect ratio", "widescreen 16:9 4:3 stretch", 1 },
    { 2, "Render resolution", "quality sharpness 720 1080 graphics", 1 },
    { 2, "VSync", "tearing frame pacing", 0 },
    { 2, "Smooth motion", "interpolation 60 fps", 0 },
    { 2, "Edit game HUD", "interface elements scale position", 0 },
    { 2, "High-res HUD", "sharp interface", 0 },
    { 2, "High-res text", "sharp font", 0 },
    { 2, "Video options", "graphics video setup", 0 },
    { 2, "Anti-aliasing", "aa fxaa msaa smoothing jaggies edges", 0 },
    { 2, "Shadow resolution", "shadows quality", 0 },
    { 2, "Per-pixel lighting", "lights", 0 },
    { 2, "Shield glow", "glow intensity light show", 0 },
    { 2, "Shield color", "armor glow colour", 0 },
    { 2, "Field of view", "fov", 1 },
    { 2, "Weapon and hands field of view", "viewmodel fov", 0 },
    { 2, "Arm shields", "viewmodel shield flare", 0 },
    { 2, "Legs", "first person body", 0 },
    { 2, "Player names", "nametags overhead name size", 0 },
    { 2, "Scoreboard", "layout team score panel", 0 },
    { 2, "Text chat", "chat messages colors", 0 },
    /* Audio */
    { 3, "Master volume", "sound loudness all", 1 },
    { 3, "Music", "soundtrack volume", 0 },
    { 3, "Dialogue", "voice lines volume", 0 },
    { 3, "Effects", "sound effects volume", 0 },
    { 3, "Ambient", "environment sound volume", 0 },
    { 3, "Reverb", "echo room sound", 0 },
    { 3, "Your microphone", "voice chat open mic push to talk mute talk", 1 },
    { 3, "Voice volume", "voice chat other players loudness", 0 },
    { 3, "Restart audio output", "no sound crackle fix", 0 },
    /* Cheats */
    { 4, "Splitscreen campaign", "player 1 player 2 both cheats act on host coop", 0 },
    { 4, "Restore health and shield", "heal god mode", 0 },
    { 4, "Weapon giver", "give gun rifle pistol spawn", 0 },
    { 4, "Vehicle Spawner", "warthog ghost banshee scorpion spawn vehicle", 1 },
    { 4, "Teleport me to crosshair", "move warp", 0 },
    { 4, "Infinite Active Camo", "invisible", 0 },
    { 4, "Infinite Overshield", "shield", 0 },
    { 4, "Time scale", "slow motion speed", 0 },
    { 4, "Erase All AI", "enemies remove", 0 },
    { 4, "Force checkpoint now", "save revert", 0 },
    /* Profiles */
    { 5, "New profile", "create make add player name color", 0 },
    { 5, "In-game name", "player profile gamertag", 1 },
    { 5, "Multiplayer armor color", "spartan colour", 0 },
    { 5, "Choose a Halo player profile", "switch account", 0 },
    { 5, "Import / export Halo player profiles", "backup transfer", 0 },
    { 5, "Import / export campaign saves", "backup transfer progress", 0 },
    { 5, "Back up or move your profile", "export import restore backup share settings haloprofile halobackup player profile saves", 1 },
    { 5, "Reset all settings to defaults", "factory reset", 0 },
    /* Options */
    { 6, "Choose icon", "settings button gear emoji photo star favorite", 1 },
    { 6, "Hide / show shortcut", "gear button secret code sequence", 0 },
    { 6, "Opacity", "transparency settings button gear", 0 },
    { 6, "Preset colors", "accent theme", 1 },
    { 6, "Chroma mode", "rainbow color cycle", 0 },
    { 6, "Open color wheel", "custom colour hex", 0 },
    /* Mods */
    { 7, "Mods", "texture sound model text pack mod folder load order priority on off", 1 },
    { 7, "Add a mod folder", "install import mod.toml tags", 0 },
    { 7, "Custom Edition Maps", "ce import map custom_maps", 1 },
    { 7, "Multiplayer only (A–Z)", "filter maps alphabetical sort", 0 },
    { 7, "Campaign only", "filter maps missions", 0 },
    { 7, "Installed Xbox game files", "maps import ui.map", 0 },
    { 7, "Movies", "intro credits mp4 video", 0 },
    /* Advanced */
    { 8, "Lower the frame rate when the phone is hot", "thermal heat throttle", 0 },
    { 8, "Performance overlay", "fps stats", 0 },
    { 8, "Original player animations", "enhanced animations big games", 0 },
    { 8, "Performance profiler", "lag stutter", 0 },
    { 8, "Report a problem", "bug logs support", 1 },
    { 8, "Copy logs as text", "diagnostics", 0 },
    { 8, "Share log files", "diagnostics", 0 },
    { 8, "Manage backups", "restore save", 0 },
    { 8, "App version", "build engine network about", 0 },
    { 8, "Quit Game", "close exit", 0 }
};
#define HSS_COUNT ((int)(sizeof(hss_entries) / sizeof(hss_entries[0])))

static inline char hss_lower(char c) { return (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c; }

/* 1 when the word (length n, any case) starts a word of text */
static inline int hss_word_prefix(const char *text, const char *word, size_t n)
{
    for (const char *p = text; *p; p++)
    {
        size_t i = 0;
        int boundary = p == text || p[-1] == ' ' || p[-1] == '-' || p[-1] == '/' || p[-1] == '(' || p[-1] == '_';

        if (!boundary)
            continue;
        while (i < n && p[i] && hss_lower(p[i]) == hss_lower(word[i]))
            i++;
        if (i == n)
            return 1;
    }
    return 0;
}

/* 0 = no match, otherwise higher is better. Empty queries match nothing. */
static inline int hss_score(const HssEntry *entry, const char *query)
{
    int score = 0, words = 0;
    const char *p = query;

    while (*p)
    {
        const char *start;
        size_t n = 0;
        int best;

        while (*p == ' ')
            p++;
        if (!*p)
            break;
        start = p;
        while (*p && *p != ' ')
            p++, n++;
        words++;
        if (hss_word_prefix(entry->title, start, n))
            best = (hss_lower(entry->title[0]) == hss_lower(start[0]) && hss_word_prefix(entry->title, start, n) && !strncmp(entry->title, start, n)) ? 6 : 4;
        else if (hss_word_prefix(entry->keywords, start, n))
            best = 2;
        else if (hss_word_prefix(hss_category_names[entry->category], start, n))
            best = 1;
        else
            return 0;
        score += best;
    }
    return words ? score + (entry->popular ? 1 : 0) : 0;
}

/* Fills out[] with entry indexes, best first (stable for equal scores); returns how many. */
static inline int hss_search(const char *query, int *out, int max)
{
    int scores[HSS_COUNT], count = 0;

    for (int i = 0; i < HSS_COUNT; i++)
    {
        int s = hss_score(&hss_entries[i], query), at = count;

        if (!s || count >= max || count >= HSS_COUNT)
            continue;
        while (at > 0 && scores[at - 1] < s)
        {
            scores[at] = scores[at - 1];
            out[at] = out[at - 1];
            at--;
        }
        scores[at] = s;
        out[at] = i;
        count++;
    }
    return count;
}

/* The suggestions shown before anything is typed */
static inline int hss_suggestions(int *out, int max)
{
    int count = 0;

    for (int i = 0; i < HSS_COUNT && count < max; i++)
        if (hss_entries[i].popular)
            out[count++] = i;
    return count;
}

#endif
