#ifndef HALO_CRASH_REPORT_H
#define HALO_CRASH_REPORT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opens crash.txt and launch-phase.txt in `folder` (created if needed) and installs handlers for the
 * fatal signals. Must run before the PAGEZERO bridge is installed so that faults that are not the
 * guest's reach it (the bridge hands those on to the handler that was there before it). */
void halo_crash_install(const char *folder);

/* Records the step the start has reached (written to disk at once). */
void halo_crash_phase(const char *phase);

/* Reads the previous run's files; `phase` and `crash` get their text (empty if none), `crash_exists`
 * says whether crash.txt had anything. Call before halo_crash_install. */
int halo_crash_read_previous(const char *folder, char *phase, size_t phase_size, char *crash, size_t crash_size);

/* Deletes crash.txt (after a start that ran fine). */
void halo_crash_clear(const char *folder);

#ifdef __cplusplus
}
#endif

#endif
