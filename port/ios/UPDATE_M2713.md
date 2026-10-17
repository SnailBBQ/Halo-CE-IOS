# M2.6.113 - OpenCE build 220, Mods in step with the game

**OpenCE build 220** (commit 7524ba61689a912bdec234d9687b178f0b0e7389) over build 211. The network version is unchanged (29), so build 211
and build 220 players can join each other. Includes everything in M2.6.112.

## What build 220 brings
- **Mods**: folders of Halo PC tag files in `Documents/Halo/mods` (texture, sound, text and model packs) that play over the maps on your device
  only, in any game. Each has a `mod.toml`; the game's main menu has a Mods screen to turn them on and off and set their order
  (`docs/mods.md`).
- Also new in the engine: a sound resampler setting (`audio.resampler`), Arch/AUR notes, and updated menu art.
- iOS work: 111 files taken byte for byte, 7 merged with the iOS guest changes (`menu_functions.c`, `port_config.c`, `dsound_sdl.c`,
  `sdl_platform.c`, `xbox_textures.c`, `xbox_sound_cache.c`, `ui_widget.c`). The strict check (`tools/ios_upstream_acceptance.py`) passes: with the iOS
  switches off, every adapted file equals build 220. One new host import (`host_sdl_show_message_box`) is answered "could not ask".

## Settings > Mods is the game's Mods list
The game keeps its mods as folders plus `mods/load_order.toml` (the order, and the mods turned off). Settings > Mods now reads and writes
exactly those, so there is one list:
- Turn a mod **On/Off**, **Move up/down**, **Remove** it, or **Add a mod folder** in Settings; the running game reads the change at once (the
  same way the game's own Mods > OK does), and the game's Mods screen shows it.
- Change the order or on/off in the game's Mods screen; Settings > Mods shows it within a couple of seconds.
- Remove a mod in Settings and it is gone from the game's list too.
- Each entry shows its version, authors, maps, description, priority and any "cannot be played with" warning.
- The top of the list plays over the ones below, as in the game's menu.

Limits: mods are added as folders (unzip a zip in the Files app first). The game asks about mods that say they cannot be played together
before it starts; iOS cannot show that question, so it plays them all and Settings > Mods shows the warning so you can turn one off.

## Profiles, made consistent
- Your in-game name and armor color belong to the **Halo player profile**; they were never in a `.haloprofile` (which held app settings only).
  Settings > Profiles no longer has a separate Export / Import profile card. **Back up or move your profile** opens the backup screen with app
  settings, layouts, campaign saves and Halo player profiles all ticked, so one `.halobackup` holds the whole profile. An **Open an older .haloprofile
  file** button still imports old settings-only files.
- **Import / export Halo player profiles** now sits above In-game name and Multiplayer armor color, and the "What a profile holds" text matches.

## Device checklist
- Regular build first. Settings > Mods shows "Mods" above the Custom Edition maps.
- Put a mod folder (with `mod.toml` and `tags`) in the Files app under Halo CE > Halo > mods, or use Add a mod folder.
- Start a map, open Settings > Mods, turn the mod off and on: the game's Mods screen and the textures/sounds follow.
- In the game, main menu > Mods: move a mod, press OK; Settings > Mods shows the new order.
- Remove a mod in Settings: it disappears from the game's list.

## Not verified
Checked with plain C tests (the mod.toml / load_order.toml reader and writer) and source checks only. Nothing was compiled against the iOS SDK or
run on a device here, and the new engine files were not compiled for the iOS guest: the Actions guest build is the first real check.
