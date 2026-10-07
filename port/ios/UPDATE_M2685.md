# M2.6.85 — OpenCE build 144 integration

Regular app **0.2.85 / 2685**. The Mod Test app derives **0.2.85.1 / 268501**. This update moves the engine from OpenCE build 138 (`76addf661f02e2fd090d7b00f9dd12c29e562a9b`, network 20) to **OpenCE build 144** (`76b1898ee14e6fb58e0412acc183da509c10e001`), **network version 21**. The source game-state capacity remains 20 MiB. M2.6.84 is the green GitHub Actions baseline; M2.6.85 still needs its own Apple build and device validation.

## Upstream changes

Build 144 is 28 upstream commits ahead of build 138 and changes/adds 148 upstream paths. The integration includes:

- renderer call-reduction work: sampler-object reuse, desktop vertex-array/layout caching, batched texture binding and stream/declaration reuse;
- co-op fixes for teammate-relative respawn, the campaign scoreboard, player gates/BSP transitions and team movement through level boundaries;
- netcode fixes for resting bodies, killing blows/death state and join-in-progress score reset;
- a co-op-only garbage-collection throttle for many-enemy sessions;
- map-tag validation before loading plus a third upstream hardening round;
- survival/reporting for broken light arrays;
- rendering/performance fixes for cloaked skinned models, water mip rebuilds and CPU visibility reads that no longer stall for GPU results;
- network version 21.

## iOS rebase

The M2.6.84 iOS host is retained. Of the 43 upstream-owned source files containing `HALO_IOS_GUEST` adaptations, 17 changed in build 144. Fifteen merged cleanly. Two required explicit resolution:

- `port/linux/src/d3d8_gl.c`: build 144 split Android attribute streaming from the new desktop vertex-array/layout cache. The iOS native attribute and wireframe hooks are kept only under `HALO_IOS_GUEST`, while the flags-off path is exactly build 144.
- `source/saved games/game_state.c`: build 144 adds checkpoint-revert event logging. The upstream event remains, and the iOS checkpoint-cheat restore hook runs alongside it only in the iOS guest.

Strict promotion now reports **43/43 exact build-144 flags-off equivalence**. The other changed upstream paths are taken directly from the supplied build-144 tree.

## What stays unchanged

- The renderer remains **Apple OpenGL ES**; ANGLE/Metal is not added.
- M2.6.84's Non-Jailbreak exact-4-GiB-anywhere probe, guest-arena execution canary and persistent phases 401–418 remain unchanged.
- The guest architecture remains `aligned-arena-v1` / `ios-guarded-v1`.
- Automatic engine-change protection continues to use the verified `.halobackup` format. Because the OpenCE commit/network identity changes, an install with existing persistent saves should create an engine-change backup before build 144 opens them.
- Mod Test remains isolated in its own bundle/data identity.

## Validation before Apple CI

The supplied build-144 archive matches release commit `76b1898ee14e6fb58e0412acc183da509c10e001`; its source network constant is 21. Local acceptance requires no merge markers, complete host-import coverage, intact iOS guard structure, current build identity and **43/43** exact flags-off equality against the supplied build-144 tree. The existing iOS regression suite and portable C tests are run again before packaging. GitHub Actions remains authoritative for the actual arm64_32 guest compile/link and Xcode app package.

## Device / release checklist

1. Build the **Regular** artifact. Confirm About/logs show **M2.6.85 / 0.2.85 (2685)**, OpenCE **build-144 / 76b1898…**, **network 21**, 20 MiB game state, Regular, aligned-arena-v1, ios-guarded-v1 and Apple OpenGL ES.
2. Install over an existing data container and confirm the automatic engine-change `.halobackup` is created before the new engine opens persistent saves/profiles.
3. Reach the main menu, start `a10`, save/quit/reload a checkpoint and test another campaign map. Build 144 now validates map tags before loading, so map/import failures should be checked carefully.
4. Exercise menus/HUD, first-person weapons, transparent geometry, water, cloaking, dynamic lights and other renderer paths affected by the build-144 performance changes.
5. Test campaign co-op behavior if available: respawn, scoreboard, gates/BSP transitions and many-enemy sessions.
6. Cross-play only with a **network-version-21-compatible OpenCE client**. Check LAN/direct/public browser, host/join, join-in-progress scoring and a normal match.
7. Build **Mod Test** manually and confirm **0.2.85.1 / 268501** and its isolated bundle/data behavior.
8. Build **Non-Jailbreak Version** manually if continuing the stock-iOS investigation. Confirm the M2.6.84 flexible-arena and phases 401–418 diagnostics are still present; this engine update does not enable arbitrary-base execution or claim free-signing support.

Until the Apple build and smoke tests complete, M2.6.85 is a **source-integrated build-144 candidate**, not a confirmed public build.
