# Mods for Halo CE for iOS

A mod is a folder of Halo PC tag files that the game plays **over a map's own tags, on your
iPhone only**. Nothing is sent to other players, so you can play online with players who have
other mods or none. The rules come from OpenCE's Mods system (`docs/mods.md` in the OpenCE
sources).

## Will this download work? (start here)

Open the download and look inside for files ending in `.gbxmodel`, `.model`, `.bitmap`, `.sound`,
`.unicode_string_list` or `.string_list`.

| What you find | Result |
| --- | --- |
| Only `.biped`, `.weapon`, `.vehicle`, `.scenario`, `.globals`, `.projectile`, `.effect` | **Does nothing.** These are never read, and a mod cannot add new characters, weapons or maps. |
| Textures, sounds or text that **replace** the game's own (same name as a stock tag) | **Works** once it has a `mod.toml`. |
| A model that replaces a stock one, with the same skeleton and markers | **Works.** If the skeleton differs, the game leaves the model out and the stock one plays. |
| A model for a **new** character or weapon (own skeleton, own animations) | **Does nothing as it is.** It has to be converted onto a stock model first (the Lucario and Hayabusa mods in this project were done that way). |

Quick test: a file only matters if the **same path exists in the game**, e.g.
`tags/characters/cyborg/cyborg.gbxmodel`. A new name (`characters/lucario/...`) is ignored.

## Making your own

Only read this part if you want to build a mod yourself. Most people just add a finished mod folder.

### The folder

```
MyMod/                       <- the folder you add in Settings > Mods > Add a mod folder
  mod.toml                   <- required (every line inside it is optional)
  tags/
    sound/sfx/weapons/assault rifle/fire.sound
    characters/cyborg/bitmaps/cyborg.bitmap
    ui/hud/hud_item_messages.unicode_string_list
    characters/cyborg/cyborg.gbxmodel
```

- **`mod.toml` is the only required file besides `tags/`.** A folder without it is not a mod,
  and the app tells you so when you add it. A starter is in `docs/ios/mod-template/MyMod`.
- **A file's path is the map tag's name plus its group's extension.** The tag
  `characters\cyborg\bitmaps\cyborg` becomes `tags/characters/cyborg/bitmaps/cyborg.bitmap`.
  Names are not case-sensitive.
- The folder name is the mod's name in the list: up to 63 bytes, no slash, no links inside.
  Add up to 32 folders at once; 256 mods and 262,144 files in all.

### What a mod can change

| Kind | Extension | Typical use |
| --- | --- | --- |
| Sound | `.sound` | Music, weapon sounds, dialogue |
| Bitmap | `.bitmap` | Textures, HUD pictures |
| Text | `.unicode_string_list`, `.string_list` | Translations, messages |
| Model | `.gbxmodel` (Halo PC) or `.model` (Xbox) | How weapons, vehicles, scenery and characters look |

Everything else (`.weapon`, `.biped`, `.vehicle`, `.scenario`, `.globals`, animations, collision)
is **never read**. Those decide what every player's game must agree on, so a mod cannot change
them. That is also why a mod cannot add a new character or weapon: a file only replaces a tag the
map already has.

### Rules that decide whether a file is accepted

- **Bitmaps** need at least as many bitmaps, of the same types, and as many sequences as the
  map's tag of that name. Larger is fine. Format DXT1/DXT3/DXT5 or uncompressed; keep one bitmap's
  pixels under about 5 MB to be safe on iPhone (a 2048 x 2048 DXT5 with mipmaps fits).
- **Text** keeps the map's number of strings, and a string that holds `%s` or `%d` must keep the
  same ones in the same order.
- **Models** must keep the map's **skeleton** (node names, hierarchy and default positions),
  **markers** (names, nodes, positions, rotations) and **regions/permutations** (names, flags),
  within 0.001. Only what is drawn is yours: the mesh, its UVs and which shader each part uses.
  Every shader a part names must already be in the map. To use your own picture, redraw one of
  the map's bitmaps (a bitmap mod) and point your part at that shader.
- A file that fails is **left out and the map's own plays**. The rest of the mod still works.

### When something does not change

1. Open Settings > Logs and share the logs, or open `debug.txt`. Each file the game left out has
   a line starting `mods:` with the reason.
2. Check it is on in Settings > Mods and that the mod's `maps` line (if any) names your map.
3. Check the path: the file must have the same name as the map's tag, with forward slashes.
4. On a model, the usual reasons are a different skeleton, missing markers, or a shader the map
   does not have.

### Worked example: Lucario in place of the Spartan

The community "LucarioBiped" download is a new biped. A mod cannot add a biped, so nothing
changed. The working version replaces the Spartan's own model instead:

1. Its mesh was moved onto the Chief's skeleton (the original used a different arm pose).
2. The Chief's eight markers (weapon, flashlight, hands, feet) were added.
3. All five textures were packed into one 1024 x 1024 picture that replaces
   `characters\cyborg\bitmaps\cyborg`, with the mesh's UVs moved to match.
4. A neutral picture replaces `characters\cyborg\bitmaps\cyborg multipurpose` so the Chief's
   team tint and shine do not touch it.

It shows every player as Lucario **on your phone only**, and team colors are gone.
