# M2.6.39 — landscape Settings and shader constants

Updated October 2, 2026. Halo CE Universal build 73 / network protocol 10.

## Device evidence

The user reports M2.6.38 working and supplied a multiplayer screenshot with the PC player xSkullHD 2 joined. The first-person obstruction persists after disabling additional weapon bone interpolation; that mitigation did not repair it. The screenshot cannot distinguish malformed weapon/hands geometry from an obstructing world object. The Settings heading and dismissal button are clipped in landscape.

## Changes

- Settings has a fixed safe-area header. Categories scroll when the available landscape height is too small, keeping their touch targets and Logs accessible. Content no longer compresses the heading or moves Back to game above the screen.
- iOS shader constant reflection scans all 192 registers. It no longer treats an inactive slot as the end of the array or assumes that irregular locations can be uploaded as a single full array. Sparse programs upload each active dirty register to its reflected location; consecutive programs retain the existing range upload. Locations are owned by each linked program, so existing program disposal/invalidation drops them.
- A bounded shader-link diagnostic reports sparse maps (at most eight messages per process). Reflection happens only at link, with no GPU readback or added per-frame address validation.

The shader change fixes a demonstrable state-handling bug and is a candidate for the stretched viewmodel, **not a device-confirmed visual repair**. No resolution, simulation, audio, networking, signal bridge, arena rewrite or invite behavior changes. The M2.6.38 authoritative weapon pose remains enabled.

## Build and test

Build the Halo CE iOS workflow on main; download HaloCE-iOS and install HaloCE.ipa. Version 0.2.39 / build 2639 keeps the existing bundle ID and Documents/Halo data.

1. Open Settings in landscape. Confirm the entire heading and Back to game button are visible and scroll the categories to Logs.
2. Host multiplayer, join from PC and test the plasma pistol, charged fire, weapon switching, zoom and respawn; also compare pistol and assault rifle.
3. Test a10 and verify world, HUD and weapon rendering and frame rate. Save fresh ios-boot.log, debug.txt and gamestate.txt plus a screenshot if obstruction remains. Sparse-location messages indicate the corrected fallback ran; their absence is normal for consecutive arrays and does not prove the obstruction fixed.

Local regression tests cover inactive holes before bone registers, nonconsecutive locations, inactive c[0], highest register, changed subranges and the consecutive fast path. CI compiles the real arm64_32 guest and Apple host. Only a device test can establish visual correctness.
