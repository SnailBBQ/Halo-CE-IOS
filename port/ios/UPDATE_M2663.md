# M2.6.63 — Lower-overhead performance diagnostics

Frequent native datum, scene, attribute, uniform and renderer-scan helpers now
sample timing on approximately 1/1024 calls. Overlapping engine sub-phases sample
approximately 1/64 calls. Call, item, fallback and pointer-upgrade counters remain
exact. Full update, render, upload and presentation phases remain fully timed.
Sampled durations are labelled estimates with their sample counts; they are not
exact totals. Validation, guest address translation and renderer reuse checks
are unchanged.

Each heartbeat retains the eight worst successful presentation intervals above
25 ms and at most 250 ms. Longer intervals are counted separately; these may be
loading, background pauses or severe stalls and must still be investigated.
Reports include measured phase durations, intentional frame-cap sleep, drawable
presentation wall time, available map/mode/connection role, tunnel peer count,
reported ping, thermal state and Low Power Mode.

Drawable time includes driver/display waiting and is not a GPU timer. Phase
hooks cover specific work and may overlap; their durations need not sum to the
whole frame interval. Peers are connected machines, not player count. Zero ping
means no useful reported RTT. Network snapshots do not establish the cause of a
slow frame. Native helper timings with zero samples are unavailable estimates.

## Integration and validation

The official and Mod Test apps share these changes and keep separate identities.
Only main automatically builds the official IPA. No changes to signing, guest ELF
loading, pointer mapping, resolution, frame caps or multiplayer protocol.

Native regression tests cover clock-read frequency, unsampled calls, invalid
clock values, bounded slow-frame retention/reset, and actual scene/render helper
validation and outputs. Apple CI compiles the complete guest and iOS host.

## Device comparison

1. Use the same fullscreen 720p setting, map and approximate scene/server load
   as the previous build. Keep the profiler enabled in both comparisons.
2. Play a10 and a busy multiplayer match for several minutes, including effects
   and vehicles. Save boot/game logs after each run.
3. Compare successful frame-interval bins and slow-frame records, full update/
   render timings, profiler clock overhead and thermal state. Helper call counts
   should continue increasing and helper pointer upgrades should remain zero.
4. Check touch/gamepad input, models, map transitions and multiplayer continuity.

This pass removes avoidable measurement overhead. A stable 60 FPS under every
resolution and scene load is not guaranteed; further optimization depends on
these device measurements.
