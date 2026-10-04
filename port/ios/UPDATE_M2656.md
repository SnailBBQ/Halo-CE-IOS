# M2.6.56 — On-device Xbox disc import

This update extends the current M2.6.55 tree. It does not replace the historical M2.6.50 picture/touch update.
Regular app version: 0.2.56 / 2656. Halo CE Universal remains build 94.

## Importing

**Import maps** is unchanged. **Import disc image** on the title screen opens a single `.iso` / `.xiso` in Files,
then extracts Xbox `maps/*.map` into `Documents/Halo/maps`. The C reader runs in-process on a background job;
there is no Python or external extractor on the device. A security-scoped, coordinated read keeps Files access valid.

The XDVDFS reader follows extract-xiso's sector, directory-tree and game-partition behavior. It probes plain and
whole-disc partition offsets, checks both media markers, bounds every read, rejects duplicate/unsafe filenames and
cyclic directory trees, and uses a 256 KB copy buffer. ISO filenames and retail disc revisions are not whitelisted.

All maps must pass Xbox cache v5 `head` / version 5 / `foot` validation. Map build strings must be
NTSC `01.10.12.2276` or PAL `01.01.14.2342`. A supported `ui.map` is required. PC/MCC/Custom Edition images,
wrong-game images, invalid headers and unsupported builds produce readable errors before library installation.
Header validation does not guarantee every map payload is undamaged; the engine still validates its contents while loading.

## Existing maps, cancellation and mods

The user chooses **Keep** or **Replace** when maps exist. Keep adds missing maps only; Replace changes matching maps
and leaves unrelated maps alone. Existing filename casing is preserved. Every file is staged in private storage;
no partially copied `ui.map` becomes visible in the map library.

Progress reports files, percentage and copied bytes. Cancel during extraction removes private staging. Cancel during
installation rolls back renamed originals. A durable journal recovers interrupted installation before restore/mod work
and engine startup. Recovery failure blocks startup rather than loading an inconsistent library.

For an enabled mod, disc replacement updates the preserved base map, queues mod reapplication, and leaves its live
overlay intact until the next launch. Unloading restores the imported original. No guest loader, pointer mapping,
renderer, multiplayer protocol or signing changes are included. Existing `ui.map` launches do not depend on an ISO.

## Files and validation

- `halo_xiso.c/.h`: bounded native C disc reader and streamed extraction.
- `HaloDiscImport.m/.h`: journaled installation, keep/replace, cancellation and recovery.
- `HaloMods.m/.h`: plan original-map replacements together with mod catalog metadata.
- `AppDelegate.m`: Files picker, progress/cancel, conflict choice and startup recovery.
- Xcode source membership, Info.plist, workflow tests and game-data instructions.

`tools/tests/test_ios_xiso.py` builds and exercises the C reader using synthetic NTSC/PAL XDVDFS images at all four
partition offsets, PC ISO rejection, invalid v5, wrong builds, duplicate/cyclic entries, truncated images and cancellation.
`test_ios_disc_install.m` exercises Keep, Replace, cancellation rollback, interrupted-install recovery and enabled-mod
original replacement/unload using the real Foundation install code. Python runs only on the build/test host.

Rebuild the normal IPA with the existing main workflow. Device checks: import an owned retail image from Files;
cancel both early and late; test Keep/Replace with existing maps and an enabled mod; relaunch and unload the mod;
confirm normal `.map` imports and existing-library automatic startup. Real retail device testing remains required.

This product includes software developed by in <in@fishtank.com>.
The extract-xiso license is in `port/third_party/extract-xiso/LICENSE.TXT`.
