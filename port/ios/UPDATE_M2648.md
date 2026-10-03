# M2.6.48 — Settings polish, cheat sections, controls, display, audio, multiplayer, profiles, diagnostics

Based on M2.6.47. Nothing here has been compiled for iOS or run on a device when it was written; the game-side code is
compiled only by CI. Device checks are listed at the end.

## Fixes

- **Sidebar icons.** Every tab click re-applied the accent colour to every view, the sidebar icons included, and the selected
  tab's background is the accent colour too, so the selected icon was accent-on-accent and vanished. Sidebar rows now keep a
  fixed white icon and are skipped by the accent pass.

## Options

- Preset accent colours are kept. New: a **custom colour** (Apple's colour wheel, which also takes hex, plus a hex field with
  validation) and **Chroma (RGB) mode**, a cycling accent with a 3–60 second cycle. Colours that are too dark or too light are
  adjusted so button text stays readable (`halo_color.h`, tested over 4,913 sampled colours); the swatch shows what is used.

## Mods → installed game files

- **Show installed game files** (hidden by default: the list is long), **Sort multiplayer maps A–Z** and **Multiplayer only**
  (hides the campaign maps, nothing else). Campaign maps are in mission order; the stock multiplayer maps follow in the order the
  game's menu lists them (Battle Creek, Sidewinder, Damnation, Rat Race, Prisoner, Hang 'Em High, Chill Out, Derelict, Boarding
  Action, Blood Gulch, Wizard, Chiron TL-34, Longest); maps the table does not know come after them; ui.map is last. Cards show
  the map's name with the file name under it. Logic and tests: `halo_map_order.h`, `test_ios_map_order.c`.

## Cheats (campaign only, as before)

The screen is now collapsible sections: Survival, Weapons, Power-ups, Movement, World, Checkpoints, Teleport, Spawn. Sections
open at any time; their controls are disabled outside a solo campaign. All of these were checked against the engine source.

- **Slow motion** 75/50/25/10 %: `game_time_set_speed`, put back with `game_time_reset_speed`. It slows cutscenes too.
- **AI ignores you**: the engine's own `ai_debug.ignore_player`.
- **Jetpack**: the engine's `cheat.jetpack`.
- **Checkpoints**: Save (`main_save_map_safe`: waits up to 8 s for a moment without combat), Force (`main_save_map_nonsafe`) and
  Revert (`main_revert_map`, with a confirmation). This is the game's own checkpoint.
- **Teleport to crosshair** and **teleport enemies to crosshair**: a ray from the camera against the level (150 world units),
  the point pulled back along the ray and required to be inside the level. Enemies are living, hostile, AI-controlled bipeds that
  are not in a vehicle, at most 24, placed in a ring. **Three saved positions** (save / return) remember where the player, or
  the vehicle, was; they are forgotten when the mission changes.
- **Restore health and shield** (one tap). It does not refill ammo: no verified engine function exists for that; use Infinite ammo.
- Recipes per control profile include Jetpack, AI ignore and slow motion.
- Held cheats are set every tick while wanted and put back once when let go, when the mode leaves the campaign, or when the map
  changes. `tools/tests/test_ios_world_cheats.py` runs that code with mocked engine state.

## Controls

- **Left-handed layout** (per profile): the whole layout is mirrored and the steering zone moves to the right. Layouts are stored
  unmirrored and edited in the mirrored view.
- **Toggle crouch / toggle zoom** (per profile): a tap latches the stick click, the next tap releases it.
- **Gyro aiming** (per profile): sensitivity and two flip switches. The axis directions could not be checked on a device; the
  flips are there to correct them. It also moves the view in menus.
- **Controller**: stick dead zone (removed, not cut off) and response curve, and a **button remap** list. The defaults pass
  everything through unchanged. Tests: `halo_pad_input.h`, `test_ios_pad_input.c` (every subset of the 14 buttons).
- Not done: swipe and double-tap shortcuts (they would compete with drag-to-look).

## Display, Audio

- **Heat-aware frame cap**: Smooth 60 and Uncapped drop to 45 under serious heat or Low Power Mode and to 30 under critical heat,
  and return when it passes. The original 30 FPS mode is never changed.
- **Performance overlay**: frame time, app memory, memory left before iOS closes the app, and heat, under the frame rate.
- **Ambient volume** (sound classes 28–30 and 33–35: device and ambient classes) and **Restart audio output**. The class numbers
  follow Halo's standard sound-class order and agree with the five values in `sound_classes.h`; the others are not listed there.
- Not done: widescreen, brightness and screenshot to Photos (engine support was not verified).

## Multiplayer, Profiles, Diagnostics

- **Recent games** (the last 8 hosted or joined, with Join again and a QR code) and an **invite QR code** for the game you host.
  Auto-rejoin after a dropped connection is not done.
- **Profiles** tab: a summary, **export** to a `.haloprofile` file (Files, AirDrop), **import**, and **reset everything**.
- **Report a problem**: one text file with the device, the settings (never running cheats) and the ends of the logs.

## Tests added or changed

`test_ios_map_order.c`, `test_ios_pad_input.c`, `test_ios_color.c`, `test_ios_world_cheats.py`, new cases in
`test_ios_settings_core.c`; the stubs for two new functions in `test_ios_campaign_policy.py`.

## Device checklist

1. Tap every Settings tab: each icon stays visible, selected or not.
2. Options: pick a custom colour with the wheel and with hex; turn Chroma on and off; reopen Settings.
3. Mods: show and hide the files; check the order in both sort modes and Multiplayer only.
4. Campaign: Slow motion (and back to Off), AI ignore, Jetpack, Save checkpoint then Revert, teleports, saved positions.
   Leave to multiplayer and confirm everything is off.
5. Left-handed layout (and editing it), toggle crouch and zoom, gyro direction in both landscape orientations, a controller remap.
6. Heat cap and overlay, Ambient volume (is the water sound under it?), Restart audio output.
7. Host and join: recents, QR; export, import and reset a profile; Report a problem.
