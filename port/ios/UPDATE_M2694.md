# M2.6.94 — Non-Jailbreak real-guest flexible-base Stage 3

Regular app **0.2.94 / 2694**. The Mod Test app derives **0.2.94.1 / 269401**. OpenCE remains **build 146** (`314f576515585560ea6b375b0d5b8a02fd8991af`), **network version 22**. Regular and Mod Test keep the existing aligned-arena guest. This milestone changes only the manual **Non-Jailbreak Version** into the first real OpenCE arbitrary-base candidate.

## Evidence from M2.6.93

M2.6.93 passed GitHub Actions. On the iPhone 14 Plus (`iPhone14,8`, iOS 16.2), the normal 4-GiB-aligned arena was unavailable, but an exact 4 GiB span was reserved at `0x2A0000000`. Stage 2 passed the base+uint32 memory model, guest mmap/decommit/recommit, atomics, a second thread, host-import/callback dispatch and an AArch64 RW→RX canary. The last persistent phase was **527**. This proved that the device can execute translated code from a hostile arena; it did not yet prove that the complete OpenCE guest can run there.

## Stage 3 guest ABI

The Non-JB workflow now builds a distinct guest with `HALO_IOS_FLEX_BASE=1`. Clang reserves **x27** and **x15** (`-ffixed-x27 -ffixed-x15`):

- **x27** is the immutable 64-bit host arena base while guest code runs.
- **x15** is scratch for translated memory/indirect-branch addresses.
- guest pointers stored in game state remain canonical 32-bit VAs.
- a guest load/store through `xN` becomes `x27 + zero_extend(wN)` in x15 before the original access.
- narrow indirect `BR`/`BLR` targets are translated through x27; wide host-import targets remain native 64-bit addresses.
- addresses materialized from PC, SP or FP are canonicalized back to guest VAs before they can be stored/passed as C pointers.
- compressed jump tables are disabled for this flavor. An unsupported general-register memory form, reserved-register use or residual compressed table is a **build error**, not a signal-bridge fallback.

Generated host-import stubs remain intentionally direct PC-relative assembly: their import-table address relocates with the guest image and the table stores true 64-bit host function addresses. Host ABI calls preserve x27 because it is callee-saved.

## Real arbitrary-base arena

If the production 8 GiB reservation and both aligned 4 GiB fallbacks fail, the Non-JB runtime now reserves one exact 4 GiB span anywhere and makes it the **real** guest arena. The bundled `halo_guest.elf` must contain `HALO_IOS_FLEX_BASE_GUEST_V1`; a normal/aligned guest is refused on this path. Main and secondary host→guest entries use a small trampoline that establishes x27 before entering arm64_32 code.

The old low-pointer memory-fault upgrade is disabled for an active unaligned Stage-3 arena. A missed translated memory access aborts with diagnostics instead of converting a guest register into a host pointer whose low 32 bits no longer equal the guest VA.

## Persistent real-guest boundaries

The Non-JB log/`launch-phase.txt` now records:

- **600** — real arbitrary-base guest arena active
- **601** — flexible guest ABI marker verified
- **602** — real ELF segments copied
- **603** — host import table resolved
- **604** — boot argv/environment block built
- **605** — real guest stack mapped
- **606** — x27 established; branch to `__guest_start`
- **607** — guest entered `__guest_start` and completed its first `host_log`
- **608** — guest TLS/thread pointer reached `host_set_tp`
- **609** — guest constructors completed; entering OpenCE `main()`

Stage 2 remains available only if Stage 3 cannot reserve a real 4 GiB arena. Devices such as the tested older iPad that cannot reserve **any** contiguous 4 GiB span are still outside this architecture and would need a future sparse/segmented guest-memory design.

## Build identity

Regular and Mod Test IPAs remain `aligned-arena-v1 / ios-guarded-v1`. The Non-Jailbreak IPA is stamped **`flexible-base-x27-v1 / ios-flex-x27-v1`**, so About/logs and engine-change backup protection distinguish the two execution models.

## Validation before packaging

Local validation includes the strict OpenCE build-146 acceptance gate, exact flags-off equivalence for **46/46** upstream-owned adapted files, 51/51 standard host imports, workflow transformation checks, the Stage-2 fallback test, the Stage-3 x27 ABI/source guards, broad load/store/atomic addressing coverage, import-stub invariants, declaration-order checks and portable Non-JB runtime compilation. The local Linux environment does not have the Android NDK or Apple iPhoneOS SDK, so the actual ~1,400-object flexible guest compile, Xcode host link and device execution remain GitHub Actions/device responsibilities.

## Device checklist

1. Build **Non-Jailbreak Version** only. Confirm About/logs show `flexible-base-x27-v1`, `ios-flex-x27-v1`, OpenCE build 146/network 22 and the current guest SHA.
2. On the iPhone 14 Plus, share logs after the first run. The first new question is how far phases **600–609** progress.
3. If the app stops silently, relaunch and share `launch-phase.txt`; the last persisted phase is the boundary.
4. If a low-pointer miss is reported, include the guest PC/base register line; that is a converter gap to fix, not a reason to re-enable the aligned pointer-upgrade fallback.
5. If **609** is reached, test the main menu, audio, input, a normal Xbox campaign map and a Custom Edition map before calling the arbitrary-base runtime usable.
6. Also test the same Non-JB IPA on the iPhone 16 Pro Max. It may receive an aligned arena, but the guest still uses the flex-aware x27 ABI, which lets us compare startup behavior without changing the guest build.

This milestone is experimental and is **not** a claim that free-signed Non-JB Halo is solved until the real guest passes on-device.
