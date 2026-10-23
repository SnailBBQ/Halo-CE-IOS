# M2.6.120 - OpenCE build 256

This source update integrates OpenCE **build 256** (commit `ce95f7deed5bbf726e50a9d5fe5227437194cf3b`) over build 246. The regular app is **0.2.120 / 2720** and Mod Test is **0.2.120.1**. The network version remains **32**. Players still need a compatible network-32 build.

The upstream delta includes co-op script and tag-list changes, Linux renderer and platform fixes, asset tooling, and their tests. The iOS-specific engine additions remain inside `HALO_IOS_GUEST` blocks; with that flag off, the adapted sources match the supplied build 256 tree.

## iPhone controls

- **Settings > Cheats > Developer Console** now has an Open/Close button and a text field for one console command. The text field uses the iOS keyboard and normal copy/paste. A command opens the console before executing if needed. Commands run on the game thread through the engine's existing console parser; this is not a shell or a Windows command prompt.
- **Change console shortcut** records a touch-button or controller-button sequence to open or close the console. It is separate from the solo-campaign cheat shortcuts and can be cleared.
- The game's **Mods** menu saves a toggle immediately on iOS. **Settings > Mods** detects that file change and refreshes its switches. Toggling a switch in Settings reads the latest load order first, then signals the running game to apply it.

## Validation and release status

The local strict upstream acceptance check passed, including exact flags-off equivalence for 53 adapted files. Build identity, map-load recovery, mod synchronization, and iOS host declaration checks passed. A local C compiler and Apple's SDK were unavailable, so the guest and native iOS app were not compiled here. **No IPA was built or device-tested for M2.6.120.** The Build IPA workflow remains manual (`workflow_dispatch`); pushing or merging this update does not start an IPA build.

For device validation, build both intended IPA flavors manually, then check boot, multiplayer compatibility, console button/shortcut/command input, and mod toggles in both menus while a map is running. Check that disabling a mod in either menu updates the other menu and the loaded game, and that the console is usable without a tilde key.
