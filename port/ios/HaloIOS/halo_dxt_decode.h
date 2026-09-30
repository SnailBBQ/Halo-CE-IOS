/* Shared scalar DXT decoder. Pixels are explicitly 32-bit on both hosts. */
#ifndef HALO_DXT_DECODE_H
#define HALO_DXT_DECODE_H
#include <stdint.h>
static uint32_t expand5(uint32_t v) { return (v << 3) | (v >> 2); }
static uint32_t expand6(uint32_t v) { return (v << 2) | (v >> 4); }
static uint32_t expand4(uint32_t v) { return v * 0x11; }
static uint32_t argb(uint32_t a, uint32_t r, uint32_t g, uint32_t b)
{ return (a << 24) | (r << 16) | (g << 8) | b; }
static uint32_t halo_dxt_color565(uint32_t value)
{
	return argb(255, expand5(value >> 11), expand6((value >> 5) & 0x3f), expand5(value & 0x1f));
}

static uint32_t halo_dxt_mix(uint32_t a, uint32_t b, uint32_t weight_a, uint32_t weight_b,
	uint32_t divisor)
{
	uint32_t result = 0;
	int shift;

	for (shift = 0; shift < 24; shift += 8)
	{
		uint32_t channel = (((a >> shift) & 0xff) * weight_a + ((b >> shift) & 0xff) * weight_b) / divisor;

		result |= channel << shift;
	}
	return result | 0xff000000UL;
}

/* one 4x4 block's colors; dxt1 selects the punch-through alpha mode */
static void halo_dxt_color_block(const unsigned char *block, int dxt1, uint32_t colors[16])
{
	uint32_t c0 = block[0] | (block[1] << 8);
	uint32_t c1 = block[2] | (block[3] << 8);
	uint32_t palette[4];
	uint32_t bits = block[4] | (block[5] << 8) | ((uint32_t)block[6] << 16) | ((uint32_t)block[7] << 24);
	int index;

	palette[0] = halo_dxt_color565(c0);
	palette[1] = halo_dxt_color565(c1);
	if (c0 > c1 || !dxt1)
	{
		palette[2] = halo_dxt_mix(palette[0], palette[1], 2, 1, 3);
		palette[3] = halo_dxt_mix(palette[0], palette[1], 1, 2, 3);
	}
	else
	{
		palette[2] = halo_dxt_mix(palette[0], palette[1], 1, 1, 2);
		palette[3] = 0;
	}
	for (index = 0; index < 16; index++)
		colors[index] = palette[(bits >> (index * 2)) & 3];
}

static void halo_dxt_decode_level(unsigned char kind, const unsigned char *source, uint32_t width, uint32_t height,
	uint32_t depth, uint32_t *destination)
{
	uint32_t blocks_x = (width + 3) / 4, blocks_y = (height + 3) / 4;
	uint32_t block_bytes = kind == 1 ? 8 : 16;
	uint32_t z, bx, by, x, y;

	for (z = 0; z < depth; z++)
	{
		for (by = 0; by < blocks_y; by++)
		{
			for (bx = 0; bx < blocks_x; bx++)
			{
				const unsigned char *block = source + ((z * blocks_y + by) * blocks_x + bx) * block_bytes;
				uint32_t colors[16];
				uint32_t alpha[16];
				int index;

				if (kind == 1)
				{
					halo_dxt_color_block(block, 1, colors);
					for (index = 0; index < 16; index++)
						alpha[index] = colors[index] >> 24;
				}
				else
				{
					halo_dxt_color_block(block + 8, 0, colors);
					if (kind == 3)
					{
						for (index = 0; index < 16; index++)
							alpha[index] = expand4((block[index / 2] >> ((index & 1) * 4)) & 0xf);
					}
					else
					{
						uint32_t a0 = block[0], a1 = block[1], values[8];
						uint64_t bits = 0;
						int bit;

						for (bit = 0; bit < 6; bit++)
							bits |= (uint64_t)block[2 + bit] << (bit * 8);
						values[0] = a0;
						values[1] = a1;
						if (a0 > a1)
						{
							for (index = 2; index < 8; index++)
								values[index] = ((8 - index) * a0 + (index - 1) * a1) / 7;
						}
						else
						{
							for (index = 2; index < 6; index++)
								values[index] = ((6 - index) * a0 + (index - 1) * a1) / 5;
							values[6] = 0;
							values[7] = 255;
						}
						for (index = 0; index < 16; index++)
							alpha[index] = values[(bits >> (index * 3)) & 7];
					}
				}
				for (y = 0; y < 4; y++)
				{
					for (x = 0; x < 4; x++)
					{
						uint32_t px = bx * 4 + x, py = by * 4 + y;

						if (px < width && py < height)
						{
							destination[(z * height + py) * width + px] =
								(colors[y * 4 + x] & 0x00ffffffUL) | (alpha[y * 4 + x] << 24);
						}
					}
				}
			}
		}
	}
}
#endif
