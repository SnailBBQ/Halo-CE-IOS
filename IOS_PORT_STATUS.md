# Halo CE iOS — Project status

**Status: playable.** **Current source update: M2.6.87** (regular app 0.2.87, Mod Test 0.2.87.1), integrating OpenCE build 146 / network 22 on top of the M2.6.86 Non-Jailbreak Stage-2 baseline. Build 146 adds upstream Halo Custom Edition cache/map support, validation and listing, missing-map reporting and further hostile-map hardening. GitHub Actions and device validation are still required for this exact milestone. The maintainer reports playable `a10` and PC cross-play on earlier physical-device builds. See the [release notes](docs/ios/RELEASE_NOTES.md) and the [README](README.md).

**Source update:** [M2.6.87](port/ios/UPDATE_M2687.md) promotes OpenCE build 146/network 22 and preserves **Non-Jailbreak flexible-base Stage 2** from M2.6.86. The upstream delta introduces Custom Edition cache/map loading and validation, menu listing, missing-map reporting and hardening; OpenSauce maps are refused. The iOS mobile guest keeps its existing memory layout, so Custom Edition behavior—especially large maps—requires device validation. The synthetic Stage-2 path still never assigns its unaligned arena to the real guest or calls the real OpenCE entry point.

## Two apps, plus a stock-iOS build

| App | How to build | Output |
| --- | --- | --- |
| Halo CE (regular) | `main`, options off | `HaloCE.ipa` |
| Halo CE Mod Test | `main`, tick **Mod Test app** | artifact `HaloCE-iOS-ModTest` |
| Non-Jailbreak Version | `main`, tick **Non-Jailbreak Version** | artifact `HaloCE-iOS-NonJailbreak` |

The regular app and Mod Test share the same features and are updated together. The Mod Test app adds an experimental loader for very large converted campaign maps; see [Mod Test](docs/ios/MOD_TEST.md). The Non-Jailbreak Version is the regular app plus stock-iOS address-space/JIT diagnostics. M2.6.87 preserves M2.6.86's step beyond the feasibility probe: when a non-aligned contiguous 4 GiB reservation exists, it runs an isolated synthetic guest model in that span and records phases 520–527. The real Halo guest still requires its existing aligned arena. Free-account sideloading is therefore still experimental rather than supported; see [M2.6.87](port/ios/UPDATE_M2687.md) and [Install](docs/ios/INSTALL.md#sideloading-with-free-and-paid-accounts).

## What works (reported from device testing)

- The Halo main menu, `a10` campaign progression, and the other campaign maps tried so far, which load fine; reported 60 FPS menus and gameplay in tested scenes, without a guarantee across devices or maps; native audio.
- Cross-play multiplayer with an OpenCE PC client, including joining by invite link.
- On-screen Xbox-style controls with five schemes, touch look, and physical controllers.

## Implemented, waiting for device validation

- M2.6.87 OpenCE build-146/network-22 integration, preserving M2.6.86 Non-Jailbreak Stage-2 flexible-base diagnostics. The host arithmetic model is locally validated at the iPhone-style hostile base `0x2A0000000`; Actions still needs to compile/package the exact Apple build and a physical device must prove the 4 GiB reservation, thread/remap tests and RX canary. The real OpenCE guest is intentionally not started on this path.
- OpenCE build 144 / network 21 source integration from M2.6.85, including renderer call reduction, co-op/netcode fixes, map-tag validation, additional hardening and GPU/visibility/water performance changes through build 144.
- The Settings additions of M2.6.48 (cheat sections and new cheats, left-handed layout, gyro, controller remap, heat-aware frame cap, performance overlay, Ambient volume, recent games and QR, Profiles, problem report, custom accent colours).
- Picture options, touch aiming and AirPlay mirroring (M2.6.50).
- The Mod Test loader has offline structural checks. Device attempts with converted Cursed Halo maps have failed; playable mod compatibility is not established.

- M2.6.54 campaign modifiers, flying camera, wireframe, bounded checkpoint editor and separate cache-free save/profile exports.

## Known limits

- Public server discovery is integrated; iOS public browsing/hosting and cross-play need device validation. Discovery uses public MQTT signalling brokers and requires network connectivity.
- Disc import and **Import maps** both fill `Documents/Halo/maps`. Xbox cache version 5 only. See [Game data](docs/ios/GAME_DATA.md).
- AirPlay is system screen mirroring. A separate TV-only game window is not implemented.
- Bink videos are skipped.
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
