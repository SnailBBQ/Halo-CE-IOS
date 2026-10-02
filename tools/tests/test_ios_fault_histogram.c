/* Checks the lock-free pointer-fault histogram in halo_guest_exec_bridge.c. */
#include "../../port/ios/HaloIOS/halo_guest_exec_bridge.c"
/* the bridge's only external dependency, unused here */
void *halo_guest_base_address(void) { return 0; }
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

static void *worker(void *arg)
{
    uint32_t base = (uint32_t)(uintptr_t)arg;
    for (unsigned i = 0; i < 200000; i++) fault_hist_add(0x88000000u + base * 4 + (i % 5) * 4);
    return NULL;
}

int main(void)
{
    pthread_t threads[4];
    /* four threads hammer 5 PCs each, with overlap between neighbouring threads */
    for (uintptr_t t = 0; t < 4; t++) pthread_create(&threads[t], NULL, worker, (void *)(t * 2));
    for (int t = 0; t < 4; t++) pthread_join(threads[t], NULL);
    static halo_fault_hist_entry out[HALO_FAULT_HIST_SLOTS];
    unsigned n = halo_guest_fault_hist_take(out, HALO_FAULT_HIST_SLOTS);
    unsigned long long total = 0;
    for (unsigned i = 0; i < n; i++) total += out[i].count;
    if (total != 4ull * 200000ull) { printf("FAIL: lost counts, total %llu\n", total); return 1; }
    if (n != 11) { printf("FAIL: expected 11 distinct PCs, got %u\n", n); return 1; }
    /* taking clears the counts */
    if (halo_guest_fault_hist_take(out, HALO_FAULT_HIST_SLOTS) != 0) { printf("FAIL: counts not cleared\n"); return 1; }
    /* many distinct PCs must not loop forever or corrupt anything */
    for (uint32_t pc = 1; pc < 20000; pc++) fault_hist_add(pc * 4);
    n = halo_guest_fault_hist_take(out, HALO_FAULT_HIST_SLOTS);
    if (n == 0 || n > HALO_FAULT_HIST_SLOTS) { printf("FAIL: overflow handling, %u entries\n", n); return 1; }
    printf("PASS: fault histogram keeps every count across 4 threads, clears on take, survives table overflow\n");
    return 0;
}
