# M2.6.61 — Startup compatibility checks and separate allocation test

The regular app keeps the proven 8 GiB reservation/aligned 4 GiB runtime. Address
reservation failures now stop the loading spinner and show an explanation,
Share logs and Startup help. Rejected executable-page protections are reported
separately. Entitlement inspection remains optional: unknown never means absent,
and missing entitlements do not block otherwise working installations by themselves.

CI inspects the actual ad-hoc signature after packaging, requiring both requested
memory capabilities. `tools/verify_ios_signing.py` also checks an embedded profile
when present, without printing account identities. Re-signing must be inspected
again: the supplied signature cannot confer privileges on the installed app.

## Compatibility test app

Manually run the main iOS workflow with `compatibility_test=true`. It produces
`HaloCE-iOS-Compatibility-Test`, display name **Halo Compatibility Test**, bundle
ID `com.haloceuniversal.ios.compatibility`. It has a separate data container;
import compatible maps or restore a backup explicitly. It does not replace the
regular or Mod Test app and is not a fourth maintained gameplay branch.

This host build calls `mach_vm_map` for exactly 4 GiB with a 4 GiB alignment mask,
`VM_FLAGS_ANYWHERE` and no initial page access. It never overwrites occupied
address ranges. Rejected/invalid reservations fail clearly; there is no silent
allocator fallback. The original guest VA/low-32-bit property, page behavior,
guest ELF, bridge, signing requests, rendering and controller behavior remain
unchanged. It reduces the temporary reservation requirement, not OS restrictions.

## Provisioning and execution validation

See [installation guidance](../../docs/ios/INSTALL.md#stock-ios-compatibility-test).
Authorize Extended Virtual Addressing in the App ID/profile if your account and
signer support it, regenerate the profile and re-sign. Increased Memory Limit is
separate. Do not add unauthorized keys or treat `get-task-allow` as active JIT.
Use the current SideStore/debugger guide for the exact OS, then test Halo.
Newer iOS JIT support can be app-specific; this update does not establish it.
There is no embedded privilege bypass or claim that a paid service solves this.

## Validation

- Deterministic Mach allocation tests: no-space error, invalid alignment cleanup,
  successful 16 KiB-page arena, VA truncation, bounds, idempotence and shutdown.
- Existing production allocator failure tests remain unchanged.
- Signing tests distinguish signature presence from provisioning authorization.
- Device: compare the regular and compatibility apps through the failing signer;
  share `ios-boot.log` and `launch-phase.txt` with installer/OS versions.
- If allocation succeeds, verify guest execution before testing menu, a10,
  multiplayer, controller/touch holds, graphics and long-session stability.
- Maintain the working TrollStore baseline. No stock-iOS compatibility claim until
  the same test app completes these checks on a non-jailbroken device.

M2.6.60 input fixes and Universal build 95 remain included. No performance or
graphics settings were lowered. Native signed-engine integration is a separate
architecture project, not part of this update.
