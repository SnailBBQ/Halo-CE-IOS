# M2.6.122 - OpenCE build 268

This source update integrates [OpenCE build 268](https://github.com/OpenCommunityEdition/OpenCE/releases/tag/build-268), commit `5e27f3a27b2d3c27d3edeb450fe40c24defb9c15`, over build 266. The regular app is **0.2.122 / 2722** and Mod Test is **0.2.122.1**. The iOS guest still uses its guarded OpenCE engine adaptations.

The network protocol rises from **36 to 38**. Build-266/network-36 clients cannot join build-268/network-38 games. Build 268 adds each OpenCE gametype's mode and Hardcore flag to LAN advertisements and public lobby listings so the server browser can name them. It also adds `players` to the host's shield-effects choices, letting each machine use its own shield display settings instead of a synchronized effect. These changes affect multiplayer compatibility and need a network-38 device test.

The upstream delta changes 24 files. Two overlap iOS-adapted files (`menu_functions.c` and `port_config.c`); their iOS behavior was preserved while the build-268 changes were merged. The package also includes the DXT1-to-ASTC conditional fix prepared after the build-266 guest compile failure: the iOS DXT decoder remains guarded, while the Android ASTC converter used by the iOS guest is visible to the compiler. The earlier geometry-mirror fix is retained. With `HALO_IOS_GUEST` disabled, all 53 adapted upstream files match build 268 exactly.

## Validation and device checklist

Strict upstream acceptance passed locally, including build identity, network version 38, source guard structure, host imports, workflow configuration and exact flags-off equivalence. The build-identity, map-load-recovery and source-structure checks passed. A C compiler, `pytest`, a Mac build and a device were unavailable locally, so the guest compile and new upstream harness tests still need CI, and **no IPA or device run has been performed for M2.6.122**. The IPA workflow remains manual; pushing or merging this source update does not trigger an IPA build.

After CI passes, manually build the intended IPA flavor. Confirm boot and a base campaign map, then load a Custom Edition map to exercise texture conversion and the HUD. With compatible network-38 peers, check LAN and public listings for SWAT, Infection, Gun Game and Hardcore names, join and play a round, then compare synchronized shield effects with the new `players` choice. Recheck the iOS Developer Console, mod toggles, touch/controller input and save protection. Record the device, iOS version, flavor, map and logs for any failure.
