# Halo CE iOS — Project status

**Status: playable on the regular/jailbreak path.** **Current source update: M2.6.121** (regular app 0.2.121, Mod Test 0.2.121.1), on OpenCE build 266 / network 36 with Custom Edition maps, map-aware Weapon Giver and Vehicle Spawner, and the MP4 movie fallback, while continuing the Non-Jailbreak **real-guest flexible-base Stage 3** path, which is device-confirmed playable on one phone. M2.6.93 passed GitHub Actions and the iPhone 14 Plus passed Stage 2 at `0x2A0000000`. The M2.6.98 Non-Jailbreak IPA ran the real guest into OpenCE `main()` on that phone and stopped on an untranslated `ldr w9, [x30]` in `mod_l`; M2.6.99 fixes that class. M2.6.100 applies the same x30 translation to the regular (aligned) converter to remove a frame-rate bottleneck seen in a Regular device log. M2.6.101 fixes the next Non-Jailbreak fault (frame-pointer chain load in `get_return_eip`). The M2.6.100 Regular log held about 60 FPS in gameplay. **Device result (2026-10-08):** the M2.6.101 Non-Jailbreak build (sideloaded with Sideloadly, no memory entitlements) is confirmed playable on an iPhone 14 Plus (iOS 16.2): it booted, played the a10 campaign level and loaded a second map in a roughly ten-minute session at about 60 FPS with no crashes and no pointer faults (device log of 2026-10-08). Only that device and session are covered; other phones, long sessions, vehicles and multiplayer still need logs.

**Update:** [M2.6.121](port/ios/UPDATE_M2721.md) moves to OpenCE **build 266** (network version 36), including new multiplayer modes and Custom Edition HUD/texture work. Network-32 clients cannot cross-play with this build. [M2.6.120](port/ios/UPDATE_M2720.md) added iOS Developer Console access and synchronized mod toggles. [M2.6.119](port/ios/UPDATE_M2719.md) brought build 246 and increased the memory window and texture cache. [M2.6.118](port/ios/UPDATE_M2718.md) integrated OpenCE build 244 / network 32 and kept the map-aware Custom Edition pickers. Network-29 clients cannot cross-play with this version. Strict source acceptance passes; Mac build and device validation remain outstanding.

**Previous:** [M2.6.113](UPDATE_M2713.md) moves to OpenCE **build 220** (same network version 29) and makes Settings > Mods the same list as the game's new Mods menu: mods turned on or off, reordered, removed or added in either place show in both.

**Previous:** [M2.6.112](UPDATE_M2712.md) adds Settings search, a Talk / Mute button on the touch controls, the voice chat microphone off by default and in sync with the game, a profile picker, emoji and photo Settings icons with favorites, and clearer Mods filters.

**Update:** [M2.6.110](UPDATE_M2710.md) moves to OpenCE **build 211** (same network version 29) and turns **map sharing off by default** on iOS, with a switch in Settings > Multiplayer. Not yet run on a device.

**Source update:** [M2.6.109](UPDATE_M2709.md) moves to OpenCE **build 206 / network 29**: a new network version (it cannot join build 201 or older hosts, nor they it). Custom Edition maps keep their own names (build 201 renamed them with a hash), map downloads are checked, and the changes are described in the update note. Not yet run on a device.

**Source update:** [M2.6.105](port/ios/UPDATE_M2705.md) integrates OpenCE build 201 (network version 28; Custom Edition map sharing, shield glow and armor colors, first-person legs, no host import change). [M2.6.104](port/ios/UPDATE_M2704.md) integrated OpenCE build 182 (network version 25; Video Setup categories, a viewmodel switch, an elevator netcode fix, a profiler, and seven new host imports for Android's touch controls and gamepad close that iOS answers as an idle touch layer). [M2.6.103](port/ios/UPDATE_M2703.md) integrated OpenCE build 167 (netcode, sound-lifecycle and transparent-geometry fixes, a vote-kick switch, finer mouse sensitivity, one new memory-watch host import that iOS answers as a no-op). [M2.6.102](port/ios/UPDATE_M2702.md) integrated OpenCE build 159 (voice chat with the Opus codec, player vote-kick, three new host audio-stream imports that iOS answers as "no microphone"). [M2.6.101](port/ios/UPDATE_M2701.md) canonicalizes the saved frame pointer loaded from `[x29]` in the Non-Jailbreak converter. [M2.6.100](port/ios/UPDATE_M2700.md) makes the aligned (Regular and Mod Test) converter treat x30 as a guest-pointer base, as the flexible-base converter has since M2.6.99. A Regular device log showed 16.2 million SIGSEGV-bridge faults, 99.7% from the audio ADPCM decode loop (`stream_process`), costing roughly 7 µs each and collapsing some windows to 10-33 FPS.

## Two apps, plus a stock-iOS build

| App | How to build | Output |
| --- | --- | --- |
| Halo CE (regular) | `main`, options off | `HaloCE.ipa` |
| Halo CE Mod Test | `main`, tick **Mod Test app** | artifact `HaloCE-iOS-ModTest` |
| Non-Jailbreak Version | `main`, tick **Non-Jailbreak Version** | artifact `HaloCE-iOS-NonJailbreak` |

The regular app and Mod Test share the same features and are updated together. The Mod Test app adds an experimental loader for very large converted campaign maps; see [Mod Test](docs/ios/MOD_TEST.md). The Non-Jailbreak Version is the regular app plus the Stage-3 guest ABI (confirmed playable on one iPhone 14 Plus; not yet broadly tested). When a non-aligned contiguous 4 GiB reservation exists, M2.6.96 may use it as the **real** guest arena and records phases 600–609. Stage 2 remains only as a fallback diagnostic if Stage 3 cannot reserve an arena. Free-account sideloading works on the one tested device but is not yet a supported path; see [M2.6.96](port/ios/UPDATE_M2696.md) and [Install](docs/ios/INSTALL.md#sideloading-with-free-and-paid-accounts).

## What works (reported from device testing)

- The Halo main menu, `a10` campaign progression, and the other campaign maps tried so far, which load fine; reported 60 FPS menus and gameplay in tested scenes, without a guarantee across devices or maps; native audio.
- Cross-play multiplayer with an OpenCE PC client, including joining by invite link.
- On-screen Xbox-style controls with five schemes, touch look, and physical controllers.

## Implemented, waiting for device validation

- M2.6.101 Non-Jailbreak frame-pointer chain load (device log: `get_return_eip` faulted at x27 + low32(sp)).
- M2.6.100 aligned-converter x30 translation (Regular/Mod Test frame-rate fix from the device log).
- M2.6.99 Non-Jailbreak x30 guest-pointer translation, found from the M2.6.98 device log (guest reached OpenCE `main()`, OpenGL and audio, then faulted at `mod_l+0x190`). M2.6.98 integrated OpenCE build 155 and M2.6.97 build 154; both passed Actions.
- OpenCE build 144 / network 21 source integration from M2.6.85, including renderer call reduction, co-op/netcode fixes, map-tag validation, additional hardening and GPU/visibility/water performance changes through build 144.
- The Settings additions of M2.6.48 (cheat sections and new cheats, left-handed layout, gyro, controller remap, heat-aware frame cap, performance overlay, Ambient volume, recent games and QR, Profiles, problem report, custom accent colours).
- Picture options, touch aiming and AirPlay mirroring (M2.6.50).
- The Mod Test loader has offline structural checks. Device attempts with converted Cursed Halo maps have failed; playable mod compatibility is not established.

- M2.6.54 campaign modifiers, flying camera, wireframe, bounded checkpoint editor and separate cache-free save/profile exports.

## Known limits

- Public server discovery is integrated; iOS public browsing/hosting and cross-play need device validation. Discovery uses public MQTT signalling brokers and requires network connectivity.
- Disc import and **Import maps** both fill `Documents/Halo/maps`. Xbox cache version 5 only. See [Game data](docs/ios/GAME_DATA.md).
- AirPlay is system screen mirroring. A separate TV-only game window is not implemented.
- Native Bink decoding is not included; user-supplied MP4 fallbacks are supported for the known Halo movie slots.
- Touch behaviour in the PC menus has not been validated; the Xbox menus remain available in Settings.
- Mod conversion is paused.
- Checkpoint editing supports finite health/shields, grenades and existing weapon ammo in validated Xbox 2342 campaign saves of this build's own game-state size (20 MB since upstream's pools grew; the game cannot load a save from a build with a different size, so earlier saves and checkpoints are not usable). It does not fabricate skulls, vehicle boost, new weapon objects, or runtime cheat fields.

## Where to read more

| | |
| --- | --- |
| Install, build and game data | [Install](docs/ios/INSTALL.md) · [Build the IPA](docs/ios/BUILD.md) · [Game data](docs/ios/GAME_DATA.md) |
| Using the app | [Settings](docs/ios/SETTINGS.md) · [Controls](docs/ios/CONTROLS.md) · [Multiplayer](docs/ios/MULTIPLAYER.md) · [Backups](docs/ios/BACKUPS.md) |
| Problems | [Troubleshooting](docs/ios/TROUBLESHOOTING.md) |
| Development | [Developer guide](port/ios/README.md) · [Engineering history](docs/ios/HISTORY.md) |
| The official project | [OpenCE and credits](docs/UPSTREAM.md) |
