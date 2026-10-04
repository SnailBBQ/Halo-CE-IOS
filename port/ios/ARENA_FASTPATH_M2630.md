> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# M2.6.30 — arena fast path (fault-free guest loads/stores)

## Why

Device logs for M2.6.21–M2.6.29 show about 640,000 pointer upgrades per render call and about 120,000 per update call at roughly 3 µs per signal round trip. That is ~2 s per frame, which matches the 0.4 FPS in `a10`. The native helpers removed individual hot loops but could not remove the faults: the signal bridge only upgrades the one register that faulted, so every pointer reloaded from a struct faults again.

## What changed

`tools/android_asm_convert.py --ios-arena-fastpath` rewrites ordinary guest loads/stores so they never fault:

```
adr  x15, .                         ; guest code runs at arena + VA
and  x15, x15, #0xffffffff00000000  ; arena base (4-GiB aligned)
add  x15, x15, wN, uxtw             ; arena + low32(base)
ldr  w0, [x15, <original offset>]   ; original instruction, new base
```

- No spill, no host variable, no flags touched, original base register left unchanged (writeback forms are split into `add`/`sub` plus an offset-free access).
- Works for zero-extended 32-bit VAs and for pointers that are already arena addresses (stack, `adrp` results) because both have the same low 32 bits.
- `blr xN` is translated when `xN` is a narrow function pointer and called unchanged when it is wide.
- The signal bridge stays installed. Any site the pass skips still works exactly as before.

Skipped on purpose: `sp`/`x29`/`x30` bases, `[xN, :lo12:sym]` (already arena-wide), ambiguous `[xN, xM]` register offsets, `ld1/st1`, `prfm`, exclusives/acquire-release, `br`, and any object under `port/android/guest/`.

## Safety conditions

1. **x15 is reserved.** The workflow adds `-ffixed-x15` to the guest target flags. The pass additionally refuses any object whose assembly mentions `x15`/`w15` (it prints a warning and leaves that object on the signal bridge).
2. **Compressed jump tables.** Functions that own `.byte/.hword (a-b)>>2` tables are left untouched, because the inserted instructions could overflow those fixed-width entries.
3. **Invariant:** every wide pointer the guest holds is an arena pointer. Stacks and the image live in the arena and the host only hands the guest guest-VAs. A raw host pointer inside guest code would be corrupted by the rewrite.

## A/B testing

Run **Halo CE iOS — Build IPA** manually and set **arena_fastpath** to `false` for a baseline build with the old behaviour. Push-triggered builds default to `true`.

Compare in the same scenes (menu, a10 intro, skip, tutorial):

- presentation FPS
- render and update CPU time
- pointer upgrades per call (should drop by orders of magnitude; residual faults come from skipped sites)

If the app crashes at launch, share `ios-boot.log` first; the abort breadcrumb (`reason`, `last_guest_pc`, `last_fault`, `insn`) names the instruction. Then build once with `arena_fastpath=false` to confirm the rewrite is the cause.

## Validation

`tools/tests/test_ios_arena_fastpath.py` (pure Python, runs in the workflow) models the emitted sequence for 640+ instruction forms and compares effective address, writeback and register preservation with the signal bridge's behaviour; it also checks skip rules, `blr`, jump-table handling and the CLI. `tools/tests/test_ios_workflow_configuration.py` checks the workflow's `build.ninja` patching with the rewrite on, off, defaulted and with a missing guest target.

Not verified here: Apple/Android-NDK compilation of the rewritten assembly, `-ffixed-x15` acceptance by the CI clang, and any device behaviour. This milestone makes no FPS claim until it is measured on a device.
