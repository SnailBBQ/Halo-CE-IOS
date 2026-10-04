# Game data

The app does not include game maps. Supply them from your own copy of *Halo: Combat Evolved*.

## What you need

- **Xbox `.map` files** from the original Xbox game (the Xbox cache format, "version 5"). The PC release and the Master Chief Collection use a
  different map format that this engine does not read.
- **`ui.map`** is required. It is the main menu.
- The maps for the levels you want to play. A few are listed below; the retail disc has all of them.
- European (PAL) maps work. The engine adjusts them as they load so they play like the North American maps, so players of both releases
  can play together. This is the same behaviour as the upstream project.

| Campaign | File | Multiplayer | File |
| --- | --- | --- | --- |
| The Pillar of Autumn | `a10.map` | Battle Creek | `beavercreek.map` |
| Halo | `a30.map` | Sidewinder | `sidewinder.map` |
| Truth and Reconciliation | `a50.map` | Damnation | `damnation.map` |
| The Silent Cartographer | `b30.map` | Rat Race | `ratrace.map` |
| Assault on the Control Room | `b40.map` | Prisoner | `prisoner.map` |
| 343 Guilty Spark | `c10.map` | Hang 'Em High | `hangemhigh.map` |
| The Library | `c20.map` | Chill Out | `chillout.map` |
| Two Betrayals | `c40.map` | Derelict | `carousel.map` |
| Keyes | `d20.map` | Boarding Action | `boardingaction.map` |
| The Maw | `d40.map` | Blood Gulch | `bloodgulch.map` |
| | | Wizard | `wizard.map` |
| | | Chiron TL-34 | `putput.map` |
| | | Longest | `longest.map` |

## Getting the maps from a disc image (ISO or XISO)

On the title screen, choose **Import disc image**, then select an `.iso` or `.xiso` in Files.
The app extracts `maps/*.map` on the device into the same `Documents/Halo/maps` folder used by **Import maps**.
Download an iCloud image in Files first. Keep enough free storage for the extracted maps; the app opens the image in place.

Every map must have the Xbox cache v5 `head`, version and `foot` fields, with build **01.10.12.2276 (NTSC)** or
**01.01.14.2342 (PAL)**. Disc regions, retail revision names, Platinum Hits labels and ISO filenames are not filters.
Version 5 describes the map format, not the disc revision. PC, MCC and Custom Edition disc images are unsupported.

If maps already exist, choose **Keep** to preserve matching files and add missing ones, or **Replace** to install matching disc originals.
Files are validated and copied into private staging before installation. **Cancel** preserves the previous library; an interrupted
installation is recovered before the next engine launch. An incomplete `ui.map` is never installed.
Enabled mods remain separate and apply on the next app launch. Replacing a modded map updates its saved original, so unloading
the mod restores the newly imported disc map. Existing maps not found on the disc are preserved.

You can still extract maps on a computer with `extract-xiso` or `xdvdfs`, then use **Import maps** as before.
An existing `ui.map` never causes Halo to wait for a disc image.

## Importing maps into the app

1. **Open Halo CE once.** The first launch creates `Documents/Halo/maps`. iOS does not run an app while installing it, so the folder
   cannot exist before this.
2. Choose one of:
   - **Import maps** on the setup screen (or in Settings). Pick one or more `.map` files from the Files app, including iCloud Drive and AirDrop
     downloads. Existing maps are kept, not replaced. Files are copied to a temporary place first and published only when complete.
   - Or copy the files into **Files → On My iPhone/iPad → Halo CE → Halo → maps**. Finder file sharing on a Mac reaches the same folder.
3. Include `ui.map`. The setup screen reports when it is ready and enables **Start Halo**.
4. Tap **Start Halo**. Later launches can start the engine automatically; see *On app launch* in [Settings](SETTINGS.md#controls).

Imports made from inside Settings are staged and installed the next time you open the app, before the engine opens any map file.
The app checks that `ui.map` is present and not tiny; the engine does the real validation when it loads a map.

## Where files live

| Location (Files → On My iPhone/iPad → Halo CE → Halo) | Contents |
| --- | --- |
| `maps/` | Your game maps |
| `map_thumbnails/` | Map pictures you chose in the library |
| `save/` | Profiles and saved campaign progress |
| `config.toml` | The engine's own configuration (most settings are in the app's Settings instead) |
| `game_invite.txt` | The current multiplayer invite, when no iCloud Drive folder is chosen. See [Multiplayer](MULTIPLAYER.md#alternate-way-of-using-invite-codes-icloud-drive) |
| log files | Diagnostics shared from Settings → Logs. See [Troubleshooting](TROUBLESHOOTING.md) |

The mod library keeps its originals and recovery copies in the app's private storage, not in Files, and that takes extra space.

## The map library and mods

**Settings → Mods** is the map library. It lists the installed game files with their pictures and header checks, and it manages replacement maps
("mods") that can be switched on and off. See [Settings → Mods](SETTINGS.md#mods).

Only compiled Xbox map files work as mods. Loose editor tags, PC-format maps and executable plugins are not supported.
