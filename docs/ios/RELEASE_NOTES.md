# Release notes

The current update is **M2.6.96**. Each update has its own notes in [`port/ios`](../../port/ios), with what changed, the limits that remain and a **device checklist**. Local checks and CI
cannot prove how the app looks or feels on a device, so every note says what still needs a device test.

## Publication status

No iOS release or downloadable release attachment has been published yet. A source milestone is not proof that its IPA passed a device test.

**Latest:** [M2.6.100](../../port/ios/UPDATE_M2700.md) translates guest pointers held in x30 in the Regular/Mod Test (aligned) converter, removing the 16-million-fault audio decode hot spot found in a Regular device log. OpenCE stays on build 155/network 24.

**Previous:** [M2.6.99](../../port/ios/UPDATE_M2699.md) translated x30 guest pointers in the Non-Jailbreak converter (found from the M2.6.98 iPhone log).

**Previous:** [M2.6.98](../../port/ios/UPDATE_M2698.md) integrated OpenCE build 155 (network 24). No host import changed.

**Previous:** [M2.6.97](../../port/ios/UPDATE_M2697.md) (passed Actions) integrated build 154/network 24, updated the `host_gl_read_buffer` import and narrowed the Stage-3 x27 guard.

**Previous:** [M2.6.96](../../port/ios/UPDATE_M2696.md) (passed Actions) kept build 146/network 22 and accepted only x27 host-stack preservation/restoration while rejecting x27 computation, w27 use and all source x15 use.

**Previous:** [M2.6.89](../../port/ios/UPDATE_M2689.md) repaired the first Apple packaging harness failure in `test_ios_mods.m`. [M2.6.88](../../port/ios/UPDATE_M2688.md) introduced the Custom Edition library and MP4 fallback but failed during the Apple packaging test harness. [M2.6.87](../../port/ios/UPDATE_M2687.md) integrated OpenCE build 146/network 22. [M2.6.86](../../port/ios/UPDATE_M2686.md) added Non-Jailbreak flexible-base Stage 2 on the previous build-144 engine.

**Previous engine update:** [M2.6.81](../../port/ios/UPDATE_M2681.md) integrated OpenCE build 138/network 20; M2.6.82 and M2.6.83 repaired the two guest-compile regressions that integration exposed, and M2.6.83 passed GitHub Actions. [M2.6.84](../../port/ios/UPDATE_M2684.md) then added only deeper Non-Jailbreak diagnostics without changing that engine.

**Previous:** [M2.6.79](../../port/ios/UPDATE_M2679.md) is the green baseline-cleanup build: stale version/upstream metadata was corrected, notes-only iOS Markdown no longer starts an automatic IPA build, the mod-cache diagnostics test runs once, and the XISO test driver is warning-clean under GCC and Clang.

**Previous:** [M2.6.78](../../port/ios/UPDATE_M2678.md) makes logs easy to send: Share logs sends one text file, Copy logs is new, and a start history records where a run that stopped without a report ended.

**Previous:** [M2.6.77](../../port/ios/UPDATE_M2677.md) corrected the Non-Jailbreak Version's address-space report and documented free and paid accounts.

**Previous:** [M2.6.76](../../port/ios/UPDATE_M2676.md) went back to OpenCE build 125 (network version 16) and repaired the checkpoint editor for the larger game state.

**Previous:** [M2.6.75](../../port/ios/UPDATE_M2675.md) integrated OpenCE build 128 (network version 17) and repaired two damaged HUD sheets. The build 128 part was replaced by build 125 in M2.6.76; the repairs stand.

**Previous:** [M2.6.74](../../port/ios/UPDATE_M2674.md) integrated OpenCE build 115 and added the system's own aligned-window request to the Non-Jailbreak Version.

**Previous:** [M2.6.73](../../port/ios/UPDATE_M2673.md) took the signed-code experiment out of the Non-Jailbreak Version and added its address-space map.

**Previous:** [M2.6.72](../../port/ios/UPDATE_M2672.md) made Non-Jailbreak a signed-code build. Removed in M2.6.73.

**Previous:** [M2.6.71](../../port/ios/UPDATE_M2671.md) added that signed-code path as its own SideStore checkbox. Superseded by M2.6.72.

**Previous:** [M2.6.70](../../port/ios/UPDATE_M2670.md) builds Mod Test from `main` (tick it in Actions). It removes the `ios/modtest` branch, the profile-guided build option, and the workflow that built the Linux, Windows and Android ports. Those ports stay on Halo CE Universal.

**Previous:** [M2.6.69](../../port/ios/UPDATE_M2669.md) adds a manual Non-Jailbreak Version build of the official app, with address-space and JIT diagnostics and a fixed-window fallback. Ordinary builds are unchanged; it has not been built or tested on a device.

**Previous:** [M2.6.68](../../port/ios/UPDATE_M2668.md) clarifies checkpoint identity and ammo pools, with higher finite health, shield and grenade limits.

**Previous:** [M2.6.64](../../port/ios/UPDATE_M2664.md) adds per-call OpenGL wall-time reporting and campaign map names to the performance log. It measures only and has not been built or tested on a device.

**Previous:** [M2.6.63](../../port/ios/UPDATE_M2663.md) lowers the cost of the diagnostic clocks and adds worst-frame reports; no measured FPS gain is claimed.

**Previous:** [M2.6.62](../../port/ios/UPDATE_M2662.md) adds a button-based shortcut editor, clearer cheat summaries, grenade giving, organized controls and corrected gyro yaw. Allocation testing now uses the existing Mod Test app.

**Previous:** [M2.6.60](../../port/ios/UPDATE_M2660.md) preserves held touch and controller input during unrelated settings synchronization.

**Previous:** [M2.6.59](../../port/ios/UPDATE_M2659.md) adds signing-capability and memory-allocation diagnostics without changing the working runtime.

**Previous:** [M2.6.58](../../port/ios/UPDATE_M2658.md) adds exact texture-content reuse and frame-interval measurements; device performance validation remains required.

**Previous:** [M2.6.57](../../port/ios/UPDATE_M2657.md) integrates Universal build 95 and local two-player split-screen campaign co-op. Touch plus one controller or two controllers are supported. Device validation remains required.

**Previous source update:** [M2.6.56](../../port/ios/UPDATE_M2656.md) adds on-device Xbox disc import with validated staging, Keep/Replace, progress, cancellation and interrupted-install recovery. Import maps and mod-original restoration are preserved. Both apps remain on Halo CE Universal build 94. Disc-import device validation is still required.

## Recent updates at a glance

| Update | Highlights |
| --- | --- |
| M2.6.100 | Regular/Mod Test converter: guest pointers held in x30 are translated, so the audio ADPCM decode no longer takes ~16M SIGSEGV-bridge faults; frame-rate fix from the Regular device log. |
| M2.6.99 | Non-Jailbreak converter: guest pointers held in x30 (reused link register) are translated; found on-device from the M2.6.98 log. |
| M2.6.98 | OpenCE build 155 / network 24 integration; no host import change. |
| M2.6.97 | OpenCE build 154 / network 24 integration; `host_gl_read_buffer` import update; Stage-3 x27 guard narrowed to exact LLVM forms. |
| M2.6.96 | Stage-3 reserved-register guard hotfix: allow only LLVM's 64-bit x27 callee-save preservation/restoration through the real host stack; all computational x27/w27 and source x15 uses remain fatal; runtime ABI unchanged. |
| M2.6.95 | Stage-3 converter hotfix: support valid AArch64 register-offset guest memory forms exposed by the real OpenCE compile (`[Xn, Xm]`, LSL/SXTX, UXTW/SXTW), with assembler regression coverage; runtime ABI unchanged. |
| M2.6.94 | Non-Jailbreak real-guest flexible-base Stage 3: x27 arena-base ABI, fail-closed assembly rewrite, real arbitrary-base guest arena, flex ELF marker and phases 600–609. M2.6.93 Stage 2 passed on iPhone 14 Plus; Stage 3 Actions/device validation pending. |
| M2.6.93 | Non-Jailbreak workflow hotfix: move the arm64 iPhoneOS `xcrun`/symbol preflight from Ubuntu to the macOS app job. Runtime unchanged; Non-JB Actions/device validation pending. |
| M2.6.92 | Non-Jailbreak Stage-2 Apple link hotfix: use `sys_icache_invalidate()` for the arbitrary-base RX canary and preflight the real arm64 iPhoneOS object for forbidden `__clear_cache` lowering. Regular runtime unchanged; Non-JB Actions/device validation pending. |
| M2.6.91 | Apple host-link hotfix: link CoreMedia for the MP4 fallback's `kCMTimeZero` use and extend the framework dependency audit. Runtime behavior unchanged; Actions/device validation pending. |
| M2.6.90 | Second Apple packaging-test hotfix: rename the final `Marker` helper in the disc-install harness and add a suite-wide collision guard. CE/MP4/runtime behavior unchanged; Actions/device validation pending. |
| M2.6.89 | First Apple packaging-test hotfix: repair `test_ios_mods.m` (`Marker` collision and comma-safe variadic `CHECK`). The Custom Edition migration step passes after this fix. |
| M2.6.88 | iOS Custom Edition map manager replaces replacement maps; user-supplied MP4 fallback for Bink intro/credits/attract movies; legacy overlay retirement; OpenCE build 146/network 22 and M2.6.86 Stage-2 Non-JB diagnostics retained. Actions/device validation pending. |
| M2.6.87 | OpenCE build 146 / network 22 integration; 9 upstream commits, 69 changed/added upstream paths, Custom Edition cache/map loading and validation, menu listing, missing-map reporting and hostile-map hardening; M2.6.86 Stage-2 Non-JB diagnostics retained. Actions/device validation pending. |
| M2.6.86 | Non-Jailbreak flexible-base Stage 2: hostile unaligned 4 GiB arena, base+uint32 pointer model, stack/heap/guest-pointer structures, remap, atomics, second thread, import/callback dispatch and RX canary; real Halo guest remains disabled on this path. |
| M2.6.85 | OpenCE build 144 / network 21 integration; 28 upstream commits, 148 changed/added upstream paths, strict 43/43 flags-off equivalence, renderer/co-op/netcode/map-validation/hardening/performance updates; M2.6.84 Non-JB diagnostics retained. Actions/device validation pending. |
| M2.6.84 | Non-Jailbreak execution-boundary diagnostics: guest-arena RW→RX canary, persistent phases 401–418 around `__guest_start`, first-host-import proof, and the existing flexible 4 GiB probe. M2.6.83 is the green build-138 baseline. |
| M2.6.83 | Second build-138 guest-compile hotfix: returns `TRUE` from the host-decoded `BOOL decode_level()` path, adds a return-contract regression check, and keeps OpenCE build 138/network 20 plus strict 43/43 flags-off equivalence. GitHub Actions passed; physical build-138 device validation remains. |
| M2.6.82 | Guest-compile hotfix for M2.6.81: restores iOS-only dependency headers under `HALO_IOS_GUEST`, adds a regression test, keeps OpenCE build 138/network 20 and strict 43/43 flags-off equivalence. Actions/device validation pending. |
| M2.6.81 | OpenCE build 138 / network 20 integration; strict 43/43 flags-off upstream equivalence; first Actions run failed the arm64_32 guest compile before IPA packaging. |
| M2.6.80 | Build identity, automatic engine-change `.halobackup`, reusable upstream acceptance gates, and Non-JB flexible 4 GiB-anywhere feasibility probe. GitHub Actions passed; device validation remains feature-dependent. |
| M2.6.79 | Baseline cleanup: current version/upstream metadata corrected, notes-only build trigger removed, diagnostics loop fixed, XISO test warning cleaned. Device validation pending. |
| M2.6.78 | Share logs sends one text file, Copy logs is new, and a start history keeps where a stopped run ended. Device validation pending. |
| M2.6.77 | The Non-Jailbreak address-space report is corrected; free and paid accounts are documented. Device validation pending. |
| M2.6.76 | Back to OpenCE build 125 (network version 16, matching current PC builds); the checkpoint editor reads the larger game state. Device validation pending. |
| M2.6.75 | OpenCE build 128 (online co-op improvements, network version 17); two damaged HUD sheets restored, binary files protected, sound clamp limited to iOS. Device validation pending. |
| M2.6.74 | OpenCE build 115 (network co-op, co-op spectating, display options); the Non-Jailbreak Version asks the system for an aligned 4 GiB window. Device validation pending. |
| M2.6.73 | Non-Jailbreak Version is a diagnostics build again (signed-code path removed); address-space map in its log; Mod Test version derived. Device validation pending. |
| M2.6.72 | Non-Jailbreak is the signed-code IPA. The separate SideStore checkbox is gone. Device validation pending. |
| M2.6.69 | Manual Non-Jailbreak Version build: address-space and JIT diagnostics and a fixed 4 GiB window fallback; ordinary builds unchanged. Device validation pending. |
| M2.6.68 | Clearer checkpoint identity and ammo fields; 999% vitality and 127-grenade limits. |
| M2.6.67 | OpenCE build 101, co-op/lobby controller improvements and SpringBoard icon identity refresh. |
| M2.6.66 | Looping-sound preemption lifetime fix and reference diagnostics; device retesting pending. |
| M2.6.65 | Universal build 98, broker-file support, split-player lobby routing and in-game Quit. Device validation pending. |
| M2.6.64 | Per-call OpenGL wall-time reporting and campaign map names in the performance log; measurement only. Device validation pending. |
| M2.6.63 | Lower-overhead sampled timing and worst-frame reports in the performance log; no measured FPS gain claimed. |
| M2.6.62 | Button-based cheat shortcut editor, clearer cheat summaries, grenade giving, organized controls and corrected gyro yaw. |
| M2.6.56 | On-device Xbox ISO/XISO map extraction, Keep/Replace, cancellation and mod-original preservation. |
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
