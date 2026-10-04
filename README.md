# Halo: Combat Evolved for iOS

A native iPhone and iPad port of *Halo: Combat Evolved*. It runs the recovered Xbox engine from
[Halo CE Universal](https://github.com/cybersecurity/halo-ce-universal) inside a native iOS app, with touch and
controller support, cross-play multiplayer with Halo CE Universal players, and a full in-app Settings menu.

> **You are on the regular app branch.** A separate **Mod Test** app lives on the [`ios/cursed-a10-mod-test`](https://github.com/xSkullHD/Halo-CE-IOS/tree/ios/cursed-a10-mod-test) branch.

> **Status: experimental.** The current update is **M2.6.50**. The core game (menus, campaign, multiplayer, audio)
> has been tested on a physical iPhone. The newest features are built and checked by automated tests but still wait for
> on-device validation; see the [release notes](docs/ios/RELEASE_NOTES.md) and the [project status](IOS_PORT_STATUS.md).

## Highlights

- **Native app.** An `arm64` iOS app hosts the recovered `arm64_32` engine and draws with OpenGL ES 3. iOS and iPadOS 15 or later.
- **Touch controls.** Five named control schemes (Xbox and PlayStation styles), a drag-to-edit layout, touch look, floating sticks, left-handed
  layout, toggle crouch and zoom, gyro aiming and optional touch-aiming helpers. [Controls guide](docs/ios/CONTROLS.md)
- **Controller support.** Xbox, PlayStation and other controllers supported by Apple's GameController framework, with stick tuning and button remapping.
- **Multiplayer.** Cross-play with Halo CE Universal on PC: invite links, an invite file in iCloud Drive or the app's folder, a QR code,
  recent games, LAN games, and the Direct Link and Create Game screens. [Multiplayer guide](docs/ios/MULTIPLAYER.md)
- **Display.** 30 FPS original, smooth 60 or uncapped; 4:3, widescreen or fullscreen; three render-detail levels; a live HUD editor;
  first-person view options; AirPlay mirroring. [Settings reference](docs/ios/SETTINGS.md), [AirPlay](docs/ios/AIRPLAY.md)
- **Sound.** Native audio with separate Master, Music, Dialogue, Effects and Ambient volumes.
- **Campaign tools.** An optional, campaign-only Cheats menu organised into sections (survival, weapons, power-ups, movement, world,
  checkpoints, teleport, spawn), with a saved cheat recipe for each control scheme.
- **Your data, kept safe.** A map library with Mods support, versioned backups you can export to Files or iCloud Drive, profile export and import,
  and diagnostics with a one-tap problem report. [Backups](docs/ios/BACKUPS.md)

## Quick start

1. **Get the app.** Download the pre-built `HaloCE.ipa` from the [latest release](https://github.com/xSkullHD/Halo-CE-IOS/releases/latest), or
   [build it yourself](docs/ios/BUILD.md) with GitHub Actions. No Mac is needed.
2. **Install it.** The IPA must be re-signed and sideloaded onto your device. [Install guide](docs/ios/INSTALL.md)
3. **Add your game data.** The app does not include any game files. Import the Xbox `.map` files from your own copy of the game,
   including `ui.map`. [Game data guide](docs/ios/GAME_DATA.md)
4. **Play.** Open Halo CE, import your maps and start the game. Open the gear button at any time for Settings.

## Two apps from one project

| | **Halo CE** (regular) | **Halo CE Mod Test** |
| --- | --- | --- |
| Purpose | The regular app | A separate experiment that loads very large converted campaign maps |
| Branch | [`main`](https://github.com/xSkullHD/Halo-CE-IOS/tree/main) | [`ios/cursed-a10-mod-test`](https://github.com/xSkullHD/Halo-CE-IOS/tree/ios/cursed-a10-mod-test) |
| Workflow | Halo CE iOS — Build IPA | Halo CE iOS — Mod Loading Test |
| Output | `HaloCE.ipa` (artifact `HaloCE-iOS`) | `HaloCE-ModTest.ipa` (artifact `HaloCE-iOS-ModTest`) |
| Bundle ID | `com.haloceuniversal.ios.m0` | `com.haloceuniversal.ios.modtest` |
| Invite scheme | `halo://` | `halomodtest://` |

Both apps share the same features and are kept up to date together. They install side by side and keep separate data. See
[Mod Test](docs/ios/MOD_TEST.md) for what makes the second app different.

## Documentation

| Guide | What it covers |
| --- | --- |
| [Install](docs/ios/INSTALL.md) | Requirements, getting the IPA, sideloading, first launch, updating |
| [Build the IPA](docs/ios/BUILD.md) | Building with GitHub Actions or on a Mac, build options, publishing a release |
| [Game data](docs/ios/GAME_DATA.md) | Importing maps, extracting maps from an Xbox ISO or XISO, where files live |
| [Backups](docs/ios/BACKUPS.md) | What a backup contains, exporting, restoring, recovery |
| [Settings reference](docs/ios/SETTINGS.md) | Every Settings screen and option |
| [Controls](docs/ios/CONTROLS.md) | Touch controls, controllers, gyro, touch aiming |
| [Multiplayer](docs/ios/MULTIPLAYER.md) | Invites, iCloud Drive and folder invite files, LAN, cross-play |
| [AirPlay](docs/ios/AIRPLAY.md) | Showing the game on a TV or display |
| [Troubleshooting](docs/ios/TROUBLESHOOTING.md) | Safe Start, logs, problem reports, common problems |
| [Mod Test](docs/ios/MOD_TEST.md) | The separate Mod Test app |
| [Release notes](docs/ios/RELEASE_NOTES.md) | Every update, with its device checklist |
| [Official project and other platforms](docs/UPSTREAM.md) | Halo CE Universal, its downloads and credits |

## Looking for the official project or other platforms?

This repository is an iOS-focused fork. The official project, its updates, and the Windows, Linux and Android versions
are maintained by **Halo CE Universal**:

- Repository: <https://github.com/cybersecurity/halo-ce-universal>
- Releases and downloads: <https://github.com/cybersecurity/halo-ce-universal/releases>

[Official project and other platforms](docs/UPSTREAM.md) lists the downloads, where each platform is documented, and the credits.
The original README of the upstream project is kept in [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md).

## Credits

This port exists because of the work of others:

- **[Halo CE Universal](https://github.com/cybersecurity/halo-ce-universal)** and its contributors: the cross-platform port of the decompiled
  engine, its netcode and invite-link multiplayer, the Custom Edition style menus, and the project this app is built on.
- **[bnunu/halo-1](https://github.com/bnunu/halo-1)**, the decompilation of the Xbox build 2342 (`cachebeta.exe`) that Halo CE Universal starts from,
  and **[punpckhdq/halo](https://github.com/punpckhdq/halo)**, the project it was forked from.
- **Bungie**, who created *Halo: Combat Evolved*, and **Microsoft / Xbox Game Studios** and **343 Industries**, its later owners and stewards.
- The open-source libraries bundled in [`port/third_party`](port/third_party): expat, extract-xiso, kcp, mbedtls, miniupnpc, musl math, stb and
  tomlc17, each under its own license.
- The iOS port in this repository is maintained by [xSkullHD](https://github.com/xSkullHD/Halo-CE-IOS).

See [Official project and other platforms](docs/UPSTREAM.md#credits) for details.

## Legal

This is an unofficial, non-commercial fan project. It is not affiliated with or endorsed by Microsoft, Xbox Game Studios, 343 Industries or
Bungie. *Halo* and related names are trademarks of Microsoft. **No game data is included.** You need your own copy of the game, and you
are responsible for using it in line with its license. The source code in this repository is released under [CC0 1.0](LICENSE.md); bundled third-party
code keeps its own license.
