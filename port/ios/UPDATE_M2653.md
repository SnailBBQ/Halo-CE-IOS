# M2.6.53 — Universal build 89 and campaign tools

Regular app 0.2.53; separate ModTest app 0.2.53.1. The baseline is Universal build 89, tag `39350fb81fda3bdf08693961d4ff2cece603e7f3`.

## Upstream integration

Reviewed the supplied build-89 source archive against the exact build-84 baseline. All 29 changed/new non-workflow files were integrated, using three-way merges where iOS has changes. There were no upstream deletions or unresolved source conflicts.

- Multiplayer PC-style pause menus gain Settings and host-only End Game. End Game finishes the match while retaining players for the next match; these menus do not stop the network clock.
- Profile Settings saves return correctly when there are no profile changes; widget navigation avoids a deleted widget.
- Enemy-name labels follow motion-tracker range and player filters.
- Unarmed melee and grenades cannot be used from vehicle seats.
- Updated menu/pause artwork, HUD ammo meter artwork and asset-generation tools are included.
- Upstream's workflow changes were reviewed separately. This fork retains main-only official IPA builds, dependent diagnostics, latest-run cancellation and disabled upstream release publication. ModTest remains a separate app and does not build automatically.

## iOS changes

- Startup choices are **Start Halo CE iOS Title Screen** and **Boot Halo to Main Menu**. Automatic startup presents a loading state directly, including after successful map import, instead of briefly showing the ready title screen. Engine loading time still exists; Safe Start retains the title screen.
- Local Network diagnostics publish and browse a temporary Bonjour service. Success and actual error domain/code are shown and logged. This is a diagnostic, not a new discovery protocol. Raw UDP LAN broadcast requires appropriate Apple multicast signing; permission checks cannot bypass that requirement. The existing manual-invite path is preserved.
- New campaign-only tools: Low Gravity, Medusa, separate vehicle/NPC contact hijacking, occupied vehicle health, faction selection, loaded-tag projectile swapping, equipment collection, weapon ring, encounter AI erase, camera teleport, detached flying camera and wireframe rendering. Time scale includes 150%, 200% and 300% as well as slow motion.
- Visuals follows World and contains FOV, camera detachment and wireframe. Detached camera freezes only the player's body using the existing suspension behavior. It restores prior suspension on release and removes the temporary freeze while saving a checkpoint. Wireframe uses bounded triangle-edge conversion because GLES has no polygon-mode wireframe.
- New held modifiers are session-only, gated to the living local solo player, reset when leaving the campaign and available in preset recipes. Cached projectile identifiers are cleared with map/checkpoint lifecycle changes; no live guest pointers are retained.
- Campaign save editing is available in Profiles. It validates the 16 MB Xbox 2342 snapshot, CRC, data-array descriptors, salted object references and inventory. It edits finite health/shields, grenades and existing weapon magazine values, recomputes the CRC and stages the file for next-launch restoration with recovery archives. Guest layout assertions fail compilation if the schema drifts. It does not create new weapon objects or silently install runtime modifiers.
- Campaign saves and Halo player profiles export/restore independently. Temporary map caches and the volatile checkpoint are excluded. Existing archives remain readable, but their temporary files are not restored. On a fresh install, restore the matching Halo profile alongside its campaign checkpoint. Installed maps remain optional, and existing save directories are preserved.

## Supported limits

The equipment and weapon ring actions use the map's configured cheat collections. Projectile swapping can only use already-loaded tags and affects local-player shots. AI erase and faction/body changes can disrupt campaign scripts. Energy weapons may use charge fields rather than magazine ammo.

Infinite Vehicle Boost and Force Skull Modifiers are not exposed: a matching consumable boost/skull system is not established in this recovered engine. Unlock/completion data is in Halo player profiles, not the checkpoint editor. HUD colors, infinite health, gravity, time and camera behavior are runtime settings rather than ordinary checkpoint fields.

## Validation

Local tests pass for campaign gating and one-shot consumption, powerups, reversible world modifiers, settings round trips, bounded wireframe conversion, source/declaration structure, host imports, framework linkage and workflow configuration. The checkpoint mutation/checksum harness passes on synthetic inventory data and a verified memory-only copy of the maintainer's a10 checkpoint. The original backup is unchanged and private test data is not committed.

Apple compilation, the Objective-C archive harness and device gameplay validation remain separate checks. Local tests do not establish launch performance, LAN permission behavior or public-lobby reliability on a signed iPhone.

## Device checklist

1. Update over the existing regular app. Verify maps, profiles and saves remain. Confirm automatic startup uses the loading screen directly, and manual/Safe Start shows the title screen.
2. Test each campaign modifier, release it, die/revert and change maps. Host/join multiplayer and verify cheats clear; relaunch and verify no held cheats remain.
3. Detach camera on foot, fly, save/revert, disable and verify the body resumes. Check scripted cameras, death and vehicle transitions. Verify wireframe can be disabled cleanly.
4. Export campaign saves alone and Halo profiles alone, inspect size and restore each. Reinstall a test copy and restore both. Confirm old backups restore without installing cache files.
5. Edit a checkpoint, reopen and resume it; check finite health, grenades and ammo, then restore its recovery backup. Verify an invalid/truncated checkpoint is rejected.
6. Request Local Network access, accept/deny and read the reported diagnostic. Test LAN discovery with appropriate signing and manual invites without it.
7. With compatible build-89 clients, test public/private invites, join/rejoin, pause Settings, host End Game, vehicle-seat melee/grenades, and motion-tracker name filters.
8. Verify ModTest keeps its separate bundle, storage, invite scheme and large-campaign-map loader. Mod conversion remains paused.
