# Troubleshooting

## Safe Start

If the last start did not finish, the app starts in **Safe Start** and says so in Settings → Advanced. Safe Start turns off sound, internet play, smooth 60 FPS,
hi-res HUD and text, the profiler, the PC menus and the picture options so the game has the best chance of opening. Running for 15 seconds after the first frame marks the launch as successful, so normal options return on the next launch; or
use **Leave safe mode** in Advanced. If Safe Start keeps appearing, share your logs.

## Logs and problem reports

- **Settings → Logs** shows Diagnostics: a **Summary** (including memory) and a **Problems** tab that picks out what went wrong.
- **Settings → Advanced → Share log files** exports the log files from the app's `Documents/Halo` folder, including the boot log, the game log and any crash report.
- **Settings → Advanced → Report a problem…** makes one text file with your device and iOS version, thermal state, Low Power Mode, memory, your settings (never running cheats) and the end of the logs, then opens
  the share sheet. Look through it before you post it publicly.

When you report a problem, include the app version (Settings → Advanced → About), which app you use (regular or Mod Test), the map and what you were doing, the logs or the report file, and a screenshot or recording if you can.

## Common problems

| Problem | What to try |
| --- | --- |
| The app will not open after about a week | A free Apple ID signs apps for 7 days. Re-install or refresh the app in your sideloading tool. Update in place with the same bundle ID and signing identity; back up first and do not delete the app. |
| "Untrusted developer" | Trust your profile in **Settings → General → VPN & Device Management**. For development-signed apps, your installation method may also require **Developer Mode** on iOS 16 or later. |
| **Start Halo** is disabled | `ui.map` is missing or too small. Import it. See [Game data](GAME_DATA.md). |
| Black screen, crash, or the app closes while starting | Open the app again to get Safe Start, then share your logs. |
| A map fails to load | Check that it is an Xbox version-5 `.map`. The library in **Settings → Mods** shows a header check. PC and MCC maps do not work. |
| LAN games are not found | Allow **Local Network** for Halo CE in iOS Settings and put both devices on the same Wi-Fi. |
| A friend cannot join, or you cannot join them | Use compatible protocol versions and matching map content, preferably matching tested Universal builds. An invite only works while that game is running. Try the [iCloud Drive invite method](MULTIPLAYER.md#alternate-way-of-using-invite-codes-icloud-drive). |
| Low frame rate, or the phone gets hot | Use **60 · Smooth**, lower **Render detail**, keep *Lower the frame rate when the phone is hot* on, close other apps, and use the **Performance overlay** to watch heat and memory. |
| Sound cuts out or crackles | **Settings → Audio → Restart audio output**. |
| The first-person weapon or hands look wrong | Try the other options under **Settings → Display → First-person view**, and report which one helps. |
| The touch controls are missing | A controller is connected and *Touch controls* is on Auto. Choose **Always show**. |
| A cheat is greyed out or does nothing | Cheats work only in a solo campaign with a living player. See [Cheats](SETTINGS.md#cheats). |
| The PC menus are awkward with touch | Choose **Xbox menus** in **Settings → Display → Menus** and reopen the app. |
| You are running low on storage | Maps, mods and backups are large. The [Mod Test app](MOD_TEST.md) needs well over 1 GB free. |

## If something is lost

Restoring a [backup](BACKUPS.md) brings back saves, profiles and layouts. A restore keeps a recovery copy of whatever it overwrites.
