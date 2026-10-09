# Game data

The app does not include game maps. Supply them from your own copy of *Halo: Combat Evolved*.

## What you need

- **Xbox `.map` files** from the original Xbox game (the Xbox cache format, "version 5"). The original Xbox maps remain the base game data. OpenCE build 167 can additionally load standard Halo Custom Edition version-609 maps from a separate `custom_maps` folder; those do not replace the Xbox files.
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
Custom Edition maps are separate from disc/Xbox imports. Installing or replacing an Xbox disc map does not overwrite `custom_maps`. Existing Xbox maps not found on the disc are preserved.

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
| `maps/` | Original/Xbox version-5 game maps |
| `custom_maps/` | Enabled Halo Custom Edition v609 maps, resource caches and optional `.bmp`/`.txt` sidecars |
| `custom_maps_disabled/` | CE maps you disabled without deleting |
| `videos/` | User-supplied MP4 fallbacks for Halo Bink movie requests |
| `map_thumbnails/` | Pictures you chose for the Xbox map library |
| `save/` | Profiles and saved campaign progress |
| `config.toml` | The engine's own configuration (most settings are in the app's Settings instead) |
| `game_invite.txt` | The current multiplayer invite, when no iCloud Drive folder is chosen. See [Multiplayer](MULTIPLAYER.md#alternate-way-of-using-invite-codes-icloud-drive) |
| log files | Diagnostics shared from Settings → Logs. See [Troubleshooting](TROUBLESHOOTING.md) |

## Custom Edition maps and movies

**Settings → Mods** keeps the original Xbox library separate from OpenCE's Custom Edition library. Import standard CE version-609 maps, their optional `.bmp`/`.txt` sidecars and the shared `bitmaps.map`, `sounds.map` and `loc.map` resources into the Custom Edition section. OpenSauce maps are not supported by OpenCE build 167.

The same screen can import user-supplied MP4 fallbacks for Halo's movie names (`intro`, `credits`, `attract1`–`attract3`). The app does not include or convert copyrighted movie assets; it only supplies native playback for files the user provides.
