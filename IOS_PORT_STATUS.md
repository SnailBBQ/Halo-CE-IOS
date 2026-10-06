# Halo CE iOS — Project status

**Status: playable.** **Current source update: M2.6.81** (regular app 0.2.81, Mod Test 0.2.81.1), integrating OpenCE build 138 / network 20 from the green M2.6.80 baseline. The maintainer reports playable `a10` and PC cross-play on a physical iPhone in earlier builds, with other tested campaign maps loading successfully. The build-138 integration has passed local strict source acceptance and portable regressions; its Apple build and physical-device behavior are still pending. See the [release notes](docs/ios/RELEASE_NOTES.md) and the [README](README.md).

**Source update:** [M2.6.81](port/ios/UPDATE_M2681.md) integrates the complete OpenCE build-125→138 source change set (except OpenCE's own repository workflow), rebases the iOS-only adaptations onto the new renderer/audio/network APIs, and promotes network version 20. The strict promotion gate reports 43/43 adapted upstream files exact when `HALO_IOS_GUEST` is disabled, so the 27 historical build-125 flags-off deltas are not carried into build 138. M2.6.80's build identity, automatic engine-change `.halobackup` protection and Non-Jailbreak flexible 4 GiB-anywhere probe remain. M2.6.80 passed GitHub Actions; M2.6.81 still needs its Apple build and device checks.

## Two apps, plus a stock-iOS build

| App | How to build | Output |
| --- | --- | --- |
| Halo CE (regular) | `main`, options off | `HaloCE.ipa` |
| Halo CE Mod Test | `main`, tick **Mod Test app** | artifact `HaloCE-iOS-ModTest` |
| Non-Jailbreak Version | `main`, tick **Non-Jailbreak Version** | artifact `HaloCE-iOS-NonJailbreak` |

The regular app and Mod Test share the same features and are updated together. The Mod Test app adds an experimental loader for very large converted campaign maps; see [Mod Test](docs/ios/MOD_TEST.md). The Non-Jailbreak Version is the regular app plus stock-iOS address-space/JIT diagnostics. It still measures whether one exact 4 GiB span can be reserved **anywhere** even when no aligned guest window exists; it does not yet run Halo from that unaligned span. Free-account sideloading is therefore still experimental rather than supported; see [M2.6.81](port/ios/UPDATE_M2681.md) and [Install](docs/ios/INSTALL.md#sideloading-with-free-and-paid-accounts).

## What works (reported from device testing)

- The Halo main menu, `a10` campaign progression, and the other campaign maps tried so far, which load fine; reported 60 FPS menus and gameplay in tested scenes, without a guarantee across devices or maps; native audio.
- Cross-play multiplayer with an OpenCE PC client, including joining by invite link.
- On-screen Xbox-style controls with five schemes, touch look, and physical controllers.

## Implemented, waiting for build/device validation

- OpenCE build 138 / network 20 source integration, including the accumulated multiplayer/co-op, audio, renderer/menu, lighting and hardening changes through build 138. This exact engine still needs Apple/device validation; earlier OpenCE integrations are the device-tested basis.
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
