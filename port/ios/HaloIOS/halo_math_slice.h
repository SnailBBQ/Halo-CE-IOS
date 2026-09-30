#ifndef HALO_MATH_SLICE_H
#define HALO_MATH_SLICE_H

#include <stdint.h>

typedef float real;

typedef struct halo_real_vector3d {
    real i, j, k;
} halo_real_vector3d;

typedef struct halo_real_vector4d {
    real i, j, k, l;
} halo_real_vector4d;

typedef struct halo_real_point3d {
    real x, y, z;
} halo_real_point3d;

typedef struct halo_rectangle2d {
    int16_t x0, x1, y0, y1;
} halo_rectangle2d;

typedef struct halo_point2d {
    int16_t x, y;
} halo_point2d;

/* source/math/real_math.c */
void halo_vectors_interpolate(const halo_real_vector3d *a,
                              const halo_real_vector3d *b,
                              real t,
                              halo_real_vector3d *result);
void halo_points_interpolate(const halo_real_point3d *a,
                             const halo_real_point3d *b,
                             real t,
                             halo_real_point3d *result);
halo_real_vector3d *halo_perpendicular3d(const halo_real_vector3d *a,
                                         halo_real_vector3d *result);
halo_real_vector4d *halo_perpendicular4d(const halo_real_vector4d *a,
                                         halo_real_vector4d *result);

/* source/math/integer_math.c */
int16_t halo_rectangle2d_width(const halo_rectangle2d *rect);
int16_t halo_rectangle2d_height(const halo_rectangle2d *rect);
uint8_t halo_intersect_rectangles2d(const halo_rectangle2d *r1,
                                    const halo_rectangle2d *r2,
                                    halo_rectangle2d *intersection);
uint8_t halo_point2d_in_rectangle2d(const halo_rectangle2d *rectangle,
                                    const halo_point2d *point);
int16_t halo_floor_log2(uint32_t k);
uint32_t halo_integer_square_root(uint32_t k);

#endif
