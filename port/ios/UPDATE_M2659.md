# M2.6.59 — Signing-dependent startup diagnostics

Adds optional signing-capability inspection and an exact initialization error to investigate installations that fail to reserve the guest arena. Reports app/version, OS/device, physical RAM and process memory allowance when available. No Apple account email, credentials or provisioning profile are logged.

Capability inspection may be unavailable and then reports unknown. Requested/signed memory capabilities do not establish executable-code authorization. Executable-page failures now record protection flags and the OS error separately. This update does not grant capabilities, change signing, alter the allocator or add an alternate execution bridge.

The existing 8 GiB reservation / aligned 4 GiB guest window, PAGEZERO bridge and renderer remain unchanged. Universal build 95, co-op, texture-content reuse and frame diagnostics are preserved in regular and Mod Test source updates. No broader device/signing compatibility is claimed yet.

A deterministic runtime test simulates page-size failure, ENOMEM and EACCES, then verifies successful initialization and unchanged alignment. Apple compilation and device comparison are separate checks.

Install this version in both a known-working environment and a failing SideStore/Sideloadly installation, keeping app identity/data and maps. Capture ios-boot.log and launch-phase.txt plus exact device, OS and installer versions. Compare signed capabilities and the allocation/protection error before selecting a provisioning or architectural fix. See [installation troubleshooting](../../docs/ios/INSTALL.md#diagnosing-signing-dependent-startup-failures).
