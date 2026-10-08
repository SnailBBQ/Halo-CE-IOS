# M2.6.101 — Non-Jailbreak frame-pointer chain fix

Regular app **0.2.101 / 2701**. The Mod Test app derives **0.2.101.1 / 270101**. OpenCE stays on **build 155 / network 24**. The Regular and Mod Test (aligned) converter output is unchanged by this update.

## What the M2.6.100 logs showed

**Regular** (iPhone 14 Plus, 60 Hz): 11 of 15 reporting windows presented at 59.8–59.97 FPS with 98–100% of frames at or under 18 ms. SIGSEGV-bridge upgrades fell from millions per window to 2,000–5,000 per 10 s. About seven frames in roughly 7,300 took 25–43 ms, all render-side. Three windows ran at 73, 90 and 241 FPS on a static screen because the Settings mode in that log was *Uncapped*, which does not hold 60 on a 60 Hz screen when frames are cheap.

**Non-Jailbreak** (flexible base `0x2a0000000`): the guest ran through phases 600–609, loaded `ui.map`, completed every loading step and the first game frame, then stopped in `get_return_eip+0x10`, called from `motion_sensor_tick` in `hud_draw_screen`, with a fault at host `0x32dffed78`.

## Cause

`get_return_eip()` returns `__builtin_return_address(1)`. LLVM walks the frame chain with:

```text
ldr x8, [x29]          ; the caller's saved frame pointer
ldr x30, [x8, #8]      ; its return address
```

x29 is a **host** stack address (the guest stack is at guest `0xed000000`, host `0x38d000000`). Every other pointer a guest keeps in memory is a 32-bit guest VA, so the flexible converter translated the second load with `add x15, x27, w8, uxtw`. That truncated the host address (`0x38dffed70` became `0x8dffed70`) and added the base: `0x2a0000000 + 0x8dffed70 = 0x32dffed70`, which is not mapped. The fault address in the log is exactly that plus 8. The aligned (Regular) model does not truncate this way, so Regular never showed it.

## Fix (tools/android_asm_convert.py, flexible-base only)

A 64-bit `ldr xN, [x29]` (or `[x29, #0]`) and the first register of `ldp xN, xM, [x29]` load the saved frame pointer. The converter now follows them with `sub xN, xN, x27`, the same host-to-guest canonicalization it already applies to `mov xN, sp`, so the next dereference translates correctly. `ldr w`, nonzero offsets, `ldp x29, x30, [sp]` and everything else are unchanged.

## Tests

`tools/tests/test_ios_flex_stage3.py` gained unit cases for the two frame-load forms and the unchanged forms, and a regression that compiles the real `get_return_eip` with the guest flags, converts it, checks the load/sub/translate sequence and assembles it. It fails on the M2.6.100 converter.

## Limits

The 1,492-object guest build, the Xcode build and device behavior run only on GitHub Actions and the phone. This fixes the one fault seen; the guest had just finished its first frame, so later code may expose another. Any further unconverted form still stops with the same fail-closed message and a PC.

For Regular, the log suggests choosing **60 · Smooth** instead of Uncapped on a 60 Hz phone: it holds 60 on menus and pauses too. No Regular code changed in this update.
