#ifndef HALO_IOS_XISO_H
#define HALO_IOS_XISO_H
#include <stdint.h>
/* In-process XDVDFS reader. The caller supplies a NEW private staging folder;
 * this API never writes to the live map library. Return 1: success, 0: error,
 * -1: cancelled. Returning nonzero from progress cancels at the next chunk.
 * The caller owns staging cleanup, including partially copied files. */
typedef int (*halo_xiso_progress)(void *, const char *, uint64_t, uint64_t);
int halo_xiso_extract(const char *image, const char *staging,
    halo_xiso_progress progress, void *context, char *error, unsigned error_size);
#endif
