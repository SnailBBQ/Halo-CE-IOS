#ifndef HALO_MAP_NAME_H
#define HALO_MAP_NAME_H
/* The map a file path names, for diagnostics: "d:/maps/A50.MAP" -> "a50". Only plain names are taken (letters, digits, '_' and
 * '-' before ".map"), so nothing odd ever reaches a log line. Returns 1 and fills out, or 0 and leaves it untouched. */
static inline int halo_map_name_from_path(const char *path, char *out, unsigned size) {
    unsigned length = 0, start = 0, base, i;
    if (!path || !out || size < 2) return 0;
    while (length < 1024 && path[length]) { if (path[length] == '/' || path[length] == '\\') start = length + 1; length++; }
    if (length >= 1024 || length - start < 5) return 0;
    {
        const char *tail = path + length - 4;
        if (tail[0] != '.' || (tail[1] | 32) != 'm' || (tail[2] | 32) != 'a' || (tail[3] | 32) != 'p') return 0;
    }
    base = length - start - 4;
    if (base >= size) return 0;
    for (i = 0; i < base; i++) {
        char c = path[start + i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-')) return 0;
    }
    for (i = 0; i < base; i++) { char c = path[start + i]; out[i] = (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c; }
    out[base] = 0;
    return 1;
}
#endif
