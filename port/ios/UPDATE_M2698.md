# M2.6.98 — OpenCE build 155

Regular app **0.2.98 / 2698**. The Mod Test app derives **0.2.98.1 / 269801**. The engine moves from OpenCE build 154 (`544ee497b6c1da195fa4dd9363851074edc63cbb`) to **OpenCE build 155** (`71bf206bd05b607136761f43f109f6a58bcaa026`, taken from the supplied archive's commit stamp). **Network version stays 24** and game state stays 20 MiB. M2.6.97 (build 154) was green on GitHub Actions before this update.

## What changed upstream (build 154 → 155, from the supplied trees)

Only 14 paths differ. Read from the files themselves (upstream commit messages were not available):

- **Loose sounds for map makers** (`port/linux/game/loose_sounds.c`, new): with the new `audio.loose_sounds` setting (default **false**, environment `HALO_LOOSE_SOUNDS`), a map's sound plays from a Halo PC sound tag file under the data root's `tags` folder, and the console functions `loose_sounds` and `loose_sounds_reload` control it. Inert unless turned on; there is no iOS setting for it.
- The sound-cache size became one shared constant, `HALO_PORT_SOUND_CACHE_SIZE`: **16 MB on desktop builds, 4 MB under `HALO_ANDROID`**. The iOS guest is compiled with `HALO_ANDROID`, so it keeps the Xbox-sized 4 MB cache and memory use does not change.
- Custom Edition sound decoding was refactored for big-endian PCM, plus a new harness test (`tools/harness/tests/test_loose_sound_paths.py`).

No host import changed (`port/android/host_imports.list` is identical to build 154), so no iOS host code was touched.

## iOS merge

The delta was applied onto the M2.6.97 tree using the exact build-154 files as the merge base. 11 files were taken straight from build 155 and 3 added. The two iOS-adapted files that changed upstream (`source/cache/xbox_sound_cache.c`, `source/sound/sound_dsound_xbox.c`) merged without conflicts. With `HALO_IOS_GUEST` disabled, every adapted upstream file reduces exactly to build 155.

## Validation limits

The 1,492-object guest build and the Xcode build only run on GitHub Actions, and nothing here is confirmed on a device. Test Regular first (the sound cache and cache loading code were touched), then Non-Jailbreak.
