/*
 * M1.2 source-derived Halo Universal math cluster.
 *
 * Function bodies come from:
 *   source/math/real_math.c
 *   source/math/integer_math.c
 *
 * The standalone fixed-width type names isolate this slice from the full
 * Xbox/Win32 header graph while preserving the recovered algorithms.
 */
#include "halo_math_slice.h"

#include <math.h>
#include <string.h>

void halo_vectors_interpolate(const halo_real_vector3d *a,
                              const halo_real_vector3d *b,
                              real t,
                              halo_real_vector3d *result)
{
    real one_minus_t = 1-t;
    result->i = one_minus_t*a->i + t*b->i;
    result->j = one_minus_t*a->j + t*b->j;
    result->k = one_minus_t*a->k + t*b->k;
    return;
}

void halo_points_interpolate(const halo_real_point3d *a,
                             const halo_real_point3d *b,
                             real t,
                             halo_real_point3d *result)
{
    real one_minus_t = 1-t;
    result->x = one_minus_t*a->x + t*b->x;
    result->y = one_minus_t*a->y + t*b->y;
    result->z = one_minus_t*a->z + t*b->z;
    return;
}

halo_real_vector3d *halo_perpendicular3d(const halo_real_vector3d *a,
                                         halo_real_vector3d *result)
{
    real i = fabsf(a->i);
    real j = fabsf(a->j);
    real k = fabsf(a->k);

    if (i <= j && i <= k)
    {
        result->i = 0.f;
        result->j = a->k;
        result->k = -a->j;
    }
    else
    {
        if (j <= k)
        {
            result->i = -a->k;
            result->j = 0.f;
            result->k = a->i;
        }
        else
        {
            result->i = a->j;
            result->j = -a->i;
            result->k = 0.f;
        }
    }
    return result;
}

halo_real_vector4d *halo_perpendicular4d(const halo_real_vector4d *a,
                                         halo_real_vector4d *result)
{
    result->i = a->k;
    result->j = a->l;
    result->k = -a->i;
    result->l = -a->j;
    return result;
}

int16_t halo_rectangle2d_width(const halo_rectangle2d *rect)
{
    return rect->x1 - rect->x0;
}

int16_t halo_rectangle2d_height(const halo_rectangle2d *rect)
{
    return rect->y1 - rect->y0;
}

uint8_t halo_intersect_rectangles2d(const halo_rectangle2d *r1,
                                    const halo_rectangle2d *r2,
                                    halo_rectangle2d *intersection)
{
    uint8_t result = 0;
    halo_rectangle2d new_rectangle;
    new_rectangle.x0 = r1->x0 > r2->x0 ? r1->x0 : r2->x0;
    new_rectangle.x1 = r1->x1 < r2->x1 ? r1->x1 : r2->x1;
    new_rectangle.y0 = r1->y0 > r2->y0 ? r1->y0 : r2->y0;
    new_rectangle.y1 = r1->y1 < r2->y1 ? r1->y1 : r2->y1;

    if (new_rectangle.x0 >= new_rectangle.x1 ||
        new_rectangle.y0 >= new_rectangle.y1)
    {
        memset(intersection, 0, sizeof(new_rectangle));
    }
    else
    {
        *intersection = new_rectangle;
        result = 1;
    }
    return result;
}

uint8_t halo_point2d_in_rectangle2d(const halo_rectangle2d *rectangle,
                                    const halo_point2d *point)
{
    uint8_t result = 0;
    if (point->x >= rectangle->x0 && point->x < rectangle->x1)
    {
        if (point->y >= rectangle->y0 && point->y < rectangle->y1)
            result = 1;
    }
    return result;
}

int16_t halo_floor_log2(uint32_t k)
{
    uint32_t counter = k;
    int32_t result = 0;

    if (k > 0)
    {
        for (; counter != 1; result++)
            counter >>= 1;
    }
    return (int16_t)result;
}

uint32_t halo_integer_square_root(uint32_t k)
{
    uint32_t sum;
    uint32_t result = 0;
    uint32_t magic = 0x40000000;

    do
    {
        sum = magic + result;
        if (magic + result <= k)
        {
            k -= sum;
            result = sum + magic;
        }
        magic >>= 2;
        result >>= 1;
    }
    while (magic);

    if (k > result)
        result++;

    return result;
}
