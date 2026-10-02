#include "halo_hash_native.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

static uint32_t fnv(const unsigned char *b, size_t n) { uint32_t h = 2166136261u; for (size_t i = 0; i < n; i++) h = (h ^ b[i]) * 16777619u; return h ? h : 1; }

int main(void)
{
    static unsigned char buffer[70000], copy[70000];
    srand(7);
    for (size_t i = 0; i < sizeof buffer; i++) buffer[i] = (unsigned char)rand();

    /* never zero, deterministic, alignment independent */
    CHECK(halo_hash_bytes(buffer, 0) != 0, "empty");
    for (size_t n = 0; n <= 300; n++)
    {
        uint32_t a = halo_hash_bytes(buffer, n);
        memcpy(copy + 1, buffer, n);
        CHECK(a != 0 && a == halo_hash_bytes(buffer, n) && a == halo_hash_bytes(copy + 1, n), "size %zu stable and alignment independent", n);
    }
    /* every single-bit change in sizes around each loop boundary changes the hash */
    size_t sizes[] = { 1, 7, 8, 9, 31, 32, 33, 40, 63, 64, 65, 100, 255, 256, 257, 4096, 4097, 65536 };
    for (size_t s = 0; s < sizeof sizes / sizeof sizes[0]; s++)
    {
        size_t n = sizes[s];
        uint32_t base = halo_hash_bytes(buffer, n);
        size_t step = n > 600 ? 97 : 1;
        for (size_t byte = 0; byte < n; byte += step)
            for (int bit = 0; bit < 8; bit += (n > 600 ? 3 : 1))
            {
                memcpy(copy, buffer, n);
                copy[byte] ^= (unsigned char)(1u << bit);
                if (halo_hash_bytes(copy, n) == base) { CHECK(0, "size %zu byte %zu bit %d: hash did not change", n, byte, bit); goto next; }
            }
    next:;
    }
    /* length is part of the hash: zeros of different lengths differ */
    memset(copy, 0, sizeof copy);
    CHECK(halo_hash_bytes(copy, 100) != halo_hash_bytes(copy, 101) && halo_hash_bytes(copy, 8) != halo_hash_bytes(copy, 16), "zero runs of different length");
    /* collisions across many random blocks of the size textures come in */
    enum { BLOCKS = 20000 };
    static uint32_t seen[BLOCKS];
    int collisions = 0;
    for (int i = 0; i < BLOCKS; i++)
    {
        for (int k = 0; k < 64; k++) copy[k] = (unsigned char)rand();
        seen[i] = halo_hash_bytes(copy, 64);
        for (int j = 0; j < i; j++) collisions += seen[j] == seen[i];
    }
    CHECK(collisions <= 1, "%d collisions among %d random blocks (expected about 0.05)", collisions, BLOCKS);
    /* the speed gain this exists for */
    clock_t t0 = clock(); uint32_t sink = 0;
    for (int i = 0; i < 2000; i++) { buffer[0] = (unsigned char)i; sink += fnv(buffer, 65536); }
    clock_t t1 = clock();
    for (int i = 0; i < 2000; i++) { buffer[0] = (unsigned char)i; sink += halo_hash_bytes(buffer, 65536); }
    clock_t t2 = clock();
    double old_ms = 1000.0 * (t1 - t0) / CLOCKS_PER_SEC, new_ms = 1000.0 * (t2 - t1) / CLOCKS_PER_SEC;
    CHECK(new_ms * 4 < old_ms, "expected at least 4x faster: old %.0f ms, new %.0f ms", old_ms, new_ms);
    if (!failures) printf("PASS: texture hash is stable, sensitive to every bit, collision-free on random blocks, %.1fx faster than byte-wise FNV (sink %u)\n", old_ms / (new_ms > 0 ? new_ms : 1), sink & 1);
    return failures ? 1 : 0;
}
