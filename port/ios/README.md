# iOS port — developer guide

This folder holds the native iOS app. For using the app, see the [documentation](../../docs/ios) and the [README](../../README.md). This page is for people working on the code.

## Architecture

- **Host.** A native `arm64` app (Objective-C and C, in [`HaloIOS/`](HaloIOS)) with its own Xcode project, [`HaloIOS.xcodeproj`](HaloIOS.xcodeproj).
- **Guest.** The recovered engine, built as `arm64_32` code with 32-bit pointers (`halo_guest.elf`) using the shared guest toolchain flow with `HALO_IOS_GUEST=1`. It runs inside a
  4 GiB-aligned arena, so a 32-bit guest pointer is the same as an offset from the arena base. A build step (`tools/android_asm_convert.py --ios-arena-fastpath`) rewrites guest loads and stores to add the
  base directly, and a fault bridge remains as a safety net.
- **Graphics.** EAGL with OpenGL ES 3. The guest's GL calls go through generated imports (`tools/ios_gl_stubs.py`) to the host.
- **Audio.** Native audio engine with a lock-free ring; per-class gains applied once by the native mixer. Shared audio preferences synchronize with the in-game configuration.
- **Network.** A translated socket layer for system link and the invite-link protocol of Halo CE Universal.
- **Settings.** `halo_settings_core.h` is plain C so it can be tested anywhere; `HaloSettingsStore` persists it and `HaloSettingsViewController` shows it.

## Key files in `HaloIOS/`

| File | Role |
| --- | --- |
| `halo_guest_runner.m/.h` | Guest thread, host imports (`MAP(...)`), launch environment, campaign actions, memory |
| `halo_guest_runtime.c`, `halo_guest_vm.h` | The arena and its address-space allocator |
| `halo_guest_exec_bridge.c` | Fault bridge and diagnostics |
| `halo_ios_gl_host.m` | EAGL context and the GL bridge |
| `halo_ios_controls.m` | Touch controls, gamepad input, gyro |
| `halo_ios_audio.m` | Core Audio output |
| `halo_ios_platform.m`, `halo_ios_net.c` | Invites, recent games, networking |
| `halo_settings_core.h` | All settings, saving, bounds |
| `HaloSettingsViewController.m`, `HaloUI.m` | Settings screens |
| `HaloLibrary.m`, `HaloMods.m`, `halo_map_order.h` | Xbox/Custom Edition libraries, legacy replacement migration and MP4 movie library |
| `HaloBackupArchive.m` | Backups and recovery |
| `halo_log_report.h`, `HaloLogViewController.m` | Diagnostics |
| `halo_pad_input.h`, `halo_color.h`, `halo_scancodes.h` | Controller shaping, colours, key names (all tested) |

Engine changes for iOS live in the shared `source/` and `port/linux/` files behind `HALO_IOS_GUEST`, for example `source/game/cheats.c`.

## Checks

The tests are in [`tools/tests`](../../tools/tests) and run in `.github/workflows/ios.yml` and `.github/workflows/ios-memory-tests.yml`. Beyond unit tests of the settings, map order, controller, colour and key-name code,
three source checks catch known project declaration, framework-link and host-import coverage mistakes. They supplement the actual Apple build; they are not a complete compiler or linker check. A test also makes sure the iOS-only blocks in the shared engine files do not change their structure.

Run a test locally, for example:

```sh
python3 tools/tests/test_ios_header_declarations.py
cc -std=c11 -Wall -Wextra -Werror -Iport/ios/HaloIOS tools/tests/test_ios_settings_core.c -o /tmp/settings-test -lm && /tmp/settings-test
```

## Conventions

- Keep iOS-only engine changes inside `#ifdef HALO_IOS_GUEST` so the other platforms are unaffected.
- A new function the game calls on the host needs a `MAP("name", function)` entry in the runner, and a declaration in a header.
- A new Apple framework must be added to `OTHER_LDFLAGS` in both build configurations of the Xcode project.
- Add a device checklist to the release notes for anything that only a device can prove.

## Following the upstream project

New OpenCE builds are merged from the previous upstream build, this repository and the new build, then checked locally where possible and by the Apple workflow before release. M2.6.80 added `tools/ios_upstream_acceptance.py`; the PC updater can run it against the exact candidate OpenCE tree with `--upstream-root <tree> --require-upstream`. The historical build-125 baseline keeps 27 pre-M2.6.80 flags-off divergences fingerprinted in `upstream_baseline_deltas.json` for audit history. M2.6.81 was the first promoted newer integration to pass `--require-clean-flags-off`; M2.6.83 became the green build-138 compile baseline and M2.6.84 added only Non-Jailbreak host diagnostics. M2.6.85 promoted OpenCE build 144/network 21; M2.6.86 added only Non-Jailbreak Stage-2 host diagnostics. M2.6.87 promotes OpenCE build 146/network 22 while preserving those diagnostics. M2.6.88 keeps build 146 and adapts its Custom Edition map system to iOS while adding the guarded MP4 movie bridge. M2.6.89 keeps that feature set unchanged and repairs the Apple packaging test harness. All 43 upstream-owned files containing iOS adaptations become exact OpenCE build-146 source when `HALO_IOS_GUEST` is disabled. Files that are only upstream's are taken byte-for-byte. See
[the official project and credits](../../docs/UPSTREAM.md).

## Release notes

[Every update](../../docs/ios/RELEASE_NOTES.md), with its device checklist. Earlier detail is in the [engineering history](../../docs/ios/HISTORY.md).
