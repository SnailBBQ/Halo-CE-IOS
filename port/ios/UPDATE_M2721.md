# M2.6.121 - OpenCE build 266

This source update integrates [OpenCE build 266](https://github.com/OpenCommunityEdition/OpenCE/releases/tag/build-266), commit `dedb3755d4b131d6757bfe62851f9b7e2b0b7c2f`, over build 256. The regular app is **0.2.121 / 2721** and Mod Test is **0.2.121.1**.

The network protocol changes from **32 to 36**. Build-256/network-32 clients cannot join build-266/network-36 games, or vice versa. All players need a compatible network-36 build.

## Upstream changes

Build 266 adds SWAT, Infection, Gun Game and Hardcore multiplayer modes and their options. It also changes online co-op and network handling, adds Custom Edition HUD layout assets, and changes Android's Custom Edition texture cache. The iOS guest uses the Android engine configuration, so the new cache path is part of this iOS source update. These changes need device validation, especially on large Custom Edition maps.

The upstream delta touches 100 files. Source and assets without iOS edits were taken from build 266; overlapping engine files were merged against build 256. The unrelated upstream native-build workflow was not added to this iOS repository. The iOS render snapshot and texture-generation hooks remain inside `HALO_IOS_GUEST` guards. With those guards disabled, all 53 adapted engine files match build 266 exactly.

## Validation and device checklist

The local strict upstream acceptance check passed, including build identity, network version, host import coverage, workflow configuration, and exact flags-off equivalence. The build-identity, map-load-recovery, mod-sync, and declaration-order source checks also passed. The new upstream harness tests need `pytest` and a C compiler, which are unavailable in this local environment. **No Mac build, IPA, or device test was performed for M2.6.121.** The IPA workflow remains manual; pushing or merging this source update does not start an IPA build.

After a manual IPA build, check boot and campaign first, then a base multiplayer map with a network-36 peer. Test SWAT, Infection, Gun Game and Hardcore, including lobby options and round transitions. Load a Custom Edition map with its shared resource maps, inspect its HUD, and watch memory use and the texture log through map changes. Recheck the iOS Developer Console, mod toggles, touch/controller input, and save protection. Record the device model, iOS version, app flavor, map and logs for any failure.
