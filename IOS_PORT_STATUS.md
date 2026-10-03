# Halo CE iOS — Port Status

Updated October 2, 2026. Current development milestone: **M2.6.40** (device testing pending).

## Current status

M2.6.37 device logs confirm a healthy running session, successful protocol-10 multiplayer join, audio without underruns, approximately 3.4 ms render CPU time and about two pointer upgrades per render call. The user reports smooth 60 FPS menus. The plasma-pistol first-person model still shows severe distortion.

M2.6.38 adds an active-session `Documents/Halo/game_invite.txt`, expanded campaign tools and numeric movement/FOV controls. It isolates weapon bone interpolation while retaining world/camera smoothing and the working arena rewrite. See [release notes and test checklist](port/ios/UPDATE_M2638.md) and the [current iOS guide](port/ios/README.md). M2.6.38 device feedback confirms continued operation and a PC multiplayer join, but the weapon-pose mitigation did not fix the obstruction. M2.6.39 protects the landscape Settings header and corrects sparse shader constant mapping; see [M2.6.39 release notes](port/ios/UPDATE_M2639.md). Device testing now confirms the header repair, but the shader correction did not resolve the obstruction.

M2.6.39 device evidence confirms approximately 60 FPS, a complete Settings heading and a persistent obstruction while alive that disappears in the death camera. M2.6.40 adds independent first-person mesh visibility, validated bone remapping/pose measurements and document-picker-based iCloud Drive invite export/import. See [current release notes](port/ios/UPDATE_M2640.md). The mesh fault is not yet diagnosed; Hidden is a local workaround.

## Earlier milestones (historical evidence)


Halo's real main menu rendered on a physical iPhone with **M2.6.12**. The test ran for more than ten minutes and showed the Halo background and Campaign, Multiplayer, and Settings. Startup and frame rendering were very slow, and blocks covered portions of the menu text. This was the first menu milestone; later campaign evidence is recorded below.

**M2.6.13 device evidence:** the supplied 65-second recording shows the menu and legible text without the old glyph blocks. Some background frames still have green color artifacts, and terminal messages cover part of the menu. The supplied boot log ended early and appears to represent a different launch, so total startup time cannot be measured reliably from that log.

**M2.6.14 device evidence:** the user confirmed working touch menu controls. The supplied game log reached `starting precaching of map 'a10'` after menu navigation. This confirms a campaign loading attempt, not completed loading or playable gameplay. The remaining color artifacts still require verification.

**M2.6.15 added log improvements:** it removes the cyan presentation marker and its log description, and adds separate Boot log and Game log views with a persistent explanation of skipped Bink videos and muted audio. Important terminal messages remain accessible in `debug.txt` and shared logs.

**M2.6.16 device evidence:** The M2.6.16 device test reached the main menu quickly but still had low frame rates. For `a10`, scripts finished in 16.886 seconds and object placement in 2.330 seconds. Map initialization completed; later heartbeats repeatedly sampled CRC processing for roughly 90 seconds, then texture conversion and drawing. The screen remained black during the user test. `debug.txt` also reports a persistent-storage checksum failure. These logs show continued execution, not confirmed campaign gameplay or a diagnosed rendering failure.

**M2.6.19 device evidence:** the user reports a faster responding menu, the `a10` intro cutscene, successful skipping of the intro and initial gameplay. Logs show cinematic state changing to zero and simulation ticks advancing, with successful presentation and no skipped draws in the sampled renderer report. Gameplay CPU update averages were about 0.8–1.0 s and rendering about 1.9–2.1 s, with hundreds of thousands of pointer upgrades per call. This confirms initial campaign boot, not acceptable performance or complete gameplay controls.

**M2.6.20 launch regression:** the user reports a launch crash. M2.6.21 disables the direct pointer experiment and awaits testing. Original M2.6.20 scope: selective direct pointer conversion, performance defaults and a successful-presentation FPS metric.

## Current capabilities

| Area | Status |
| --- | --- |
| Engine | Real recovered `arm64_32` guest runs inside a native `arm64` iOS host. |
| Graphics | EAGL/OpenGL ES 3 presents real game frames; M2.6.12 reached the main menu. |
| Map loading | `ui.map` and `a10` loaded on the test device; first campaign boot confirmed. |
| Setup | First launch creates `Documents/Halo/maps` and offers map import before engine startup. |
| Diagnostics | Show game / Show log and Share logs are available. |
| Audio | Intentionally muted in the current iOS build. |
| Controls | On-screen menu navigation confirmed by user in M2.6.14. |
| Campaign | `a10` intro and initial gameplay reached with M2.6.19; performance remains very low. |
| Multiplayer | Not yet validated on iOS. |

## Remaining work

- Compare M2.6.20 presentation FPS and update/render CPU times in the menu, intro and initial gameplay.
- Reduce guest/host pointer overhead while preserving collision, visibility and rendering correctness.
- Validate sustained campaign gameplay, add movement/aim controls, and investigate persistent-storage checksum warnings.
- Add and validate audio and networking support. Bink movies are currently skipped.

## Build and installation

Use the **Halo CE iOS — Build IPA** workflow on `main`. Its final artifact is **HaloCE-iOS**, containing **HaloCE.ipa**. The workflow builds the guest on Linux, then builds and packages the device app with Xcode on macOS. The IPA is ad-hoc signed for packaging and must be re-signed by your sideloading tool before installation.

See the [iOS build and setup guide](port/ios/README.md) and [workflow](.github/workflows/ios.yml). iOS uses a separate workflow from the Linux/Windows/Android release builds.

## Milestone history

| Milestone | Progress |
| --- | --- |
| M0 / M0.1 | Physical-device address-space probes showed that the original low-address mappings could not be copied directly from Android. |
| M2.5 | Original-address guest runtime and full engine execution bridge. |
| M2.6–M2.6.7 | Visible OpenGL ES path, renderer configuration, presentation, fixed-function loading vertices, and GL argument bridging. |
| M2.6.8–M2.6.9 | Loading diagnostics, initialized fallback loading texture, native cache decompression, and render-target feedback snapshot. |
| M2.6.10–M2.6.11 | File timestamp and Linux memory-query host support. |
| M2.6.12 | Map setup/import and log sharing; real main menu confirmed on device with severe slowness and text artifacts. |
| M2.6.13 | Native DXT decode, muted playback optimization, and mutable texture refresh; menu with readable text confirmed in recording, intermittent color artifacts remain. |
| M2.6.14 | Hide in-game terminal, isolate final texture bindings, and add menu controls; touch navigation confirmed, `a10` precaching reached. |
| M2.6.15 | Remove cyan test marker; add Boot log / Game log views and clear video/audio limitations notice; device verification pending. |

## M2.6.16 performance and loading diagnostics

Bulk guest memory copies, moves, and fills of at least 256 bytes now use native host routines with guest-span validation. Smaller operations retain the guest implementation. Ten-second heartbeats report native call and byte totals. Compiler-inlined operations are unaffected; speed improvements require device measurement.

Map cache preparation, scenario/assets loading, and major initialization steps report elapsed times in Boot log. A loading label displays the current instrumented stage and elapsed seconds, including when Show game is open. It is stage information, not a percentage or proof that loading has completed. Menu navigation uses a left D-pad with Select and Back on the right. Audio remains muted and Bink movies remain skipped.

Historical test plan: compare menu startup and campaign loading. M2.6.19 subsequently reached the intro and initial gameplay.

## M2.6.17 Xbox touch buttons

A (green), B (red), X (blue), Y (yellow), Black, and White replace Select/Back. A/B/X/Y form a diamond on the right; Black and White flank A. The left D-pad remains. Buttons feed the existing guest controller: A confirms menus, B cancels, and Black/White use the right/left shoulder mappings in the Xbox input adapter. This adds buttons, not a complete gameplay controller; sticks and triggers remain unimplemented.

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

## M2.6.30 arena fast path

Device logs show the remaining cost is signal-handled pointer faults (about 640,000 per render call), not any one renderer loop. M2.6.30 rewrites guest loads/stores at build time so they use an arena base derived from the program counter, with `x15` reserved as scratch, instead of faulting. The signal bridge remains as the fallback. The workflow has an `arena_fastpath` input for A/B builds. No FPS gain is claimed until device-tested. See [the design, safety conditions and test checklist](port/ios/ARENA_FASTPATH_M2630.md).

## M2.6.31 controls and fault hot spots

M2.6.30 device test: boot is near-instant and render CPU fell from about 2,000 ms to 10-200 ms per frame (menu around 30 FPS, a10 tutorial 5-7 FPS). The remaining cost is still pointer faults in code the rewrite skipped. M2.6.31 adds the full Xbox on-screen layout (both sticks, LT/RT, LS/RS, Back/Start, White/Black, D-pad), Xbox/PlayStation/MFi controller support, and a per-function fault hot-spot report in the boot log. See [the details](port/ios/CONTROLS_M2631.md).

## M2.6.32 game first, audio, touch-look, schemes, multiplayer

M2.6.31 device test: render CPU 9-60 ms per frame, remaining pointer faults in malloc/mutex atomics. M2.6.32 covers those atomics,
adds a sampling profiler, shows the game first with a readable four-tab log, adds touch-look, floating sticks, five named control schemes
with a layout editor, real audio (Core Audio) and a working network layer for invite-link multiplayer. See [the details](port/ios/UPDATE_M2632.md).
Untested on a device: touch-look, audio, multiplayer, the settings and log screens.

## M2.6.33 sound, multiplayer, Share logs, frame rate

The host had switched off sound, internet play and 60 FPS in the guest's environment; fixed. System link broadcasts now also go to the
Wi-Fi's directed broadcast address and failures are logged. Share logs presents from the top screen. The busy-wait frame limiter sleeps and the
texture hash is 16x faster. See [the details](port/ios/UPDATE_M2633.md). Untested on a device.

## M2.6.34 Halo CE Universal build 73

The port now builds from build 73's source (network protocol 10, hi-res HUD and text options, upstream's sockets changes), so it can find and join
current PC and Android builds. The audio shortcut that would have left every sound silent is fixed. Profile-guided optimisation is enabled when clang 22
can be installed. See [the details](port/ios/UPDATE_M2634.md). Not compiled or run on a device yet.

## M2.6.35 start-up crash handling

After the build 73 update the app stopped silently while starting the guest. This milestone adds a crash report, start-up step tracking, an automatic safe start
(sound, internet play, smooth 60 FPS, hi-res HUD/text and the profiler off after a failed start) and turns profile-guided optimisation off by default. See
[the notes](port/ios/UPDATE_M2634.md#m2635--start-up-crash-handling). The cause of the stop is not yet known.

## M2.6.36 start-up crash fixed (not yet device-tested)

The crash report from the device pinned the stop to image loading: the loader invalidated the instruction cache across unmapped pages between the image's
segments. The span is now mapped whole and invalidation is per executable segment; the crash handler no longer loops. See
[the notes](port/ios/UPDATE_M2634.md#m2636--the-start-up-crash-found).

## M2.6.37 settings, diagnostics, cheats, frame rate modes

Device test of M2.6.36: smooth 60 FPS and multiplayer work. This milestone adds a category-based Settings screen, a two-tab Diagnostics screen (the Log button is
replaced by Settings > Logs), campaign cheats, frame rate modes (30 / 60 / Uncapped) and the two upstream rendering fixes that most likely explain the warped
first-person plasma pistol. See [the notes](port/ios/UPDATE_M2634.md#m2637--settings-and-diagnostics-redesign-cheats-frame-rate-modes-rendering-fixes).
Not compiled or run on a device yet.
