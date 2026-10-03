#include "halo_pad_input.h"
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

static uint32_t bit(int index) { return 1u << hp_sdl_button[index]; }

int main(void)
{
    unsigned char map[HP_BUTTONS];
    hp_identity(map);
    CHECK(hp_is_identity(map), "identity");

    /* every button maps to itself by default, and nothing else changes */
    for (int i = 0; i < HP_BUTTONS; i++) CHECK(hp_remap(bit(i), map) == bit(i), "identity keeps button %d", i);
    CHECK(hp_remap(0, map) == 0 && hp_remap(bit(0) | bit(3) | bit(9), map) == (bit(0) | bit(3) | bit(9)), "combinations survive");

    /* swap A and B (the Xbox confirm/back swap) */
    map[0] = 1; map[1] = 0;
    CHECK(!hp_is_identity(map), "not identity any more");
    CHECK(hp_remap(bit(0), map) == bit(1) && hp_remap(bit(1), map) == bit(0), "A and B swapped");
    CHECK(hp_remap(bit(0) | bit(1), map) == (bit(0) | bit(1)), "both pressed: both still pressed");
    CHECK(hp_remap(bit(2), map) == bit(2), "X untouched");

    /* two buttons onto one: either presses it; the other button sends nothing of its own */
    hp_identity(map); map[2] = 3;   /* physical X presses Y */
    CHECK(hp_remap(bit(2), map) == bit(3) && hp_remap(bit(3), map) == bit(3) && hp_remap(bit(2) | bit(3), map) == bit(3), "many to one");

    /* bits that are not remappable buttons (such as a stray high bit) pass through; out-of-range entries send the button itself */
    hp_identity(map); map[5] = 200;
    CHECK(hp_remap(bit(5), map) == bit(5), "out of range entry leaves the button alone");
    CHECK(hp_remap(0x80000000u, map) == 0x80000000u, "unknown bits pass through");

    /* the SDL numbers are the ones the guest layout uses */
    CHECK(hp_sdl_button[0] == 0 && hp_sdl_button[4] == 9 && hp_sdl_button[5] == 10 && hp_sdl_button[6] == 6 && hp_sdl_button[7] == 4 && hp_sdl_button[13] == 14, "SDL numbers");

    /* a remap is a function of the physical buttons only: exhaustive over every subset of 14 buttons */
    hp_identity(map); map[0] = 5; map[5] = 0; map[7] = 6; map[6] = 7;
    for (uint32_t subset = 0; subset < (1u << HP_BUTTONS); subset++)
    {
        uint32_t physical = 0, expected = 0;
        for (int i = 0; i < HP_BUTTONS; i++) if (subset & (1u << i)) { physical |= bit(i); expected |= bit(map[i]); }
        if (hp_remap(physical, map) != expected) { CHECK(0, "subset %u wrong", subset); break; }
    }

    /* sticks: dead zone removed, curve, direction kept, clamped */
    float x, y;
    hp_stick(0.05f, 0.0f, 0.1f, 1.0f, &x, &y);
    CHECK(x == 0 && y == 0, "inside the dead zone is zero");
    hp_stick(0.1f, 0.0f, 0.1f, 1.0f, &x, &y);
    CHECK(x == 0 && y == 0, "exactly at the dead zone is zero");
    hp_stick(0.55f, 0.0f, 0.1f, 1.0f, &x, &y);
    CHECK(fabsf(x - 0.5f) < 1e-5f && y == 0, "the dead zone is removed: 0.55 with 0.1 gives 0.5 (%f)", x);
    hp_stick(1.0f, 0.0f, 0.1f, 1.0f, &x, &y);
    CHECK(fabsf(x - 1.0f) < 1e-5f, "full deflection is still full");
    hp_stick(0.6f, 0.8f, 0.0f, 1.0f, &x, &y);
    CHECK(fabsf(x - 0.6f) < 1e-5f && fabsf(y - 0.8f) < 1e-5f, "no dead zone, no curve: unchanged");
    hp_stick(-0.6f, -0.8f, 0.2f, 1.0f, &x, &y);
    CHECK(x < 0 && y < 0 && fabsf(y / x - 0.8f / 0.6f) < 1e-4f, "direction is kept (%f %f)", x, y);
    hp_stick(0.5f, 0.0f, 0.0f, 2.0f, &x, &y);
    CHECK(fabsf(x - 0.25f) < 1e-5f, "curve 2 squares the response: 0.5 gives 0.25 (%f)", x);
    hp_stick(1.4f, 1.4f, 0.1f, 1.0f, &x, &y);
    CHECK(sqrtf(x * x + y * y) <= 1.0001f && x > 0 && y > 0, "a corner reading is clamped to the unit circle");
    hp_stick(0.0f, 0.0f, 0.1f, 3.0f, &x, &y);
    CHECK(x == 0 && y == 0, "zero in, zero out");
    hp_stick(0.5f, 0.5f, 5.0f, 1.0f, &x, &y);
    CHECK(x == 0 && y == 0, "a silly dead zone just gives zero");
    hp_stick(NAN, 0.3f, 0.1f, 1.0f, &x, &y);
    CHECK(x == 0 && y == 0, "NaN gives zero");
    /* monotonic: more push never gives less output */
    float previous = -1;
    for (int i = 0; i <= 200; i++) { hp_stick(i / 200.0f, 0, 0.12f, 1.8f, &x, &y); CHECK(x >= previous - 1e-6f, "monotonic at %d", i); previous = x; }

    /* gyro */
    float lx, ly;
    hp_gyro_look(0, 0, 0.016f, 1.0f, 0, 0, 0, 0.02f, &lx, &ly);
    CHECK(lx == 0 && ly == 0, "no turning, no look");
    hp_gyro_look(1.0f, 0.5f, 0.01f, 1.0f, 0, 0, 0, 0.02f, &lx, &ly);
    CHECK(fabsf(lx - 4.2f) < 1e-4f && fabsf(ly - 2.1f) < 1e-4f, "1 rad/s for 10 ms is 4.2 points (%f %f)", lx, ly);
    float fx, fy;
    hp_gyro_look(1.0f, 0.5f, 0.01f, 1.0f, 1, 0, 0, 0.02f, &fx, &fy);
    CHECK(fabsf(fx + lx) < 1e-5f && fabsf(fy + ly) < 1e-5f, "the other landscape reverses both");
    hp_gyro_look(1.0f, 0.5f, 0.01f, 1.0f, 0, 1, 0, 0.02f, &fx, &fy);
    CHECK(fabsf(fx + lx) < 1e-5f && fabsf(fy - ly) < 1e-5f, "flip yaw reverses only yaw");
    hp_gyro_look(1.0f, 0.5f, 0.01f, 1.0f, 0, 0, 1, 0.02f, &fx, &fy);
    CHECK(fabsf(fx - lx) < 1e-5f && fabsf(fy + ly) < 1e-5f, "flip pitch reverses only pitch");
    hp_gyro_look(1.0f, 0.5f, 0.01f, 2.0f, 0, 0, 0, 0.02f, &fx, &fy);
    CHECK(fabsf(fx - 2 * lx) < 1e-5f, "sensitivity scales linearly");
    hp_gyro_look(0.01f, 0.01f, 0.01f, 3.0f, 0, 0, 0, 0.02f, &fx, &fy);
    CHECK(fx == 0 && fy == 0, "a held device's tiny drift is ignored");
    hp_gyro_look(1.0f, 1.0f, 5.0f, 1.0f, 0, 0, 0, 0.02f, &fx, &fy);
    CHECK(fx == 0 && fy == 0, "a stale sample (after a pause) is ignored");
    hp_gyro_look(NAN, 1.0f, 0.01f, 1.0f, 0, 0, 0, 0.02f, &fx, &fy);
    CHECK(fx == 0 && fy == 0, "NaN is ignored");
    hp_gyro_look(1.0f, 1.0f, 0.0f, 1.0f, 0, 0, 0, 0.02f, &fx, &fy);
    CHECK(fx == 0 && fy == 0, "zero time gives nothing");

    if (!failures) printf("PASS: controller remap (every subset of 14 buttons), stick dead zone and curve, gyro look mapping\n");
    return failures ? 1 : 0;
}
