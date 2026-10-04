#ifndef HALO_PAD_INPUT_H
#define HALO_PAD_INPUT_H

/*
 * Physical-controller input shaping, as plain C so tools/tests/test_ios_pad_input.c can check it: which game button
 * each controller button presses (remapping), a radial dead zone and response curve for the sticks, and the mapping of
 * a device's turning rate onto look movement (gyro aiming). Button numbers are SDL3's, as in halo_controls_layout.h.
 */

#include <math.h>
#include <stdint.h>

#define HP_BUTTONS 14

/* the remappable buttons, in the order the settings store and show them */
static const unsigned char hp_sdl_button[HP_BUTTONS] = { 0, 1, 2, 3, 9, 10, 6, 4, 7, 8, 11, 12, 13, 14 };
static const char *const hp_names[HP_BUTTONS] = {
    "A", "B", "X", "Y", "White (left shoulder)", "Black (right shoulder)", "Start", "Back",
    "Left stick click", "Right stick click", "D-pad up", "D-pad down", "D-pad left", "D-pad right"
};

static inline void hp_identity(unsigned char map[HP_BUTTONS])
{
    for (int i = 0; i < HP_BUTTONS; i++)
        map[i] = (unsigned char)i;
}

static inline int hp_is_identity(const unsigned char map[HP_BUTTONS])
{
    for (int i = 0; i < HP_BUTTONS; i++)
        if (map[i] != i)
            return 0;
    return 1;
}

/* Pressing physical button i sends game button map[i]. Entries out of range send the button itself. */
static inline uint32_t hp_remap(uint32_t physical, const unsigned char map[HP_BUTTONS])
{
    uint32_t known = 0, out = 0;

    for (int i = 0; i < HP_BUTTONS; i++)
    {
        unsigned target = map[i] < HP_BUTTONS ? map[i] : (unsigned)i;

        known |= 1u << hp_sdl_button[i];
        if (physical & (1u << hp_sdl_button[i]))
            out |= 1u << hp_sdl_button[target];
    }
    return out | (physical & ~known);
}

/* Radial dead zone and response curve for one stick, -1..1 in and out. The dead zone is removed, not just cut off, so the
 * output still starts from zero. A curve above 1 gives finer control near the centre. */
static inline void hp_stick(float x, float y, float dead, float curve, float *out_x, float *out_y)
{
    float magnitude = sqrtf(x * x + y * y), scaled;

    if (!(magnitude > 0.0f) || !(magnitude > dead))
    {
        *out_x = *out_y = 0.0f;
        return;
    }
    if (magnitude > 1.0f)
        magnitude = 1.0f;
    if (dead >= 0.99f)
        dead = 0.99f;
    scaled = (magnitude - dead) / (1.0f - dead);
    if (scaled < 0.0f) scaled = 0.0f;
    if (scaled > 1.0f) scaled = 1.0f;
    scaled = curve > 1.0f ? powf(scaled, curve) : scaled;
    {
        float source = sqrtf(x * x + y * y);   /* direction comes from the unclamped input */
        *out_x = x / source * scaled;
        *out_y = y / source * scaled;
    }
}

/* Gyro aiming: a turning rate in radians per second about the device's x and y axes, over dt seconds, becomes look movement
 * in the units the touch look uses. Held in landscape, turning about x turns the view left and right and about y tilts it.
 * landscape_flipped is the other landscape orientation (everything reverses); flip_yaw and flip_pitch are the player's
 * own corrections. Rates below dead (rad/s) are ignored so a held device does not drift. */
#define HP_GYRO_POINTS_PER_RADIAN 420.0f

static inline void hp_gyro_look(float rate_x, float rate_y, float dt, float sensitivity, int landscape_flipped,
                                int flip_yaw, int flip_pitch, float dead, float *look_x, float *look_y)
{
    float orientation = landscape_flipped ? -1.0f : 1.0f;
    float yaw = fabsf(rate_x) < dead ? 0.0f : rate_x;
    float pitch = fabsf(rate_y) < dead ? 0.0f : rate_y;

    if (!(dt > 0.0f) || dt > 0.25f || !isfinite(yaw) || !isfinite(pitch) || !isfinite(sensitivity))
    {
        *look_x = *look_y = 0.0f;
        return;
    }
    /* Device yaw and screen look have opposite signs; pitch is unchanged. */
    *look_x = -orientation * (flip_yaw ? -1.0f : 1.0f) * yaw * dt * sensitivity * HP_GYRO_POINTS_PER_RADIAN;
    *look_y = orientation * (flip_pitch ? -1.0f : 1.0f) * pitch * dt * sensitivity * HP_GYRO_POINTS_PER_RADIAN;
}

#endif
