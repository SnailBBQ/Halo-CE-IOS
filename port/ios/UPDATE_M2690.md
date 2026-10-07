# M2.6.90 — Apple disc-install test hotfix

Regular app **0.2.90 / 2690**. The Mod Test app derives **0.2.90.1 / 269001**. OpenCE remains **build 146** (`314f576515585560ea6b375b0d5b8a02fd8991af`), **network version 22**. The M2.6.88 Custom Edition map manager, MP4 movie fallback, legacy replacement migration and M2.6.86 Non-Jailbreak Stage-2 diagnostics are unchanged.

## Why M2.6.89 still failed

M2.6.89 fixed the Apple SDK `Marker` collision and comma-containing `CHECK(...)` assertions in `test_ios_mods.m`. That workflow step then passed. The workflow progressed to **Verify disc extraction and cancellation**, where `tools/tests/test_ios_disc_install.m` still declared its own helper named `Marker`. Apple's CarbonCore headers also define `Marker`, so Apple Clang rejected the test before the device host app was built.

M2.6.90 renames that final helper to `ReadDiscMarker` and updates every assertion in the disc-install harness. It also adds a suite-wide source guard over all Objective-C iOS test harnesses so another helper named `Marker` cannot silently reappear. The existing variadic `CHECK(...)` form remains in both harnesses.

No runtime Halo, Custom Edition, MP4, renderer, networking, save, XISO, guest-loader or Non-Jailbreak behavior changes in this hotfix.

## Validation target

The Apple workflow must now compile and run the exact disc-install harness that failed in M2.6.89:

```sh
clang -fobjc-arc -DHALO_BACKUP_TEST -framework Foundation \
  -Iport/ios/HaloIOS \
  port/ios/HaloIOS/HaloDiscImport.m \
  port/ios/HaloIOS/HaloBackupArchive.m \
  tools/tests/test_ios_disc_install.m \
  -o "$RUNNER_TEMP/halo-disc-test"
"$RUNNER_TEMP/halo-disc-test"
```

Once Actions is green, use the existing M2.6.88 device checklist for Custom Edition maps and user-supplied MP4 movies.
