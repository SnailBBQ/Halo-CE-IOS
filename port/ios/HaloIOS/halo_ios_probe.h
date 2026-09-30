#ifndef HALO_IOS_PROBE_H
#define HALO_IOS_PROBE_H

void halo_ios_run_m0_probe(void (^line)(const char *text));
int halo_ios_run_m05_dynamic_probe(void (^line)(const char *text));

#endif
