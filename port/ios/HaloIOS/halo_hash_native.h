#ifndef HALO_HASH_NATIVE_H
#define HALO_HASH_NATIVE_H

/*
 * Fast content hash for texture and cache data (host_texture_hash). The old byte-at-a-time FNV
 * took 25-28% of the game thread in the M2.6.32 profile; this reads 32 bytes per step through four
 * independent 64-bit lanes. The value is only compared within a run, so it may change between
 * versions; it never leaves the process.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

static inline uint64_t halo_hash_rotl(uint64_t value, int bits) { return (value << bits) | (value >> (64 - bits)); }

static inline uint64_t halo_hash_load64(const uint8_t *p) { uint64_t v; memcpy(&v, p, 8); return v; }

static inline uint64_t halo_hash_round(uint64_t acc, uint64_t input)
{
    acc += input * 0xC2B2AE3D27D4EB4FULL;
    acc = halo_hash_rotl(acc, 31);
    return acc * 0x9E3779B185EBCA87ULL;
}

static inline uint32_t halo_hash_bytes(const void *data, size_t size)
{
    const uint8_t *p = (const uint8_t *)data;
    const uint8_t *end = p + size;
    uint64_t h;

    if (size >= 32)
    {
        uint64_t a = 0x243F6A8885A308D3ULL, b = 0x13198A2E03707344ULL, c = 0xA4093822299F31D0ULL, d = 0x082EFA98EC4E6C89ULL;

        do
        {
            a = halo_hash_round(a, halo_hash_load64(p));
            b = halo_hash_round(b, halo_hash_load64(p + 8));
            c = halo_hash_round(c, halo_hash_load64(p + 16));
            d = halo_hash_round(d, halo_hash_load64(p + 24));
            p += 32;
        } while ((size_t)(end - p) >= 32);
        h = halo_hash_rotl(a, 1) + halo_hash_rotl(b, 7) + halo_hash_rotl(c, 12) + halo_hash_rotl(d, 18);
    }
    else
        h = 0x452821E638D01377ULL;
    h += (uint64_t)size;
    while ((size_t)(end - p) >= 8)
    {
        h ^= halo_hash_round(0, halo_hash_load64(p));
        h = halo_hash_rotl(h, 27) * 0x9E3779B185EBCA87ULL + 0x165667B19E3779F9ULL;
        p += 8;
    }
    while (p < end)
    {
        h ^= (uint64_t)(*p++) * 0x27D4EB2F165667C5ULL;
        h = halo_hash_rotl(h, 11) * 0x9E3779B185EBCA87ULL;
    }
    h ^= h >> 33;
    h *= 0xC2B2AE3D27D4EB4FULL;
    h ^= h >> 29;
    h *= 0x165667B19E3779F9ULL;
    h ^= h >> 32;
    return (uint32_t)h ? (uint32_t)h : 1u;
}

#endif
