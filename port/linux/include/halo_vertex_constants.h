#ifndef HALO_VERTEX_CONSTANTS_H
#define HALO_VERTEX_CONSTANTS_H
#include <stdio.h>

/* Reflection runs once after link. An inactive array element is a hole, not
   evidence that all higher registers are inactive. Store GL locations only;
   no guest pointers or frame data are retained. */
#define HALO_VERTEX_CONSTANT_COUNT 192
struct halo_vertex_constant_locations {
    GLint location[HALO_VERTEX_CONSTANT_COUNT];
    unsigned long count;
    int consecutive;
};
static inline void halo_vertex_constants_reflect(struct halo_vertex_constant_locations *map, GLuint program)
{
    map->count = 0;
    map->consecutive = 1;
    for (unsigned long i = 0; i < HALO_VERTEX_CONSTANT_COUNT; ++i) {
        char name[16];
        snprintf(name, sizeof(name), "c[%lu]", i);
        map->location[i] = glGetUniformLocation(program, name);
        if (i == 0 && map->location[i] < 0)
            map->location[i] = glGetUniformLocation(program, "c");
        if (map->location[i] >= 0) map->count = i + 1;
    }
    for (unsigned long i = 0; i < map->count; ++i)
        if (map->location[0] < 0 || map->location[i] != map->location[0] + (GLint)i)
            map->consecutive = 0;
}
/* first..last is the existing dirty range. Preserve the single-call fast
   path, but never manufacture a location or upload through an inactive hole. */
static inline void halo_vertex_constants_upload(const struct halo_vertex_constant_locations *map,
    unsigned long first, unsigned long last, const float values[][4])
{
    if (!values || first >= map->count || first > last) return;
    if (last >= map->count) last = map->count - 1;
    if (map->consecutive) {
        glUniform4fv(map->location[first], (GLsizei)(last - first + 1), values[first]);
    } else {
        for (unsigned long i = first; i <= last; ++i)
            if (map->location[i] >= 0) glUniform4fv(map->location[i], 1, values[i]);
    }
}
#endif
