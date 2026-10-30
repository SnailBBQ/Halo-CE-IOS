# M2.6.123 — OpenCE build 335

This source update integrates [OpenCE build 335](https://github.com/OpenCommunityEdition/OpenCE/releases/tag/build-335), commit `da8d455623cf50002e6a798b1980068fd3ca0292`, over the iOS build-268 baseline. The regular app identity is **0.2.123 / 2723** and Mod Test is **0.2.123.1**. OpenCE's network protocol rises from **38 to 41**; older network-38 builds cannot join network-41 games.

The upstream jump touches renderer, controller, HUD, bots, multiplayer and server-browser code and adds dedicated-server sources. The dedicated server is an upstream component, not a new iOS app flavor. The iOS guest gains host interfaces for external URLs and bounded HTTPS server-list requests. Android's native text keyboard and touch overlay remain idle on iOS, which uses its own controls. The iOS guest retains its existing geometry mirror and Custom Edition texture path under `HALO_IOS_GUEST` guards.

The three-way integration used the build-268 OpenCE tree as its base. Six overlapping source files required manual resolution: chat, controller routing, cache cleanup, rendering, the GL renderer and checkpoint saving. The build-335 upstream view with iOS guards disabled matches the candidate OpenCE tree exactly. No changes were made to the separate Windows, Linux or Android apps beyond taking the new upstream source.

## Validation and device checklist

The strict upstream acceptance, source guard structure, host-import coverage, workflow checks, build identity and map-load recovery checks must pass before this update is applied. The iOS guest and native app still require GitHub Actions compilation on Ubuntu and macOS, followed by a device run. No IPA or device result is claimed from this source preparation. The IPA workflow is manual (`workflow_dispatch`), so pushing or merging this update does not start a Mac IPA build.

After CI passes, manually build the regular IPA first. Check boot, a stock campaign map, save/reload, a Custom Edition map, mods, on-screen and controller input, chat with the iOS keyboard, and renderer stability. With matching network-41 peers, check server discovery, join/host, player/team chat and a full round. Check external links and the server browser's HTTPS path. Then build and test Mod Test and Non-Jailbreak separately if needed; note the phone model, iOS version, app flavor and logs. Old saves are protected by the engine-identity backup process before this new engine starts.
