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

## Fix 1 (first CI run)

The first build stopped in `port/linux/src/xbox_textures.c`: in my merge, the `#endif` that closes the iOS branch of `palette_hash` had landed after the
function's closing brace, so with `HALO_IOS_GUEST` defined the function never closed. My merge checks had only compared the non-iOS view of each file, which
cannot see that. Fixed, and `tools/tests/test_ios_source_structure.py` now checks every C file with iOS blocks in both views (same brace depth, no function
opened inside another block) before the build starts; it fails on the broken file and passes on the fixed one. It is a structure check, not a compile: other
mistakes could still show up as compiler errors.

## M2.6.35 — start-up crash handling

After the build 73 update the app stopped during the start of the guest. The boot log ends at "Launching the full recovered arm64_32 Halo guest image"
with no error, which means a hard crash or the system ending the app; the log alone cannot say which, so this build adds three things.

- **Crash report.** A handler for SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP and SIGFPE writes `crash.txt` (signal, fault address, program counter, and the last
  start-up step) and still lets the app die normally. If the crash was in game code the next start's log names the function. Tested here by crashing a real
  child process and reading the report back.
- **Start-up steps.** `launch-phase.txt` records each step (app launched, engine boot, guest bridge, guest image, boot environment, guest thread, entering
  `__guest_start`, first frame, running ok) and is flushed to disk at once, so a silent stop still shows how far it got.
- **Safe start.** If the last start crashed or stopped during start-up, the next one turns off what can be switched off at run time and has never been proved on a
  device: sound, internet play, smooth 60 FPS, hi-res HUD and text, and the profiler. The log says so, Settings has **Leave safe mode**, and a start that runs 15
  seconds past its first frame returns to normal by itself. Going to the background does not count as a failed start.
- **Share logs** now includes `crash.txt`, `last-crash.txt` and `launch-phase.txt`.
- **Profile-guided optimisation is off by default** (the `guest_pgo` input is now false). It was the only toolchain change in M2.6.34 and had never run on a device.

### Finding the cause if it still stops

Run **Halo CE iOS — Build IPA** by hand (Actions → Run workflow) and change one input at a time:

1. Defaults (PGO off). If this starts, PGO was the problem.
2. `arena_fastpath` = false. If this starts, the rewrite breaks something in the build 73 code.
3. If neither starts, the cause is in the build 73 merge or the M2.6.33 runtime changes; send `crash.txt` and `launch-phase.txt` from Share logs.


## M2.6.36 — the start-up crash, found

M2.6.35's crash report did its job: `crash.txt` and `launch-phase.txt` from the device say a bus error (signal 10) at guest address `0x88848000` while the
last step was "guest bridge installed", which is the loading of the game image.

- **Cause (very likely).** `guest.ld` aligns `.data` to 64 KiB, so whole 16 KiB pages can lie between the read-only and the writable segment. The loader
  mapped each segment on its own and then ran the instruction-cache invalidation over the whole image, first byte to last, gap included. The first gap page
  is unmapped, hence the bus error exactly on a page boundary. The old, smaller image happened to have no such gap; build 73's is larger and does.
  The failing address is the evidence; the layout itself was not inspected on a device.
- **Fix.** The whole image span is mapped as one range before anything is copied, and the instruction cache is invalidated for each executable segment over its
  own bytes only. The loader also says what it found (`guest image: segment N at ... rwx`) and no longer fails without a message.
  `tools/tests/test_ios_image_load.c` runs this plan against the real guest memory manager: the old plan faults on the first gap page, the new one does not.
- **The 111 MB `crash.txt` and the hang.** The M2.6.35 handler returned after writing its report, the faulting instruction ran again, and it was logged again
  without end: the app hung on a black screen instead of closing. The handler now writes one report, restores the default action (so the system writes its own
  crash log) and ends the process itself if it is ever entered a third time. Two tests reproduce the bridge handing a fault back and a handler that keeps coming
  back; the old behaviour hangs the same test.
- **Black screen.** The game is shown first, so a game that never draws left a black screen with no explanation. After 25 seconds without a frame the app opens
  the log, whose Summary now has a "Game image" section with the segment layout.
