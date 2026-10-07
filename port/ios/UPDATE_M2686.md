# M2.6.86 — Non-Jailbreak flexible-base Stage 2

Regular app **0.2.86 / 2686**. The Mod Test app derives **0.2.86.1 / 268601**. The engine remains **OpenCE build 144** (`76b1898ee14e6fb58e0412acc183da509c10e001`), **network version 21**, with the same 20 MiB game-state capacity and Apple OpenGL ES renderer. M2.6.86 does not change OpenCE source, networking, gameplay, save format, Regular runtime behavior or Mod Test runtime behavior.

## Why this exists

M2.6.84 device logs separated three stock-iOS address-space cases. An iPhone 14 Plus on iOS 16.2 could reserve exactly 4 GiB at `0x2A0000000`, but that address is not 4-GiB aligned. An iPhone 16 Pro Max could obtain an aligned arena and progressed to the real guest handoff. An older iPad could not reserve 4 GiB contiguously at all. The first case is enough evidence to test the proposed arbitrary-base memory model without yet converting the real OpenCE guest.

## Stage 2

When the normal aligned-arena runtime fails, the **Non-Jailbreak Version only** now attempts an isolated Stage-2 experiment:

- reserve exactly one 4 GiB span with `mmap` at any address;
- require the returned base to be deliberately hostile (not 4-GiB aligned);
- translate guest addresses with `host = guest_base + zero_extend(uint32_t guest_va)` and reverse them with `guest = host - guest_base`;
- prove the old `low32(host) == guest_va` rule is false at representative guest addresses;
- test globals, a synthetic guest stack and heap, 32-bit pointers stored in guest-owned structures, pointer arithmetic and `memcpy`/`memset`;
- test a guest-mmap analogue by decommitting/replacing a page and checking that its recommitted anonymous storage is zeroed;
- test a lock-free 32-bit atomic from two host threads using only guest virtual addresses;
- test explicit host-import and callback dispatch without storing truncated host function pointers in guest memory; and
- write and execute a two-instruction AArch64 canary from the hostile arena after RW → RX protection.

The synthetic arena is **never** assigned to `g_guest_base`, and Stage 2 never calls `__guest_start` or the real Halo guest. Even a complete PASS is feasibility evidence for Stage 3, not a playable Non-Jailbreak build.

## Persistent phases

Stage 2 writes launch breadcrumbs so a silent process termination still identifies the boundary:

- `520` — requesting the exact 4 GiB Stage-2 reservation;
- `521` — hostile non-aligned arena obtained;
- `522` — base-relative memory, pointer and decommit/recommit model passed;
- `523` — atomics and second-thread access passed;
- `524` — host-import and callback dispatch passed;
- `525` — about to execute the unaligned RX canary;
- `526` — RX canary returned;
- `527` — complete Stage-2 synthetic guest passed.

The existing M2.6.84 phases 401–418 remain for devices where the normal aligned arena succeeds and the real guest reaches the execution-handoff investigation.

## CI guards

`tools/tests/test_ios_flex_base_model.c` checks representative Halo guest addresses against the exact hostile base seen on the iPhone (`0x2A0000000`) and requires correct base-relative round-trips while the legacy low32 identity fails. `tools/tests/test_ios_flex_stage2.py` checks that Stage 2 stays inside the Non-Jailbreak path, never assigns the synthetic reservation to `g_guest_base`, never calls the real guest, and is wired into CI. The workflow also compiles `halo_guest_runtime.c` with `HALO_NON_JAILBREAK=1` before the Apple build so pthread/atomic/Stage-2 compile regressions are caught early.

## Device checklist

1. Build **Non-Jailbreak Version** manually from M2.6.86; Regular and Mod Test are not Stage-2 test artifacts.
2. On the iPhone 14 Plus, export a problem report after launch. The expected useful path is `Flexible 4 GiB ANYWHERE: SUCCESS`, followed by `FLEXIBLE-BASE STAGE 2`.
3. If the app disappears, relaunch and inspect `launch-phase.txt`. A last phase of `525` strongly isolates the stop to instruction fetch from the hostile RX mapping; `526` proves that canary returned; `527` proves the complete synthetic model passed.
4. On the iPhone 16 Pro Max, the aligned arena may continue to use phases 401–418 instead; that is expected.
5. On the older iPad that cannot reserve 4 GiB anywhere, Stage 2 should report BLOCKED rather than attempting the real guest.
6. Do not interpret Stage-2 PASS as Non-Jailbreak support. Stage 3 still has to convert the real OpenCE guest away from low32/aligned-arena assumptions.

## Validation boundary

Local tests can validate the arithmetic model, source isolation, strict build-144 upstream equivalence and portable C/Python regressions. Only GitHub Actions can compile/package the exact Apple target, and only a physical free-signed iOS device can prove the hostile 4 GiB reservation and RX canary behavior.
