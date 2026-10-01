#pragma once
#include <stdint.h>
#include <stdlib.h>
/* Same Xbox channel and swizzle rules, using fixed-width host types.
   One/two-byte formats do not read the following texel. */
enum texel_kind
{
	_texel_unknown,
	_texel_a8r8g8b8, _texel_x8r8g8b8, _texel_r5g6b5, _texel_a1r5g5b5, _texel_x1r5g5b5, _texel_a4r4g4b4,
	_texel_l8, _texel_al8, _texel_a8, _texel_a8l8, _texel_p8, _texel_g8b8, _texel_r8b8, _texel_r6g5b5,
	_texel_l16, _texel_v16u16, _texel_a8b8g8r8, _texel_b8g8r8a8, _texel_r8g8b8a8, _texel_r5g5b5a1,
	_texel_r4g4b4a4, _texel_yuy2, _texel_uyvy, _texel_d24s8, _texel_d16,
	_texel_dxt1, _texel_dxt3, _texel_dxt5,
};

struct halo_native_swizzle_masks
{
	uint32_t x, y, z;
};

static struct halo_native_swizzle_masks halo_native_swizzle_masks(uint32_t width, uint32_t height, uint32_t depth)
{
	struct halo_native_swizzle_masks masks = { 0, 0, 0 };
	uint32_t bit = 1, mask_bit = 1;
	int done;

	/* bits of x, y and z alternate until each dimension runs out */
	do
	{
		done = 1;
		if (bit < width)
		{
			masks.x |= mask_bit;
			mask_bit <<= 1;
			done = 0;
		}
		if (bit < height)
		{
			masks.y |= mask_bit;
			mask_bit <<= 1;
			done = 0;
		}
		if (bit < depth)
		{
			masks.z |= mask_bit;
			mask_bit <<= 1;
			done = 0;
		}
		bit <<= 1;
	} while (!done);
	return masks;
}

static uint32_t halo_native_spread(uint32_t mask, uint32_t value)
{
	uint32_t result = 0, bit = 1;

	while (value && bit)
	{
		if (mask & bit)
		{
			if (value & 1)
				result |= bit;
			value >>= 1;
		}
		bit <<= 1;
	}
	return result;
}

/* ---------- texel conversion */

static uint32_t halo_native_expand5(uint32_t v) { return (v << 3) | (v >> 2); }
static uint32_t halo_native_expand6(uint32_t v) { return (v << 2) | (v >> 4); }
static uint32_t halo_native_expand4(uint32_t v) { return v * 0x11; }

static uint32_t halo_native_argb(uint32_t a, uint32_t r, uint32_t g, uint32_t b)
{
	return (a << 24) | (r << 16) | (g << 8) | b;
}

static unsigned char halo_native_clamp_byte(int32_t value)
{
	return (unsigned char)(value < 0 ? 0 : value > 255 ? 255 : value);
}

static uint32_t halo_native_yuv_to_argb(int32_t y, int32_t u, int32_t v)
{
	int32_t c = y - 16, d = u - 128, e = v - 128;

	return halo_native_argb(255, halo_native_clamp_byte((298 * c + 409 * e + 128) >> 8),
		halo_native_clamp_byte((298 * c - 100 * d - 208 * e + 128) >> 8),
		halo_native_clamp_byte((298 * c + 516 * d + 128) >> 8));
}

static uint32_t halo_native_convert_texel(unsigned char kind, const unsigned char *source, const uint32_t *palette,
	uint32_t x, const unsigned char *row, uint32_t bytes)
{
	uint32_t v16 = source[0] | (bytes >= 2 ? ((uint32_t)source[1] << 8) : 0);
	uint32_t v32 = v16 | (bytes >= 4 ? ((uint32_t)source[2] << 16) | ((uint32_t)source[3] << 24) : 0);

	switch (kind)
	{
	case _texel_a8r8g8b8: return v32;
	case _texel_x8r8g8b8: return v32 | 0xff000000UL;
	case _texel_r5g6b5: return halo_native_argb(255, halo_native_expand5(v16 >> 11), halo_native_expand6((v16 >> 5) & 0x3f), halo_native_expand5(v16 & 0x1f));
	case _texel_a1r5g5b5: return halo_native_argb((v16 & 0x8000) ? 255 : 0, halo_native_expand5((v16 >> 10) & 0x1f), halo_native_expand5((v16 >> 5) & 0x1f), halo_native_expand5(v16 & 0x1f));
	case _texel_x1r5g5b5: return halo_native_argb(255, halo_native_expand5((v16 >> 10) & 0x1f), halo_native_expand5((v16 >> 5) & 0x1f), halo_native_expand5(v16 & 0x1f));
	case _texel_a4r4g4b4: return halo_native_argb(halo_native_expand4(v16 >> 12), halo_native_expand4((v16 >> 8) & 0xf), halo_native_expand4((v16 >> 4) & 0xf), halo_native_expand4(v16 & 0xf));
	case _texel_l8: return halo_native_argb(255, source[0], source[0], source[0]);
	case _texel_al8: return halo_native_argb(source[0], source[0], source[0], source[0]);
	case _texel_a8: return halo_native_argb(source[0], 255, 255, 255);
	case _texel_a8l8: return halo_native_argb(source[1], source[0], source[0], source[0]);
	case _texel_p8: return palette ? palette[source[0]] : halo_native_argb(255, source[0], source[0], source[0]);
	/* V8U8 shares this format: U (the low byte) reads as red, V as green */
	case _texel_g8b8: return halo_native_argb(255, source[0], source[1], 0);
	case _texel_r8b8: return halo_native_argb(255, source[1], 0, source[0]);
	case _texel_r6g5b5: return halo_native_argb(255, halo_native_expand6(v16 >> 10), halo_native_expand5((v16 >> 5) & 0x1f), halo_native_expand5(v16 & 0x1f));
	case _texel_l16: return halo_native_argb(255, source[1], source[1], source[1]);
	case _texel_v16u16: return halo_native_argb(255, source[1], source[3], 0);
	case _texel_a8b8g8r8: return halo_native_argb(source[3], source[0], source[1], source[2]);
	case _texel_b8g8r8a8: return halo_native_argb(source[0], source[1], source[2], source[3]);
	case _texel_r8g8b8a8: return halo_native_argb(source[0], source[3], source[2], source[1]);
	case _texel_r5g5b5a1: return halo_native_argb((v16 & 1) ? 255 : 0, halo_native_expand5(v16 >> 11), halo_native_expand5((v16 >> 6) & 0x1f), halo_native_expand5((v16 >> 1) & 0x1f));
	case _texel_r4g4b4a4: return halo_native_argb(halo_native_expand4(v16 & 0xf), halo_native_expand4(v16 >> 12), halo_native_expand4((v16 >> 8) & 0xf), halo_native_expand4((v16 >> 4) & 0xf));
	case _texel_yuy2:
	{
		const unsigned char *pair = row + (x & ~1UL) * 2;

		return halo_native_yuv_to_argb(pair[(x & 1) ? 2 : 0], pair[1], pair[3]);
	}
	case _texel_uyvy:
	{
		const unsigned char *pair = row + (x & ~1UL) * 2;

		return halo_native_yuv_to_argb(pair[(x & 1) ? 3 : 1], pair[0], pair[2]);
	}
	case _texel_d24s8: return halo_native_argb(255, source[3], source[3], source[3]);
	case _texel_d16: return halo_native_argb(255, source[1], source[1], source[1]);
	default: return v32;
	}
}


static int halo_texel_native(uint32_t kind, uint32_t bytes, int linear,
    uint32_t width, uint32_t height, uint32_t depth, uint32_t pitch,
    const uint8_t *source, const uint32_t *palette, uint32_t *destination)
{
    if (linear) {
        for (uint32_t y = 0; y < height; y++) {
            const uint8_t *row = source + (size_t)y * pitch;
            for (uint32_t x = 0; x < width; x++)
                destination[(size_t)y * width + x] = halo_native_convert_texel(kind, row + x * bytes, palette, x, row, bytes);
        }
        return 1;
    }
    struct halo_native_swizzle_masks masks = halo_native_swizzle_masks(width, height, depth);
    uint32_t *offsets = malloc((size_t)width * sizeof(*offsets));
    if (!offsets) return 0;
    for (uint32_t x = 0; x < width; x++) offsets[x] = halo_native_spread(masks.x, x);
    for (uint32_t z = 0; z < depth; z++)
        for (uint32_t y = 0; y < height; y++) {
            uint32_t yz = halo_native_spread(masks.y, y) | halo_native_spread(masks.z, z);
            for (uint32_t x = 0; x < width; x++) {
                const uint8_t *texel = source + (size_t)(offsets[x] | yz) * bytes;
                destination[((size_t)z * height + y) * width + x] = halo_native_convert_texel(kind, texel, palette, x, texel, bytes);
            }
        }
    free(offsets);
    return 1;
}
