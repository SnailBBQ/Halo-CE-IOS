# Halo CE iOS — Project status

**Status: playable on the regular/jailbreak path.** **Current source update: M2.6.96** (regular app 0.2.96, Mod Test 0.2.96.1), keeping OpenCE build 146 / network 22, Custom Edition maps and MP4 movie fallback while continuing the experimental Non-Jailbreak **real-guest flexible-base Stage 3** path. M2.6.93 passed GitHub Actions and the iPhone 14 Plus passed Stage 2 at `0x2A0000000`. M2.6.94 first exercised the real guest converter; M2.6.95 fixed legal register-offset addressing and advanced the real compile to object 63/1492, where LLVM's harmless x27 callee-save spill was falsely rejected. M2.6.96 narrows the reserved-register guard so only 64-bit x27 preservation/restoration through the real host stack is accepted; every computational x27 use and all x15 source use remain fatal. Actions/device validation are required for this exact milestone.

**Source update:** [M2.6.96](port/ios/UPDATE_M2696.md) keeps the manual Non-Jailbreak guest's distinct x27 flexible-base ABI and repairs the next real-build converter guard exposed by M2.6.95. LLVM may pair fixed x27 with another callee-saved register in a host-stack prologue/epilogue even though it never allocates x27 for computation. Stage 3 now accepts only those 64-bit stack save/reload forms while continuing to reject arithmetic, branches, guest-memory addressing, 32-bit w27 use and all source x15 use. The x27 arena-base/x15 scratch ABI, fail-closed memory conversion, arbitrary 4 GiB real guest arena and phases 600–609 are unchanged. Regular and Mod Test builds keep the aligned-arena architecture. OpenCE remains build 146/network 22.

## Two apps, plus a stock-iOS build

| App | How to build | Output |
| --- | --- | --- |
| Halo CE (regular) | `main`, options off | `HaloCE.ipa` |
| Halo CE Mod Test | `main`, tick **Mod Test app** | artifact `HaloCE-iOS-ModTest` |
| Non-Jailbreak Version | `main`, tick **Non-Jailbreak Version** | artifact `HaloCE-iOS-NonJailbreak` |

The regular app and Mod Test share the same features and are updated together. The Mod Test app adds an experimental loader for very large converted campaign maps; see [Mod Test](docs/ios/MOD_TEST.md). The Non-Jailbreak Version is the regular app plus the experimental Stage-3 guest ABI. When a non-aligned contiguous 4 GiB reservation exists, M2.6.96 may use it as the **real** guest arena and records phases 600–609. Stage 2 remains only as a fallback diagnostic if Stage 3 cannot reserve an arena. Free-account sideloading is still experimental rather than supported; see [M2.6.96](port/ios/UPDATE_M2696.md) and [Install](docs/ios/INSTALL.md#sideloading-with-free-and-paid-accounts).

## What works (reported from device testing)

- The Halo main menu, `a10` campaign progression, and the other campaign maps tried so far, which load fine; reported 60 FPS menus and gameplay in tested scenes, without a guarantee across devices or maps; native audio.
- Cross-play multiplayer with an OpenCE PC client, including joining by invite link.
- On-screen Xbox-style controls with five schemes, touch look, and physical controllers.

## Implemented, waiting for device validation

- M2.6.96 Non-Jailbreak Stage 3 converter guard hotfix on OpenCE build 146/network 22. M2.6.95 fixed the first register-offset gap and reached object 63/1492, where musl `scandir.o` exposed LLVM preserving fixed x27 with `stp/ldp ... [sp]`. M2.6.96 accepts only that 64-bit host-stack preservation/restoration while keeping computational x27/w27 and all source x15 uses fail-closed. The Stage-3 runtime ABI and Regular/Mod Test paths are unchanged.
- OpenCE build 144 / network 21 source integration from M2.6.85, including renderer call reduction, co-op/netcode fixes, map-tag validation, additional hardening and GPU/visibility/water performance changes through build 144.
- The Settings additions of M2.6.48 (cheat sections and new cheats, left-handed layout, gyro, controller remap, heat-aware frame cap, performance overlay, Ambient volume, recent games and QR, Profiles, problem report, custom accent colours).
- Picture options, touch aiming and AirPlay mirroring (M2.6.50).
- The Mod Test loader has offline structural checks. Device attempts with converted Cursed Halo maps have failed; playable mod compatibility is not established.

- M2.6.54 campaign modifiers, flying camera, wireframe, bounded checkpoint editor and separate cache-free save/profile exports.

## Known limits

- Public server discovery is integrated; iOS public browsing/hosting and cross-play need device validation. Discovery uses public MQTT signalling brokers and requires network connectivity.
- Disc import and **Import maps** both fill `Documents/Halo/maps`. Xbox cache version 5 only. See [Game data](docs/ios/GAME_DATA.md).
- AirPlay is system screen mirroring. A separate TV-only game window is not implemented.
- Native Bink decoding is not included; user-supplied MP4 fallbacks are supported for the known Halo movie slots.
- Touch behaviour in the PC menus has not been validated; the Xbox menus remain available in Settings.
- Mod conversion is paused.
- Checkpoint editing supports finite health/shields, grenades and existing weapon ammo in validated Xbox 2342 campaign saves of this build's own game-state size (20 MB since upstream's pools grew; the game cannot load a save from a build with a different size, so earlier saves and checkpoints are not usable). It does not fabricate skulls, vehicle boost, new weapon objects, or runtime cheat fields.

## Where to read more

| | |
| --- | --- |
| Install, build and game data | [Install](docs/ios/INSTALL.md) · [Build the IPA](docs/ios/BUILD.md) · [Game data](docs/ios/GAME_DATA.md) |
| Using the app | [Settings](docs/ios/SETTINGS.md) · [Controls](docs/ios/CONTROLS.md) · [Multiplayer](docs/ios/MULTIPLAYER.md) · [Backups](docs/ios/BACKUPS.md) |
| Problems | [Troubleshooting](docs/ios/TROUBLESHOOTING.md) |
| Development | [Developer guide](port/ios/README.md) · [Engineering history](docs/ios/HISTORY.md) |
| The official project | [OpenCE and credits](docs/UPSTREAM.md) |
