# Halo CE iOS — Project status

**Status: playable on the regular/jailbreak path.** **Current source update: M2.6.100** (regular app 0.2.100, Mod Test 0.2.100.1), on OpenCE build 155 / network 24 with Custom Edition maps and the MP4 movie fallback, while continuing the experimental Non-Jailbreak **real-guest flexible-base Stage 3** path. M2.6.93 passed GitHub Actions and the iPhone 14 Plus passed Stage 2 at `0x2A0000000`. The M2.6.98 Non-Jailbreak IPA ran the real guest into OpenCE `main()` on that phone and stopped on an untranslated `ldr w9, [x30]` in `mod_l`; M2.6.99 fixes that class. M2.6.100 applies the same x30 translation to the regular (aligned) converter to remove a frame-rate bottleneck seen in a Regular device log. Actions/device validation are required for M2.6.99 and M2.6.100.

**Source update:** [M2.6.100](port/ios/UPDATE_M2700.md) makes the aligned (Regular and Mod Test) converter treat x30 as a guest-pointer base, as the flexible-base converter has since M2.6.99. A Regular device log showed 16.2 million SIGSEGV-bridge faults, 99.7% from the audio ADPCM decode loop (`stream_process`), costing roughly 7 µs each and collapsing some windows to 10-33 FPS. OpenCE stays on build 155 / network 24.

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

- M2.6.100 aligned-converter x30 translation (Regular/Mod Test frame-rate fix from the device log).
- M2.6.99 Non-Jailbreak x30 guest-pointer translation, found from the M2.6.98 device log (guest reached OpenCE `main()`, OpenGL and audio, then faulted at `mod_l+0x190`). M2.6.98 integrated OpenCE build 155 and M2.6.97 build 154; both passed Actions.
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
