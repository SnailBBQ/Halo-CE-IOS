# M2.6.27 — Selective iOS pointer fast path (Phase 1)

## Intent

Bounded native helpers plateaued on a10 (~0.5–0.9 FPS). Update and object-render
paths still pay ~120k / ~41k signal upgrades per call. M2.6.27 restores the
M2.6.20 selective assembly conversion on four measured hot objects, on **main**,
with host arena publication and crash breadcrumbs so a launch regression is diagnosable.

## Scope

Instrumented objects only (unchanged from M2.6.20):

- `port/linux/src/d3d8_gl`
- `source/physics/collision_bsp`
- `source/structures/structure_visibility`
- `source/structures/structure_render`

For each ordinary load/store through a nonzero 32-bit base register the converter
inserts a short sequence that adds `halo_ios_arena_base` instead of waiting for a
PAGEZERO fault. Wide pointers, null bases, SP operands, literal pools, atomics and
all other translation units keep the original signal bridge.

## Host / guest contract

1. Guest defines `unsigned long long halo_ios_arena_base` in `guest_start.c`.
2. Host resolves the symbol via the existing ELF symtab helper, writes the
   4-GiB-aligned arena base, and logs the VA / host pointer / value.
3. On `siglongjmp` abort the host logs reason, upgrade count, last fault address,
   last guest/host PC and instruction word.

## Build

`ios.yml` injects `--ios-pointer-fastpath` into the `android_asm_convert.py`
invocation after configure. Android builds are unaffected (no injection).

## Success criteria

- IPA launches to menu without crash.
- Log shows `M2.6.27 pointer fast path: halo_ios_arena_base ... value=0x...`.
- Residual signal upgrades drop on paths that hit the four objects.
- Geometry, text and a10 progression remain intact.

## If it crashes on launch

Share the full `ios-boot.log`. The abort breadcrumb line is the first thing to
inspect (`reason`, `last_guest_pc`, `last_fault`, `insn`). Do not expand the
object list until a clean boot is confirmed.

## Explicitly out of scope

- Full static rewrite / register reservation (x27/x15)
- Disabling the signal bridge
- Resolution / audio / networking changes
