# Halo CE iOS

Experimental Halo: Combat Evolved port for physical iPhone and iPad devices running iOS/iPadOS 15 or later. A native `arm64` app hosts the recovered `arm64_32` engine and presents graphics through EAGL/OpenGL ES 3.

**Current version: M2.6.41**, awaiting device validation. M2.6.41 corrects stale iOS vertex/index GPU mirror data by refreshing requested ranges before drawing. M2.6.40 testing shows a correct campaign assault rifle alongside corrupted world geometry and persistent multiplayer distortion. Device validation is needed for the visual fix and upload-cost impact; the separate guest_glUniform4fv execution fault remains under investigation. See [release notes](UPDATE_M2641.md).

## Current multiplayer and campaign tools

Settings → Multiplayer accepts a supported `halo://join/` invite or its bare 64-digit token. Compatible peers use protocol 10. Choose **Choose iCloud Drive folder** to move game_invite.txt into a remembered folder, then use **Join from game_invite.txt** to read a PC invite after sync. Until a folder is chosen, Documents/Halo is the fallback. Hosting publishes its current code; stopping or launch cleanup clears only the code this app wrote, preserving a different incoming PC code. No invite history is kept; abrupt termination/provider delays can defer cleanup until next launch/sync.

Settings → Cheats contains god mode, infinite ammo/grenades, bottomless clip, loaded-map weapon and vehicle pickups, overshield/invisibility, hostile-unit one-hit kills, unlimited flashlight, no fall damage, rapid fire, no recoil, noclip and third person. Jump (1–10), local-player speed (1–5) and vertical FOV (0 = default; 20–90 degrees) have sliders and numeric entry. All gameplay tools are campaign-only; unavailable map assets report a message. See the release notes for exact behavior and validation limits.

The M2.6.38 weapon test uses authoritative first-person weapon poses while keeping world/camera smoothing. Device testing confirmed the obstruction persists. M2.6.39 corrects shader constant reflection/upload for sparse locations and fixes the landscape Settings header. M2.6.39 device testing still shows the obstruction. M2.6.40 adds Both / Weapon / Hands / Hidden under Display and bounded pose diagnostics, not a confirmed complete model repair.

## Build with GitHub Actions

This is the supported packaging route, including when working from Windows. No local Mac is required.

1. Push your changes to the repository.
2. Open **Actions → Halo CE iOS — Build IPA**.
3. Select **Run workflow**, choose `main` (or your development branch), and start a new run.
4. Wait for **Build Halo engine guest** and **Build and package iOS app** to finish successfully.
5. Download the **HaloCE-iOS** artifact and extract its ZIP. It contains **HaloCE.ipa**.
6. Re-sign and install `HaloCE.ipa` with your sideloading tool, such as Sideloadly, using your own signing setup.
7. Launch **Halo CE** on the physical device.

Re-running an old workflow uses its original commit. Start a new run on the branch to test newer changes. The intermediate **HaloCE-iOS-Guest** artifact contains the engine ELF, not an installable app. The final IPA artifact is retained for 14 days; the intermediate guest artifact for one day.

The [workflow](../../.github/workflows/ios.yml) performs two builds:

- Ubuntu configures the shared guest build with `python3 configure.py --pgo=off`, applies `HALO_IOS_GUEST=1` and the iOS GL stubs, and runs `ninja build/android/halo_guest.elf`.
- macOS builds `port/ios/HaloIOS.xcodeproj` with the `HaloIOS` scheme for `iphoneos`, bundles `halo_guest.elf`, ad-hoc signs the app, and packages `HaloCE.ipa`.

The guest's `build/android` directory is shared build infrastructure; the resulting IPA uses the iOS host. There is currently no `ninja ios` target. The separate **Build** workflow packages Linux, Windows, and Android releases; it does not produce an IPA.

## Maps and first launch

Game assets are not included. Supply Xbox Halo: Combat Evolved `.map` files from your own game data. PC Halo CE maps are not the format this engine expects.

The app creates **Documents/Halo/maps** on its first launch, before starting the engine. iOS does not run the app during installation, so this folder cannot be created by app code at install time.

1. Open Halo CE once to create its folders.
2. Use **Import maps** to select `.map` files from Files, or copy them into **Files → On My iPhone/iPad → Halo CE → Halo → maps**.
3. Include `ui.map` for the main menu, plus the maps needed for any levels you intend to test.
4. Tap **Start Halo** when setup reports that `ui.map` is ready. On later launches, an existing `ui.map` allows automatic engine startup.

Import supports multiple files and keeps existing maps instead of replacing them. Files are copied into a temporary location before being published into the maps folder. Setup checks the presence and minimum size of `ui.map`; the engine performs the actual cache validation.

## Controls and settings

On-screen Xbox controls include the D-pad, both sticks, LT/RT, A/B/X/Y in their respective colors, Black/White, Back/Start and stick presses. Settings → Controls provides five named presets, placement/size editing, touch-look, sensitivity and floating-stick options. Physical GameController devices are supported; Auto hides touch controls while a controller is connected, with Always/Hidden overrides. A confirms menus; B returns/cancels. Opening native screens or leaving the app resets held touch input.

Settings has Multiplayer, Controls, Display, Audio, Cheats and Advanced categories, plus a pinned Logs entry. Display selects 30 / smooth 60 / uncapped presentation. Hi-res HUD/text options and some timing mode changes apply at launch. A safe start following a failed launch temporarily disables sound, internet play, smoothing and optional assets/profiling; a healthy run clears it.

## Testing and logs

Settings → Logs opens Diagnostics Summary and Problems. Share logs exports available files from `Documents/Halo`, including boot/game/game-state and launch reports. Terminal output remains available in the logs without covering the game. Audio is supported through the native audio engine; Bink movie files are still unsupported and skipped. Engine-rendered campaign cinematics are separate from Bink movies.

For a report, include the milestone, workflow commit, all logs, the map/weapon/action involved, and a screenshot or recording. Local checks do not establish device correctness. For M2.6.40, compare Both / Weapon / Hands / Hidden while alive and after respawn, then test iCloud host-code cleanup and PC-invite preservation across app launches.

## Build the host locally on macOS

Install Xcode with the iOS SDK and clone this repository. Obtain `halo_guest.elf` from **HaloCE-iOS-Guest** for the same commit as your checkout, and extract it to `build/guest/halo_guest.elf`. Building only the host without bundling the matching guest is insufficient.

From the repository root, build the device host:

```sh
xcodebuild \
  -project port/ios/HaloIOS.xcodeproj \
  -scheme HaloIOS \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$PWD/build/ios/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build
```

Then bundle the guest and package the IPA:

```sh
APP="$PWD/build/ios/DerivedData/Build/Products/Release-iphoneos/HaloIOS.app"
test -s build/guest/halo_guest.elf
cp build/guest/halo_guest.elf "$APP/halo_guest.elf"
codesign --force --sign - --entitlements port/ios/HaloIOS/HaloIOS.entitlements --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"
mkdir -p build/ios/package
PACKAGE=$(mktemp -d "$PWD/build/ios/package/ipa.XXXXXX")
mkdir "$PACKAGE/Payload"
cp -R "$APP" "$PACKAGE/Payload/"
(cd "$PACKAGE" && zip -qry HaloCE.ipa Payload)
cp "$PACKAGE/HaloCE.ipa" build/ios/HaloCE.ipa
```

Re-sign `build/ios/HaloCE.ipa` with your sideloading tool to install it. The internal target, executable, and app bundle remain `HaloIOS`; the device display name is **Halo CE**. The existing bundle identifier is retained to preserve upgrade continuity. Validate on a physical device: an iOS Simulator build does not validate this guest execution path.

## Historical development notes

The sections below describe earlier milestones and their then-current limitations. Use the current guide and release notes above for M2.6.40.

## M2.6.16 performance and loading diagnostics

Bulk guest memory copies, moves, and fills of at least 256 bytes now use native host routines with guest-span validation. Smaller operations retain the guest implementation. Ten-second heartbeats report native call and byte totals. Compiler-inlined operations are unaffected; speed improvements require device measurement.

Map cache preparation, scenario/assets loading, and major initialization steps report elapsed times in Boot log. A loading label displays the current instrumented stage and elapsed seconds, including when Show game is open. It is stage information, not a percentage or proof that loading has completed. Menu navigation uses a left D-pad with Select and Back on the right. Audio remains muted and Bink movies remain skipped.

Historical test plan: compare menu startup and campaign loading. M2.6.19 subsequently reached the intro and initial gameplay.

## Latest device evidence

The M2.6.16 device test reached the main menu quickly but still had low frame rates. For `a10`, scripts finished in 16.886 seconds and object placement in 2.330 seconds. Map initialization completed; later heartbeats repeatedly sampled CRC processing for roughly 90 seconds, then texture conversion and drawing. The screen remained black during the user test. `debug.txt` also reports a persistent-storage checksum failure. These logs show continued execution, not confirmed campaign gameplay or a diagnosed rendering failure.

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

The workflow checks cache transitions, each descriptor field, buffer side effects, invalidation and bounds. Apple compilation and device performance still need verification. Compare presentation FPS, vertex-preparation time/upgrades and render time/upgrades in the same menu and tutorial scenes; a passing build alone does not establish improved performance. The full static pointer-rewrite experiment remains disabled. See the [performance migration review](PERFORMANCE_PLAN.md).

## M2.6.24 native renderer scans

Index bounds, shader/texture cache searches and uniform comparisons now run in bounded native helpers. No native cache or static pointer rewrite is introduced; the working signal bridge, page protection behavior and resolution remain unchanged. New scene categories cover visibility, objects, structure passes, particles, lights and UI. Device correctness and performance remain to be tested; no FPS gain is claimed yet. See the [implementation, exact functions, rebuild checklist and log acceptance criteria](RENDER_PERFORMANCE_M2624.md).

## M2.6.25 native scene traversal

The M2.6.24 device test confirms working native renderer helpers and better menu performance, but very slow a10 gameplay. M2.6.25 adds bounded native datum lookup/iteration, BSP surface sorting/triangle gathering/material runs and visibility marking/reference scans. Object callbacks and portal recursion retain their existing guest behavior. No new native cache or pointer rewrite is introduced. See the [exact loops, safety properties, tests and device checklist](SCENE_PERFORMANCE_M2625.md).

## M2.6.29 object filtering and performance measurements

The current test build preserves shared object lists, invisible parents and widgets, and safely skips only shadowless objects on shadow passes. New timings separate object lighting, model/widget traversal and simulation updates. Static pointer rewriting remains disabled. See the [correctness changes and device comparison checklist](PERFORMANCE_M2629.md).

## Invite file in iCloud Drive (M2.6.40)

Choose Settings > Multiplayer > Choose iCloud Drive folder, then select a folder in iCloud Drive. The app remembers access and publishes the current hosted invite into game_invite.txt there. Once selected, the export moves out of Documents/Halo. Paste a supported PC invite into the same file, wait for iCloud sync, and press Join from game_invite.txt on the phone. Host-stop and launch cleanup preserve a different incoming PC code. If permission expires, choose the folder again. See the current release notes for offline-sync and revoked-access limitations.

## M2.6.41 geometry correction

Device testing found campaign world corruption as well as multiplayer mesh distortion. The iOS GPU geometry mirror incorrectly treated no-op write-tracking generations as unchanged data. Requested ranges now refresh before every draw, including same-frame writes and reused map addresses. This may increase upload cost; FPS and visual correctness need device validation. The guest_glUniform4fv execution fault remains under investigation. See [release notes](UPDATE_M2641.md). Swipe-away terminates the app through iOS; final callbacks and iCloud cleanup are best-effort, with existing next-launch cleanup retained.
