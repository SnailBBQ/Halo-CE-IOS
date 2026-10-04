> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# M2.6.42 — geometry caching, session cheats and preset editors

Updated October 2, 2026. Based on M2.6.41, Halo CE Universal build 73, protocol 10.

## Device evidence and performance correction

M2.6.41 corrected the multiplayer viewmodel in the supplied screenshot, but gameplay fell to roughly 2–6 FPS while menus remained at 60. The phone's log says client machine 1 timed out, then the server entered postgame; the phone process remained running. Rendering stalls are a plausible contributor, not proof that low FPS alone caused the network timeout. No network timeout is changed in this release.

The upload-every-draw geometry fallback is replaced by exact native byte comparisons against owned snapshots of the requested logical 4 KiB pages. Unchanged pages cause no GPU uploads. Changed pages, same-frame edits, respawns and reused map addresses still upload before drawing through the existing synchronized path. There are no hash collisions to hide a change, no retained live guest pointers and no change to the arena/signal bridge or 640×480 rendering.

Inputs and outputs are arena-span validated; output may not alias geometry. Snapshot allocation is lazy and bounded by the 128 MiB contiguous window. Invalid input/allocation failure falls back to uploading the requested range, preserving correctness. Context initialization frees snapshots; ordinary binding invalidation does not destroy immutable byte comparisons. These are logical comparison blocks, not memory protection pages: 16 KiB VM behavior remains unchanged. Logs add `geometry cache: ... comparisons, ... KiB checked, ... changed pages`. Actual gameplay FPS and visual correctness still require device validation. The earlier guest_glUniform4fv execution fault is not established as resolved.

## Cheats and presets

Active cheat toggles and numeric overrides are session-only. They are cleared on relaunch (including legacy saved toggles), when leaving campaign, and on native invite join/host transitions. The engine continues to enforce campaign/local-player ownership. Non-campaign UI controls are disabled; re-entering campaign never re-enables cheats automatically. Pending actions are cleared at boundaries.

Each of the five control presets has a gear editor for Xbox/PlayStation face labels, all eleven cheat toggles, compact numeric Jump/Speed/FOV entries, Spawn/Apply Active Camo and Overshield, and a selected weapon giver. Recipes persist; active cheats do not. Apply this preset’s cheats in a solo campaign explicitly enables the recipe and queues its one-shot actions once. Selecting a control preset alone does not enable cheats or spawn assets. A bounded sixteen-action queue handles a recipe's multiple one-shot requests, consuming one per game tick; unavailable map assets still report a message.

Default Preset 1 is Classic Xbox UI and Preset 2 is Playstation UI. Existing default names migrate; renamed presets are preserved. PlayStation ×/○/□/△ labels and their colors retain positional Xbox/SDL actions. Asset and preset-weapon choices use a dedicated scrolling list that starts at the top, replacing long alerts that focused the bottom.

## Advanced

Quit Game and Restart Game are above Diagnostics. Both require confirmation. Quit explicitly ends the entire app process. Restart explains that iOS cannot automatically relaunch a terminated app: close for restart, then tap Halo's icon. Unsaved progress is lost. This is manual reopening, not a promised automatic relaunch. Next-launch owned-invite cleanup is still required because provider I/O is asynchronous and force quit may skip final callbacks. Credits sits below About and links to https://github.com/xSkullHD/Halo-CE-IOS.

## Validation checklist

Local/CI regression tests exercise the production mirror plus production native comparison helper: no uploads for repeated unchanged draws, precise changed-page refresh, same-frame changes, reused map memory, invalidation, safe resolver failure, mixed pages, batch/segment bounds and overflow. Settings tests check recipe round trips, runtime-cheat reset, explicit application, numeric bounds and unchanged PlayStation input mapping. The real engine cheat gate is tested across local ownership and multiplayer transitions. CI compiles the recovered guest and native Apple app.

Install HaloCE.ipa version 0.2.42 /2642. Test:

1. Multiplayer: confirm corrected weapons, FPS, repeated respawns and a PC client staying connected for several minutes.
2. a10: acquire/spawn weapons and progress through several rooms; check geometry and FPS.
3. Enable cheats in campaign, return to menu, host/join multiplayer, and relaunch. All active values should reset; recipes should remain saved.
4. Edit both default preset styles, verify face labels/colors and actions; apply a multi-action recipe only in campaign. Verify every choice list starts at the top.
5. Test explicit Quit and the manual Restart instructions; iCloud file cleanup is best-effort until relaunch/sync.

Share fresh logs if corruption, low FPS or another renderer stop persists. A successful build alone is not device validation.
