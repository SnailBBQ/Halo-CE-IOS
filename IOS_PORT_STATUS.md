# Halo CE iOS — Project status

**Current update: M2.6.50** (regular app 0.2.50, Mod Test app 0.2.50.1). The core game has been tested on a physical iPhone; the newest features are built and checked by automated tests and
are waiting for device validation. See the [release notes](docs/ios/RELEASE_NOTES.md) and the [README](README.md).

## Two apps

| App | Branch | Output |
| --- | --- | --- |
| Halo CE (regular) | `main` | `HaloCE.ipa` |
| Halo CE Mod Test | `ios/cursed-a10-mod-test` | `HaloCE-ModTest.ipa` |

Both share the same features and are updated together. The Mod Test app adds an experimental loader for very large converted campaign maps; see [Mod Test](docs/ios/MOD_TEST.md).

## What works (reported from device testing)

- The Halo main menu, campaign start (`a10` and onward), 60 FPS menus and gameplay, native audio.
- Cross-play multiplayer with Halo CE Universal clients, including joining by invite link.
- On-screen Xbox-style controls with five schemes, touch look, and physical controllers.

## Built and tested locally, waiting for device validation

- The PC menus from the newer Halo CE Universal build (M2.6.49).
- The Settings additions of M2.6.48 (cheat sections and new cheats, left-handed layout, gyro, controller remap, heat-aware frame cap, performance overlay, Ambient volume, recent games and QR, Profiles, problem report, custom accent colours).
- Picture options, touch aiming and AirPlay mirroring (M2.6.50).
- The Mod Test loader, offline-validated only.

## Known limits

- The PC menus' public **Server Browser** is empty, because the upstream project has not built a public server list yet. LAN, Direct Link and Create Game work.
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
