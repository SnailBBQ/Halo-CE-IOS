# Halo CE Mod Test

**Halo CE Mod Test** is a second app built from `main` when you tick **Mod Test app** on **Actions → Halo CE iOS — Build IPA**. It is a device experiment, not a release, and
it makes no claim of general PC or Master Chief Collection mod compatibility. Mod conversion itself is paused. Everything else in the project is shared: the Mod Test app has all the
features of the regular app and receives every update at the same time.

## How it differs from the regular app

| | Halo CE (regular) | Halo CE Mod Test |
| --- | --- | --- |
| How to build | Actions → Build IPA, options off | Same workflow, tick **Mod Test app** |
| Name on the device | Halo CE | Halo CE Mod Test |
| Bundle ID | `com.haloceuniversal.ios.m0` | `com.haloceuniversal.ios.modtest` |
| Invite scheme | `halo://` | `halomodtest://` |
| Version | 0.2.110 | 0.2.110.1 |
| Build | Automatic IPA on `main` | Manual: tick **Mod Test app** |
| Output | `HaloCE.ipa`, artifact `HaloCE-iOS` | `HaloCE.ipa`, artifact `HaloCE-iOS-ModTest` |
| Data | Its own maps, saves and settings | Its own, completely separate |
| Largest campaign map | The stock limit, about 278 MiB expanded | Up to 384 MiB expanded |
| Disk cache | Stock slot sizes | Two campaign slots of 384 MiB plus a sector (about 770 MiB of logical disk space) |

The 22 MiB memory area for tags and the level's geometry is **unchanged**. The larger limit is about file size on disk, not memory. Extended multiplayer and menu maps are still unsupported; only
campaign maps may be larger than stock. The engine changes are limited to the iOS build, so the other platforms are unaffected.

## Install and test

1. Run **Halo CE iOS — Build IPA** on `main` with **Mod Test app** ticked. Install that IPA next to the regular app. See [Build the IPA](BUILD.md) and [Install](INSTALL.md).
   Check the app's name and its separate Files folder before copying any content.
2. Import your working Xbox version-5 `ui.map` into the test app. Leave the regular app and its maps alone.
3. For the **large converted-map experiment**, import the converted Xbox-format map under the exact file name **`a10.map`**. Separately, M2.6.88 also exposes OpenCE build-201 Custom Edition v609 maps in the normal Custom Edition library; that upstream feature does not use the Mod Test replacement path.
4. Start a fresh campaign. Capture the logs before and after loading, the intro, your first weapon pickup and each level transition.
5. Test saving a checkpoint, reloading it, and returning to the menu. Report crashes, rejected ranges, memory pressure, missing scripts or assets, distorted models and audio problems.
6. Compare with the stock a10 **in the test app only** using a separate backup/import. The old replacement-map Mods switch/restore feature was retired in M2.6.88. Do not assume a save from the converted map can resume with stock content.

## What to look for in the log

Expected lines include `cache worker: header ready`, a successful decompression whose output equals the declared image length minus 2048, and
`MOD TEST: BSP load ... capacity=23068672`. A line starting `MOD TEST: rejected` means a header or BSP range failed a safety check; send that line with your report.
Successful decompression alone does not prove a mod is playable.

## The converted Cursed V1 a10

From its offline audit:

| | Map | Limit | Headroom |
| --- | --- | --- | --- |
| Expanded size | 369.5 MiB (3,729 tags, 9 BSPs) | 384 MiB | about 14.5 MiB |
| Largest tag + BSP | 20.9 MiB | 22 MiB | about 1.1 MiB (roughly 5%) |
| File size (compressed) | about 176 MiB | n/a | n/a |

Device attempts with converted Cursed Halo maps have failed, including script type errors. No playable Cursed Halo conversion has been established. The offline checks prove structure only. They do not prove scripts, audio, animation, checkpoint reload or gameplay.

## Known limits

- The headroom for tags and geometry is small, so the map has little room for further changes.
- The BSP safety check runs for **every** map, stock maps included, and is stricter than the original loader. If a stock map is rejected, look for `MOD TEST: rejected BSP range` and report it.
- You need over 1 GB of free storage: the map, its expansion and the cache slots.
- Build 84 public server discovery is shared with the regular app; both need iOS device testing.
- The branch contains no copyrighted maps or extracted tags. Supply your own.
