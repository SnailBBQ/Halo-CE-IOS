# M2.6.74 — OpenCE build 115 and the system's own aligned-window request

Regular app 0.2.74 / 2674. The Mod Test app derives its version from it (0.2.74.1 / 267401). Nothing here has been built on Apple hardware or tested on a device.

## OpenCE build 115

The build-101 archive was not available, so the merge used the Oct 3 upstream snapshot as its base: a three-way merge of that snapshot, this tree and build 115. Changes already
in this tree from builds 98 and 101 are recognized as identical on both sides.

- **Result:** 47 files taken unchanged, 26 merged cleanly, 8 conflicts resolved by hand, 6 files added. Upstream also re-added `.github/workflows/build.yml`, the native-ports
  workflow; it was deleted again. The new `network_coop`, `network_actors` and `coop_spectate` sources are picked up by the build automatically.
- **What upstream changed** (from the diff and its own README): network co-op code and co-op spectating, the difficulty shown in co-op game names, the Map screen's back handling,
  new display options (`display.resolution`, `display.resolution_scaling`, `display.window_size`, and `display.fullscreen` now meaning borderless), lone-gamepad assignment when two
  or more players share a computer, and fixes across interface, objects, units, AI, scripting, camera, effects, rasterizer and devices.
- **Texture binding:** build 115 adopted the same fix this port made for iOS (bind every stage only after all uploads, since an upload can replace the active unit's binding). Its
  samplers are sampler objects, so configuring them before the final bind is equivalent to our order after it. We took upstream's function and kept only our profiling wrapper; our own
  copy of the fix is gone. This is the one place the merge removed iOS-specific code, and the first thing to check for wrong or flickering textures.
- **Kept from our side:** the in-game settings bridge in the menus, the split-routing publish call, the invite hook in `p2p.c`, and the guard that keeps upstream's lone-gamepad logic
  off iOS, which routes controllers itself.
- **About screen:** it said "Halo CE Universal build 89", which had been wrong for many updates. It now names OpenCE build 115.

### What was checked here, and what was not

- With the iOS and Mod Test flags off, 59 of the 68 changed source files equal upstream exactly. The other 9 already carried deliberate edits of ours, and the merge added no new
  unguarded line to any of them.
- `configure.py` works on the merged tree, and the workflow's patch of `build.ninja` was run against the real Android rules (generated with stand-ins for the NDK and third-party
  folders) for all four option combinations: it applies, and all 582 guest compile commands, including the three new sources, get the guest flags.
- All 61 runnable tests pass, including the import-coverage guard, so no new host function was needed.
- **Not checked:** nothing here can compile the merged engine for the guest. The Apple workflow is the first compile, and a device the first run.

## The system's own aligned-window request (Non-Jailbreak Version)

When the 8 GiB reservation is refused, the Non-Jailbreak build now first asks the system to find a 4 GiB window aligned to 4 GiB by itself (`vm_map`, any address, aligned to the
size, no access until committed), and only then tries the fixed windows. It needs 4 GiB of address space where the production path needs 8, and its result is a line in the log either way.

Be clear about what this is. It is the same request the Mod Test app's direct allocation has made since M2.6.62, and a Sideloadly test of that on iOS 16.2 without the memory
entitlements was refused. An independent iOS port reviewed alongside this update makes the identical call. So on that kind of install, refusal is the expected result; the value here
is that the Non-Jailbreak build no longer needs a separate Mod Test build to find out, and that a newer iOS may grant what iOS 16.2 did not.

## Device checklist

1. Install the regular app (TrollStore). Check the menu, `a10`, and the About screen (OpenCE build 115).
2. Look for the places the merge touched: wrong, black or flickering textures; the resolution, aspect and HUD scale; 60 FPS pacing.
3. Try local co-op (touch plus a controller, or two controllers) and the in-game Settings.
4. For multiplayer with a PC, use the matching OpenCE release; mixed builds may not interoperate.
5. Build the Non-Jailbreak Version, install it with Sideloadly, and send `ios-boot.log`. The new line reads "found by the system itself (vm_map)".
