/*
 * Halo iOS M1.1 real-source function slice.
 *
 * Provenance:
 *   Halo CE Universal source/math/real_math.c
 *   public function: vectors_interpolate()
 *
 * This is intentionally a source-derived standalone slice. The function body
 * below is the recovered Halo implementation verbatim; only the local type name
 * is adapted to isolate it from the still-Windows/Xbox-heavy full header graph.
 */

#include "halo_m11_real_slice.h"

void halo_m11_vectors_interpolate(
    halo_real_vector3d const *a,
    halo_real_vector3d const *b,
    real t,
    halo_real_vector3d *result)
{
    real one_minus_t = 1-t;
    result->i = one_minus_t*a->i + t*b->i;
    result->j = one_minus_t*a->j + t*b->j;
    result->k = one_minus_t*a->k + t*b->k;
    return;
}
