# Halo CE iOS — Port Status

Updated September 30, 2026. Current development milestone: **M2.6.14**.

Halo's real main menu rendered on a physical iPhone with **M2.6.12**. The test ran for more than ten minutes and showed the Halo background and Campaign, Multiplayer, and Settings. Startup and frame rendering were very slow, and blocks covered portions of the menu text. This confirms engine execution and menu rendering; playable campaign and multiplayer are not yet confirmed.

**M2.6.13 device evidence:** the supplied 65-second recording shows the menu and legible text without the old glyph blocks. Some background frames still have green color artifacts, and terminal messages cover part of the menu. The supplied boot log ended early and appears to represent a different launch, so total startup time cannot be measured reliably from that log.

**M2.6.14 is awaiting device testing.** It hides the in-game terminal output while retaining logs, finishes texture uploads before binding all stages for a draw, and adds an on-screen menu pad. Local mocked GL binding and input checks passed; visual correctness and actual menu navigation still need a phone test.

## Current capabilities

| Area | Status |
| --- | --- |
| Engine | Real recovered `arm64_32` guest runs inside a native `arm64` iOS host. |
| Graphics | EAGL/OpenGL ES 3 presents real game frames; M2.6.12 reached the main menu. |
| Map loading | Native cache decompression completed for `ui.map` on the test device. |
| Setup | First launch creates `Documents/Halo/maps` and offers map import before engine startup. |
| Diagnostics | Show game / Show log and Share logs are available. |
| Audio | Intentionally muted in the current iOS build. |
| Controls | On-screen menu pad added in M2.6.14; device verification pending. |
| Campaign, multiplayer | Not yet validated on iOS. |

## Remaining work

- Test M2.6.14 startup time, menu input, and menu rendering on the device.
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
| M2.6.13 | Native DXT decode, muted playback optimization, and mutable texture refresh; menu with readable text confirmed in recording, intermittent color artifacts remain. |
| M2.6.14 | Hide in-game terminal, isolate final texture bindings, and add menu controls; device verification pending. |
