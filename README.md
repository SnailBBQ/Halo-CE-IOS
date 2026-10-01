# Halo: Combat Evolved for Linux, Windows, Android and iOS

This project is a port of the Halo: Combat Evolved decompilation to Linux,
Windows, Android and an experimental iOS port. The decompilation is of the Xbox build 2342
(`cachebeta.exe`, SHA-256
`4cc87b45f721270392a96f1674ed2b5cd4a7bb4355faeab4531d1cf1884d9520`).

<img width="1289" height="995" alt="The game on Linux" src="https://github.com/user-attachments/assets/0d3ad50f-f8b8-46cf-aef8-e3661da2a7d7" />

The port starts from the decompilation of [bnunu/halo-1](https://github.com/bnunu/halo-1).
That project is a fork of [punpckhdq/halo](https://github.com/punpckhdq/halo).

## iOS development status

**M2.6.19 is awaiting device testing.** The main menu and readable text are confirmed on device. M2.6.14 touch menu controls worked in the latest test, and the game log reached precaching of `a10`. Campaign gameplay is still unconfirmed. M2.6.16 improved menu startup in the user test, but frame rates remain low and `a10` stayed black despite completing map initialization. M2.6.17 adds the colored original Xbox A/B/X/Y/Black/White touch buttons alongside the left D-pad. M2.6.18 targets checksum and texture-conversion delays and keeps loading status visible through first presentation. Boot log and Game log retain important messages.

See [iOS port status](IOS_PORT_STATUS.md) and the [iOS build, installation, and map setup guide](port/ios/README.md).

## Download

The Linux/Windows/Android workflow publishes successful builds as releases.
The links below point to this repository’s latest release assets:

| Platform | Release | Debug |
| --- | --- | --- |
| Linux | [halo-linux-release.zip](https://github.com/xSkullHD/Halo-CE-IOS/releases/latest/download/halo-linux-release.zip) | [halo-linux-debug.zip](https://github.com/xSkullHD/Halo-CE-IOS/releases/latest/download/halo-linux-debug.zip) |
| Windows | [halo-windows-release.zip](https://github.com/xSkullHD/Halo-CE-IOS/releases/latest/download/halo-windows-release.zip) | [halo-windows-debug.zip](https://github.com/xSkullHD/Halo-CE-IOS/releases/latest/download/halo-windows-debug.zip) |
| Android | [halo-android-release.zip](https://github.com/xSkullHD/Halo-CE-IOS/releases/latest/download/halo-android-release.zip) | [halo-android-debug.zip](https://github.com/xSkullHD/Halo-CE-IOS/releases/latest/download/halo-android-debug.zip) |

For iOS, open [Actions → Halo CE iOS — Build IPA](https://github.com/xSkullHD/Halo-CE-IOS/actions/workflows/ios.yml), run it on `main`, and download **HaloCE-iOS**. Extract the artifact ZIP to obtain **HaloCE.ipa**, then re-sign and install it with your sideloading tool. iOS builds are experimental and are distributed as Actions artifacts, separately from the releases above.

Use the release build to play. The debug build stops at the first failed
assertion and writes it to the log. Use the debug build to find and report
problems.

The Linux/Windows/Android ports support updates. The iOS build currently requires installing a newly built IPA.

On the established ports, the game updates itself. At start-up it looks for a newer release, and asks
if you want to install it. Refer to "Updates" in
[port/linux/README.md](port/linux/README.md#updates).

Each build of the `main` branch that passes on all three platforms is a new
release. The [Releases](https://github.com/xSkullHD/Halo-CE-IOS/releases)
page keeps the last five releases. If the latest build has a problem, get
an older build from that page.

## Game data

The port does not include game data. Supply an Xbox disc image
(`.xiso` or `.iso`) of Halo: Combat Evolved. All versions of the game
operate. The maps of the European (PAL) version were made for a slower
console. The port changes them to play as the North American (NTSC) maps do,
so players of the two versions can play together.

For Linux, Windows, and Android:

1. Start the game.
2. At the first start, the game asks for the disc image. Select it.
3. The game extracts the `maps/` folder. Then the game starts.

On Linux and Windows, the game puts `maps/` next to the executable. On
Android, copy the disc image to the phone first. The app puts `maps/` in its
data folder. Refer to [port/android/README.md](port/android/README.md).

For iOS, launch **Halo CE** to create `Documents/Halo/maps`, then use **Import maps** or copy Xbox `.map` files into that folder through Files. Include `ui.map` before starting the engine. iOS does not currently provide the disc-image extraction flow above. See the [iOS setup guide](port/ios/README.md#maps-and-first-launch).

## Platforms

Each platform has its own instructions:

| Platform | Instructions |
| --- | --- |
| Linux (32-bit x86 executable, OpenGL 4.5, SDL3) | [port/linux/README.md](port/linux/README.md) |
| Windows (32-bit x86 executable, OpenGL 4.5, SDL3) | [port/windows/README.md](port/windows/README.md) |
| Android (arm64 app, OpenGL ES 3, SDL3) | [port/android/README.md](port/android/README.md) |
| iOS/iPadOS 15+ (arm64 host, arm64_32 guest, OpenGL ES 3; experimental) | [port/ios/README.md](port/ios/README.md) |

The Linux README also gives the controls, the settings and the multiplayer
functions for Linux, Windows, and Android. iOS controls and multiplayer still need validation.

## Multiplayer

The Linux, Windows, and Android ports support system link games on a local network and on the internet. iOS multiplayer is not yet validated:

- A system link game can have up to 128 players on up to 128 machines.
- Linux, Windows and Android machines can play in the same game.
- An invite link lets a machine join a game on the internet. No server of
  this project is necessary.
- The default netcode is new. Each machine moves its own player at once,
  and the host makes the decisions for the game. Refer to
  [port/linux/NETCODE.md](port/linux/NETCODE.md).

## Build the game

You do not need the Xbox SDK. The port supplies the SDK declarations that
the game uses. Refer to [port/include/xdk](port/include/xdk/README.md).

For iOS, use **Halo CE iOS — Build IPA** to produce `HaloCE.ipa`. The [iOS build instructions](port/ios/README.md#build-with-github-actions) explain the Linux guest build, macOS/Xcode host build, and optional local Mac packaging. There is no `ninja ios` target.

To build Linux, Windows, or Android:

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

### The byte-matching build

The original project also has a byte-matching build. That build compiles
the game with the compiler of the Xbox SDK and compares the result with
`cachebeta.exe`. This project does not generate that build, because the
Xbox SDK is not free to distribute. The sources of that build are not
changed. To use the build again, set `SolutionConfig.matching` in
`tools/project_x86.py`. You must also have the Xbox SDK in `xbox/` and
`cachebeta.exe` in the root folder.

## M2.6.16 performance and loading diagnostics

Bulk guest memory copies, moves, and fills of at least 256 bytes now use native host routines with guest-span validation. Smaller operations retain the guest implementation. Ten-second heartbeats report native call and byte totals. Compiler-inlined operations are unaffected; speed improvements require device measurement.

Map cache preparation, scenario/assets loading, and major initialization steps report elapsed times in Boot log. A loading label displays the current instrumented stage and elapsed seconds, including when Show game is open. It is stage information, not a percentage or proof that loading has completed. Menu navigation uses a left D-pad with Select and Back on the right. Audio remains muted and Bink movies remain skipped.

Awaiting device testing: compare menu startup time and try `a10`. If loading appears stalled, share logs while the loading stage is still visible. Campaign gameplay remains unconfirmed.

## M2.6.18 performance test bundle

CRC buffers of at least 256 bytes use a native, raw incremental CRC matching the Xbox implementation. Validation remains enabled; persistent-storage mismatches report stored and computed values, and incomplete reads are rejected. Uncompressed texture conversion uses fixed-width native routines for supported linear, palettized and swizzled formats, with guest fallback for unsupported layouts. DXT decoding remains native.

Loading status now continues through local player creation, initial update, persistent storage checks, and the first game frame with submitted draw calls and a successful drawable presentation. This is not proof of a visually correct campaign frame. Ten-second diagnostics report native CRC/conversion totals and CPU timings for game-time update, rendering, presentation and GL uploads. Render timing includes conversion/uploads; categories overlap and are not GPU timings.

Device test: compare menu startup and responsiveness, load `a10`, and record the loading stage and first visible campaign frame. Share all logs if the screen stays black. Audio, movies, sticks and triggers remain future work; the M2.6.17 colored Xbox buttons are retained.

## M2.6.19 renderer and muted-audio investigation

M2.6.18 device logs confirm fast native CRC/texture conversion and a campaign frame with 447 submitted draws and successful drawable presentation, while the recording remained black. Menu render CPU times were about 1–2 seconds; campaign rendering took about 3–8 seconds. These observations do not establish the cause of the black output.

M2.6.19 adds overlapping CPU categories for draw setup, texture binding/cache, shader lookup/link, vertex preparation and uniform/state setup. Each timed category also reports pointer upgrades on the rendering thread, excluding background audio-worker faults. Rate-limited scene diagnostics report simulation ticks, cinematic state, camera, viewport, UI fade and final back buffer. No fade or rendering state is forcibly bypassed.

Without an audio output device, PCM/ADPCM packets retain their durations without decoding unused samples. Native silent-clock advancement preserves per-frame floating-point additions and packet boundaries; existing guest status/callback handling remains responsible for completion events. Native clock cost is logged. Actual audio playback remains unimplemented.

Device test: compare menu FPS, load `a10`, allow the campaign test to run, and share the three logs plus a recording. Look for advancing simulation ticks, fade values, camera/back-buffer state and the largest renderer category. This is an optimization and diagnostic update; campaign visibility remains unconfirmed.
