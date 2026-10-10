# M2.6.104 - OpenCE build 182

Source update: OpenCE build 167 -> build 182 (commit d03f6e27770b141a61fc49001d1c65b466bbd017).

**The network version is now 25 (it was 24).** An iPhone on this build cannot see or join hosts on builds 154-167, and the reverse, until both run build 182 or later. The Info.plist, the About screen and the shared logs report 25.

## What changed upstream (from the file diff; the upstream changelog was not in the archive)
- Netcode: on a moving elevator the host takes only where a client's player is across, not how high; each machine's elevator carries its own copy.
- Settings: Video Setup is split into a Graphics screen and a "FOV and Viewmodels" screen with new rows for the field of view, the weapon's field of view, a viewmodel on/off switch (`display.viewmodel_visible`) and an arm-shield flare (`display.viewmodel_shield`).
- Rendering: a high-resolution HUD texture can stand in for some sprites (`hud_hires_tags.c`), a reticle SVG set was removed, TIFF screenshots, and a new profiler (`profile_json.c`, `profile_trace.c`, `profile_console.c`).
- Sound: a Custom Edition sound whose gain is above 1 now plays at full gain instead of halting; the idle wait between frames always sleeps.
- Menus: with one person playing, any controller drives the first player's menus (`widget_takes_any_controller`).
- Android only: on-screen touch controls (`touch_input.c`, `touch_menu.c`, `touch_game.c`, `host_touch.c`), a `HALO_GLES` macro for the OpenGL ES renderer and a `HALO_ARM64_GUEST` macro for the 32-bit guest paths (both defined by the generated guest build, which the iOS workflow transforms), WSL scripts.

## How it was merged
- 228 files were identical to build 167 in the repo and were taken from build 182 byte for byte; 9 removed upstream (HUD reticle SVGs) were removed.
- 25 files carry HALO_IOS_GUEST adaptations and were three-way merged against the flags-off view of the repo file. 20 merged cleanly; 5 had conflicts, resolved by hand:
  - `sound_dsound_xbox.c`: upstream's gain clamp (`PIN`) is used; the iOS branch keeps its NaN-safe clamp of both the channel and pause gains.
  - `ui_widget.c`: kept the iOS `host_debug_state` call and upstream's new touch-target fitting.
  - `first_person_weapons.c`: the iOS host's viewmodel flags and upstream's `viewmodel_is_visible()` both apply (iOS settings first); the arm-shield block precedes the iOS arms condition.
  - `structure_visibility.c`: kept the iOS native surface-mark scan and upstream's comment on the whole-number index compare.
  - `main.c`: the idle sleep is upstream's (identical to what iOS did); the iOS phase markers now wrap upstream's profile scope around the game-time update.
- The repo's own README and workflow were kept.

## iOS host
Seven new host imports are implemented in `halo_guest_runner.m` (62 imports now covered):
- `host_gesture_insets`, `host_touch_read`, `host_touch_look_read` write zeros into the guest's output arrays, `host_touch_rumble`, `host_touch_scene`, `host_touch_bindings` and `host_sdl_close_gamepad` do nothing. The guest therefore sees Android's touch layer as idle. iOS keeps its own overlay, which reaches the game through the gamepad-1 axes, so touch play is unchanged by design.

## Test changes
- `test_ios_geometry_mirror.py` defines `HALO_GLES`, which gates the mirror code now.
- `test_ios_guest_return_contracts.py` looks for the `HALO_GLES` block that follows `decode_level`.
- `test_ios_upstream101.py` includes the new `widget_takes_any_controller` and checks the one-person-playing menu routing.

## Local validation
- Strict upstream gate: 10/10, flags-off equivalence exact 46/46, 62 host imports covered, build identity (build-182, commit, network 25, game state 20,971,520 bytes) matches the source.
- Of the changed and new game sources, the ones that compile in this sandbox (about 98) convert and assemble in aligned and flexible-base modes with no untranslated flexible-base access and no new compile failure against build 167. 34 others (including the Android-only `touch_input.c`) need system or SDL headers that this sandbox lacks, so they were not locally checked.
- Python tests pass except `test_ios_pointer_fastpath.py`, which needs `keystone`. Upstream's own pytest tests for build 182 were not run.

## Not validated
- The full guest build, the Xcode build and everything on a device, including the new Video Setup screens, the viewmodel switch and network 25 play against a build 182 host. The earlier Non-Jailbreak device confirmation is for M2.6.101.
- Test Regular first, then Non-Jailbreak.
