# Multiplayer

The game can play system link games on a local network and over the internet, and this app can host and join them.

- Up to 128 players on up to 128 machines in a system link game (the upstream project's figure).
- **Cross-play.** The app plays with Halo CE Universal on Windows, Linux and Android.
- **No server is needed** for an internet game. An invite link connects the machines directly.
- The netcode is new: each machine moves its own player immediately, and the host decides the game. The
  [upstream netcode notes](https://github.com/cybersecurity/halo-ce-universal/blob/main/port/linux/NETCODE.md) describe it.

## Compatibility

Everyone in a game must run **the same Halo CE Universal build**, and have the same map files. Update the app and your PC game together. If you use mods or custom maps,
keep every player on matching content. Settings → Advanced → About shows the version of the app and the game build it was made from.

The two apps use separate invite schemes: the regular app opens `halo://` links and the [Mod Test app](MOD_TEST.md) opens `halomodtest://` links.

<p align="center">
  <img src="images/multiplayer-settings.png" alt="Settings → Multiplayer: connection status and Join a game" width="720"><br>
  <em>Settings → Multiplayer</em>
</p>

## Joining a game

| Way | How |
| --- | --- |
| Invite link | In **Settings → Multiplayer**, paste a `halo://join/` link (or just its 64-digit code) into **Join this invite**, or use **Join the invite on the clipboard**. Tapping a `halo://` link in another app also joins. |
| Clipboard automatically | Turn on *Join links on the clipboard automatically*. It is off by default because iOS asks permission every time the clipboard is read. Opening a link does not need it. |
| Invite file | Choose an iCloud Drive folder; a PC player can paste an invite into the file, and you press **Join from game_invite.txt**. See below. |
| Recent games | **Join again** reuses a game you hosted or joined. It only works while that game is still running. |
| LAN | Games on the same Wi-Fi appear in the LAN list. Allow **Local Network** for Halo CE in iOS Settings. |
| PC menus | **Join Game → Direct Link** takes an invite from a link, the clipboard or Discord. **Join Game → LAN** lists local games. The public **Server Browser** is empty for now because upstream has not built a public server list. |

## Hosting a game

Start a game from **Create Game** in the menus: **Internet** for a game friends can join by invite, or **LAN** for your local network (the Xbox menus call this System Link).
While you host:

- Your invite is shown in **Settings → Multiplayer → Host a game**, ready to share.
- It is written to **game_invite.txt** (see below).
- **Invite QR code** shows it as a code that someone next to you can scan with their camera.

Ending the game clears the invite. An old link cannot rejoin a game that has ended.

## The invite file

`game_invite.txt` holds the invite of the game you are hosting.

1. In **Settings → Multiplayer**, choose **Choose iCloud Drive folder** and pick iCloud Drive or a folder inside it. The app remembers the folder and writes the file there. Until you choose one,
   the file is in the app's own `Documents/Halo` folder.
2. When you host, the app writes the current invite into the file.
3. To join a PC player's game, paste their invite into the same file, wait for iCloud to sync, and press **Join from game_invite.txt**. It reads the file once when you press the button and never joins by itself.

Ending a game, or the next launch, clears the file only if it still holds the code this app wrote, so an invite you pasted from a PC is kept. The file holds a single link of at most 1,024 bytes.
iCloud syncs eventually, and a force-quit app may clean up on its next launch. If access stops working, choose the folder again.

## Connection status

The status row shows whether you are hosting, joined or connecting, the tunnel round-trip time when there is one (LAN-only games may have none), the connected peers, the current map and the mode.
A peer count is not a player count. It refreshes every two seconds while Settings is open.

## Good to know

- All cheats are switched off when you host or join a game.
- Cross-play with a PC is easiest when you pick maps both sides have.
- Smooth, stable play depends on the phone: see [Display → Heat and battery](SETTINGS.md#display) and the [troubleshooting](TROUBLESHOOTING.md) page if a game drops.
