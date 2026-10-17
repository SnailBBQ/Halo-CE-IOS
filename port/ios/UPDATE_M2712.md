# M2.6.112

Settings, controls and Mods changes on top of M2.6.111 (OpenCE build 211, network 29, unchanged).

## Audio and voice chat
- **Ambient** is now a slider in the Sound card; the separate Ambient card is gone. **Reverb** and **Voice volume** were added.
- **Your microphone** (Off, Open mic, Push to talk) is **off by default** and now stays in step with the game's own Audio > Voice Chat setting in both
  directions (it no longer writes the config file behind the game's back). Voice volume and Reverb sync the same way.
- **Talk / Mute button** on the touch controls, between Back and Start. It only appears when the microphone is Open mic or Push to talk.
  Open mic: the button mutes and unmutes you (MUTE / MUTED). Push to talk: hold it to talk (TALK).

## Profiles and Cheats
- In-game name and Multiplayer armor color now let you **choose the Halo player profile** from Settings (Profiles > Halo player profiles). The list
  comes from the running game, so start Halo first.
- Cheats: the "Spawn" section is now **Vehicle Spawner**.

## Settings search
- A magnifier next to "Settings" opens search with suggested options first. Picking a result opens its category and flashes the row.

## Options
- **Choose icon** for the Settings button: built-in icons, any emoji, pictures from Photos (square crop) or Files. A star on the right of each row
  keeps a favorite at the top of the list.

## Mods filters
- "Sort multiplayer maps A-Z" is gone. **Multiplayer only (A-Z)** lists only the multiplayer maps, alphabetically. **Campaign only** lists only the
  campaign maps. The two cannot both be on.
- **Custom Edition Maps** has the same two filters plus **Show installed maps**. Campaign or multiplayer is read from the map's header.

## Title screen
- The "UNIVERSAL" and "iOS x.y.z" line is gone. **Share logs** and **Copy logs** are one **Logs** button.

## Device checklist
- Settings > Audio: Ambient is in the Sound card; Reverb and Voice volume exist; microphone starts Off on a fresh install.
- Change the microphone in Settings, then open the game's Audio > Voice Chat: it matches. Change it there: Settings matches (within a second).
- Open mic or Push to talk: the Talk / Mute button shows between Back and Start; Off: it is hidden. Hold it in Push to talk and speak.
- Profiles > Halo player profiles lists your profiles; choosing one lets In-game name and Armor color edit it.
- Search: tap the magnifier, try "mic", "fps", "vehicle".
- Options > Choose icon: pick an emoji and a photo, star one, reopen the picker.
- Mods: Multiplayer only (A-Z) and Campaign only on both lists.

## Not verified
These changes were checked with plain C tests and source checks only. Nothing was compiled against the iOS SDK or run on a device here.
