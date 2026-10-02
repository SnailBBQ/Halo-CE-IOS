# Halo: Combat Evolved for Linux, Windows, Android and iOS

This project is a port of the Halo: Combat Evolved decompilation to Linux,
Windows, Android and an experimental iOS port. The decompilation is of the Xbox build 2342
(`cachebeta.exe`, SHA-256
`4cc87b45f721270392a96f1674ed2b5cd4a7bb4355faeab4531d1cf1884d9520`).

<img width="1289" height="995" alt="The game on Linux" src="https://github.com/user-attachments/assets/0d3ad50f-f8b8-46cf-aef8-e3661da2a7d7" />

The port starts from the decompilation of [bnunu/halo-1](https://github.com/bnunu/halo-1).
That project is a fork of [punpckhdq/halo](https://github.com/punpckhdq/halo).

## iOS development status

**M2.6.33 turns on sound, internet play and Smooth 60 FPS, fixes Share logs and the system link search (see [details](port/ios/UPDATE_M2633.md)).** **M2.6.32 showed the game first, adds audio, touch-look, five named control schemes with a layout editor, invite-link multiplayer sockets and a readable log (see [details](port/ios/UPDATE_M2632.md)).** **M2.6.31 added the full Xbox controller layout, physical controller support and a pointer-fault hot-spot report; the M2.6.30 arena fast path cut render time from about 2 s to 10-200 ms per frame (see [controls](port/ios/CONTROLS_M2631.md) and [fast path](port/ios/ARENA_FASTPATH_M2630.md)).** **M2.6.21 confirmed menu, intro and initial campaign gameplay on the test iPhone.** Menu presentation is generally 6.5–7.3 FPS; tutorial gameplay is around 0.38–0.48 FPS. **M2.6.22 device logs show about 0.38 FPS in tutorial gameplay. M2.6.23 awaits device testing:** it moves vertex-attribute state comparisons and GL setup into the native host. The working pointer bridge is retained and the assembly experiment remains disabled. Audio remains muted; full movement/aim controls and multiplayer are pending.

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

Historical test plan: compare menu startup and campaign loading. M2.6.19 subsequently reached the intro and initial gameplay.

## M2.6.18 performance test bundle

CRC buffers of at least 256 bytes use a native, raw incremental CRC matching the Xbox implementation. Validation remains enabled; persistent-storage mismatches report stored and computed values, and incomplete reads are rejected. Uncompressed texture conversion uses fixed-width native routines for supported linear, palettized and swizzled formats, with guest fallback for unsupported layouts. DXT decoding remains native.

Loading status now continues through local player creation, initial update, persistent storage checks, and the first game frame with submitted draw calls and a successful drawable presentation. This is not proof of a visually correct campaign frame. Ten-second diagnostics report native CRC/conversion totals and CPU timings for game-time update, rendering, presentation and GL uploads. Render timing includes conversion/uploads; categories overlap and are not GPU timings.

Device test: compare menu startup and responsiveness, load `a10`, and record the loading stage and first visible campaign frame. Share all logs if the screen stays black. Audio, movies, sticks and triggers remain future work; the M2.6.17 colored Xbox buttons are retained.

## M2.6.19 renderer and muted-audio investigation

M2.6.18 device logs confirm fast native CRC/texture conversion and a campaign frame with 447 submitted draws and successful drawable presentation, while the recording remained black. Menu render CPU times were about 1–2 seconds; campaign rendering took about 3–8 seconds. These observations do not establish the cause of the black output.

M2.6.19 adds overlapping CPU categories for draw setup, texture binding/cache, shader lookup/link, vertex preparation and uniform/state setup. Each timed category also reports pointer upgrades on the rendering thread, excluding background audio-worker faults. Rate-limited scene diagnostics report simulation ticks, cinematic state, camera, viewport, UI fade and final back buffer. No fade or rendering state is forcibly bypassed.

Without an audio output device, PCM/ADPCM packets retain their durations without decoding unused samples. Native silent-clock advancement preserves per-frame floating-point additions and packet boundaries; existing guest status/callback handling remains responsible for completion events. Native clock cost is logged. Actual audio playback remains unimplemented.

Device test: compare menu FPS, load `a10`, allow the campaign test to run, and share the three logs plus a recording. Look for advancing simulation ticks, fade values, camera/back-buffer state and the largest renderer category. The subsequent M2.6.19 device test confirmed the intro and initial gameplay; performance remains poor.

## M2.6.20 campaign performance trial

M2.6.19 reached the `a10` intro and initial gameplay on the test iPhone. M2.6.20 adds an iOS-only assembly pass for four measured hot objects: `d3d8_gl`, `collision_bsp`, `structure_visibility` and `structure_render`. Before ordinary loads/stores through a nonzero 32-bit base, it adds the host arena base directly instead of waiting for a PAGEZERO fault. Wide pointers, null pointers, registers, flags, stack alignment and the Darwin leaf red zone are preserved. Atomic exclusive-access objects fail closed; indirect branches and uninstrumented code retain the signal bridge. The host initializes the shared arena value before guest execution. Android uses the original converter invocation.

The performance defaults stop forcing per-draw GL error polling and stop forcing frame-zero draw tracing. Interpolation stays off and graphics fidelity is retained. To investigate GL errors, set `gl_debug = true` in the `[debug]` table of `Documents/Halo/config.toml`; set `gpu_trace_frame` to a frame number only for a diagnostic run. These diagnostics add overhead. Muted-audio decoding was already removed in M2.6.19; the latest native silent-clock timings are small, so timing and completion behavior are retained.

Boot logs now report successful drawable presentations per measured wall-clock interval, independent of loading-stage durations. Update/render/draw/vertex timing categories overlap and must not be added together. Direct conversions are not counted as signal pointer upgrades; compare FPS and CPU time as well as residual fault counts.

Validation: 1,540 assembled ARM64 emulation cases compare the fast path with the existing pointer-upgrade behavior, including wide/null bases, register overlap, writeback, memory stores, NZCV and red-zone preservation. The emulation test is retained in `tools/tests/test_ios_pointer_fastpath.py` and runs in the iOS workflow. Apple compilation and real performance gains require CI and a device test. Test the same menu, `a10` intro, skip and initial gameplay, then share the logs; verify geometry, text and progression alongside FPS. The white cryotube wake-up effect is left intact.

## M2.6.21 launch recovery

The user reports that the M2.6.20 IPA crashes on launch. The exact cause has not been established from a crash report. M2.6.21 disables the experimental assembly pointer pass in the shipping workflow and removes its shared arena variable and host initialization, restoring the original signal-based pointer bridge used by the working M2.6.19 campaign test. The experimental converter and its emulation tests remain available for investigation but are not applied to the shipped guest.

Successful-presentation FPS reporting and the reduced forced debugging defaults are retained. This recovery build requires a device test: first verify startup, then the menu and `a10` intro/gameplay. No performance improvement is claimed from the disabled experiment.

## M2.6.22 native vertex-color trial

The M2.6.21 device test restored campaign boot. Menu presentation was generally 6.5–7.3 FPS; tutorial gameplay was about 0.38–0.48 FPS. Rendering averaged roughly 1.8–2.1 seconds while presentation took only milliseconds.

M2.6.22 moves the existing streamed-vertex BGRA-to-RGBA copy/conversion loop into a bounded native helper. It validates every color offset before writing, preserves duplicate-offset ordering and partial trailing vertices, and retains the original conversion on unsupported input. Texture cache invalidation, geometry, collision and the working signal bridge are unchanged. The assembly pointer experiment stays disabled.

New overlapping timing categories isolate vertex-color conversion/upload, index bounds/cache and texture lookup/upload. Native conversion call, byte, time and fallback totals show how often the helper is used. This is a narrow optimization candidate, not a claim that it accounts for the full rendering delay. Device testing must compare menu, intro and tutorial frame times and verify colors and progression.

## M2.6.23 native vertex-state trial

M2.6.22 device logs show roughly 0.38 FPS in tutorial gameplay, about two seconds of CPU rendering per frame and about 640,000 pointer upgrades per rendering call. Native color conversion took only 0.5 ms across 1,228 calls: it works, but does not materially resolve overall performance.

M2.6.23 moves vertex-attribute descriptor comparisons, enable/disable state and GL setup into the native host. Every renderer cache invalidation also invalidates the native cache. Buffer-binding side effects are returned to the guest, and constant attribute values are copied from validated guest memory. This is a default iOS optimization; resolution stays 640×480 and the working execution bridge remains enabled. Other platforms keep their existing path.

The workflow checks cache transitions, each descriptor field, buffer side effects, invalidation and bounds. Apple compilation and device performance still need verification. Compare presentation FPS, vertex-preparation time/upgrades and render time/upgrades in the same menu and tutorial scenes; a passing build alone does not establish improved performance. The full static pointer-rewrite experiment remains disabled. See the [performance migration review](port/ios/PERFORMANCE_PLAN.md).

## M2.6.24 native renderer scans

Index bounds, shader/texture cache searches and uniform comparisons now run in bounded native helpers. No native cache or static pointer rewrite is introduced; the working signal bridge, page protection behavior and resolution remain unchanged. New scene categories cover visibility, objects, structure passes, particles, lights and UI. Device correctness and performance remain to be tested; no FPS gain is claimed yet. See the [implementation, exact functions, rebuild checklist and log acceptance criteria](port/ios/RENDER_PERFORMANCE_M2624.md).

## M2.6.25 native scene traversal

The M2.6.24 device test confirms working native renderer helpers and better menu performance, but very slow a10 gameplay. M2.6.25 adds bounded native datum lookup/iteration, BSP surface sorting/triangle gathering/material runs and visibility marking/reference scans. Object callbacks and portal recursion retain their existing guest behavior. No new native cache or pointer rewrite is introduced. See the [exact loops, safety properties, tests and device checklist](port/ios/SCENE_PERFORMANCE_M2625.md).

## M2.6.29 object filtering and performance measurements

The current test build preserves shared object lists, invisible parents and widgets, and safely skips only shadowless objects on shadow passes. New timings separate object lighting, model/widget traversal and simulation updates. Static pointer rewriting remains disabled. See the [correctness changes and device comparison checklist](port/ios/PERFORMANCE_M2629.md).
