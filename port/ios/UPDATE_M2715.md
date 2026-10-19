# M2.6.115 - OpenCE build 235, the iPhone keyboard in the menus

**OpenCE build 235** (commit c2086635394d78279e8c2653312d3ffa1446c9de) over build 232. The network version is unchanged (29), so build 211, 220, 232
and 235 players can join each other. Includes everything in M2.6.114.

## What build 235 brings
Nineteen small engine changes (math helpers, the HUD's nav points, items, cinematics, the S3TC decoder, the web build's WebRTC code and others).
Only `source/units/bipeds.c` is one of the files this port changes; it was merged with the iOS edits. The other 18 were taken byte for byte.
The strict check (`tools/ios_upstream_acceptance.py --upstream-root <build 235> --require-clean-flags-off`) passes: with the iOS switches off,
every adapted file equals build 235.

The build 235 zip leaves out about fifty header files that build 232 had (for example `source/ai/actor_type_definitions.h`) while the sources still
include them, so the headers of the repository are kept as they were.

## The iPhone keyboard in the menus
The PC game types into a menu's text field with the keyboard, and its on-screen keyboard is not made for a phone. On the iPhone, a field now opens
a prompt with a text field and the system keyboard, with or without a controller:

- **Server Setup > Game Name** and **Password** (a public internet game's): tap the row. The prompt starts with the current text. **OK** keeps
  what you typed, **Cancel** leaves it as it was. A password shows as dots.
- **The join password screen** (a game with a password in the browser): the prompt opens by itself, **OK** joins. A wrong password opens it again.
- **Direct Link > Paste Link**: the prompt starts with the invite link on the clipboard, if it holds one. Type or paste an invite link (or its
  code) and press **Join**. An invite link is 76 characters, so this prompt takes 159.

How it works: the game's text field (`menu_functions.c`: `text_field_show`) asks the app for a prompt through one more special index of the existing
`host_settings_value` import (-9; no new import), with a 160-byte buffer. The app shows an alert with a text field (`halo_ios_text_prompt` in
`halo_ios_platform.m`) and the game reads its answer each frame. OK posts the row's A press, the same as Enter on PC, so the field ends the way it
always does (the join password screen joins). The text chat keeps its own live line (-8) from M2.6.114.

## A shorter, tidier Settings > Mods page
The page had five long text blocks and every mod showed all its controls. It is now in this order, with one short line per section:

1. **Add** (top): **Add a mod folder…** and **Import Custom Edition maps…** (it replaces the old Custom Edition card's import button), each with one line.
2. **Mods**: one small card per mod: priority, author, description, **On**, and **Move up / Move down / Remove mod** in one row.
3. **Custom Edition maps**: **Shared files** and a single **Show in list** choice (Hide, All, Multiplayer, Campaign) in place of three switches, then the maps.
4. **Installed Xbox game files**: **Import Xbox maps** and the same **Show in list** choice, then the maps.
5. **Movies (MP4)** (bottom): **Import MP4 movies** and one line showing which of the five are installed.

The Refresh buttons are one **Refresh** button at the top left (the page also refreshes by itself). Nothing about what the page does has changed.
Device check: scroll the page; add a mod; turn it on and off; move it; change **Show in list** in both map sections; import an MP4.

## Limits
- Paste Link always opens the prompt now (it used to join the clipboard's link at once). If the clipboard has the link, the prompt is already
  filled in and one more press of Join does it.
- The Server Setup invite link row only copies the link (Enter), as before; it is not edited.
- A hardware keyboard still types into the PC game's fields as before, when no prompt is up.

## Device checklist
- Regular build first, then the Non-Jailbreak build.
- Settings > Multiplayer > host a game: tap Game Name: the prompt and keyboard come up with the current name. Type, OK: the row shows the new name.
  Cancel: it is unchanged. Start the game: the name is the new one.
- Same for Password (dots in the prompt; the row shows stars afterwards). Join that game from another device: the password screen opens the prompt;
  a wrong password asks again.
- Direct Link: copy an invite link, tap Paste Link: the prompt is filled in; Join joins. Clear it and type or paste another: it joins that one.
  Garbage text: nothing joins.
- Chat (D-pad Up) still works.

## Not verified
Checked with the repository's source checks, the build 235 equivalence gate and the iOS Python tests; the changed C file passes a clang syntax check
with and without the iOS switch (apart from the 64-bit size asserts of this machine). Nothing was compiled against the iOS SDK or run on a
device here: the app's prompt code (`halo_ios_platform.m`) and the new Mods page (`HaloLibrary.m`) and the guest build are first checked by GitHub Actions. Whether the game's A press posted
after OK is taken by the field's row on every screen needs a device.

## Also in this update

- **Report a problem** (Settings > Advanced > Diagnostics) now opens our GitHub problem form with the app, version and device filled in, and copies a report to paste into its Logs box. Sharing it as a file is still offered.
- **Cheats page**: Cheat shortcuts moved to the bottom. Infinite ammo and Unlimited flashlight are in Survival (ammo above One-hit kills, flashlight above No fall damage); Bottomless clip is first in Weapons; Third person is under Detach Camera in Visuals; Infinite Vehicle Health is in Vehicle Spawner; AI ignores you sits with AI Alliance. Only the layout moved; nothing behaves differently.
- **AirPods connect/disconnect crashes**: the cause is not confirmed. Audio route changes and the voice-chat microphone now recover instead of failing (guarded engine start, tap rebuilt on route changes, retries), and the log gets an "audio route:" line. Not verified on a device. If it still happens, turn Voice chat off in Settings > Audio and test again, then send last-crash.txt, ios-boot.log and start-history.txt right after.
- **Backups, simpler**: the Profiles page has one "Back up and restore" button (the separate saves and profiles buttons and the old .haloprofile button are gone). The Backups screen is now three steps: 1. Choose what to include, 2. Export a backup file / Restore from a backup file (same ticks), 3. optional backup folder outside the app.

## Settings overhaul (same build)

Nothing here has been compiled against the iOS SDK or run on a device.

- **Import maps** (start screen and Settings > Mods): bitmaps.map, sounds.map, loc.map and MP4 fallback movies can be picked together with the base maps. The shared files and movies install at once (optional; the game boots without them), the Xbox maps go through the usual staged import. The shared files are checked by header before they are accepted.
- **Cheats**: "Cheats act on" (Player 1 / Player 2 / Both) for splitscreen campaigns. Saved in the settings, so it is in the .halobackup. Global cheats stay global.
- **Display**: new Video options (anti-aliasing, shadow resolution, per-pixel lighting, shield glow and intensity, shield color, field of view, weapon and hands field of view, arm shields, legs, high-res HUD/text), Player names (with name size), Scoreboard and Text chat modules. Each is shared with config.toml, so the in-game menus and Settings show the same values (slots 23 to 42).
- **Multiplayer**: Options now holds Join links on the clipboard, Internet play, UPnP and Share maps, in that order; new Streamer mode module below it.
- **Profiles**: New profile (name and armor color), a check mark on the saved armor color, and the duplicate Halo controller settings and the Network setup card are gone.
- **Advanced**: Game and Startup are one module; the Performance overlay is measured to its text so the second line is no longer cut off, and reads "Mem X MB · free Y MB · heat".
- **Mods**: opens directly inside Settings, "Mod order" with compact rows (the On/Off text now follows the switch), and Custom Edition maps, Installed Xbox game files and Movies (MP4) are collapsed modules.

## Follow-up: Both players, weapon giver, Local Network check

- **Both players** now repeats one-time actions (restore health, grenades, weapon giver, power-ups, vehicles, weapon ring) for each local player, and Infinite Active Camo/Overshield and Infinite Vehicle Health cover both.
- **Weapon giver**: tap a weapon directly; a switch picks Drop in front, Add to my weapons, or Replace the one in hand (the weapon in hand is dropped and the new one put in its place). Action IDs 120-129 add, 130-139 replace, 402 gives both grenade types.
- Cheats order: Movement, Visuals, World; Projectile Swapping and Weapon giver first in Weapons; grenades under Restore health and shield; Infinite Vehicle Health above Choose a vehicle. Multiplayer Options: Internet play first.
- **Check Local Network access** now looks for its own test service and says whether it was seen.
