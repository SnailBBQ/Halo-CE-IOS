# Halo CE iOS — Port Status

Updated September 30, 2026. Current development milestone: **M2.6.13**.

Halo's real main menu rendered on a physical iPhone with **M2.6.12**. The test ran for more than ten minutes and showed the Halo background and Campaign, Multiplayer, and Settings. Startup and frame rendering were very slow, and blocks covered portions of the menu text. This confirms engine execution and menu rendering; playable campaign and multiplayer are not yet confirmed.

**M2.6.13 is awaiting device testing.** It adds native DXT texture decoding, skips PCM mixing during muted playback while preserving packet timing, and checks uncompressed texture contents to refresh the font atlas. Local decoder and playback comparisons passed. The speed improvement and visual correction still need a phone test.

## Current capabilities

| Area | Status |
| --- | --- |
| Engine | Real recovered `arm64_32` guest runs inside a native `arm64` iOS host. |
| Graphics | EAGL/OpenGL ES 3 presents real game frames; M2.6.12 reached the main menu. |
| Map loading | Native cache decompression completed for `ui.map` on the test device. |
| Setup | First launch creates `Documents/Halo/maps` and offers map import before engine startup. |
| Diagnostics | Show game / Show log and Share logs are available. |
| Audio | Intentionally muted in the current iOS build. |
| Controls, campaign, multiplayer | Not yet validated on iOS. |

## Remaining work

- Test M2.6.13 startup time and menu rendering on the device.
- Investigate remaining rendering artifacts and guest/host bridge overhead.
- Validate menu input and campaign loading before claiming playable gameplay.
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
| M2.6.13 | Native DXT decode, muted playback optimization, and mutable texture refresh; device verification pending. |
