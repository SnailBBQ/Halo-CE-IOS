# M2.6.114 - OpenCE build 232, text chat on the iPhone keyboard

**OpenCE build 232** (commit 38ccb5f9a4232bb51fc8a79e797b5570f6b69fb8) over build 220. The network version is unchanged (29), so build 211,
build 220 and build 232 players can join each other. Includes everything in M2.6.113.

## What build 232 brings
- **Text chat** in network games (`port/linux/game/network_chat.c`, `NETCODE.md`): a player types a line, the host sends it to the players who
  hear it (everyone, the sender's team, or the sender's vehicle), and each player's screen shows the lines with the sender's name in their team's
  colour. The host can turn it on, allow links or turn it off (Server Setup > Teamplay Options; `network.text_chat`), and always off in a game
  listed in the server browser. The host has `/mute <player> [minutes]` and `/unmute <player>`, and the scoreboard's Mute for everyone is the same
  mute. A machine's own scoreboard mute hides that machine's lines.
  Builds without the chat drop its messages as unknown, so a build 220 or build 211 player can still join a build 232 host.
- **Streamer mode** (Settings > Network Setup > Streamer Mode): hides offensive words, as stars, in other players' names and text, maps and mods.
  Off by default.
- **Multiplayer HUD** options (Settings > Network Setup > Multiplayer HUD): the text chat on or off, and its colours.
- Menu art, the map sharing upload limits (up to 20 MB/s hosting and 10 MB/s seeding) and other engine changes in the build.
- iOS work: 45 files taken byte for byte, 23 new files, 8 merged with the iOS guest changes (`hud.c`, `terminal.c`, `main.c`, `sdl_platform.c`,
  `port_config.c`, `p2p.c`, `xinput_sdl.c`, `menu_functions.c`). The strict check (`tools/ios_upstream_acceptance.py --upstream-root <build 232>
  --require-clean-flags-off`) passes: with the iOS switches off, every adapted file equals build 232.

## Typing on the iPhone keyboard
The PC game types a line with T (everyone) or Y (team) and a keyboard, and has a built-in on-screen keyboard for a controller that you move through
with the stick. An iPhone has the system keyboard, so the app uses it instead, with or without a controller:

- In a network game, press **D-pad Up** (the touch controls' D-pad, or a controller's) and the iPhone keyboard comes up. The line goes to everyone.
- What you type shows in the game's chat line at the top left, as it does on PC. **Send** sends it. Closing the keyboard lets the line go.
- While the keyboard is up the game takes no controller input and no touch-controls stick or look, so you do not move while typing.
- It does not come up where the host has the chat off (the game says "Text chat is off in this game"), in a menu or a cinematic, or with the HUD hidden.
- A line holds 63 printable ASCII characters. Other characters are shown as `?`.

How it works: the game asks the app for the keyboard while a line is open, through one more special index of the existing `host_settings_value`
import (-8; no new import). The app owns an almost invisible text field in the game's window; the game reads what it holds each frame
(`halo_ios_chat_input` in `halo_ios_platform.m`, `network_chat.c` in the guest).

## Limits
- A line to the team or the vehicle cannot be started from the touch controls or a controller yet; D-pad Up starts a line to everyone. Tab to
  change the channel needs a hardware keyboard.
- The on-screen keyboard of the PC game (the stick moving through keys) is not used on iOS.
- If the D-pad is hidden in your touch layout, show it again in the touch controls editor to open the chat.

## Device checklist
- Regular build first, then the Non-Jailbreak build.
- Host a network game on the iPhone (or join one) with a second player. Press D-pad Up: the iPhone keyboard comes up. Type a line and press Send:
  both players see it, with the sender's name.
- While the keyboard is up, the touch sticks and look do nothing. After Send or closing the keyboard, they work again.
- With a controller connected: D-pad Up opens the keyboard too, and the controller does nothing else until the line is sent or let go.
- Pause the game or open a menu while typing: the keyboard goes and the line is let go.
- Host with the chat off (Server Setup > Teamplay Options): D-pad Up says the chat is off.
- Streamer mode on: another player's or a map's offensive words show as stars.

## Not verified
Checked with the repository's source checks, the build 232 equivalence gate and the iOS Python tests. Nothing was compiled against the iOS SDK or run on
a device here, and the new engine files were not compiled for the iOS guest: the Actions guest build is the first real check. The keyboard behaviour
(whether iOS gives the almost invisible text field the keyboard in every window state) needs a device.
