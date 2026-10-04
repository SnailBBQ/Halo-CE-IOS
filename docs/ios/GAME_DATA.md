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

The app imports `.map` files. **It does not open disc images itself.** (The desktop and Android versions of Halo CE Universal can open a
disc image directly; the iOS app cannot yet.) Extract the maps on a computer first:

1. Start with a disc image of your own copy of the game, an `.iso` or `.xiso` file.
2. Extract its files with a tool that reads Xbox disc images, for example `extract-xiso` or `xdvdfs`. With extract-xiso the command is
   along the lines of `extract-xiso -x "Halo - Combat Evolved.iso"`; check the help of the tool you use.
3. Open the extracted `maps` folder. It holds `ui.map` and the campaign and multiplayer maps.
4. Copy the `.map` files to your device (see below).

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
