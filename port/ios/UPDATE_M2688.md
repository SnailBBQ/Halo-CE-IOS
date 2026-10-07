# M2.6.88 — Custom Edition Maps and native MP4 movie fallback

Regular app **0.2.88 / 2688**. The Mod Test app derives **0.2.88.1 / 268801**. OpenCE remains **build 146** (`314f576515585560ea6b375b0d5b8a02fd8991af`), **network version 22**, with the 20 MiB game-state capacity, Apple OpenGL ES renderer and M2.6.86 Non-Jailbreak Stage-2 flexible-base diagnostics preserved.

## Custom Edition Maps replaces the old replacement-map UI

OpenCE build 146 can load standard Halo Custom Edition cache files beside the Xbox maps, so the iOS map-replacement feature is retired instead of maintaining two competing systems.

- **Settings → Mods → Custom Edition Maps** imports standard Custom Edition **version 609** `.map` files directly into `Documents/Halo/custom_maps`.
- `bitmaps.map`, `sounds.map` and `loc.map` are supported as shared Custom Edition resource caches.
- Optional `<map>.bmp` and `<map>.txt` sidecars are imported with the map for OpenCE's picture/description support.
- Custom Edition maps do not overwrite `Documents/Halo/maps`; the original Xbox library remains separate.
- A map can be disabled without deletion by moving it, plus its picture/description, to `custom_maps_disabled`. Shared resource caches remain active.
- Xbox version-5 maps are rejected from the Custom Edition importer and continue to use the Xbox/disc import path.
- OpenSauce maps remain unsupported, matching OpenCE build 146.
- On the first M2.6.88 launch, an existing legacy replacement-map catalog is unwound before Halo starts: enabled overlays are removed/restored through the old durable journal/base store, then the retired private catalog is deleted. The legacy replacement code remains only for this migration/recovery path and is no longer exposed by the UI.

## User-supplied MP4 fallback for Halo Bink movies

The project still does not ship a Bink decoder or Halo movie assets. Instead, iOS can satisfy Halo's normal Bink requests with user-supplied MP4 files in `Documents/Halo/videos`.

Recognized names are `intro.mp4`, `credits.mp4`, `attract1.mp4`, `attract2.mp4` and `attract3.mp4`, plus `_de`, `_fr`, `_es` and `_it` localized variants. A localized request falls back to the unsuffixed MP4 when needed.

- OpenCE still chooses the movie and controls its Bink playback state/skip rules.
- The iOS guest asks the native host whether a matching MP4 exists and starts it through AVPlayer/AVPlayerLayer.
- The game audio is muted while the MP4 plays and restored when playback ends or is skipped.
- Halo's controller skip input remains handled by the guest. Touch-to-skip is enabled only when the Bink flags allow button-click skipping.
- Looping, event suppression, return-to-main-menu behavior and attract-mode reset remain in the existing Bink state machine.
- A missing/failed MP4 is skipped safely, matching the previous native-port behavior where Bink playback was unavailable.

The four movie host imports are generated only for the iOS guest and are resolved by the native host. With `HALO_IOS_GUEST` disabled, the two touched OpenCE engine files reduce byte-for-byte to build 146.

## Backups

The optional Maps backup section now also covers `custom_maps`, `custom_maps_disabled` and `videos/*.mp4` in addition to Xbox maps and map thumbnails. User-supplied movie files can make these backups large; they remain uncompressed.

## Validation before device testing

Local/static validation must pass the strict build-146 acceptance gate, the Custom Edition/movie wiring test, build identity/workflow checks, existing guest compile regression guards and the portable iOS tests. The Apple/Xcode build and physical-device behavior remain authoritative for AVPlayer presentation and real Custom Edition map compatibility.

## Device checklist

1. Confirm **Settings → Advanced → About** reports M2.6.88, OpenCE build 146/network 22.
2. If upgrading from an install that had replacement-map mods enabled, verify the next launch restores the original Xbox map and the old replacement UI is gone.
3. Import a standard CE v609 map plus any required `bitmaps.map`, `sounds.map` and `loc.map`; verify the map appears in OpenCE's Custom Singleplayer/Custom Multiplayer menus without replacing the Xbox map of the same base name.
4. Disable and re-enable the CE map; verify its optional `.bmp`/`.txt` follow it and shared resources remain active.
5. Supply `intro.mp4` and/or `credits.mp4`, trigger the matching sequence, verify fullscreen native playback/audio, controller/touch skip and normal return to Halo.
6. Remove an MP4 and verify the corresponding movie request skips without crashing.
7. Recheck a normal Xbox campaign start, save/reload and network-version-22 multiplayer after the library changes.
