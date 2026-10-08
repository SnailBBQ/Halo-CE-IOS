# Install

## Requirements

- An iPhone or iPad running **iOS or iPadOS 15.0 or later**. The app needs a physical device; the iOS Simulator does not run the engine.
- Your own Xbox *Halo: Combat Evolved* map files. See [Game data](GAME_DATA.md).
- A compatible installation/signing environment (see step 2). Installation alone does not establish engine compatibility; the runtime needs sufficient virtual address space and authorization to execute loaded engine code. No Mac is required for downloading the IPA.
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
as you install it. Tools such as Sideloadly, AltStore or SideStore install the app, but free-account Halo is not yet supported: different devices have stopped at different startup boundaries (see [Sideloading with free and paid accounts](#sideloading-with-free-and-paid-accounts)). Follow your tool's setup instructions. The general process is:

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
2. Use **Import maps** for `.map` files, **Import disc image** for an Xbox Halo CE `.iso` / `.xiso`, or copy maps in with Files. Include `ui.map`. See [Game data](GAME_DATA.md).
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

Use matching tested OpenCE builds and compatible content for multiplayer, so update the app and your PC game together.
See [Multiplayer](MULTIPLAYER.md#compatibility).

## Running both apps

The regular app and the Mod Test app use different bundle identifiers, so they install side by side with separate maps, saves and settings.
Invite links use different schemes (`halo://` and `halomodtest://`), so each app only opens its own links.

## Removing the app

Deleting the app also deletes its maps, saves and settings. Export a [backup](BACKUPS.md) first if you want to keep your progress.

## Sideloading with free and paid accounts

**Confirmed to work:** jailbroken devices. TrollStore installs keep the entitlements the app asks for, so they are expected to work too.

**A free Apple ID (Sideloadly, AltStore, SideStore): not supported.** Device logs now show three useful stock/free-signed memory/execution cases:

- An iPhone 14 Plus on iOS 16.2, signed with Sideloadly, has neither memory entitlement. It has no usable 4-GiB-aligned guest window, but it can reserve one exact 4 GiB span at `0x2A0000000`, offset `0xA0000000` inside a 4 GiB block. M2.6.93's Stage-2 model passed there: globals/stack/heap/pointer structures, decommit/recommit, atomics, a second thread, host imports/callbacks and an RX canary all passed. That result is the basis for M2.6.94 Stage 3.
- An iPhone 16 Pro Max (`iPhone17,2`) on iOS 27.2, also without those memory entitlements, let the system place an aligned 4 GiB arena at `0x7000000000`. That older Non-Jailbreak build loaded the maps, scenario/BSP/global state and real guest ELF and resolved all host imports, then disappeared when control was handed to `__guest_start`. That result shows that address space is not the only stock-iOS blocker.
- An older `iPad7,11` on iOS 18.3.2 had no 4 GiB hole at all: its largest free gap was about 2.03 GiB and `Flexible 4 GiB ANYWHERE` failed. Stage 2 cannot help that class of device; supporting it would require a future sparse/segmented guest-memory design rather than one contiguous 4 GiB arena.

M2.6.96 is the current **flexible-base Stage 3** candidate. M2.6.94 introduced the real-guest path. M2.6.95 added the valid AArch64 register-offset forms exposed by the first Actions attempt. M2.6.96 keeps that ABI and permits only LLVM's harmless 64-bit x27 host-stack save/reload pattern, which the second real guest compile exposed in `scandir.o`. The manual Non-Jailbreak workflow compiles a distinct OpenCE arm64_32 guest with x27 reserved as the arena base and x15 as scratch. If the aligned arena is unavailable but an exact 4 GiB span can be reserved anywhere, that span becomes the real guest arena. The converter rewrites general-register memory accesses and indirect branches and canonicalizes PC/SP/FP-derived C pointers; unsupported forms fail the build. The app verifies a matching guest ABI marker and records phases 600–609 through real ELF loading, import resolution, boot/stack setup, `__guest_start`, TLS and entry into OpenCE `main()`. Stage 2 remains only as a diagnostic if Stage 3 cannot reserve a real arena.

**A paid Apple Developer account (untested):** documentation for other apps says extended virtual addressing is available only to paid accounts, and that you enable it for your own App ID in the developer portal. If you have such an account and one of these tools, you may be able to sign the regular `HaloCE.ipa` with the `extended-virtual-addressing` and `increased-memory-limit` capabilities, so that the app starts the way it does on a jailbroken device. Use the regular app, not the Non-Jailbreak Version, which requests no entitlements by design. We have not tried this. This project does not require a paid account, does not build around one, and cannot support signing problems. If you try it, please share `ios-boot.log` and what you did.

## Diagnosing signing-dependent startup failures

M2.6.59 records the app/version, OS/device, physical RAM, process memory allowance when available, and signed values of `extended-virtual-addressing`, `increased-memory-limit` and `get-task-allow` when optional inspection is available. Unknown is not evidence that a capability is absent. Do not share Apple account credentials or full provisioning profiles.

The app requests both memory capabilities in its entitlements file. An installer must sign using a provisioning profile that authorizes the requested capabilities; adding keys to Info.plist or retaining unauthorized keys does not grant them. App Groups are not requested by this app.

A failed initial 8 GiB virtual reservation now records the underlying allocation error. It happens before map loading and does not mean 8 GiB of physical RAM is needed. An executable-page failure is reported separately with protection flags and the OS error. Memory capabilities alone do not authorize guest code execution. `get-task-allow` alone does not prove that execution authorization is active.

Compare the same diagnostic IPA installed through a known-working environment and the failing signer. Preserve the bundle identity and back up saves before any installer change. Share ios-boot.log, launch-phase.txt, the exact OS version and installer version; redact private paths if needed. Maps do not need to be replaced for this startup comparison.

[GetMoreRam](https://github.com/hugeBlack/GetMoreRam) requests `INCREASED_MEMORY_LIMIT` for an App ID and instructs users to reinstall afterward. It does not request extended virtual addressing or establish guest-code execution authorization. Results depend on Apple account/provisioning eligibility and the installer. A standard-sideloading compatibility claim requires successful device tests, not just an IPA build.

## Stock iOS compatibility test

Use the dedicated **Non-Jailbreak Version** from **Halo CE iOS — Build IPA** on `main`. Leave **Mod Test app** off. This flavor requests no memory entitlements and, in M2.6.96, builds a separate `flexible-base-x27-v1` guest rather than the regular `aligned-arena-v1` guest. It now attempts real OpenCE execution from an arbitrary 4 GiB base when necessary; it does **not** bypass iOS signing restrictions, JIT policy or the requirement for one contiguous 4 GiB span. Export a backup before changing installers or signing methods.

1. In the developer/signing setup, enable **Extended Virtual Addressing** for the
   actual App ID if the account supports it, then regenerate the provisioning
   profile and re-sign. Enable Increased Memory Limit separately if available.
   Ask the signer to preserve authorized capabilities; changing Info.plist is not
   sufficient. Do not assume free/paid account eligibility without checking.
2. On macOS, inspect the resulting app with
   `python3 tools/verify_ios_signing.py /path/to/HaloIOS.app --report-only`.
   This reports signature and embedded-profile booleans, not private identities.
   The installed app's boot log provides a second check after re-signing.
3. Launch and share the logs. If address allocation succeeds but executable memory
   is rejected, follow [SideStore's current JIT guide](https://docs.sidestore.io/docs/advanced/jit)
   for the exact device/OS and try again. JIT enabling is external to Halo; support
   on newer iOS versions can be limited to particular apps. Halo is not yet verified.
   Before that test, turn off **Boot Halo to Main Menu** in Settings so the app
   stays at its title screen. Attach using the compatible external helper before
   pressing **Play Halo CE**. A failed engine launch is not safely retried in the
   same process; do not assume attaching after the failure restarts the engine.
4. Compare with the regular app under the same signing method and record whether
   allocation, engine execution and the first game frame each succeed.

Never share Apple credentials, pairing files or full provisioning profiles.
The supplied IPA's ad-hoc capabilities are checked in CI, but an installer can
change them. Neither a signature inspection nor a paid account guarantees engine
execution. A fully signed native engine without an external JIT step would require
a separate porting effort; it is not implemented in this update.
