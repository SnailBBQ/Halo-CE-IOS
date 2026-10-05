# M2.6.70 — One branch, three build options

Regular app 0.2.70 / 2670. Mod Test, when ticked, is 0.2.70.1 / 267001. OpenCE build 101 is unchanged.

## Actions → Halo CE iOS — Build IPA

| Option | Default | What it builds |
| --- | --- | --- |
| Mod Test | off | The second app. Larger campaign maps, its own bundle ID, saves and invite scheme. |
| Non-Jailbreak | off | The normal app plus address-space diagnostics for stock iOS. Same bundle ID and multiplayer. |
| Pointer rewrite | on | Rewrites guest loads and stores so pointers do not fault. Turn off only to compare with an older build. |

Do not tick Mod Test and Non-Jailbreak together.

The profile-guided option is removed. It needed clang 22 and had not been proved on a device. Builds use `--pgo=off`.

**Native ports — manual build** is removed. This repository builds the iOS app only. Windows, Linux and Android downloads stay on [Halo CE Universal](https://github.com/OpenCommunityEdition/OpenCE/releases). The port sources used to compile the iOS guest are still in the tree. They are not a second product.

## Mod Test is no longer a branch

Ticking **Mod Test** used to check out `ios/modtest`. That branch is retired. The same loader now compiles on `main` only when `HALO_MOD_TEST` is set:

- campaign files up to 384 MiB, campaign scenario type only
- stock tag capacity (22 MiB) is unchanged
- the direct aligned 4 GiB reservation stays on for that app
- a normal build does not define the flag, so its map limit and allocator stay as they were

Delete the `ios/modtest` branch on GitHub after this lands. Nothing in the workflow reads it.

## Device checklist

1. Run the workflow on `main` with every option off. Confirm the artifact is `HaloCE-iOS` and the app is still **Halo CE** 0.2.70.
2. Run it again with only **Mod Test** ticked. Confirm the home-screen name is **Halo CE Mod Test**, it installs beside the regular app, and a stock `ui.map` still opens.
3. Confirm **Native ports — manual build** is gone from the Actions list.
