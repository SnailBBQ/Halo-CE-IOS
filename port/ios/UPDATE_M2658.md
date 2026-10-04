# M2.6.58 — Texture content checks and frame stability measurements

The supplied a10 capture runs at 1557×720, not 1080p. Most ten-second windows are near 60 FPS. One later window falls to 50.30 FPS with average render CPU time 15.626 ms; texture binding remains a measured CPU cost. Pointer upgrades are already around one or two per render, so another pointer rewrite is not indicated. No crowded multiplayer capture was supplied.

## Changes

Texture content checks reuse an existing hash only after comparing every byte against an owned snapshot. Changed bytes use the original full-content hash, preserving texture change detection. Snapshots are bounded to 32 entries / 8 MiB, at most 1 MiB per texture; smaller than 4 KiB and larger textures retain the original hash path. Allocation failures also fall back to full hashing. No guest pointer is retained. Memory releases invalidate overlapping entries; renderer initialization clears snapshots. The cache is synchronized for renderer/worker access.

Heartbeat logs now report actual successful-present interval counts (up to 18, 25, 33.4, 50 and 250 ms), plus long gaps separately. These expose brief drops concealed by a ten-second FPS average. Texture logs report exact reuse hits and bytes compared/hashed. Wait-heavy presentation samples at 60 FPS include frame pacing and must not be interpreted as pure GPU work.

## Validation and limits

Portable checks cover exact hash identity, every-byte mutations, trailing data, bounded eviction, address overlap, resets and fallback inputs. Apple CI runs the same check and reports an unchanged-texture microbenchmark. The Windows benchmark is slower on its C library's comparison path, so Apple results must be examined before treating this as a performance win. On-device frame measurements remain necessary.

Resolution, simulation, network updates, visual effects, signing, the ELF loader and the PAGEZERO bridge are unchanged. Universal remains build 95. Regular and Mod Test source updates stay synchronized. A fixed 1080p / 60 FPS guarantee is not established.

## Device comparison

Repeat the same a10 area with the same resolution, fullscreen setting and profiler setting. Compare active frame intervals, render CPU and texture exact reuse counts. Then capture a populated multiplayer match (map, player count, resolution and duration). Test explosions, vehicles, HUD/camo animation, map switching and two-player co-op. Report the logs and any rendering regression; do not substitute reduced resolution for this comparison.
