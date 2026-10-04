# Release notes

The current update is **M2.6.55**. Each update has its own notes in [`port/ios`](../../port/ios), with what changed, the limits that remain and a **device checklist**. Local checks and CI
cannot prove how the app looks or feels on a device, so every note says what still needs a device test.

## Publication status

No iOS release or downloadable release attachment has been published yet. A source milestone is not proof that its IPA passed a device test.

**Source update:** M2.6.55 adds configurable input shortcuts, Settings icon customization, shared in-game preferences, player-profile editing and separate campaign-save imports. Both apps remain on Halo CE Universal build 94. The [official IPA build](https://github.com/SnailBBQ/Halo-CE-IOS/actions/runs/37192857268) passed. Device validation is still required.

## Recent updates at a glance

| Update | Highlights |
| --- | --- |
| M2.6.55 | Input shortcuts, icon customization, Jetpack Jump thrust, shared settings and separate save/profile imports. |
| M2.6.54 | Universal build 94: campaign melee, weapon pickup/swap, scoreboard and browser fixes. |
| M2.6.52 | Settings organization, optional 1080p, draggable performance overlay, LAN permission check and external save backups. Apple/device validation pending. |
| M2.6.51 | Universal build 84: public server browser, signed lobby listings and multiplayer lifecycle fixes. Device validation pending. |
| M2.6.50 | Picture options (4:3, widescreen, fullscreen; three render-detail levels), opt-in touch aiming, AirPlay mirroring guidance. |
| M2.6.49 | Updated to the newer Halo CE Universal: the PC menus (Join Game, Create Game, Direct Link), a Menus choice in Display, new engine imports. Build-error fixes. |
| M2.6.48 | Collapsible Cheats sections with slow motion, AI ignore, jetpack, checkpoints and teleports; left-handed layout, toggle crouch and zoom, gyro, controller remap; heat-aware frame cap and performance overlay; Ambient volume; recent games and QR; Profiles; problem report; custom and chroma accent colours; map library ordering. |
| M2.6.47 | Options (settings button size, accent colours); new Black and White button icons; map picture polish. |
| M2.6.46 | Movable settings button, the Mods library, HUD recipe per control scheme, PlayStation L2/R2/L3/R3. |
| M2.6.45 | New launch screen, direct boot, host-invite file explained, preset recipes applied on entering the campaign. |
| M2.6.44 | Timed power-ups, live HUD editor, Music/Dialogue/Effects volumes, connection status, backups. |

## Every update

| Update | Title | Notes |
| --- | --- | --- |
| M2.6.54 | Universal build 94 campaign and multiplayer fixes | [notes](../../port/ios/UPDATE_M2654.md) |
| M2.6.53 | Universal build 89, campaign tools and checkpoint editing | [notes](../../port/ios/UPDATE_M2653.md) |
| M2.6.52 | Settings organization, 1080p and external save backups | [notes](../../port/ios/UPDATE_M2652.md) |
| M2.6.51 | Universal build 84 and public server browser | [notes](../../port/ios/UPDATE_M2651.md) |
| M2.6.50 | Picture options and touch aiming | [notes](../../port/ios/UPDATE_M2650.md) |
| M2.6.49 | Halo CE Universal update (PC menus) and build fixes | [notes](../../port/ios/UPDATE_M2649.md) |
| M2.6.48 | Settings polish, cheat sections, controls, display, audio, multiplayer, profiles, diagnostics | [notes](../../port/ios/UPDATE_M2648.md) |
| M2.6.47 | Options and visual polish | [notes](../../port/ios/UPDATE_M2647.md) |
| M2.6.46 | Settings access, profiles and mods | [notes](../../port/ios/UPDATE_M2646.md) |
| M2.6.45 | Settings and launch presentation | [notes](../../port/ios/UPDATE_M2645.md) |
| M2.6.44 | Settings, power-ups and backups | [notes](../../port/ios/UPDATE_M2644.md) |
| M2.6.42 | Geometry caching, session cheats and preset editors | [notes](../../port/ios/UPDATE_M2642.md) |
| M2.6.41 | Geometry mirror coherence | [notes](../../port/ios/UPDATE_M2641.md) |
| M2.6.40 | First-person isolation and iCloud invites | [notes](../../port/ios/UPDATE_M2640.md) |
| M2.6.39 | Landscape Settings and shader constants | [notes](../../port/ios/UPDATE_M2639.md) |
| M2.6.38 | Active invites and campaign tools | [notes](../../port/ios/UPDATE_M2638.md) |
| M2.6.34 | Halo CE Universal build 73 | [notes](../../port/ios/UPDATE_M2634.md) |
| M2.6.33 | Sound, multiplayer, Share logs, frame rate | [notes](../../port/ios/UPDATE_M2633.md) |
| M2.6.32 | Game first, audio, touch-look, control schemes, multiplayer, readable log | [notes](../../port/ios/UPDATE_M2632.md) |

## Performance and engineering notes

| Document | File |
| --- | --- |
| M2.6.30 — arena fast path (fault-free guest loads/stores) | [ARENA_FASTPATH_M2630.md](../../port/ios/ARENA_FASTPATH_M2630.md) |
| M2.6.31 — Xbox controller layout, physical controllers, fault hot-spot log | [CONTROLS_M2631.md](../../port/ios/CONTROLS_M2631.md) |
| Memory leak in the guest allocator, and a backtrace for the next crash | [MEMORY_FIX.md](../../port/ios/MEMORY_FIX.md) |
| M2.6.29 — object filtering correctness and focused performance measurements | [PERFORMANCE_M2629.md](../../port/ios/PERFORMANCE_M2629.md) |
| iOS performance migration review | [PERFORMANCE_PLAN.md](../../port/ios/PERFORMANCE_PLAN.md) |
| M2.6.27 — Selective iOS pointer fast path (Phase 1) | [POINTER_FASTPATH_M2627.md](../../port/ios/POINTER_FASTPATH_M2627.md) |
| M2.6.24 bounded renderer helpers | [RENDER_PERFORMANCE_M2624.md](../../port/ios/RENDER_PERFORMANCE_M2624.md) |
| M2.6.25 scene traversal update | [SCENE_PERFORMANCE_M2625.md](../../port/ios/SCENE_PERFORMANCE_M2625.md) |
| M2.6.26 object render list prefilter | [SCENE_PERFORMANCE_M2626.md](../../port/ios/SCENE_PERFORMANCE_M2626.md) |

For the earlier development record, see the [engineering history](HISTORY.md).
