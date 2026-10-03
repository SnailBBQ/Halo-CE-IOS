# Halo: Combat Evolved for Linux, Windows, Android and iOS

Current iOS update: **M2.6.47** — clear grenade-swap and flashlight symbols, Settings size/color Options, centered larger map previews and direct-boot polish. See [release notes](port/ios/UPDATE_M2647.md). Device validation is pending.

[![Join our Discord](https://invidget.switchblade.xyz/9gqcHyr5km)](https://discord.gg/9gqcHyr5km)

This project is a port of the Halo: Combat Evolved decompilation to Linux,
Windows, Android and an experimental iOS port. The decompilation is of the Xbox build 2342
(`cachebeta.exe`, SHA-256
`4cc87b45f721270392a96f1674ed2b5cd4a7bb4355faeab4531d1cf1884d9520`).

<img width="1289" height="995" alt="The game on Linux" src="https://github.com/user-attachments/assets/0d3ad50f-f8b8-46cf-aef8-e3661da2a7d7" />

The port starts from the decompilation of [bnunu/halo-1](https://github.com/bnunu/halo-1).
That project is a fork of [punpckhdq/halo](https://github.com/punpckhdq/halo).

## iOS development status

This fork is based on Halo CE Universal **build 73** and adds an experimental native iOS app (arm64 host, arm64_32 guest, OpenGL ES 3).
The iOS build has on-screen Xbox controls with five named schemes, touch-look, physical controller support, sound, a readable log and
invite-link multiplayer that follows the other ports' protocol. See [iOS port status](IOS_PORT_STATUS.md), the
[M2.6.47 release notes](port/ios/UPDATE_M2647.md) and the [iOS build, installation, and map setup guide](port/ios/README.md).
Previous iOS milestone: **M2.6.42**. M2.6.42 replaces M2.6.41’s costly upload-every-draw fallback with exact native geometry comparisons: unchanged pages avoid GPU uploads while modified/reused pages remain fresh. Active cheats are session-only; presets have gear editors, campaign recipes and Xbox/PlayStation face-button styles. Advanced adds explicit Quit, manual Restart instructions and GitHub Credits. Device FPS, visuals and client stability need validation.
Release downloads below are the upstream project's; the iOS build is an Actions artifact (**Halo CE iOS — Build IPA**).

## Download

GitHub Actions builds the game for each commit. These links download the
builds of the latest release:

| Platform | Release | Debug |
| --- | --- | --- |
| Linux | [halo-linux-release.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-linux-release.zip) | [halo-linux-debug.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-linux-debug.zip) |
| Windows | [halo-windows-release.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-windows-release.zip) | [halo-windows-debug.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-windows-debug.zip) |
| Android | [halo-android-release.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-android-release.zip) | [halo-android-debug.zip](https://github.com/cybersecurity/halo-ce-universal/releases/latest/download/halo-android-debug.zip) |

Use the release build to play. The debug build stops at the first failed
assertion and writes it to the log. Use the debug build to find and report
problems.

The game updates itself. At start-up it looks for a newer release, and asks
if you want to install it. Refer to "Updates" in
[port/linux/README.md](port/linux/README.md#updates).

Each build of the `main` branch that passes on all three platforms is a new
release. The [Releases](https://github.com/cybersecurity/halo-ce-universal/releases)
page keeps the last five releases. If the latest build has a problem, get
an older build from that page.

## Game data

The port does not include the game data. Download an Xbox disc image
(`.xiso` or `.iso`) of Halo: Combat Evolved. All versions of the game
operate. The maps of the European (PAL) version were made for a slower
console. The port changes them to play as the North American (NTSC) maps do,
so players of the two versions can play together.

1. Start the game.
2. At the first start, the game asks for the disc image. Select it.
3. The game extracts the `maps/` folder. Then the game starts.

On Linux and Windows, the game puts `maps/` next to the executable. On
Android, copy the disc image to the phone first. The app puts `maps/` in its
data folder. Refer to [port/android/README.md](port/android/README.md).

## Platforms

Each platform has its own instructions:

| Platform | Instructions |
| --- | --- |
| Linux (32-bit x86 executable, OpenGL 4.5, SDL3) | [port/linux/README.md](port/linux/README.md) |
| Windows (32-bit x86 executable, OpenGL 4.5, SDL3) | [port/windows/README.md](port/windows/README.md) |
| Android (arm64 app, OpenGL ES 3, SDL3) | [port/android/README.md](port/android/README.md) |
| iOS/iPadOS 15+ (arm64 host, arm64_32 guest, OpenGL ES 3; experimental) | [port/ios/README.md](port/ios/README.md) |

The Linux README also gives the controls, the settings and the multiplayer
functions. These are almost the same on all platforms.

## Multiplayer

The game can play system link games on a local network and on the internet:

- A system link game can have up to 128 players on up to 128 machines.
- Linux, Windows and Android machines can play in the same game.
- An invite link lets a machine join a game on the internet. No server of
  this project is necessary.
- The netcode is new. Each machine moves its own player at once,
  and the host makes the decisions for the game. Refer to
  [port/linux/NETCODE.md](port/linux/NETCODE.md).

## Build the game

You do not need the Xbox SDK. The port supplies the SDK declarations that
the game uses. Refer to [port/include/xdk](port/include/xdk/README.md).

To build the game:

1. Install Python and [ninja](https://ninja-build.org/).
2. Install the tools for your platform. Refer to the README for the
   platform.
3. In the root folder of the repository, enter `python configure.py`.
4. Enter `ninja` with the target for the platform:

| Target | Result |
| --- | --- |
| `ninja linux` | `build/linux/halo` |
| `ninja windows` (on Windows) | `build/windows/halo.exe` and `SDL3.dll` |
| `ninja android_apk` | `port/android/app/build/outputs/apk/debug/app-debug.apk` |

If you enter `ninja` without a target, ninja builds the game for the
computer that you use.

`tools/ci_build.py` makes the same builds as GitHub Actions. For example,
enter `python tools/ci_build.py linux release`.

### Build options

Give these options to `configure.py`:

| Option | Result |
| --- | --- |
| (none) | A debug build. A failed assertion stops the game. |
| `--release` | A release build. The game does not examine assertions, as in the retail game. |
| `--portable` | The Linux and Windows builds operate on all x86-64 processors. Use this option for builds that you give to other persons. |
| `--lto=thin`, `--lto=off` | Less link-time optimization. The link is faster. |
| `--pgo=off` | No profile-guided optimization. |
| `--pgo=train` | Records a new optimization profile. Refer to "Optimization profiles". |

Without `--portable`, the Linux and Windows builds use all the instructions
of the processor that builds them (`-march=native`). Such a build does not
always start on a different computer.

### Optimization profiles

The builds use profiles of the game to optimize the code:

- `pgo/halo_linux.profdata` for Linux and Android.
- `pgo/halo_windows.profdata` for Windows.

The profiles need clang 22 or later. With an older clang, the builds do not
use the profiles.

To record a new profile:

1. Delete the profile.
2. Enter `python configure.py --pgo=train`.
3. Enter `ninja linux` or `ninja windows`.

The build then plays the main menu and the first minute of each campaign
level. This procedure continues for approximately 15 minutes. The game
data must be in `assets/`.

## M2.6.41 geometry correction

Device testing found campaign world corruption as well as multiplayer mesh distortion. The iOS GPU geometry mirror incorrectly treated no-op write-tracking generations as unchanged data. Requested ranges now refresh before every draw, including same-frame writes and reused map addresses. This may increase upload cost; FPS and visual correctness need device validation. The guest_glUniform4fv execution fault remains under investigation. See [release notes](port/ios/UPDATE_M2642.md). Swipe-away terminates the app through iOS; final callbacks and iCloud cleanup are best-effort, with existing next-launch cleanup retained.

## M2.6.42 update

M2.6.42 replaces M2.6.41’s costly upload-every-draw fallback with exact native geometry comparisons: unchanged pages avoid GPU uploads while modified/reused pages remain fresh. Active cheats are session-only; presets have gear editors, campaign recipes and Xbox/PlayStation face-button styles. Advanced adds explicit Quit, manual Restart instructions and GitHub Credits. Device FPS, visuals and client stability need validation.
