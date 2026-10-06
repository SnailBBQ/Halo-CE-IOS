# M2.6.76 — Back to OpenCE build 125, and the checkpoint editor repaired

Regular app 0.2.76 / 2676. The Mod Test app derives its version from it (0.2.76.1 / 267601). Nothing here has been built on Apple hardware or tested on a device.

## Why build 125

- **Cross-play.** OpenCE changes its network version several times a day, and a build only sees games with its own number. Build 125 is network version 16, which is what the maintainer's PC runs; build 128 (M2.6.75) is 17, so the two could not see each other.
- **Less untested engine code.** The rework of the texture cache, vertex attribute setup and fragment shader cache that M2.6.75 had to merge by hand came after build 125. In build 125, `d3d8_gl.c` and `xbox_textures.c` are identical to build 115, so both return, byte for byte, to their M2.6.74 versions with our iOS blocks.
- **The cost.** The co-op script synchronization added in build 128 (`coop_scripts`) and the other co-op, damage and object changes of builds 126 to 128 are gone. Build 125 keeps the earlier online co-op work: friendly-fire modes, extra enemies, public or private listing and the Server Setup items.

## How it was done

A three-way merge from build 128 (the exact base of M2.6.75) to build 125: 24 files taken, 2 removed (`coop_scripts.c` and `.h`), the 2 GL files restored, and 6 files with our edits merged without conflict.

- With the iOS and Mod Test flags off, 27 of the 30 changed C files equal upstream 125 exactly. The other three carry our deliberate unguarded edits, the same 13, 17 and 4 lines as before, and nothing was gained.
- **No iOS-only line was lost.**
- `configure.py` works and the workflow's patch of `build.ninja` applies to the real Android rules for all four option combinations (see the checks below).

## The checkpoint editor

This was **not** caused by build 128. The game state grew from 16 MiB (build 115) to 20 MiB before build 125; builds 125 and 128 both have 20 MiB, so going back to 125 does not fix it.

- **The problem:** the editor only opened files of exactly 16 MiB, so it found none of the new checkpoints.
- **The fix:** the size and base address now come from upstream's own header (`halo_port_capacity.h`), so they follow upstream. The message no longer names a size, and a new test fails if a number is written there again.
- **Older saves:** the game cannot load a save made with other pool sizes (its allocation size checksum differs), so campaign saves and checkpoints made before the larger game state cannot be used, and the editor does not read them. Saves made by the M2.6.75 build use the same sizes as build 125 and may load; that is not verified.
- **Not verified against a real checkpoint.** The test uses a synthetic one. It can also check a real file, if its path is given as an argument.

## What was checked here, and what was not

- The full suite passes, including the import-coverage guard, and the new checkpoint tests pass strict, under sanitizers, and fail when the size is hard-coded again.
- **Not checked:** nothing here can compile the guest. The Apple workflow is the first compile of this tree; the part that changed least from M2.6.74 is the GL code, which is back to the M2.6.74 text.

## Device checklist

1. Check that the Apple build compiles and that About says OpenCE build 125.
2. With the PC on build 125, host a public game from each side and check that the other side's server browser lists it.
3. Make a fresh campaign checkpoint (save progress) and check that the checkpoint editor lists it; edit health and reload.
4. Look for wrong or flickering textures and check 60 FPS pacing, as after any update.
