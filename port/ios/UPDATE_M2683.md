# M2.6.83 — Build-138 texture return-contract hotfix

Regular app **0.2.83 / 2683**. The Mod Test app derives **0.2.83.1 / 268301**. The engine remains **OpenCE build 138** (`76addf661f02e2fd090d7b00f9dd12c29e562a9b`), **network version 20**, with the same 20 MiB game-state capacity and Apple OpenGL ES renderer as M2.6.81/M2.6.82.

M2.6.82 fixed the iOS-only dependency headers lost during the build-138 rebase. Its Actions run then advanced to object **1416/1473** before Clang stopped in `port/linux/src/xbox_textures.c`. Upstream build 138 changed `decode_level()` from `void` to `BOOL` so an allocation failure can be reported to its caller; our iOS host-decoder shortcut still used the old bare `return;`.

## Fix

- When `host_texture_decode_texels()` successfully handles the level, the iOS path now returns **`TRUE`** from `decode_level()`. This preserves the intended meaning: native decode succeeded, so the caller should continue uploading the converted texture.
- If the host decoder declines the layout, execution still falls through to OpenCE's build-138 guest converter. If that converter cannot allocate its swizzle table, `decode_level()` still returns `FALSE` exactly as upstream intends.
- Added `tools/tests/test_ios_guest_return_contracts.py` and wired it into the iOS diagnostics job so this build-138 return-type mismatch is caught before the ~1,400-object guest build.
- No renderer, networking, save format, address-space, XISO, input, backup, protocol or gameplay behavior is intentionally changed.

## Upstream invariants

- OpenCE release: **build-138**
- Commit: **`76addf661f02e2fd090d7b00f9dd12c29e562a9b`**
- Network version: **20**
- Renderer: **Apple OpenGL ES**
- `HALO_IOS_GUEST` disabled: the 43 adapted upstream files still reduce exactly to build-138 source.

## Validation

Local validation checks the strict build-138 acceptance gate, iOS source/metadata tests, the new texture return contract and the existing portable runtime tests. The authoritative arm64_32 guest compile and Apple app build remain GitHub Actions jobs.

## Device checklist

1. Confirm **Build Halo engine guest** gets beyond `port/linux/src/xbox_textures.c` object 1416/1473 and produces `build/android/halo_guest.elf`.
2. Confirm **Build and package iOS app** succeeds and the Regular artifact reports **M2.6.83 / 0.2.83 (2683)**, OpenCE build 138 / `76addf6…`, network 20.
3. Install the Regular IPA and smoke-test menu, campaign start, audio, touch/controller input, texture rendering, checkpoint save/reload and the automatic engine-change `.halobackup` path.
4. Test cross-play only with a network-version-20-compatible OpenCE PC build.

Until Actions and the physical-device smoke test pass, M2.6.83 remains a **build-138 release candidate**, not a confirmed public release.
