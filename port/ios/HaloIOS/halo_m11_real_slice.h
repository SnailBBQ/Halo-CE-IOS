#ifndef HALO_M11_REAL_SLICE_H
#define HALO_M11_REAL_SLICE_H

typedef float real;

typedef struct halo_real_vector3d {
    real i;
    real j;
    real k;
} halo_real_vector3d;

/*
 * Source-derived slice from:
 *   source/math/real_math.c :: vectors_interpolate()
 *
 * The function body is kept identical to the recovered Halo Universal source;
 * only the standalone type name differs so this tiny iOS milestone can compile
 * without pulling in the full game header graph yet.
 */
void halo_m11_vectors_interpolate(
    halo_real_vector3d const *a,
    halo_real_vector3d const *b,
    real t,
    halo_real_vector3d *result);

#endif
