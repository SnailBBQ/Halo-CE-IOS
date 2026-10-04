> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# M2.6.45 — Settings and launch presentation

October 3, 2026. Device validation is required after the build succeeds.

- Classic Xbox Y uses white lettering. PlayStation face symbols are centered vector shapes with consistent size and stroke, independent of font baselines. Input mappings are unchanged.
- Multiplayer connection information is a compact status row with tunnel ping, connected peers, current network map and game mode. It refreshes every two seconds while Settings is open; Refresh updates immediately. Unknown/stale map information shows a dash. This does not change peer timing or the network protocol.
- Hosting already writes the active invite to `game_invite.txt` in the selected Files/iCloud folder, falling back to Documents/Halo. The host card now explains this. Ending hosting clears only this app’s owned code; incoming PC codes remain protected.
- Preset cheat recipes activate on entry into solo campaign or selection of another preset during campaign. One-shot powerups and weapon requests run once per activation, not on every settings change or frame. Requests wait for a living local player if the intro has not created one yet, and are discarded on map changes or multiplayer entry. Multiplayer and app launch keep runtime cheats off. Saved recipes remain available. The redundant Apply preset button is removed.
- Display → Touch controls opens the drag-to-edit touch layout, also accessible from Controls. Its toolbar uses two compact rows for selection, size, visibility, opacity and resets. Game HUD/FPS customization has a separate, explicitly named entry.
- Maps can read stock menu pictures from the installed `ui.map` by following map-selection widget bitmap references. Parsing and decompression run outside the UI/game thread, with bounded file/tag/texture ranges. Custom thumbnails override extracted images. Unsupported/custom layouts retain fallback images; the recognized maps directory and engine loading path are unchanged. No Mods manager is introduced because menu image extraction is supported; arbitrary tag overlays and load-order management would require a separate engine integration.
- The launch screen uses a neutral library card instead of the green diagnostic terminal. Import guidance, preparation status, import progress and Start Halo are presented clearly. Boot diagnostics remain accessible through Logs. The app waits for an explicit Start Halo even with maps already installed.
- Advanced orders Restart Game above Quit Game. Restart remains a **cold process restart**: confirm, reopen the app, then return to Start Halo. A true in-app restart is not implemented; reinitializing the arena without a complete worker/network/audio/renderer teardown risks corruption. The confirmation states this behavior.

## Validation

Local settings, campaign gate, powerup and guest-build configuration tests cover the preserved engine behavior. CI additionally executes the actual Foundation settings store to verify automatic recipe activation, one-shot edge behavior and multiplayer clearing. The actual thumbnail parser is tested with synthetic compressed caches for decoding, bounded references, malformed images, oversized expansion and truncation. The normal device build checks UIKit and guest import integration.

## Device checklist

1. Import or retain existing maps; check launch layout, disabled Start without ui.map, import progress and manual Start with maps available.
2. Check white Xbox Y and centered PlayStation symbols at standard/resized button sizes; edit touch controls from Display and Controls.
3. Configure a campaign recipe, enter campaign, switch presets, and confirm actions occur once. Enter/host multiplayer and verify all active cheats clear.
4. Host/join from PC, check map/mode/status auto refresh, and confirm the chosen iCloud game_invite.txt contains only the current supported code.
5. Open Maps and compare extracted stock pictures with the original menus. Unsupported formats/custom maps should show a fallback and allow a custom picture.
6. Confirm Restart’s dialog describes closing/reopening; on reopening the clean Start Halo screen appears. Check Quit remains below Restart.

Resolution, static-pointer conversion, signal fallback, rendering mirrors, audio channels and multiplayer protocol are unchanged.
