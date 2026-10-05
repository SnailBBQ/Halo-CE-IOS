# M2.6.72 — Non-Jailbreak is the signed-code build

> **Superseded.** the signed-code Non-Jailbreak build described here was removed in [M2.6.73](UPDATE_M2673.md): its extractor rejected the real guest layout, and the address-space reservation it could not help with is what stops a stock install. The notes below are kept as history.

Regular app stays **0.2.70**. Tick **Non-Jailbreak** to build the stock-iOS IPA. There is no separate SideStore checkbox.

The guest text segment starts at `0x88000030`, 48 bytes after the image header, so it is not itself 16 KiB aligned. The signed blob starts at the 16 KiB page base and keeps that offset. `vm_remap` still maps whole pages.

## What changed

M2.6.71 added a SideStore checkbox beside the old Non-Jailbreak checkbox. That old checkbox only added diagnostics. It still copied `halo_guest.elf` and asked iOS to mark the copy executable, which SideStore and Sideloadly cannot do.

The SideStore checkbox is gone. **Non-Jailbreak** now means the signed-code build:

- Game code is linked into the signed app and mapped with `vm_remap`.
- The IPA has no kernel entitlements, so Sideloadly is not stripping something the binary needs.
- Same bundle ID, name and invite link as Halo CE.
- Pointer rewrite stays on unless you turn that box off.

The address-space diagnostics and 4 GiB fallback are still in this build. They only matter if the arena reserve fails.

## How to build

Actions → **Halo CE iOS — Build IPA** → Run workflow. Tick **Non-Jailbreak**. Leave **Pointer rewrite** checked. Leave **Mod Test** off. Artifact: `HaloCE-iOS-NonJailbreak`.

Install that IPA with SideStore, Sideloadly or AltStore. Do not enable JIT. TrollStore users keep the normal `HaloCE-iOS` artifact.

## Limits

A 4 GiB arena can still fail on older phones. Remap does not create address space. If Play dies, `debug.txt` should say either `SIGNED GUEST: remapped signed app code` or `8 GiB virtual reservation failed`. This IPA has not been installed on a device yet.

## Device checklist

1. Install `HaloCE-NonJailbreak.ipa` with Sideloadly or SideStore. Do not enable JIT.
2. Import maps the same way as the regular app.
3. Press Play. The log should contain `SIGNED GUEST: remapped signed app code`, then the menu.
