# Halo CE iOS — Project status

**Status: playable.** **Current update: M2.6.54** (regular app 0.2.54, Mod Test app 0.2.54.1). The maintainer reports playable `a10` and PC cross-play on a physical iPhone in earlier builds, with other tested campaign maps loading successfully. Some of the newest features are built and checked by automated tests and
are still waiting for device validation. See the [release notes](docs/ios/RELEASE_NOTES.md) and the [README](README.md).

**Source update:** M2.6.54 integrates Halo CE Universal build 94 on `main` and `ios/modtest`, alongside campaign tools, direct checkpoint editing and smaller, separate save/profile backups. This source update still requires Apple compilation and device validation.

## Two apps

| App | Branch | Output |
| --- | --- | --- |
| Halo CE (regular) | `main` | `HaloCE.ipa` |
| Halo CE Mod Test | `ios/modtest` | `HaloCE-ModTest.ipa` |

Both share the same features and are updated together. The Mod Test app adds an experimental loader for very large converted campaign maps; see [Mod Test](docs/ios/MOD_TEST.md).

## What works (reported from device testing)

- The Halo main menu, `a10` campaign progression, and the other campaign maps tried so far, which load fine; reported 60 FPS menus and gameplay in tested scenes, without a guarantee across devices or maps; native audio.
- Cross-play multiplayer with a Halo CE Universal PC client, including joining by invite link.
- On-screen Xbox-style controls with five schemes, touch look, and physical controllers.

## Implemented, waiting for build/device validation

- Halo CE Universal build 94 baseline, including multiplayer pause Settings/End Game, HUD name filtering and vehicle-seat fixes. Earlier build 84 integration added: signed public lobby discovery, public/private hosting and multiplayer join/leave fixes (M2.6.51).
- The Settings additions of M2.6.48 (cheat sections and new cheats, left-handed layout, gyro, controller remap, heat-aware frame cap, performance overlay, Ambient volume, recent games and QR, Profiles, problem report, custom accent colours).
- Picture options, touch aiming and AirPlay mirroring (M2.6.50).
- The Mod Test loader has offline structural checks. Device attempts with converted Cursed Halo maps have failed; playable mod compatibility is not established.

- M2.6.54 campaign modifiers, flying camera, wireframe, bounded checkpoint editor and separate cache-free save/profile exports.

## Known limits

- Public server discovery is integrated; iOS public browsing/hosting and cross-play need device validation. Discovery uses public MQTT signalling brokers and requires network connectivity.
- The app imports `.map` files only. It does not open ISO or XISO disc images; extract the maps first (see [Game data](docs/ios/GAME_DATA.md)).
- AirPlay is system screen mirroring. A separate TV-only game window is not implemented.
- Bink videos are skipped.
- Touch behaviour in the PC menus has not been validated; the Xbox menus remain available in Settings.
- Mod conversion is paused.
- Checkpoint editing supports finite health/shields, grenades and existing weapon ammo in validated 16 MB Xbox 2342 campaign saves. It does not fabricate skulls, vehicle boost, new weapon objects, or runtime cheat fields.

## Where to read more

| | |
| --- | --- |
| Install, build and game data | [Install](docs/ios/INSTALL.md) · [Build the IPA](docs/ios/BUILD.md) · [Game data](docs/ios/GAME_DATA.md) |
| Using the app | [Settings](docs/ios/SETTINGS.md) · [Controls](docs/ios/CONTROLS.md) · [Multiplayer](docs/ios/MULTIPLAYER.md) · [Backups](docs/ios/BACKUPS.md) |
| Problems | [Troubleshooting](docs/ios/TROUBLESHOOTING.md) |
| Development | [Developer guide](port/ios/README.md) · [Engineering history](docs/ios/HISTORY.md) |
| The official project | [Halo CE Universal and credits](docs/UPSTREAM.md) |
