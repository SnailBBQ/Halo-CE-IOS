# Halo CE iOS — Project status

**Status: playable.** **Current update: M2.6.51** (regular app 0.2.51, Mod Test app 0.2.51.1). `a10` and cross-play multiplayer are fully working on a physical iPhone, and the other campaign maps tried so far load fine. Some of the newest features are built and checked by automated tests and
are still waiting for device validation. See the [release notes](docs/ios/RELEASE_NOTES.md) and the [README](README.md).

## Two apps

| App | Branch | Output |
| --- | --- | --- |
| Halo CE (regular) | `main` | `HaloCE.ipa` |
| Halo CE Mod Test | `ios/cursed-a10-mod-test` | `HaloCE-ModTest.ipa` |

Both share the same features and are updated together. The Mod Test app adds an experimental loader for very large converted campaign maps; see [Mod Test](docs/ios/MOD_TEST.md).

## What works (reported from device testing)

- The Halo main menu, `a10` (fully working), and the other campaign maps tried so far, which load fine; 60 FPS menus and gameplay; native audio.
- Cross-play multiplayer with Halo CE Universal clients (fully working), including joining by invite link.
- On-screen Xbox-style controls with five schemes, touch look, and physical controllers.

## Implemented, waiting for build/device validation

- Halo CE Universal build 84: signed public lobby discovery, public/private hosting and multiplayer join/leave fixes (M2.6.51).
- The Settings additions of M2.6.48 (cheat sections and new cheats, left-handed layout, gyro, controller remap, heat-aware frame cap, performance overlay, Ambient volume, recent games and QR, Profiles, problem report, custom accent colours).
- Picture options, touch aiming and AirPlay mirroring (M2.6.50).
- The Mod Test loader, offline-validated only.

## Known limits

- Build 84 public server discovery is integrated; iOS public browsing/hosting and cross-play need device validation. Discovery uses public MQTT signalling brokers and requires network connectivity.
- The app imports `.map` files only. It does not open ISO or XISO disc images; extract the maps first (see [Game data](docs/ios/GAME_DATA.md)).
- AirPlay is system screen mirroring. A separate TV-only game window is not implemented.
- Bink videos are skipped.
- Touch behaviour in the PC menus has not been validated; the Xbox menus remain available in Settings.
- Mod conversion is paused.

## Where to read more

| | |
| --- | --- |
| Install, build and game data | [Install](docs/ios/INSTALL.md) · [Build the IPA](docs/ios/BUILD.md) · [Game data](docs/ios/GAME_DATA.md) |
| Using the app | [Settings](docs/ios/SETTINGS.md) · [Controls](docs/ios/CONTROLS.md) · [Multiplayer](docs/ios/MULTIPLAYER.md) · [Backups](docs/ios/BACKUPS.md) |
| Problems | [Troubleshooting](docs/ios/TROUBLESHOOTING.md) |
| Development | [Developer guide](port/ios/README.md) · [Engineering history](docs/ios/HISTORY.md) |
| The official project | [Halo CE Universal and credits](docs/UPSTREAM.md) |
