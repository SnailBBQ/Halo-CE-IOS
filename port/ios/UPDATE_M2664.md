# M2.6.64 — Naming where the time goes in heavy scenes

Regular app 0.2.64 / 2664; separate Mod Test app 0.2.64.1 / 266401. Universal build 95 remains the baseline. This update only
**measures**: it changes no gameplay, rendering, frame pacing, resolution, signing, allocation or guest-execution behavior, and it
adds no guest import.

## The evidence behind it

Two sets of M2.6.63 logs from an iPhone 14 Plus on iOS 16.2, both at fullscreen 720p (a 1557 × 720 back buffer):

| Session | Windows (10 s) | Frames at 60 FPS pace (≤18 ms) | Average | Median render CPU |
| --- | ---: | ---: | ---: | ---: |
| a10, Low Power Mode on | 70 | 86.3% | 57.2 FPS | 10.4 ms |
| a50 (Truth and Reconciliation), Low Power Mode off | 16 | 99.9% | 59.9 FPS | 5.6 ms |
| Multiplayer (ratrace, bloodgulch), Low Power Mode off | 12 | 99.3% | 59.2 FPS | 5.1 ms |

- In a10, the windows whose render CPU stayed under 8 ms already averaged 59.5 FPS with Low Power Mode on; the 29 windows at 12 ms or
  more averaged 54.4 FPS. What separated them was the cost of the scene. The second session never reached a heavy scene (render CPU
  peaked at 8.6 ms), so it cannot show whether turning Low Power Mode off helps the heavy a10 sections.
- Eleven of the 13 dip windows were at nominal thermal state, so heat is not the explanation.
- In the dips a frame cost about 2 ms of update plus 17 ms of render, with 500–680 draws and scene-object rendering of 4–8 ms (0.2–2.8 ms
  elsewhere). The exact texture check compared about 30 MiB per frame in good and bad windows alike; `memcmp` was roughly 10–23% of
  game-thread samples.
- Time blocked in `mach_msg2_trap` and `__ulock_wait` was 15–26% of samples in the dips and also 15–19% in multiplayer windows that held 60
  FPS. It is a real cost but is **not shown to be the cause**, and the sampling profiler cannot say which call is blocking. The per-frame GPU
  fence (8 slots) and the occlusion-query result read (it checks availability first) were read in the source and do not obviously block.
- The campaign diagnostics reported `map=unknown` because the map name came only from multiplayer network details.

## What changed

- **OpenGL call wall time.** Timing wrappers with exactly the prototype of the OpenGL function they forward to count every call and measure
  how long it took: draws, buffer data, texture uploads, shader compile/link, flush/finish, readbacks, query results and clears, plus the
  frame-fence wait. Rare or possibly blocking calls are timed on every call. Draws and buffer data, which run thousands of times a second,
  are timed on about 1 call in 64, so their totals are estimates and say how many samples back them. Any GL function not listed is resolved
  exactly as before. The wrappers pass every argument through unchanged.
- **Campaign map names.** The last `.map` file the game opened is recorded in the existing syscall bridge. Slow-frame records use the
  network map details when they are fresh and otherwise that name, and say which (`map source=`). It is a hint rather than proof: the menus
  can open other map files.
- **Heartbeat lines.** Each ten-second heartbeat now prints the per-call-type GL wall times, the worst single call of each type and how many
  calls took over 2 ms, and the last map file opened.

## Reading the new lines

```
gl wall time by call type this window (...):
  gl draws                  <calls> calls,  <ms> ms estimated from <n> samples, worst sampled <ms> ms, <n> sampled calls over 2 ms
  gl flush/finish           <calls> calls,  <ms> ms total, worst <ms> ms, <n> calls over 2 ms
map file last opened by the game: a10 (212.4 s ago); fresh network map details are used instead when there are any
slow frame #...: ...; map=a10 mode=0 role=0 peers=0 reported ping=0 ms; map source=last map file opened
```

(The format is shown without numbers; none are claimed here.) A type's milliseconds are wall time **inside** those calls, so they include
any waiting by the driver or GPU; they are not CPU time and not GPU time. Call types overlap the engine's phase timings, so their sum need not
equal the render time. Calls are counted exactly; "worst sampled" for draws and buffer data can underestimate the true worst.

## Not changed, and not proven

Nothing here makes the game faster, and it is not built or tested on a device. It exists to name the call behind the blocked time and to tie
slow frames to a map. Frame pacing, the exact texture-content comparison, renderer validation, the 4-GiB arena and signing are untouched.

## Validation

`test_ios_gl_wait_stats.c` checks exact counts, exact timing of rare calls, 1-in-64 sampling with zero clock reads for unsampled calls,
long-call and worst-call tracking, resettable windows, a backwards clock, invalid categories and no lost updates across threads.
`test_ios_map_name.c` checks which paths give a map name. `test_ios_gl_timing_wrappers.py` extracts the real wrapper block, compiles it
against fake GL functions and checks that all 16 wrappers forward every argument unchanged, are counted, and are resolved only when the real
function exists; it was confirmed to fail when an argument is swapped or a wrapper is left unresolved. Apple compilation and device
behavior are separate checks.

## Device checklist

1. Replay the heavy a10 section from the first test at fullscreen 720p with Low Power Mode off, then on. A run at 480p of the same section
   shows whether the dips follow resolution.
2. Keep each launch's `ios-boot.log` (it is replaced at every launch) and `debug.txt` (it keeps growing across launches) together.
3. Compare, window by window, the gl call-type lines against the frame-interval bins and update/render times.

## Next, once the logs name the cost

The blocked time can then be targeted. The exact texture comparison (about 1.5–3 ms per frame) is the other measured cost; the guest's import
list already contains `host_memory_watch_*` calls (initialize, protect, generation, prepare-write) that look like write tracking, and whether
the renderer can use them for exact dirty tracking needs review. The exact comparison stays until an equivalent is proven. Per-object scene
cost needs profiling inside the guest.
