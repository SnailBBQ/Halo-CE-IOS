# M2.6.95 — Non-Jailbreak Stage-3 register-offset converter hotfix

Regular app **0.2.95 / 2695**. The Mod Test app derives **0.2.95.1 / 269501**. OpenCE remains **build 146** (`314f576515585560ea6b375b0d5b8a02fd8991af`), **network version 22**. Regular and Mod Test runtime behavior is unchanged.

## What M2.6.94 exposed

The first real flexible-base guest build reached musl object **50/1492** and then stopped exactly as the fail-closed converter was designed to do. `towctrans.o` contained the legal AArch64 instruction:

```asm
ldrb w16, [x12, x16]
```

The Stage-3 converter already handled immediate offsets and explicit `Wm, UXTW/SXTW` / `Xm, LSL #N` forms, but incorrectly required an explicit positive `LSL` for every X-register index. In AArch64, bare `[Xn, Xm]` is the normal register-offset spelling for **LSL #0**. The instruction was valid compiler output; our validator was incomplete. No unsafe guest binary was emitted.

## Fix

M2.6.95 preserves the x27 arena-base / x15 scratch ABI and now accepts the register-offset families Clang can emit for ordinary loads/stores:

- bare `Xm` (default `LSL #0`)
- `Xm, LSL #N` including `#0`
- `Xm, SXTX` / `Xm, SXTX #N`
- `Wm, UXTW` / `Wm, UXTW #N`
- `Wm, SXTW` / `Wm, SXTW #N`

Only the **base guest pointer** is translated through `x27 + zero_extend(wN)` into x15. The index expression is preserved verbatim, matching the original arm64_32 effective-address calculation. Invalid register-width/extension pairings still return no rewrite and are then rejected by the Stage-3 fail-closed scan.

## Regression coverage

`tools/tests/test_ios_flex_stage3.py` now includes the exact `towctrans.o` instruction plus the accepted register-offset families and invalid pairings. When `clang` is available, the converted `ldrb w16, [x15, x16]` probe is assembled for AArch64 ELF as an end-to-end converter/assembler check.

## Validation limit

The local environment still lacks the Android NDK used by Actions for the complete ~1,492-object guest build, so GitHub Actions remains the authority for discovering the next real compiler-emitted addressing form. The converter remains deliberately fail-closed: another unsupported valid form should stop CI rather than produce a silently incorrect guest.

## Test target

Run the manual **Non-Jailbreak Version**. The first success criterion is that `Build recovered Halo guest ELF` progresses past `towctrans.o` and continues through all 1,492 objects. Only after the flexible guest links should the IPA be device-tested for phases 600–609.
