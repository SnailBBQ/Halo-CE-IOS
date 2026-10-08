# Halo: Combat Evolved for iOS

A native iPhone and iPad port of *Halo: Combat Evolved*. It runs the recovered Xbox engine from
[OpenCE](https://github.com/OpenCommunityEdition/OpenCE) (formerly Halo CE Universal) inside a native iOS app, with touch and
controller support, cross-play multiplayer with OpenCE players, and a full in-app Settings menu.

> **One branch.** The regular app, Mod Test, and the Non-Jailbreak diagnostic build are options on **Actions → Halo CE iOS — Build IPA**. There is no separate Mod Test branch.

> **Status: playable on the regular/jailbreak path.** The current source update is **M2.6.96**, keeping OpenCE build 146 (network version 22), Custom Edition maps and the MP4 movie fallback while continuing the experimental Non-Jailbreak **Stage 3 real-guest flexible-base execution** path. M2.6.95 advanced the real flexible guest compile to object 63/1492 and exposed a false-positive guard: LLVM can preserve fixed x27 in a host-stack callee-save pair. M2.6.96 accepts only that preservation pattern while keeping every computational reserved-register use fail-closed. See the [release notes](docs/ios/RELEASE_NOTES.md) and [project status](IOS_PORT_STATUS.md).

## Current Status

> **Jailbreak required:** Halo CE iOS is currently confirmed working on jailbroken iOS devices.
>
> **Non-jailbreak support:** A non-jailbreak version is currently a work in progress and is not yet considered ready for general use.
>
> **Free-account sideloading (Sideloadly, AltStore, SideStore):** experimental, not supported yet. An iPhone 14 Plus on iOS 16.2 can reserve a contiguous 4 GiB span only at a non-4-GiB-aligned address, and M2.6.93 proved base+uint32 memory, threads/imports and executable code there. M2.6.96 is the current **real** OpenCE arm64_32 arbitrary-base candidate; it retains Stage 3 and repairs the reserved-x27 preservation false positive exposed by the second real guest build. An older iPad still cannot reserve 4 GiB contiguously at all and remains outside this design. See [Install](docs/ios/INSTALL.md#sideloading-with-free-and-paid-accounts).
>
> **Paid Apple Developer accounts:** people who have one may be able to sign the regular app with the `extended-virtual-addressing` and `increased-memory-limit` capabilities and get it to start on a non-jailbroken device. We have not tested this, and the project does not require or build around paid accounts. See [Install](docs/ios/INSTALL.md#sideloading-with-free-and-paid-accounts).

**Source update:** [M2.6.96](port/ios/UPDATE_M2696.md) keeps the Non-Jailbreak **real-guest flexible-base Stage 3** architecture and fixes the next fail-closed converter guard exposed by the actual arm64_32 build. The guest still reserves x27 as the immutable 64-bit arena base and x15 as scratch. LLVM is now allowed to save/reload x27 only through the real host stack as a 64-bit callee-saved register; arithmetic, branches, guest-memory addressing, w27 use and source x15 remain forbidden. Regular and Mod Test builds keep the proven aligned architecture. OpenCE remains **build 146/network 22**; Custom Edition maps and MP4 fallback are unchanged. Windows, Linux and Android stay on [OpenCE](https://github.com/OpenCommunityEdition/OpenCE/releases).

<p align="center">
  <img src="docs/ios/images/main-menu-pc.jpg" alt="The main menu of OpenCE on PC" width="760"><br>
  <em>Main menu on PC (OpenCE)</em>
</p>

<p align="center">
  <img src="docs/ios/images/main-menu-xbox-ui.jpg" alt="The same main menu on iPhone with the Xbox UI controls" width="760"><br>
  <em>Main menu on iPhone — Xbox UI controls</em>
</p>

## Highlights

- **Native app.** An `arm64` iOS app hosts the recovered `arm64_32` engine and draws with OpenGL ES 3. iOS and iPadOS 15 or later.
- **Touch controls.** Five named control schemes (Xbox and PlayStation styles), a drag-to-edit layout, touch look, floating sticks, left-handed
  layout, toggle crouch and zoom, gyro aiming and optional touch-aiming helpers. [Controls guide](docs/ios/CONTROLS.md)
- **Controller support.** Xbox, PlayStation and other controllers supported by Apple's GameController framework, with stick tuning and button remapping.
- **Multiplayer.** Crossplay with compatible OpenCE clients on other platforms: invite links, an invite file in iCloud Drive or the app's folder, a QR code,
  recent games, LAN games, and the public Server Browser, Direct Link and Create Game screens. [Multiplayer guide](docs/ios/MULTIPLAYER.md)
- **Display.** 30 FPS original, a 60 FPS target or uncapped; 4:3, widescreen or fullscreen; four render-resolution choices; a live HUD editor;
  first-person view options; AirPlay mirroring. [Display / AirPlay](docs/ios/DISPLAY_AIRPLAY.md), [Settings reference](docs/ios/SETTINGS.md)
- **Sound.** Native audio with separate Master, Music, Dialogue, Effects and Ambient volumes.
- **Campaign tools.** An optional, campaign-only Cheats menu organised into sections (survival, weapons, power-ups, movement, world,
  visuals, checkpoints, teleport, spawn), with a saved cheat recipe for each control scheme.
- **Backups and data management.** Separate Xbox and Custom Edition map libraries, optional user-supplied MP4 movie fallback, versioned backups you can export to Files or iCloud Drive, profile export and import,
  and diagnostics with a one-tap problem report. [Backups](docs/ios/BACKUPS.md)

## Quick start

1. **Get the app.** Download `HaloCE.ipa` from a successful [Actions run](https://github.com/SnailBBQ/Halo-CE-IOS/actions), or
   [build it yourself](docs/ios/BUILD.md). There is no published iOS release yet. GitHub Actions can build it without a local Mac when account usage allows.
2. **Install it.** The IPA must be re-signed and sideloaded onto your device. [Install guide](docs/ios/INSTALL.md)
3. **Add your game data.** The app does not include game maps. Import the Xbox `.map` files from your own copy of the game,
   including `ui.map`. [Game data guide](docs/ios/GAME_DATA.md)
4. **Play.** Open Halo CE, import your maps and start the game. Open the gear button at any time for Settings.

## Two apps from one project

| | **Halo CE** (regular) | **Halo CE Mod Test** |
| --- | --- | --- |
| Purpose | The regular app | A separate experiment that loads very large converted campaign maps |
| How to build | Actions → Build IPA, options off | Same workflow, tick **Mod Test** |
| Output | `HaloCE.ipa` (artifact `HaloCE-iOS`) | `HaloCE.ipa` (artifact `HaloCE-iOS-ModTest`) |
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
| [Display / AirPlay](docs/ios/DISPLAY_AIRPLAY.md) | Frame rate, picture shape and detail, the HUD editor, first-person view, heat and battery, menus, and showing the game on a TV |
| [Troubleshooting](docs/ios/TROUBLESHOOTING.md) | Safe Start, logs, problem reports, common problems |
| [Mod Test](docs/ios/MOD_TEST.md) | The separate Mod Test app |
| [Release notes](docs/ios/RELEASE_NOTES.md) | Every update, with its device checklist |
| [Official project and other platforms](docs/UPSTREAM.md) | OpenCE, its downloads and credits |

## Looking for the official project or other platforms?

This repository is an iOS-focused fork. The official project, its updates, and the Windows, Linux and Android versions
are maintained by **OpenCE**:

- Repository: <https://github.com/OpenCommunityEdition/OpenCE>
- Releases and downloads: <https://github.com/OpenCommunityEdition/OpenCE/releases>

[Official project and other platforms](docs/UPSTREAM.md) lists the downloads, where each platform is documented, and the credits.
The original README of the upstream project is kept in [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md).

## Credits

This port exists because of the work of others:

- **[OpenCE](https://github.com/OpenCommunityEdition/OpenCE)** (formerly Halo CE Universal) and its contributors: the cross-platform port of the decompiled
  engine, its netcode and invite-link multiplayer, the Custom Edition style menus, and the project this app is built on.
- **[bnunu/halo-1](https://github.com/bnunu/halo-1)**, the decompilation of the Xbox build 2342 (`cachebeta.exe`) that OpenCE starts from,
  and **[punpckhdq/halo](https://github.com/punpckhdq/halo)**, the project it was forked from.
- **Bungie**, who created *Halo: Combat Evolved*, and **Microsoft / Xbox Game Studios** and **343 Industries**, its later owners and stewards.
- The open-source libraries bundled in [`port/third_party`](port/third_party): expat, extract-xiso, kcp, mbedtls, miniupnpc, Monocypher, musl math, stb and
  tomlc17, each under its own license.
- The iOS port in this repository is maintained by [SnailBBQ](https://github.com/SnailBBQ).

See [Official project and other platforms](docs/UPSTREAM.md#credits) for details.

### App Icon

<p align="center">
  <img src="docs/ios/images/prometheus_gearbox-shaded.png" width="256" alt="Halo CE iOS app icon">
  <br><br>
  <strong>App icon artwork by ORION</strong><br>
  <em>Used with ORION's permission. All credit goes to them.</em><br>
  <a href="https://github.com/OrionMelaeno">GitHub</a> ·
  <a href="https://discord.com/users/758542539241685003">Discord</a>
</p>

## Legal

This is an unofficial, non-commercial fan project. It is not affiliated with or endorsed by Microsoft,
Xbox Game Studios, 343 Industries or Bungie. *Halo* and its name, characters and artwork are owned by Microsoft.

**No game files are included** (no maps, assets or original executable). You need your own copy of the game,
and you are responsible for using it in line with its license. We can't provide game files or help you find
them, so please don't share them, or links to them, here.

The engine is recovered from the original game by the upstream OpenCE project. This project claims no rights
held by Microsoft or anyone else.

Code written by this project and its upstream contributors is offered under [CC0 1.0](LICENSE.md), to the
extent they own it. That gives you no rights in *Halo*. Third-party libraries and fonts, the app icon by ORION,
and the screenshots in the docs keep their own terms (see the [credits](docs/UPSTREAM.md#credits)).

Builds are free and come with no warranty. If you share one, keep it free: no selling and no ads.

For maintainers, the [public release checklist](docs/ios/PUBLIC_RELEASE.md) records the remaining publication and verification steps.
