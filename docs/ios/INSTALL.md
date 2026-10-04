# Install

## Requirements

- An iPhone or iPad running **iOS or iPadOS 15.0 or later**. The app needs a physical device; the iOS Simulator does not run the engine.
- Your own Xbox *Halo: Combat Evolved* map files. See [Game data](GAME_DATA.md).
- A way to install an app signed with your own identity (see step 2). No Mac is required.
- Free storage for the app, your maps and your saves. The [Mod Test app](MOD_TEST.md) needs well over 1 GB free.
- On iOS and iPadOS 16 or later, **Developer Mode** may be required for development-signed apps, depending on the installation method (see below).

## 1. Get the IPA

Choose one:

| Option | When to use it |
| --- | --- |
| **Published release** | No iOS release is published yet. When one is available, download its attached `HaloCE.ipa` from [Releases](https://github.com/SnailBBQ/Halo-CE-IOS/releases). |
| **Actions artifact** | Successful packaging runs keep the IPA for 14 days. Open **Actions**, choose a successful run and download the **HaloCE-iOS** artifact. Extract its ZIP to get `HaloCE.ipa`. |
| **Build it yourself** | Use your own GitHub account. See [Build the IPA](BUILD.md). |

The **Mod Test** app is a separate download, `HaloCE-ModTest.ipa` from the Mod Loading Test workflow. See [Mod Test](MOD_TEST.md).

## 2. Sideload it

The IPA is ad-hoc signed, which is not enough for iOS to run it on a device. You re-sign it with your own Apple ID or developer account
as you install it, using a sideloading tool of your choice (for example Sideloadly, AltStore or SideStore). Follow your tool's setup instructions. The general process is:

1. Connect your iPhone or iPad, or follow your tool's wireless setup.
2. Choose `HaloCE.ipa` in the tool and sign in with your Apple ID.
3. Install. The app appears on the Home Screen as **Halo CE**.
4. If iOS reports an untrusted developer, open **Settings → General → VPN & Device Management**, select your developer profile and trust it.
5. If your installation method requires Developer Mode, on iOS or iPadOS 16 or later open **Settings → Privacy & Security → Developer Mode**, turn it on, and restart when asked.

Things to know:

- A free Apple ID signs apps for **7 days**. Re-install or refresh the app in your tool before it expires. Updating in place with the same bundle identifier and signing identity normally preserves data. Do not delete the app first; make a backup before updating.
- Free accounts limit how many sideloaded apps can be active at once. Check your tool's notes if you install both Halo apps.
- Keep the **bundle identifier** the same each time. If your tool changes it, iOS treats the result as a different app with its own, empty data.

## 3. First launch

1. Open **Halo CE**. The first launch creates the app's folders and shows the setup screen.
2. Import your maps with **Import maps**, or copy them in with the Files app. Include `ui.map`. See [Game data](GAME_DATA.md).
3. Tap **Start Halo**. After the first run, the app can start the engine immediately; you can change this in Settings → Controls → *On app launch*.
4. Tap the gear button at any time to open Settings.

The app may ask for:

- **Local Network** access, which lets it find games on your Wi-Fi. If LAN games are not found, check
  **Settings → Privacy & Security → Local Network → Halo CE**.
- **Pasting from the clipboard**, only if you turn on *Join links on the clipboard automatically*. iOS may ask for paste permission.

## Updating

1. Make a [backup](BACKUPS.md) if your saves matter.
2. Install the new IPA over the old app with the same signing identity. An in-place update normally preserves maps, saves and settings; do not delete the app first.
3. Check the version in **Settings → Advanced → About**.

Use matching tested Halo CE Universal builds and compatible content for multiplayer, so update the app and your PC game together.
See [Multiplayer](MULTIPLAYER.md#compatibility).

## Running both apps

The regular app and the Mod Test app use different bundle identifiers, so they install side by side with separate maps, saves and settings.
Invite links use different schemes (`halo://` and `halomodtest://`), so each app only opens its own links.

## Removing the app

Deleting the app also deletes its maps, saves and settings. Export a [backup](BACKUPS.md) first if you want to keep your progress.
