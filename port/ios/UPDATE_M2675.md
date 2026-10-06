# M2.6.75 — OpenCE build 128, and repairs to the previous update

> **Partly superseded.** The OpenCE build 128 part was replaced by build 125 in [M2.6.76](UPDATE_M2676.md), for cross-play with current PC builds and to drop the untested texture and vertex rework. The repairs in the first section stand.

Regular app 0.2.75 / 2675. The Mod Test app derives its version from it (0.2.75.1 / 267501). Nothing here has been built on Apple hardware or tested on a device.

## Repairs to M2.6.74

One mistake was mine. My merge script converted line endings in files it copied from upstream, including binary ones, so two HUD sheets (`hud_unit_backgrounds__6.png` and `__7.png`)
lost a valid PNG header, and the asset-embedding step rejects such a file.

- **Extent:** of the 274 binary files in upstream build 115, only those two were damaged, and both were intact before my merge. They are restored to upstream's exact bytes. The
  replacements made in the meantime had the same sizes but differed from upstream in about 0.1 to 0.4 percent of their pixels.
- **Protection:** `.gitattributes` now marks binary files (PNG, JPEG, Ogg, fonts and others) so no tool converts them. It deliberately has no `text=auto`, which would rewrite this
  repository's mixed line endings. The merge tool now copies binary files byte for byte.
- **A test:** `test_ios_asset_integrity.py` checks every PNG's chunks and checksums, the encoding the embedded HUD and title sheets require (8-bit RGBA, not interlaced, within 8192 pixels),
  every JPEG's markers and the `.gitattributes` rules. It rejects exactly the damage that happened, and it runs in the quick suite.
- **Sound gain clamp:** the edit made after M2.6.74, which clamps out-of-range sound gains (and treats not-a-number as 0) so a bad sound tag no longer halts a checked build, is now inside
  `HALO_IOS_GUEST`. Behavior on iOS is the same; every other build is upstream's text again. Its declarations stay before statements.
- **App icon:** the artwork is by ORION, used with ORION's permission, and is not covered by the repository's CC0 dedication. The README and the public-release page say so.

## OpenCE build 128

This merge had its exact base: the build-115 archive integrated in M2.6.74.

- **Result:** 47 files taken unchanged, 7 merged cleanly, 5 added (`coop_enemies`, `coop_scripts` and a menu), and two files with conflicts, resolved by rebuilding three functions from
  upstream's new text and re-applying our iOS blocks. No binary file changed.
- **What upstream changed:** online co-op gets friendly-fire modes, extra enemies (per player, or a fixed multiplier), public or private listing, new Server Setup items, and enemy and script
  synchronization between players, with related changes to actors, damage, objects, breakable surfaces, devices, allegiance and AI. There is also more performance work in the Direct3D-to-GL
  layer and the texture cache.
- **Network version 17 (build 115 used 12).** Lobby listings and joins are filtered by this number, so an iPhone on this update and a player on an older build cannot see or join each other. Update
  PC players to OpenCE build 128, or a later build with the same network version. Our host keeps no copy of the number.
- **Texture cache:** upstream now caches each texture's memory-watch generation and still skips the bucket search when a watched page changed. We kept our iOS rules on top: the shortcut is only for
  immutable compressed textures, the bucket search is still the host-side scan, and a changed non-compressed texture is still detected by its content hash. Only the memory-watch part uses upstream's cache.
- **Vertex attributes:** the function now takes a binding and two offsets. Our host call replaces its body as before, using the combined offset.
- **Fragment shader cache:** upstream keeps four recent entries. The iOS build keeps its single entry with the host-side comparison, which is the behavior it had; other builds get upstream's.
- **About screen:** now names OpenCE build 128.

### What was checked here, and what was not

- With the iOS and Mod Test flags off, all 47 changed C files equal upstream exactly, except four that already carried deliberate unguarded edits of ours, and those edits are line for line the same as before.
  **No iOS-only line was lost**, and the merge added no unguarded line anywhere.
- `configure.py` works, and the workflow's patch of `build.ninja` was run against the real Android rules (generated with stand-ins for the NDK and third-party folders) for all four option combinations. It applies, and all 584 guest compile
  commands, including the two new sources, get the guest flags.
- The full suite passes, including the import-coverage guard, so no new host function was needed.
- **Not checked:** nothing here can compile the merged engine for the guest, and the rebuilt texture, vertex and fragment functions are the riskiest part of it. The Apple workflow is the first compile, and a device the first run.

## Device checklist

1. Check that the Apple build compiles. If it fails, the first place to look is the texture cache, `d3d8_gl.c` and the fragment shader cache.
2. Look for wrong or flickering textures, HUD problems (the two restored sheets are the unit backgrounds), and 60 FPS pacing.
3. Play a map with an old and a new build in turn against a PC: expect the old pairing to fail and a matching build 128 pairing to work.
4. Try online co-op with a PC host, including Server Setup.
