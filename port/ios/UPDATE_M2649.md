# M2.6.49 — Halo CE Universal update (PC menus, server browser) and a build fix

Based on M2.6.48. Merged with a newer Halo CE Universal. Nothing here has been compiled for iOS or run on a device; CI compiles
the game and the app.

## The build error in M2.6.48

CI's settings test compiles `HaloSettingsStore.m` with `-DHALO_SETTINGS_TEST`, which leaves out the audio and GL headers. My heat-aware
cap function (`HaloEffectiveCap`) sat in the part that build leaves out, while the code calling it is built both ways. It needs only
Foundation, so it now sits outside that branch, and the test has a stub for the new ambient-gain function.
`tools/tests/test_ios_store_build_modes.py` fails if that mistake is made again (it was checked against the original mistake).

## What upstream changed since build 73

63 files changed and 369 were added (none removed): 333 menu files, an XML parser (expat) that the menus use, and a rewrite of the
multiplayer menu code. Merged by a three-way merge of build 73, our repo and the new upstream: 11 of the 13 files we had also changed
merged cleanly, and the conflicts in `d3d8_gl.c` and `sound_manager.c` were independent additions, so both sides are kept. Every iOS
hook is still in its file (the count of hooks per file is identical), and so are the ported upstream fixes, the cheat hooks and the HUD
and audio hooks.

- **PC menus (the new default)**: the Halo Custom Edition menus: Server Browser, LAN, Direct Link (paste an invite), Create Game for the
  Internet or LAN, Edit Gametypes, and the redrawn profile and settings screens. Upstream's README says many of these are not wired yet;
  that list is out of date, because `menu_functions.c` implements the server browser rows, Direct Link, the server settings and starting a
  game. Settings > Display > Menus chooses PC menus or the original Xbox menus (which keep System Link), read at launch.
- **Safe Start uses the Xbox menus**, so a failure caused by the new menus cannot keep the game from starting.
- **Two new host imports** the key bindings call at start-up, `host_sdl_scancode_name` and `host_sdl_scancode_from_name`. The iOS host has
  no SDL, so `halo_scancodes.h` holds SDL3's key numbers and names (tested). Without them the game would stop when it reads its bindings.
- Not needed: `glMemoryBarrier` (new in the GL list) is only called when not built as Android; our host falls back safely for any GL
  function the device lacks. No setting name we pass to the game was renamed or removed. The build now also compiles the XML parser
  into the game; the CI patch test passes against upstream's new build scripts.
- Upstream also added per-class sound volumes (`sound_manager_port_volume`); they multiply with our Music, Dialogue, Effects and
  Ambient sliders.

## Not known yet

- How the PC menus feel with touch. The on-screen D-pad and A should move and select as before, and dragging moves the pointer, but there
  is no tap-to-click yet. If that is awkward, say so and tap-to-click for menus is the next piece.
- Typing (a server name, a name) uses the game's own on-screen keyboard.
- The menu pictures are decoded when a screen opens; the first open of a screen may be slower.

## Device checklist

1. First launch with the PC menus: main menu, Campaign, Multiplayer.
2. Multiplayer: Server Browser, LAN, Direct Link (paste an invite), Create Game > Internet and > LAN. Check hosting still shows the invite in
   Settings > Multiplayer, and joining from the PC client still works.
3. Settings > Display > Menus > Xbox menus, reopen the app: System Link as before.
4. Settings still opens, the controls overlay still works in the menus.

## Fix 1 (second CI error)

`halo_ios_set_ambient_gain` was defined in the runner and used by the settings store, but not declared in `halo_guest_runner.h`, which the
device build includes. The test build had its own `extern` line, so only the device build failed. `tools/tests/test_ios_header_declarations.py`
now follows each file's real includes (with the test-only branch removed) and fails on a call to a project function that nothing it includes
declares. It was run on the whole tree: this was the only one.

## Fix 2 (third CI error: the link step)

`HaloSettingsViewController.m` makes the invite QR code with CoreImage (`CIFilter`, `CIContext`), but CoreImage was not linked, so the link
step failed with "Undefined symbols". `-framework CoreImage` is now in `OTHER_LDFLAGS` of both configurations (CoreMotion, for gyro, was added
in M2.6.48 and was linked). Two checks now guard this kind of error, both run in CI:

- `tools/tests/test_ios_frameworks_linked.py`: every framework the sources import or name a class or function of must be linked by the project
  (checked against the original mistake; it flags CoreImage and nothing else, and all 10 frameworks in use are linked).
- `tools/tests/test_ios_import_coverage.py`: every host function the game can call (`port/android/host_imports.list`) must be mapped by the
  runner (all 51 are; checked to fail when one mapping is removed).
