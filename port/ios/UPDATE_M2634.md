# M2.6.34 — Halo CE Universal build 73

## Why

Build 73 changed the network protocol (version 4 became 10; the lockstep netcode was removed). An iPhone on the old source and a PC on
build 73 cannot find or join each other, whatever else is done to the phone. This milestone moves the iOS port onto build 73's source.

## What was done

- Every file the iOS port does not own now comes from build 73 (about 440 files, plus the new hi-res HUD and text code, its assets in `port/assets`,
  and `port/third_party/stb`).
- The 18 shared files that carry iOS hooks (renderer, memory, audio, loading stages, native scans) were merged by reconstructing each file
  without its `HALO_IOS_GUEST` blocks, three-way merging that against build 73, and resolving 11 conflicts by hand. Each merged file was
  checked: with the iOS blocks removed it matches build 73 exactly, apart from blank lines and three deliberate keep-the-braces differences;
  iOS hook counts per file are unchanged, with these intended exceptions: the audio flag (new), and one render call in a branch upstream deleted.
- The sockets layer follows upstream: poll-based select (any descriptor number), new Winsock errors, a datagram larger than the buffer is
  `WSAEMSGSIZE`, this machine's address prefers Wi-Fi, and the new `posix_user_secret` and UPnP signature are mapped.
- `.github/workflows/build.yml` is upstream's, with this repository's `docs/**` and `research/**` path filters kept.

## Fixed on the way

- **Sound.** The game's audio file shortcuts decoding when no SDL audio device exists. The iOS audio path does not use one, so with sound
  switched on every voice would still have decoded to nothing. The shortcut now steps aside when the host plays the sound.

## New options in build 73

- High-res HUD and high-res text (assets are embedded in the guest). Both are **off by default** on iOS until the new code has run on a device;
  Settings → Frame rate has the switches. They apply the next time the app opens.
- Frame cap, direct camera, scoreboard options and player-name options exist in the game; the iOS app does not expose them yet.

## Performance

- **Profile-guided optimisation.** The iOS workflow had `--pgo=off`. Upstream commits a profile for the game; the Android guest, which is built the
  same way, is optimised with it. The workflow now installs clang 22 (the profile's version) when it can and builds with it; if clang 22
  cannot be installed the build continues without, and logs a warning. The **guest_pgo** input turns it off for an A/B build.
  Functions with iOS hooks do not match the profile and simply build without it.
- Everything from M2.6.33 is included: the sleeping frame limiter, the fast texture hash and the arena rewrite for atomics.
- No new measurement exists since M2.6.33, so nothing else was tuned. The next log will show what is left.

## Checks

All the earlier tests still pass against the build 73 tree. `test_ios_workflow_configuration.py` ran against build 73's own `android_build.py`,
so the workflow's patch points still exist in it.

## Not verified

Nothing here has been compiled for iOS or run on a device. The first build is the CI run; a merge mistake would show as a compile error there.
Whether the iPhone and a build 73 PC find each other has not been tested.
