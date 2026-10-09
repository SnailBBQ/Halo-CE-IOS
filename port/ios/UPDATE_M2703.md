# M2.6.103 - OpenCE build 167

Source update: OpenCE build 159 -> build 167 (commit f479e34914604df5a22a2bdb0b38f180a1f702d8). The network version is still 24, so an iPhone on this build stays compatible with build 154, 155 and 159 hosts.

## What changed upstream (from the file diff; the upstream changelog was not in the archive)
- Netcode: a player moved at once by a teleporter is no longer sent back; clients start units without grenades until the host says; a grenade's shock wave is taken together with its explosion.
- Teamplay Options gains a VOTE KICK on/off row for the host (`port_settings.py`, `network_votekick.c`); the co-op server rows were re-laid out.
- Sound: the definition-transition fix (`sound_set_definition_end` now reports that it retired its own voice), looping-track components retired on restart/stop, new sound lifecycle/transition/stream-flush/mixer tests.
- Rendering: transparent-surface ordering (`rasterizer_transparent_enclosure.h`, plane order), a secondary render target drawn at screen scale, and visibility-query batching in `d3d8_gl.c`.
- Mouse sensitivity gets finer steps (0.1, 0.15, 0.4); profile keyboard, server teardown and settings-menu changes.
- Tooling and platforms: page-hash write tracking for the Android host (`host_watch_hash.c`), app icons, WSL scripts, a Linux sysroot. None of this is used by the iOS build.

## How it was merged
- 134 files were identical to build 159 in the repo and were taken from build 167 byte for byte; 3 files removed upstream (the old Android icon tooling) were removed.
- 14 files carry HALO_IOS_GUEST adaptations and were three-way merged against the flags-off view of the repo file. Three conflicts were resolved by hand:
  - `d3d8_gl.c`: kept the iOS vertex-constants include and added upstream's console and SDL includes.
  - `sdl_platform.c`: kept the iOS exit path (`host_exit`) ahead of upstream's new Android `exit()` path, and kept both the iOS settings-sync declaration and upstream's new screenshot functions.
  - `sound_manager.c`: dropped our own guard for a definition change that deletes its own sound, because upstream's `sound_set_definition_end` now returns that result and its caller returns. `test_ios_sound_lifecycle.py` now tests that upstream form.
- The repo's own README, workflow and `.gitattributes` were kept; only upstream's two `.sh` line-ending rules were added to `.gitattributes`.

## iOS host
Build 167 adds one host import, `host_memory_watch_begin_frame` (it refreshes page hashes for the Android host). The iOS runner does not write-protect guest pages (watch generation stays 0), so it answers the import with an empty function. All 55 host imports the game can call are implemented.

## Test changes
- `test_ios_geometry_mirror.py` now defines `STREAM_BUFFER_RING`, which the production GPU mirror uses for buffer aging.
- `test_ios_sound_lifecycle.py` follows the upstream fix (see above) and was checked to fail if the caller's early return is removed.

## Local validation
- Strict upstream gate (`ios_upstream_acceptance.py --require-clean-flags-off --require-upstream`): 10/10, flags-off equivalence exact 46/46.
- The 35 changed game files that compile in this sandbox convert and assemble in both aligned and flexible-base modes; the flexible-base converter leaves no untranslated base register, and compile and convert results match build 159's for every file. 15 other changed files cannot be compiled in this sandbox (missing SDL and system headers); they fail the same way on build 159 and were not locally checked.
- Python tests pass except `test_ios_pointer_fastpath.py`, which needs `keystone` (not installed here). Upstream's own pytest and harness tests for build 167 were not run (no pytest here).

## Not validated
- The full guest build, the Xcode build and everything on a device. Voice chat and vote-kick are still untested on iOS, as is the new transparent-surface ordering. The earlier Non-Jailbreak device confirmation is for M2.6.101.
- Test Regular first, then Non-Jailbreak.
