# M2.6.118 — OpenCE build 244 integration

This source update advances the iOS port from OpenCE build 235 to the exact upstream build 244 commit `6ec42856d73e258e5a8c7e9cd19161f46d89d0e4`. The upstream network protocol is now version 32 (was 29). A build 244 / network 32 client cannot join or host games with build 235 / network 29 clients; all peers must use a compatible network-32 build.

The integration brings in upstream changes across gameplay, networking, map handling, rendering and the Linux platform layer, including its Custom Edition and multiplayer updates. iOS-specific camera, HUD, renderer, audio, invite, network-status and SDL hooks were carried forward. `HALO_IOS_GUEST` remains guarded so the corresponding source with the iOS feature disabled is identical to build 244. The existing map-aware weapon and vehicle pickers remain in place.

## Build identity

- Source milestone: **M2.6.118**
- App version/build: **0.2.118 / 2718** (Mod Test: **0.2.118.1**)
- OpenCE: **build 244**, commit `6ec42856d73e258e5a8c7e9cd19161f46d89d0e4`
- Network protocol: **32**
- iOS workflow: still manually triggered; this source update does not build or publish an IPA.

## Checks and device validation

The strict upstream acceptance check verifies build identity, all 53 iOS guest guard structures, map-load recovery, host imports, guest ABI and exact upstream equivalence with `HALO_IOS_GUEST` off. Repository workflow configuration checks and Python tests should also pass in CI. A Mac/iOS build and on-device run have not been performed for this source update.

After building an IPA manually, validate the Regular app first, then Mod Test and Non-Jailbreak separately. Check startup, campaign and splitscreen, base and Custom Edition maps, map-load recovery, weapon/vehicle pickers, HUD options, audio, controller/touch input and multiplayer with another network-32 client. Confirm the saved-game backup/restore flow. Record the device model, iOS version, app flavor, map and logs for any failure.
