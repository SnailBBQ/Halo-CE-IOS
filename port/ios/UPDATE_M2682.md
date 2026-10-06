# M2.6.82 — Build-138 guest compile hotfix

Regular app **0.2.82 / 2682**. The Mod Test app derives **0.2.82.1 / 268201**. The engine remains **OpenCE build 138** (`76addf661f02e2fd090d7b00f9dd12c29e562a9b`), **network version 20**, with the same 20 MiB game-state capacity and Apple OpenGL ES renderer as M2.6.81.

M2.6.81 completed the build-125→138 source integration and passed the strict source acceptance gates, but its first GitHub Actions run did not produce an IPA. The arm64_32 guest compile stopped in `source/camera/director.c` because an iOS-only dependency include was lost during the upstream rebase. M2.6.82 fixes that compile class without reverting any OpenCE build-138 source.

## What changed

- Restored the iOS-only `game/cheats.h` dependency in `source/camera/director.c`, which supplies `IOS_CHEAT_THIRD_PERSON` and the `ios_cheat_*` declarations used by the preserved third-person adaptation.
- Audited the same rebase pattern before rebuilding and restored the corresponding iOS-only dependencies in `source/interface/first_person_weapons.c`, `source/game/player_control.c`, `source/ai/ai_debug.c` and `source/game/cheats.c`.
- Every restored dependency is inside a `HALO_IOS_GUEST` guard. With iOS disabled, the affected files still reduce to exact OpenCE build-138 source; the strict **43/43** upstream-equivalence gate remains green.
- Added `tools/tests/test_ios_guest_compile_dependencies.py` and runs it before the expensive guest build. It checks these dependencies and also requires every guest source that consumes the iOS cheat API to include its declaration header in the iOS view only.
- No renderer, networking, save format, address-space, XISO, input, backup or gameplay behavior was intentionally changed. The upstream identity remains build 138 / network 20, so the M2.6.80 engine-change `.halobackup` logic does not treat M2.6.82 as a second OpenCE engine transition after M2.6.81.

## Local validation

- Strict build-138 acceptance with the supplied OpenCE build-138 tree: **PASS**, 43/43 adapted upstream files exact with `HALO_IOS_GUEST` disabled.
- iOS guest dependency regression test: **PASS**.
- Existing source-structure, build-identity, workflow, import-coverage and portable iOS regressions are rerun for this hotfix before packaging.
- A full arm64_32 guest compile still requires the GitHub Actions Ubuntu runner/toolchain; that is the decisive validation for this update.

## Device / release checklist

1. Push M2.6.82 and confirm **Build Halo engine guest** gets past `source/camera/director.c` and completes `build/android/halo_guest.elf`.
2. Confirm **Build and package iOS app** succeeds and the Regular artifact reports **M2.6.82 / 0.2.82 (2682)**, OpenCE build 138 / `76addf6…`, network 20.
3. Install the Regular IPA and repeat the M2.6.81 build-138 smoke test: menu, `a10`, audio, touch/controller input, save/quit/reload, first-person weapons and third-person toggle.
4. Cross-play only with a network-version-20-compatible OpenCE PC build.
5. Build Mod Test and Non-Jailbreak only after the Regular build is green.

Until Actions and the physical-device smoke test pass, M2.6.82 remains a **build-138 release candidate**, not a confirmed public release.
