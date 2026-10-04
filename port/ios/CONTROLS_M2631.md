> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# M2.6.31 — Xbox controller layout, physical controllers, fault hot-spot log

## On-screen controls

The touch overlay is now the original Xbox controller, not generic buttons:

| Control | Guest input | Notes |
| --- | --- | --- |
| Left stick | Move | drag inside the ring; Y grows downwards like SDL |
| Right stick | Look | same; this is what gets you out of the cryotube |
| LT **GRENADE** | left trigger axis | full pull while held |
| RT **FIRE** | right trigger axis | full pull while held |
| LS **CROUCH** | left stick click | |
| RS **ZOOM** | right stick click | |
| A / B / X / Y | face buttons | green, red, blue, yellow, in the Xbox diamond |
| WHITE / BLACK | SDL left / right shoulder | the guest maps these to White and Black |
| D-pad | D-pad | 8-way, slide between directions |
| BACK / START | Back (stats) / Start (pause) | low in the middle |

Multi-touch works: any controls can be held at once. Empty screen areas pass touches through, so the **Show log** button (now top centre) still works. The home-indicator swipe and status bar are suppressed while playing.

## Physical controllers

`GameController.framework` is used, so Xbox, PlayStation and MFi controllers work once paired in iOS Settings. Mapping: A/B/X/Y as labelled (Cross/Circle/Square/Triangle on PlayStation), LB = White, RB = Black, LT/RT analog triggers, sticks and their clicks, D-pad, Menu = Start, View/Options = Back. When a controller is connected the on-screen controls hide; touch and controller are merged (the larger stick deflection wins). The screen no longer dims during controller-only play.

## Fault hot-spot log

Every 10 s heartbeat now prints `pointer faults this interval by function` with the 16 worst functions. Whatever still faults after the arena rewrite shows up there by name, so the next round of fixes can target exactly those functions.

## Build-time changes

- `-ffixed-x15` stays on; the workflow additionally probes clang for a switch that disables compressed jump tables (so the rewrite no longer has to skip functions with big `switch` statements) and logs whether it found one.
- The rewrite now also covers NEON `ld1/st1/ld2...` forms and the runtime library objects (except `guest_start` and `guest_thread`).

## Tests

`tools/tests/test_ios_controls_layout.c` (6 screen sizes: no overlap, inside the safe area, SDL numbering, stick/D-pad math), `tools/tests/test_ios_fault_histogram.c` (4-thread histogram), and the extended `test_ios_arena_fastpath.py`. The Objective-C view and the GameController bridge are compiled only by the macOS job; they have not been built or run yet.
