# M2.6.124 — OpenCE build 387

This source update integrates [OpenCE build 387](https://github.com/OpenCommunityEdition/OpenCE/releases/tag/build-387), commit `307a42ee04ba58ccafbc231353629e67476af5cd`, over the iOS build-335 baseline. The regular app identity is **0.2.124 / 2724** and Mod Test is **0.2.124.1**. Network protocol changes from **41 to 44**; peers need a compatible network-44 build.

The upstream jump includes MCC package, multiplayer, rendering and audio changes. Nine overlapping files were manually merged. With `HALO_IOS_GUEST` disabled, the adapted source view matches the exact build-387 archive. iOS retains its own map-load recovery, campaign cheats, viewmodel controls, geometry path and audio setting. MCC packages cannot load on iOS yet: their linked tag window needs a separate, verified reservation within the relocated guest arena. The host refuses that reservation rather than map at an incorrect address. Steam Workshop downloads, MCC package sharing and MCC package hosting are also unavailable. Existing Custom Edition map import remains.

## Validation and device checklist

The strict upstream acceptance, host-import coverage, version identity, workflow configuration and map recovery tests are run before delivery. These source checks do not replace the GitHub Actions guest compile or a device test. The IPA workflow is manual (`workflow_dispatch`); pushing or merging this update does not start a Mac IPA build.

After CI passes, manually build the regular IPA. Check boot, stock campaign, save/reload, Custom Edition map import, mods, touch and controller input, chat, sound and rendering. With matching network-44 peers, test server discovery and a full host/join round on a stock map, then a Custom Edition map. Build and test Mod Test and Non-Jailbreak separately if needed; collect device logs for any failed map or launch. No IPA or device outcome is claimed by this source update.
