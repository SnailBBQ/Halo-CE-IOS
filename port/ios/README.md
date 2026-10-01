# Halo CE iOS

Experimental Halo: Combat Evolved port for physical iPhone and iPad devices running iOS/iPadOS 15 or later. A native `arm64` app hosts the recovered `arm64_32` engine and presents graphics through EAGL/OpenGL ES 3.

**Current version: M2.6.18, awaiting device testing.** The real main menu and readable text are confirmed. M2.6.14 touch controls worked and the latest game log reached precaching of the first campaign map, `a10`; completed campaign loading and gameplay remain unconfirmed. M2.6.18 adds native CRC and texel conversion plus loading status through the first frame presentation. The colored Xbox buttons are retained. See [port status](../../IOS_PORT_STATUS.md).

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

## Menu controls

M2.6.17 uses a left D-pad and a right-side **A (green), B (red), X (blue), Y (yellow), Black, and White** cluster. A/B/X/Y form a diamond; Black and White flank A. A confirms menus and B returns/cancels. Black and White map to the Xbox adapter's right and left shoulder inputs respectively. All buttons feed the guest's first controller slot. Quick taps remain pending until polled; showing the log or leaving the app clears held/pending inputs.

These controls are for menu testing. Full gameplay controls and physical controller support are not implemented by this change. Test moving the highlight, opening Campaign with A, and returning with B before attempting a level.

## Testing and logs

Use **Show game** to inspect the rendered surface and **Show log** to inspect diagnostics. Switch between **Boot log** (host/guest startup and renderer output) and **Game log** (the latest 64 KiB of `debug.txt`). The in-game terminal overlay is hidden, but its messages remain in the game log. A notice explains that Bink movies are skipped and audio is muted. Game log refreshes when opened/selected and when new boot diagnostics arrive while it is visible. **Share logs** exports the existing `ios-boot.log`, `debug.txt`, and `gamestate.txt` files from `Documents/Halo`.

For a report, include the displayed milestone, the workflow commit, how long the app ran, all available logs, and a screenshot or recording. M2.6.12 needed an extended test to reveal the menu. The neutral loading image alone does not confirm a rendered game menu. Audio is currently muted and Bink movies are skipped.

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

## M2.6.16 performance and loading diagnostics

Bulk guest memory copies, moves, and fills of at least 256 bytes now use native host routines with guest-span validation. Smaller operations retain the guest implementation. Ten-second heartbeats report native call and byte totals. Compiler-inlined operations are unaffected; speed improvements require device measurement.

Map cache preparation, scenario/assets loading, and major initialization steps report elapsed times in Boot log. A loading label displays the current instrumented stage and elapsed seconds, including when Show game is open. It is stage information, not a percentage or proof that loading has completed. Menu navigation uses a left D-pad with Select and Back on the right. Audio remains muted and Bink movies remain skipped.

Awaiting device testing: compare menu startup time and try `a10`. If loading appears stalled, share logs while the loading stage is still visible. Campaign gameplay remains unconfirmed.

## Latest device evidence

The M2.6.16 device test reached the main menu quickly but still had low frame rates. For `a10`, scripts finished in 16.886 seconds and object placement in 2.330 seconds. Map initialization completed; later heartbeats repeatedly sampled CRC processing for roughly 90 seconds, then texture conversion and drawing. The screen remained black during the user test. `debug.txt` also reports a persistent-storage checksum failure. These logs show continued execution, not confirmed campaign gameplay or a diagnosed rendering failure.

## M2.6.18 performance test bundle

CRC buffers of at least 256 bytes use a native, raw incremental CRC matching the Xbox implementation. Validation remains enabled; persistent-storage mismatches report stored and computed values, and incomplete reads are rejected. Uncompressed texture conversion uses fixed-width native routines for supported linear, palettized and swizzled formats, with guest fallback for unsupported layouts. DXT decoding remains native.

Loading status now continues through local player creation, initial update, persistent storage checks, and the first game frame with submitted draw calls and a successful drawable presentation. This is not proof of a visually correct campaign frame. Ten-second diagnostics report native CRC/conversion totals and CPU timings for game-time update, rendering, presentation and GL uploads. Render timing includes conversion/uploads; categories overlap and are not GPU timings.

Device test: compare menu startup and responsiveness, load `a10`, and record the loading stage and first visible campaign frame. Share all logs if the screen stays black. Audio, movies, sticks and triggers remain future work; the M2.6.17 colored Xbox buttons are retained.
