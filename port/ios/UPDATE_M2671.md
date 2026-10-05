# M2.6.71 — SideStore build: run the signed game code

> **Superseded.** the SideStore signed-code build described here was removed in [M2.6.73](UPDATE_M2673.md): its extractor rejected the real guest layout, and the address-space reservation it could not help with is what stops a stock install. The notes below are kept as history.

Regular app stays **0.2.70**. This is a manual third app, **Halo CE SideStore 0.2.71**, bundle ID `com.haloceuniversal.ios.sidestore`. It does not replace the TrollStore IPA.

## What changed

SideStore, Sideloadly and AltStore sign with a normal Apple ID. That signature can run code that was inside the IPA. It cannot mark a copied `halo_guest.elf` executable, and it drops `extended-virtual-addressing`.

The SideStore option links the guest's executable bytes into the app's signed `__TEXT` and `vm_remap`s those pages into the arena. Writable data is still copied. The IPA is ad-hoc signed with an empty entitlements file, so a later re-sign is not stripping a capability the binary requires. The 4 GiB fixed-window fallback from the Non-Jailbreak build is included, because the 8 GiB reserve will fail without that entitlement.

The regular Halo CE and Mod Test builds are unchanged. They still load `halo_guest.elf` and still request the two kernel entitlements.

## How to build

Actions → **Halo CE iOS — Build IPA** → Run workflow → tick **SideStore** only. Artifact: `HaloCE-iOS-Sidestore`. Do not combine it with Mod Test or Non-Jailbreak.

Install that IPA with SideStore, Sideloadly or AltStore. Keep the same Apple ID and bundle ID when you update, or the save folder is a different app. TrollStore users should keep installing `HaloCE-iOS`.

## Limits

- A 4 GiB-aligned arena can still fail on older phones (including an iPhone 14 Plus on iOS 16) even after this change. Remap does not create address space. If Play dies before the menu, read `Documents/Halo/debug.txt` for `8 GiB virtual reservation failed` or `SIGNED GUEST:`.
- The SideStore app is a separate install. Saves and maps do not move over from Halo CE unless you copy `Documents/Halo`.
- Invite links from this app use the `halosidestore` URL scheme.
- This has not been installed on a device yet.

## Device checklist

1. Install `HaloCE-iOS-Sidestore` with Sideloadly or SideStore. Do not enable JIT.
2. Import maps or a disc the same way as the regular app.
3. Press Play. The log should contain `SIGNED GUEST: remapped signed app code` and then the menu.
4. If it stops earlier, send `debug.txt`. Do not treat a failed arena reserve as a failed remap.
