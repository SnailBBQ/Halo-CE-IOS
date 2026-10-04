# M2.6.51 — Halo CE Universal build 84

Integrated upstream build-84 (`3304965653692fc2f4cbea84f1bea2bb7d0f2bdd`) into the regular and separate Mod Test apps. App versions are 0.2.51 and 0.2.51.1.

## Changes

- PC menus now use upstream’s public Internet server browser, with signed lobby metadata, Refresh/Join, compatibility filtering and PUBLIC/PRIVATE hosting controls. No separate iOS directory service or Settings browser is added.
- The guest builds Monocypher’s Ed25519 implementation and the upstream lobby/signalling code. Listings travel over existing MQTT brokers; host tombstones and expiry remove abandoned games.
- Upstream join/leave/slot reuse fixes, map-unload fixes, no-map-weapons and unarmed grenade/melee behavior are preserved.
- Making a public game private rotates its invite. The iOS active-invite hook receives the replacement, keeping Settings, sharing and game_invite.txt current.
- Existing iOS display, touch aiming, audio, cheats, HUD, backups, controls and arena execution paths remain. Mod Test keeps its separate bundle, invite scheme, storage and campaign-map limits. Mod conversion remains paused.

## Validation and device checklist

Source/import/build-configuration checks are run locally. Native Apple compilation is performed by each app’s own CI workflow; local checks do not prove device rendering or Internet discovery.

1. Launch both apps with stock maps: menu, campaign a10, touch/controller input, sound and Settings.
2. In PC menus, host a PUBLIC Internet game on iPhone; find/join it from a build 84 PC client. Reverse the roles. Check map/mode/player counts and Refresh.
3. Make a public lobby PRIVATE: verify its removal and the rotated Settings/clipboard/invite-file code; verify the new private invite joins. End hosting and verify listing cleanup.
4. Test disconnect/rejoin, death/respawn and map changes with several players. Check cheats stay off in multiplayer.
5. Test an empty list, lost Internet, incompatible clients, full games and Xbox-menu manual invites.
6. Recheck the previous picture/touch options and Mod Test identity/cache limits.

Public brokers can be unavailable or blocked. Build success is not a claim that cross-network iOS discovery has been device-tested.

## Current verification result

Source structure, all 51 host imports, header declarations, framework linkage, workflow transformation and 1,172 arena-conversion cases passed locally. The upstream signature/listing harness passed (0 failures) using native Windows single-thread adapters; that does not test real network threads. The iOS invite rotation regression test passed. GitHub Actions failed before any build step due to the account billing/spending-limit condition; no new IPA is available yet.
