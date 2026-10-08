# M2.6.99 — Non-Jailbreak x30 guest-pointer translation

Regular app **0.2.99 / 2699**. The Mod Test app derives **0.2.99.1 / 269901**. OpenCE stays on **build 155 / network 24**. Regular and Mod Test runtime behavior is unchanged.

## What the M2.6.98 device log showed

The Non-Jailbreak IPA on an iPhone 14 Plus (iOS 16.2, no entitlements) reserved the flexible 4 GiB arena at `0x2a0000000`, then ran the real OpenCE guest through every Stage-3 phase **600–609**: ELF loaded, 243 host imports resolved, `__guest_start` reached, constructors run, OpenCE `main()` entered, an OpenGL ES 3 context created and audio opened. It then stopped with the converter's deliberate fail-closed abort:

```text
unconverted low-pointer memory fault at guest PC 0x883fffa0 (base register x30)
insn=0xb94003c9  (ldr w9, [x30])   in mod_l+0x190
```

## Cause

`mod_l` is monocypher's ed25519 reduction. It has so many live values that LLVM saves the link register (`stp x29, x30, [sp, ...]`) and then **allocates x30 as an ordinary register**, here holding a guest pointer. The flexible-base converter skipped every access whose base was x29 or x30 on the assumption that they only hold host stack/return addresses. That is true for x29 (the Darwin frame pointer) but not for a reused x30. The aligned model never noticed because its signal bridge upgrades such pointers; the flexible model has no fallback, so it aborted.

## Fix (flexible-base converter only)

- Memory accesses with base x30 are translated like any other base: `add x15, x27, w30, uxtw` then the access through x15 (offsets, writeback and register-offset forms included; x30 used as an *index* stays an index).
- `blr x30` / `br x30` get the existing wide-or-guest test: a real return address is host-wide (non-zero high half) and is used unchanged, a guest function pointer is mapped through x27.
- `adrp/adr x30`, `add/sub x30, sp|x29, ...` and `mov x30, sp|x29` are canonicalized back to guest VAs (`sub x30, x30, x27`) like every other register.
- x29 stays untouched; `ret`, `ldp/stp x29, x30` on SP and x15/x27 handling are unchanged. The regular aligned converter is not changed (a test pins that).

## Validation

- Reproduced with the real `arm64_32-apple-watchos` compiler and the guest flags: monocypher's `mod_l` shows `ldr w9, [x30]` / `str w11, [x30]`, which now convert and assemble.
- A generated register-pressure stress set had 246 untranslated x30 accesses per file under the M2.6.98 converter and 0 after this change; 92 further guest-flag sources converted and assembled with no untranslated memory base.
- `tools/tests/test_ios_flex_stage3.py` gained unit cases (loads, stores, writeback, index use, `blr`/`br`, address materialization, unchanged return paths), the aligned-unchanged check, and a compiler probe that fails if LLVM stops reusing x30.

## Limits

The full 1,492-object guest build and the Xcode build run only on GitHub Actions. This fixes the one fault seen so far; the next device run may reach other code. A converter cannot be proven complete locally, so any further unconverted form will again stop the guest with the same fail-closed message and a PC to look up.
