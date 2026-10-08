# M2.6.97 — OpenCE build 154

Regular app **0.2.97 / 2697**. The Mod Test app derives **0.2.97.1 / 269701**. The engine moves from OpenCE build 146 (`314f576515585560ea6b375b0d5b8a02fd8991af`, network 22) to **OpenCE build 154** (`544ee497b6c1da195fa4dd9363851074edc63cbb`, taken from the supplied archive's commit stamp), **network version 24**. Game state stays 20 MiB. M2.6.96 (the x27 callee-save guard) passed GitHub Actions before this update.

## What changed upstream (from the supplied tree)

The archive differs from build 146 in about 120 paths. Seen in the files themselves (upstream commit messages were not available):

- Visibility-test counters are now copied by the GPU at the end of each frame and read two frames later, instead of stalling on the counters (`host_gl_read_buffer`). **This changes a host import**, see below.
- More tag-validation checks (for example non-negative particle radii) and a clamp on the static multiplier of the netcode.
- A joining player's Custom Edition map version is checked against the host's (`cache_files_map_version`).
- New `object_bounds_cache.c` and `powerup_render_bounds.c`, a faster guest `memcmp`, and a `tools/harness` test harness. Android gains mouse capture; HUD layout and menu strings gained a few entries.
- Network version 22 → 24: **cross-play needs OpenCE clients on network version 24.**

## iOS merge

- Files without iOS edits were taken byte-for-byte from build 154 (61 changed, 12 new; the upstream native-port `build.yml` is deliberately not added).
- The 10 iOS-adapted files that changed upstream (`menu_functions.c`, `d3d8_gl.c`, `dsound_sdl.c`, `xbox_textures.c`, `player_control.c`, `weapons.c`, `main.c`, `objects.c`, `bipeds.c`, `game_state.c`) were three-way merged using the flags-off view of the previous tree as the build-146 base. One overlap in `game_state.c` (both sides added declarations at the same spot) was resolved by keeping both. `tools/android_asm_convert.py` was merged against build 136 as base.
- With `HALO_IOS_GUEST` disabled, every adapted upstream file reduces exactly to build 154.

## Host import change

`host_gl_read_buffer_word(buffer, offset)` became `host_gl_read_buffer(buffer, offset, size, data)`. The iOS runner now maps the new name and `halo_ios_gl_read_buffer` copies the range with OpenGL ES 3.0's `GL_COPY_READ_BUFFER`, leaving it unbound and zero-filling on a failed map, exactly like upstream's `host_gl.c`. The old version used `GL_ATOMIC_COUNTER_BUFFER`, which is not part of ES 3.0.

## Non-Jailbreak x27 guard

The Stage-3 allowance is narrowed to the exact forms LLVM was observed to emit at -O0/-O1/-O2/-Os: `stp|ldp x28, x27, [sp, #N]`, the pre-index `[sp, #N]!` and the post-index `[sp], #N`, in either register order, with `sp` as the only base and a literal offset. Near misses (other base, register offset, other partner, 32-bit width, odd writeback) and all x15 use still fail. A new assertion makes the compiler probe fail if LLVM ever stops emitting the pair.

## Validation limits

The full 1,492-object guest build needs the Android NDK and is only run by GitHub Actions. Nothing here is confirmed on a device. Test the **Regular** build first (rendering and visibility tests changed), then the manual Non-Jailbreak build.
