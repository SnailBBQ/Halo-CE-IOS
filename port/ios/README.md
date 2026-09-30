# Halo CE Universal - iOS M0

M0 is a physical-device feasibility test. It does **not** run Halo yet and does not modify the existing Windows, Linux, or Android ports.

## What M0 proves

The Android port's ILP32 guest requires fixed low-4GB ranges. The important existing constants are:

- Xbox contiguous window: `0x80000000` through `0x87ffffff` (128 MiB)
- Android guest image starts at `0x88000000`

M0 runs as a native arm64 iOS app and attempts to reserve those ranges. The result is shown on screen.

## Windows + GitHub Actions + Sideloadly workflow

No local Mac or Xcode installation is required for this test. GitHub Actions supplies the macOS/Xcode build machine; Sideloadly signs the resulting unsigned IPA with your own Apple account when you install it.

1. Create a GitHub repository and upload/push this source tree.
2. Open the repository's **Actions** tab.
3. Select **iOS M0 IPA** and choose **Run workflow**.
4. When the job completes, download the artifact named `HaloCEUniversal-iOS-M0-Sideloadly`.
5. Extract the downloaded artifact ZIP. It contains `HaloCEUniversal-iOS-M0-unsigned.ipa`.
6. On Windows, open Sideloadly and select that IPA.
7. Connect the physical iPhone/iPad, select it in Sideloadly, and sideload the IPA using your own Apple account/signing setup.
8. If iOS asks you to trust/enable the development app, follow the device prompt/settings required by your signing method.
9. Launch **Halo M0** and record or screenshot the result.

Do not use an iOS Simulator result for the feasibility decision. We need the address-space behavior of a physical device.

## Expected result

A successful device should show two `PASS mapped` lines and:

`M0 RESULT: PASS - required fixed ranges can be reserved on this device/OS.`

If either fixed mapping fails, keep the exact error shown. That tells us the Android address-space strategy cannot be copied unchanged.

## Safety of the probe

The branch maps the test ranges with `PROT_NONE`, does not load Halo data, and immediately unmaps each successful reservation. It contains no Halo game assets.

## Local Mac build (optional)

The Xcode project is retained for contributors who do have a Mac. Open `HaloIOS.xcodeproj`, configure a development team, select a physical device, and run it normally.

## Next milestone after PASS

M0.1 will generalize the Android guest ABI naming, add the iOS host loader, and compile a tiny ILP32 guest image that crosses the host/guest boundary. Only after that succeeds should the Halo guest itself be integrated.
