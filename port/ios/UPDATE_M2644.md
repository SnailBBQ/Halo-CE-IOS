# M2.6.44 — Settings, power-ups and backups

October 3, 2026. Based on M2.6.43, including its guest memory-leak fix and crash diagnostics. The user's M2.6.43 test reports working cross-platform multiplayer and nearly all of a10 without graphical glitches. This release does not claim that every performance or audio issue is resolved.

## Campaign power-ups

Active Camo and Overshield have dedicated cards with Infinite, Spawn and Apply controls. Apply Active Camo now uses the normal player power-up timer and the loaded pickup's duration (30 seconds if the asset is unavailable), instead of permanent debug camouflage. Apply Overshield charges once through the existing game function. Halo's overshield is damage-consumable; it is not replaced with an invented universal expiry timer. Infinite replenishes the living local solo player only, stops on release, never persists and cannot run in multiplayer. Infinite options can be saved in recipes; recipes still need explicit campaign activation.

## Customization

Display opens a live editor over the game for FPS, weapon HUD, health/shields/radar, navigation and damage-indicator groups. Position, scale, opacity and visibility can be changed separately or together. Three named HUD recipes and per-group/all resets are included. Draw groups reflect engine ownership, not every individual bitmap: HUD text and special overlays may retain original positions. Unchanged HUD settings use the original quad draw path; resolution and geometry-cache behavior are unchanged.

The existing touch editor adds individual button opacity and reset-selected. Five named touch schemes and existing size/position/hide controls remain. Master volume remains on native output; Music, Dialogue and Effects gain is applied per engine sound class before mixing. This is not a fix for the reported abnormal water loop: reproduce it and compare device logs/audio before changing sound decoding.

Multiplayer displays host/client/connecting status, connected tunnel peers, measured tunnel round trip when available, and a readable last connection event from the current debug log. LAN-only games may have no tunnel ping. A peer count is not a player count. No protocol or timeout changes.

## Maps

Maps opens its own library from the sidebar. Cards show pictures (user-selected thumbnails, with a fallback icon), names, recognized campaign/multiplayer type, file sizes and version-5 Xbox header checks. Header checks do not establish complete asset integrity. ui.map missing guidance is included. Custom maps are labeled multiplayer/custom; no unsupported promise of identifying every scenario from its filename.

Imports selected in Settings are staged and installed at the next launch, before the guest opens map files. Existing startup imports remain available. Maps stay in Documents/Halo/maps. Pictures are stored separately in Documents/Halo/map_thumbnails.

## Backups

Advanced contains Backups above About and Credits. Full default selection includes on-disk saves and profiles (all of Documents/Halo/save), preferences, and touch/HUD layouts and recipes. Maps and thumbnails are optional. Toggle sections for custom export or selective restore. Export uses Files, including iCloud Drive and other providers. The versioned .halobackup file streams contents in 1 MiB blocks with SHA-256 verification, avoiding loading maps into memory. No compression; archives currently support up to 32 GiB. Keep enough free app storage for staging and recovery.

Active invite files, transient networking state, logs and running cheat toggles are excluded. Backups capture saved disk progress, not a live memory snapshot. Restores merge selected files, replace matching names, and preserve unlisted files. Restore applies only on the next launch before game startup. All overwritten files are copied to recovery storage first and a recovery archive is available to export. Failed restores block startup and attempt rollback. Archive traversal paths, symbolic-link destinations, duplicates, wrong format, oversized manifests, truncation and checksum failures are rejected.

## Validation and device checklist

Local settings and campaign gate tests, power-up runtime tests and guest source checks; macOS CI tests the actual Foundation archive/recovery implementation, then compiles the full arm64_32 guest and iOS app. HaloCE.ipa naming is unchanged.

1. Apply Camo once, leave Infinite off, and wait for normal expiry. Damage a one-shot overshield and check it is not replenished. Toggle Infinite on/off in solo; join multiplayer and verify both are off.
2. Test Music/Dialogue/Effects separately in a10 and a multiplayer map; report a clip if the water noise returns.
3. Edit HUD groups/FPS and touch opacity, save named recipes, relaunch and verify settings.
4. Export a maps-excluded backup to iCloud. Restore selected layouts first; verify unrelated preferences remain. Then test a save restore after recording a recovery backup.
5. Import a map/picture, reopen and verify library and original loading paths. Check phone/PC multiplayer status and sustained gameplay performance.
