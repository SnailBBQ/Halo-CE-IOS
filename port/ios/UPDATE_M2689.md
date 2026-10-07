# M2.6.89 — Apple packaging-test hotfix

Regular app **0.2.89 / 2689**. The Mod Test app derives **0.2.89.1 / 268901**. OpenCE remains **build 146** (`314f576515585560ea6b375b0d5b8a02fd8991af`), **network version 22**. The M2.6.88 Custom Edition map manager, user-supplied MP4 movie fallback, legacy replacement migration, and M2.6.86 Non-Jailbreak Stage-2 flexible-base diagnostics are unchanged.

## Why M2.6.88 failed

The real arm64_32 Halo guest completed its GitHub Actions build. The failure occurred later in **Build and package iOS app → Verify Custom Edition library and legacy replacement migration**, while Apple Clang compiled the Foundation-only `tools/tests/test_ios_mods.m` harness.

Two test-only Objective-C issues were responsible:

- the helper function was named `Marker`, colliding with the Apple SDK's CarbonCore `Marker` typedef;
- the one-argument `CHECK(x)` macro was passed Objective-C dictionary/array literals containing commas, so the C preprocessor split one assertion into multiple macro arguments.

M2.6.89 renames the helper to `ReadMarker` and makes `CHECK` variadic. No runtime Custom Edition, MP4, guest, renderer, networking, save, or Non-Jailbreak code changes are required for this hotfix.

## Validation target

The Apple workflow must now pass the exact command that failed in M2.6.88:

```sh
clang -fobjc-arc -DHALO_BACKUP_TEST -framework Foundation \
  -Iport/ios/HaloIOS \
  port/ios/HaloIOS/HaloMods.m \
  port/ios/HaloIOS/HaloBackupArchive.m \
  tools/tests/test_ios_mods.m \
  -o "$RUNNER_TEMP/halo-mods-test"
```

After compilation, the test still exercises legacy replacement retirement, CE v609 import/resources, enable/disable, Xbox-v5 rejection, and MP4 filename mapping.

## Device checklist

Once Actions is green, use the M2.6.88 feature checklist: import a standard CE map/resources, test disable/re-enable and a normal Xbox map, then test user-supplied `intro.mp4`/`credits.mp4` playback and skipping.
