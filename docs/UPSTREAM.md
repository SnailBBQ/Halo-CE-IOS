# The official project and other platforms

This repository is an **iOS-focused fork** of **Halo CE Universal**, an open-source port of the recovered *Halo: Combat Evolved* engine. For anything that is not iOS, go to the official project:

- **Repository:** <https://github.com/cybersecurity/halo-ce-universal>
- **Releases and downloads:** <https://github.com/cybersecurity/halo-ce-universal/releases>
- **Community:** the project's [Discord](https://discord.gg/9gqcHyr5km)

## Downloads for the other platforms

The official project builds Windows, Linux and Android versions. These links download the latest release:

| Platform | Release | Debug |
| --- | --- | --- |
| Windows | [halo-windows-release.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-windows-release.zip) | [halo-windows-debug.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-windows-debug.zip) |
| Linux | [halo-linux-release.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-linux-release.zip) | [halo-linux-debug.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-linux-debug.zip) |
| Android | [halo-android-release.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-android-release.zip) | [halo-android-debug.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-android-debug.zip) |

Use the release build to play. The debug build stops at the first failed assertion and writes it to the log, which helps when you report a problem. The desktop and Android versions check for a
newer release at start-up and offer to install it. The official project keeps its last five releases, so you can go back to an older one if the latest has a problem.

## Where each platform is documented

| Platform | Documentation |
| --- | --- |
| Windows | [port/windows/README.md](https://github.com/cybersecurity/halo-ce-universal/blob/main/port/windows/README.md) |
| Linux | [port/linux/README.md](https://github.com/cybersecurity/halo-ce-universal/blob/main/port/linux/README.md) |
| Android | [port/android/README.md](https://github.com/cybersecurity/halo-ce-universal/blob/main/port/android/README.md) |

The Linux page also describes the controls, settings and multiplayer functions, which are almost the same on every platform. The upstream README is kept in this repository as
[UPSTREAM_README.md](UPSTREAM_README.md), including its build instructions for the other platforms.

## Staying compatible

Multiplayer needs compatible protocol versions and map content. M2.6.54 integrates Universal build 94 (`d578f88bd0ef447b9039353a3f04affea55295a5`) while preserving the iOS host. Matching tested builds are recommended. Update your other clients alongside the app; Apple compilation and cross-platform device testing are still required for this update. See [Multiplayer](ios/MULTIPLAYER.md#compatibility).

## What this fork adds

The iOS app lives in [`port/ios`](../port/ios). It adds the native host, the iOS Settings and controls, audio, networking, backups, the map library and mods. The engine sources are shared with the other platforms; the iOS-only changes are
guarded so they do not affect them.

## Credits

This port would not exist without the people below.

- **Halo CE Universal** ([cybersecurity/halo-ce-universal](https://github.com/cybersecurity/halo-ce-universal)) and its contributors. They built the cross-platform port of the decompiled engine, its netcode and invite-link multiplayer,
  the Custom Edition style menus and the updater, and they publish the project this app is built on. Thank you.
- **bnunu/halo-1** ([bnunu/halo-1](https://github.com/bnunu/halo-1)), the decompilation of the Xbox build 2342 (`cachebeta.exe`, SHA-256 `4cc87b45f721270392a96f1674ed2b5cd4a7bb4355faeab4531d1cf1884d9520`) that Halo CE Universal starts from.
- **punpckhdq/halo** ([punpckhdq/halo](https://github.com/punpckhdq/halo)), the project that bnunu's decompilation is a fork of.
- **Bungie**, who created *Halo: Combat Evolved*, and **Microsoft / Xbox Game Studios** and **343 Industries**, for their work on the series. This is an unofficial fan project and is not affiliated with or endorsed by them. *Halo* and related names are trademarks of Microsoft.
- **Open-source libraries** bundled in [`port/third_party`](../port/third_party), each under its own license:

| Library | Folder |
| --- | --- |
| expat (XML parser, used by the menus) | `port/third_party/expat` |
| extract-xiso (Xbox disc image extraction) | `port/third_party/extract-xiso` |
| kcp (reliable UDP) | `port/third_party/kcp` |
| mbed TLS | `port/third_party/mbedtls` |
| miniupnpc (port mapping) | `port/third_party/miniupnpc` |
| musl math | `port/third_party/musl-math` |
| stb | `port/third_party/stb` |
| tomlc17 (TOML configuration) | `port/third_party/tomlc17` |

- **The iOS port** in this repository is maintained by [SnailBBQ](https://github.com/SnailBBQ).

Project code is released under [CC0 1.0](../LICENSE.md); third-party components retain their own licenses. Fonts include Overpass and OpenCE under the SIL Open Font License and Newtown under its documented public-domain terms; see [font credits and notices](../port/assets/fonts/README.md). Menu artwork is described in the [menu asset guide](../port/assets/menus/README.md).

**No game maps or original engine executable are included.** Documentation includes gameplay screenshots. Supply maps from your own copy of the game.
