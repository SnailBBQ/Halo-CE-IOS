# M2.6.77 — A corrected address-space report, and what the first real one shows

Regular app 0.2.77 / 2677. The Mod Test app derives its version from it (0.2.77.1 / 267701). The engine is as in M2.6.76 (OpenCE build 125). Nothing here has been built on Apple hardware or tested on a device.

## What the log showed

This is the first address-space map from a free-account install: an iPhone 14 Plus (iOS 16.2, 5.5 GiB of RAM) running the Non-Jailbreak Version signed with Sideloadly.

- **Signing:** `extended-virtual-addressing` and `increased-memory-limit` absent; `get-task-allow` present. Making a writable page executable was allowed (that does not prove the game's code would run).
- **The process may use 4.007 to 15.375 GiB**, which is 11.37 GiB.
- **Free blocks inside that range:** 4.875 GiB (from 10.5 GiB to the limit), 1.47 GiB, 1.28 GiB and 0.24 GiB.
- **Why the game cannot start:** it needs one 4 GiB window aligned to 4 GiB. The nearest, 12 to 16 GiB, would end **640 MiB past the limit**. Every route to it was refused: the 8 GiB reservation, 24 fixed windows, and the system's own aligned search (`KERN_NO_SPACE`).
- **What does fit:** a 4 GiB block with any alignment. The largest single reservation that worked was 4 GiB, and 6 GiB did not.

## A mistake in the report, corrected

The M2.6.76 report printed "completely free 4 GiB-aligned 4 GiB windows: 12". That was wrong. The system also maps things far above the process's own limit, and the report counted the gaps between them as free. It now ignores everything beyond the process range, and it adds a line for free blocks of at least 4 GiB with any alignment (1 here, the 4.875 GiB one). A new test uses this device's shape, and it fails if the clipping is removed. The boot line also no longer carries a stale version number.

## Free and paid accounts

The documentation now says what the evidence supports. A free Apple ID cannot run the game through Sideloadly, AltStore or SideStore, as far as the one log shows. People with a paid Apple Developer account may be able to sign the regular app with the two capabilities and get it to start. We have not tried that, and this project does not require paid accounts, build around them or support them. See [Install](../../docs/ios/INSTALL.md#sideloading-with-free-and-paid-accounts).

## An idea that needs an audit (not started)

The guest does not use all of its 4 GiB. Today it uses the contiguous window (from 0x80000000), the image (0x88000000), a 768 MiB heap (0xA0000000 to 0xD0000000), and the boot block and stacks above that, up to about 0xEE000000.

At a base of 12 GiB, this device would hold guest addresses up to 0xD8000000. The only things above that are the thread stacks, the boot block and the main stack, which the runner chooses and could place lower. If that holds, the existing addressing rule (a 32-bit pointer is the low half of the real pointer) could work with a window of about 1.4 GiB instead of 4 GiB, with no change to how the code is converted.

It needs the image size and the thread stacks measured, and other devices and iOS versions will have other limits, so a window would have to be planned from each device's own map. It is a free route, unlike a paid account, but it is unproven, and it is not part of this update.

## Checks

- The analyzer test passes at both optimization levels and under the sanitizers, and fails without the fix.
- The full suite passes.
- Nothing about the engine, the build or the signing changed.
