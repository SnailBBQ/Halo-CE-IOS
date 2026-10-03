#ifndef HALO_COLOR_H
#define HALO_COLOR_H

/*
 * Accent colours for the Settings screens, as plain C so tools/tests/test_ios_color.c can check it: reading a hex
 * colour the player typed, keeping a chosen colour readable against the dark interface (buttons carry white text),
 * and the colour cycle ("chroma" mode). Colours are 0xRRGGBB.
 */

#include <math.h>
#include <string.h>

#define HX_DEFAULT_ACCENT 0x3385FAu

/* "#3385FA", "3385fa" or "#38F" (each digit doubled). Returns 1 and sets *rgb, or 0 for anything else. */
static inline int hx_parse(const char *text, unsigned *rgb)
{
    unsigned value = 0;
    size_t digits = 0, n;

    if (!text)
        return 0;
    while (*text == ' ' || *text == '\t')
        text++;
    if (*text == '#')
        text++;
    for (n = 0; text[n]; n++)
    {
        char c = text[n];
        unsigned d;

        if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
        {
            for (size_t k = n; text[k]; k++)
                if (text[k] != ' ' && text[k] != '\t' && text[k] != '\n' && text[k] != '\r')
                    return 0;
            break;
        }
        if (c >= '0' && c <= '9') d = (unsigned)(c - '0');
        else if (c >= 'a' && c <= 'f') d = (unsigned)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') d = (unsigned)(c - 'A' + 10);
        else return 0;
        if (digits >= 6)
            return 0;
        value = value * 16 + d;
        digits++;
    }
    if (digits == 3)
    {
        unsigned r = (value >> 8) & 15, g = (value >> 4) & 15, b = value & 15;
        value = (r * 17u << 16) | (g * 17u << 8) | (b * 17u);
    }
    else if (digits != 6)
        return 0;
    *rgb = value;
    return 1;
}

/* relative luminance 0..1 of an sRGB colour (WCAG) */
static inline float hx_luminance(unsigned rgb)
{
    float c[3] = { ((rgb >> 16) & 255) / 255.0f, ((rgb >> 8) & 255) / 255.0f, (rgb & 255) / 255.0f };

    for (int i = 0; i < 3; i++)
        c[i] = c[i] <= 0.03928f ? c[i] / 12.92f : powf((c[i] + 0.055f) / 1.055f, 2.4f);
    return 0.2126f * c[0] + 0.7152f * c[1] + 0.0722f * c[2];
}

/* Keeps a colour usable as a button background under white text and as a selection against the dark background:
 * too dark is lightened toward white and too light darkened toward black, until its luminance is in 0.06..0.40. */
static inline unsigned hx_clamp_accent(unsigned rgb)
{
    const float low = 0.06f, high = 0.40f;
    float r = ((rgb >> 16) & 255) / 255.0f, g = ((rgb >> 8) & 255) / 255.0f, b = (rgb & 255) / 255.0f;
    float luminance = hx_luminance(rgb);

    if (luminance < low)
    {
        /* mix with white until bright enough (bounded) */
        for (int i = 0; i < 40 && luminance < low; i++)
        {
            r += (1.0f - r) * 0.08f; g += (1.0f - g) * 0.08f; b += (1.0f - b) * 0.08f;
            luminance = hx_luminance(((unsigned)(r * 255.0f + 0.5f) << 16) | ((unsigned)(g * 255.0f + 0.5f) << 8) | (unsigned)(b * 255.0f + 0.5f));
        }
    }
    else if (luminance > high)
    {
        for (int i = 0; i < 40 && luminance > high; i++)
        {
            r *= 0.92f; g *= 0.92f; b *= 0.92f;
            luminance = hx_luminance(((unsigned)(r * 255.0f + 0.5f) << 16) | ((unsigned)(g * 255.0f + 0.5f) << 8) | (unsigned)(b * 255.0f + 0.5f));
        }
    }
    {
        unsigned R = (unsigned)(r * 255.0f + 0.5f), G = (unsigned)(g * 255.0f + 0.5f), B = (unsigned)(b * 255.0f + 0.5f);
        if (R > 255) R = 255;
        if (G > 255) G = 255;
        if (B > 255) B = 255;
        return (R << 16) | (G << 8) | B;
    }
}

/* hue 0..1 (wraps), saturation and value 0..1 */
static inline unsigned hx_hsv(float h, float s, float v)
{
    float r, g, b, f;
    int i;

    h = h - floorf(h);
    h *= 6.0f;
    i = (int)h;
    f = h - (float)i;
    {
        float p = v * (1.0f - s), q = v * (1.0f - s * f), t = v * (1.0f - s * (1.0f - f));
        switch (i % 6)
        {
            case 0: r = v; g = t; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = t; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = t; g = p; b = v; break;
            default: r = v; g = p; b = q; break;
        }
    }
    return ((unsigned)(r * 255.0f + 0.5f) << 16) | ((unsigned)(g * 255.0f + 0.5f) << 8) | (unsigned)(b * 255.0f + 0.5f);
}

/* the cycling colour after `seconds` of a cycle that takes `period` seconds; always readable */
static inline unsigned hx_chroma(double seconds, float period)
{
    double cycle = period < 2.0f ? 2.0 : (double)period;
    double position = fmod(seconds, cycle) / cycle;

    return hx_clamp_accent(hx_hsv((float)position, 0.78f, 0.95f));
}

#endif
