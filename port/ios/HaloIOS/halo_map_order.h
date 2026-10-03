#ifndef HALO_MAP_ORDER_H
#define HALO_MAP_ORDER_H

/*
 * The order and names the Mods screen shows the installed game files in, as plain C so
 * tools/tests/test_ios_map_order.c can check it. Campaign maps come first in mission order; the multiplayer maps
 * follow in the order the game's own menu lists them (or alphabetically if the player prefers); maps this table
 * does not know (mods and custom maps) come after the stock multiplayer maps, alphabetically; ui.map is last.
 * "Multiplayer only" hides the campaign maps and nothing else.
 */

#include <string.h>

typedef struct { const char *file; const char *title; int campaign; } HmMap;

/* campaign in mission order, then multiplayer in the game's menu order */
static const HmMap hm_stock[] = {
    { "a10", "The Pillar of Autumn", 1 }, { "a30", "Halo", 1 }, { "a50", "Truth and Reconciliation", 1 },
    { "b30", "The Silent Cartographer", 1 }, { "b40", "Assault on the Control Room", 1 }, { "c10", "343 Guilty Spark", 1 },
    { "c20", "The Library", 1 }, { "c40", "Two Betrayals", 1 }, { "d20", "Keyes", 1 }, { "d40", "The Maw", 1 },
    { "beavercreek", "Battle Creek", 0 }, { "sidewinder", "Sidewinder", 0 }, { "damnation", "Damnation", 0 },
    { "ratrace", "Rat Race", 0 }, { "prisoner", "Prisoner", 0 }, { "hangemhigh", "Hang 'Em High", 0 },
    { "chillout", "Chill Out", 0 }, { "carousel", "Derelict", 0 }, { "boardingaction", "Boarding Action", 0 },
    { "bloodgulch", "Blood Gulch", 0 }, { "wizard", "Wizard", 0 }, { "putput", "Chiron TL-34", 0 }, { "longest", "Longest", 0 }
};
#define HM_STOCK_COUNT ((int)(sizeof(hm_stock) / sizeof(hm_stock[0])))
#define HM_CAMPAIGN_COUNT 10

/* index into hm_stock for a file name without its extension, any case; -1 if not a stock map */
static inline int hm_index(const char *base)
{
    char lower[64];
    size_t n = 0;

    if (!base)
        return -1;
    for (; base[n] && n + 1 < sizeof(lower); n++)
        lower[n] = (char)((base[n] >= 'A' && base[n] <= 'Z') ? base[n] + 32 : base[n]);
    lower[n] = 0;
    if (base[n])
        return -1;
    for (int i = 0; i < HM_STOCK_COUNT; i++)
        if (!strcmp(lower, hm_stock[i].file))
            return i;
    return -1;
}

static inline int hm_is_ui(const char *base)
{
    return base && (base[0] == 'u' || base[0] == 'U') && (base[1] == 'i' || base[1] == 'I') && !base[2];
}

static inline int hm_is_campaign(const char *base)
{
    int i = hm_index(base);
    return i >= 0 && hm_stock[i].campaign;
}

/* The name to show: "Battle Creek" for beavercreek; the file name itself for a map this table does not know. */
static inline const char *hm_title(const char *base)
{
    int i = hm_index(base);
    if (i >= 0)
        return hm_stock[i].title;
    return hm_is_ui(base) ? "Main menu" : base;
}

/* 0 campaign, 1 stock multiplayer, 2 other maps, 3 ui.map */
static inline int hm_group(const char *base)
{
    int i = hm_index(base);
    if (hm_is_ui(base))
        return 3;
    if (i < 0)
        return 2;
    return hm_stock[i].campaign ? 0 : 1;
}

static inline int hm_visible(const char *base, int multiplayer_only)
{
    return !(multiplayer_only && hm_is_campaign(base));
}

static inline int hm_ci_compare(const char *a, const char *b)
{
    for (;; a++, b++)
    {
        int x = (unsigned char)*a, y = (unsigned char)*b;
        if (x >= 'A' && x <= 'Z') x += 32;
        if (y >= 'A' && y <= 'Z') y += 32;
        if (x != y)
            return x < y ? -1 : 1;
        if (!x)
            return 0;
    }
}

/* qsort-style comparison of two base names. alphabetical: stock and other multiplayer maps are mixed and sorted by the
 * name shown; otherwise the stock maps keep the game's menu order and the others follow, sorted by file name. */
static inline int hm_compare(const char *a, const char *b, int alphabetical)
{
    int ga = hm_group(a), gb = hm_group(b);
    int ia = hm_index(a), ib = hm_index(b);

    if (alphabetical && ga >= 1 && ga <= 2 && gb >= 1 && gb <= 2)
        ga = gb = 1;
    if (ga != gb)
        return ga < gb ? -1 : 1;
    if (ga == 0 || (ga == 1 && !alphabetical))
        return ia < ib ? -1 : (ia > ib ? 1 : 0);
    {
        int c = hm_ci_compare(hm_title(a), hm_title(b));
        return c ? c : hm_ci_compare(a, b);
    }
}

#endif
