#ifndef HALO_MODS_STATE_H
#define HALO_MODS_STATE_H

/*
 * The mods of OpenCE build 220 as plain C, so tools/tests/test_ios_mods_state.c can check what the Settings Mods list reads
 * and writes. A mod is a folder in Documents/Halo/mods with a mod.toml; mods/load_order.toml keeps the order the mods load in
 * and the mods turned off. The game's own Mods menu reads and writes the same two things, which is how Settings and the game
 * stay in step: this file only reads and writes them the way the engine does (port/linux/src/port_mods.c).
 *
 * The TOML understood here is the part those files use: top level  key = "string"  and  key = ["a", "b"]  (a list may
 * continue on later lines), # comments, basic and literal strings. Anything under a [table] header is ignored.
 */

#include <stddef.h>
#include <stdio.h>
#include <string.h>

#define HMS_MAX_MODS 256
#define HMS_NAME 64        /* a folder name is 63 bytes at most */
#define HMS_TEXT 512

/* reads the string list `key` at the top level of text into out (each entry HMS_TEXT bytes at most, cut short); a lone string
 * counts as a list of one. Returns how many, 0 if the key is missing. */
static inline int hms_strings(const char *text, const char *key, char out[][HMS_TEXT], int max)
{
    size_t key_length = strlen(key);
    const char *p = text;
    int count = 0;

    if (!text)
        return 0;
    while (*p)
    {
        const char *line = p;
        const char *end = strchr(p, '\n');

        p = end ? end + 1 : p + strlen(p);
        while (*line == ' ' || *line == '\t')
            line++;
        if (*line == '[')
            break;   /* a table header: nothing below it is top level */
        if (strncmp(line, key, key_length) != 0)
            continue;
        {
            const char *v = line + key_length;

            while (*v == ' ' || *v == '\t')
                v++;
            if (*v != '=')
                continue;
            v++;
            for (;;)
            {
                while (*v == ' ' || *v == '\t' || *v == '\r' || *v == '\n' || *v == ',' || *v == '[')
                    v++;
                if (*v == '#')
                {
                    while (*v && *v != '\n')
                        v++;
                    continue;
                }
                if (*v == ']' || !*v)
                    break;
                if (*v == '"' || *v == '\'')
                {
                    char quote = *v++;
                    size_t n = 0;

                    while (*v && *v != quote && *v != '\n')
                    {
                        unsigned long code = 0;
                        int digits = 0, raw = 0;

                        if (quote == '"' && *v == '\\' && v[1])
                        {
                            v++;
                            switch (*v)
                            {
                            case 'n': code = '\n'; break;
                            case 't': code = '\t'; break;
                            case 'r': code = '\r'; break;
                            case 'u': digits = 4; break;
                            case 'U': digits = 8; break;
                            default: code = (unsigned char)*v; break;
                            }
                            v++;
                            if (digits)
                            {
                                for (int i = 0; i < digits && ((*v >= '0' && *v <= '9') || (*v >= 'a' && *v <= 'f') || (*v >= 'A' && *v <= 'F')); i++, v++)
                                    code = code * 16 + (unsigned long)(*v <= '9' ? *v - '0' : (*v | 32) - 'a' + 10);
                            }
                        }
                        else
                        {
                            code = (unsigned char)*v++;
                            raw = 1;
                        }
                        if (code < 0x80)
                        {
                            if (n + 1 < HMS_TEXT && count < max) out[count][n++] = (char)code;
                        }
                        else if (raw)
                        {
                            if (n + 1 < HMS_TEXT && count < max) out[count][n++] = (char)code;   /* raw UTF-8 byte */
                        }
                        else if (code >= 0x80)
                        {
                            unsigned char b[4];
                            int k = 0;

                            if (code < 0x800) { b[k++] = (unsigned char)(0xC0 | (code >> 6)); b[k++] = (unsigned char)(0x80 | (code & 63)); }
                            else if (code < 0x10000) { b[k++] = (unsigned char)(0xE0 | (code >> 12)); b[k++] = (unsigned char)(0x80 | ((code >> 6) & 63)); b[k++] = (unsigned char)(0x80 | (code & 63)); }
                            else if (code < 0x110000) { b[k++] = (unsigned char)(0xF0 | (code >> 18)); b[k++] = (unsigned char)(0x80 | ((code >> 12) & 63)); b[k++] = (unsigned char)(0x80 | ((code >> 6) & 63)); b[k++] = (unsigned char)(0x80 | (code & 63)); }
                            for (int i = 0; i < k; i++)
                                if (n + 1 < HMS_TEXT && count < max) out[count][n++] = (char)b[i];
                        }
                    }
                    if (*v == quote)
                        v++;
                    if (count < max)
                    {
                        out[count][n] = 0;
                        count++;
                    }
                }
                else
                {
                    /* a bare value (a number, true): not a string */
                    while (*v && *v != ',' && *v != ']' && *v != '\n')
                        v++;
                    if (*v == '\n')
                        break;
                }
                /* a lone string ends its line; a list goes on to its ] */
                {
                    const char *scan = line + key_length;

                    while (*scan == ' ' || *scan == '\t')
                        scan++;
                    scan++;
                    while (*scan == ' ' || *scan == '\t')
                        scan++;
                    if (*scan != '[')
                        return count;
                }
            }
            return count;
        }
    }
    return count;
}

/* the first string of a key, or fallback */
static inline const char *hms_string(const char *text, const char *key, char *out, size_t size, const char *fallback)
{
    static char list[1][HMS_TEXT];

    if (hms_strings(text, key, list, 1) > 0 && list[0][0])
        snprintf(out, size, "%s", list[0]);
    else
        snprintf(out, size, "%s", fallback ? fallback : "");
    return out;
}

static inline int hms_equal_nocase(const char *a, const char *b)
{
    for (;; a++, b++)
    {
        int x = (unsigned char)*a, y = (unsigned char)*b;

        if (x >= 'A' && x <= 'Z') x += 32;
        if (y >= 'A' && y <= 'Z') y += 32;
        if (x != y)
            return 0;
        if (!x)
            return 1;
    }
}

/* a folder name the game accepts as a mod's: not empty, 63 bytes at most, no slash, not "." or "..", no control character */
static inline int hms_folder_ok(const char *name)
{
    size_t n = name ? strlen(name) : 0;

    if (!n || n >= HMS_NAME || !strcmp(name, ".") || !strcmp(name, ".."))
        return 0;
    for (size_t i = 0; i < n; i++)
        if (name[i] == '/' || name[i] == '\\' || (unsigned char)name[i] < 0x20 || name[i] == 0x7f)
            return 0;
    return 1;
}

static inline int hms_compare_nocase(const char *a, const char *b)
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

/*
 * The load order for the folders found (any order in `folders`), given load_order.toml's `order` list: the mods it names
 * that exist, in its order, then each other mod right after the mod before it in the alphabetical (not case-sensitive)
 * order that is already placed, or first. This is the engine's rule without the load_after / load_before refinement, which
 * only moves a mod the file does not name. order_out gets indexes into folders; returns how many.
 */
static inline int hms_order(char folders[][HMS_NAME], int count, char kept[][HMS_TEXT], int kept_count, int *order_out)
{
    int sorted[HMS_MAX_MODS], placed[HMS_MAX_MODS] = { 0 };
    int n = 0;

    if (count > HMS_MAX_MODS)
        count = HMS_MAX_MODS;
    for (int i = 0; i < count; i++)
    {
        int at = i;

        while (at > 0 && hms_compare_nocase(folders[sorted[at - 1]], folders[i]) > 0)
        {
            sorted[at] = sorted[at - 1];
            at--;
        }
        sorted[at] = i;
    }
    for (int k = 0; k < kept_count; k++)
        for (int i = 0; i < count; i++)
            if (!placed[i] && hms_equal_nocase(folders[i], kept[k]))
            {
                placed[i] = 1;
                order_out[n++] = i;
                break;
            }
    for (int s = 0; s < count; s++)
    {
        int mod = sorted[s], at = 0;

        if (placed[mod])
            continue;
        for (int before = s - 1; before >= 0; before--)
        {
            if (!placed[sorted[before]])
                continue;
            for (int o = 0; o < n; o++)
                if (order_out[o] == sorted[before])
                    at = o + 1;
            break;
        }
        for (int o = n; o > at; o--)
            order_out[o] = order_out[o - 1];
        order_out[at] = mod;
        placed[mod] = 1;
        n++;
    }
    return n;
}

static inline size_t hms_append_string(char *out, size_t size, size_t at, const char *s)
{
    if (at + 1 < size) out[at++] = '"';
    for (; *s; s++)
    {
        unsigned char c = (unsigned char)*s;

        if (c == '"' || c == '\\')
        {
            if (at + 2 < size) { out[at++] = '\\'; out[at++] = (char)c; }
        }
        else if (c < 0x20 || c == 0x7f)
        {
            char u[8];

            snprintf(u, sizeof(u), "\\u%04x", c);
            for (int i = 0; u[i]; i++) if (at + 1 < size) out[at++] = u[i];
        }
        else if (at + 1 < size)
            out[at++] = (char)c;
    }
    if (at + 1 < size) out[at++] = '"';
    out[at < size ? at : size - 1] = 0;
    return at;
}

/* load_order.toml as the game's Mods menu writes it. names[i] in load order; off[i] non-zero when turned off. Returns the
 * length, 0 when size is too small. */
static inline size_t hms_serialize(char *out, size_t size, char names[][HMS_NAME], const int *off, int count)
{
    const char *head = "# The mods' load order (the first loads first, and each plays over those\n"
        "# before it: the Mods menu shows it the other way up), and the mods turned\n"
        "# off. The Mods menu writes this.\norder = [";
    size_t at = 0;
    int first = 1;

    if (size < strlen(head) + 32)
        return 0;
    memcpy(out, head, strlen(head));
    at = strlen(head);
    for (int i = 0; i < count; i++)
    {
        if (i) { out[at++] = ','; out[at++] = ' '; }
        at = hms_append_string(out, size, at, names[i]);
    }
    {
        const char *mid = "]\ndisabled = [";

        if (at + strlen(mid) + 8 >= size)
            return 0;
        memcpy(out + at, mid, strlen(mid));
        at += strlen(mid);
    }
    for (int i = 0; i < count; i++)
    {
        if (!off[i])
            continue;
        if (!first) { out[at++] = ','; out[at++] = ' '; }
        at = hms_append_string(out, size, at, names[i]);
        first = 0;
    }
    if (at + 4 >= size)
        return 0;
    out[at++] = ']';
    out[at++] = '\n';
    out[at] = 0;
    return at;
}

#endif
