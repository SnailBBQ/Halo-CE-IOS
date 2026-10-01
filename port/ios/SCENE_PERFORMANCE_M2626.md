# M2.6.26 object render list prefilter

## Goal

Reduce the number of full guest `render_object` entries on the hot path by
compacting the rendered-object index list in native code before the per-object
callback loop runs.

## Measured baseline (M2.6.25 a10 gameplay)

| Category | Cost | Upgrades/call |
|---|---|---|
| object render callbacks | 117–152 ms | ~41–42 k |
| scene objects/shadows | 122–160 ms | ~43 k |
| update | 330–390 ms | ~120 k |

Discovery is already cheap (3–6 ms). The cost is inside each callback.

## What this change does

`host_scene_filter_objects` walks the rendered-object index list once:

1. Resolves each `object_header_datum` through the existing arena resolver.
2. Follows the guest `datum` pointer to the real `object_datum`.
3. Reads `object.flags`.
4. Drops entries that have `_object_invisible_bit` set.
5. On the shadow pass, also drops entries with `_object_shadowless_bit`.
6. Compacts the index array in place and returns the new count.

`process_rendered_objects` then iterates only the surviving indices.

## Safety

- Same resolver and layout table as the M2.6.25 datum helpers.
- No guest pointer retained across the call.
- On any native failure the guest falls back to the original full list.
- Signal bridge, PAGEZERO, static rewrite, and 640×480 resolution are untouched.

## Files changed

| File | Change |
|---|---|
| `port/ios/HaloIOS/halo_scene_scan_native.h` | `halo_scene_filter_objects` kernel |
| `port/include/ios_scene_scan.h` | New kind + `host_scene_filter_objects` declaration; export `ios_datum_layout` |
| `port/ios/HaloIOS/halo_guest_runner.m` | Host adapter, counters, MAP registration |
| `source/memory/data.c` | `ios_datum_layout` no longer static |
| `source/render/render_objects.c` | Pre-filter call inside `process_rendered_objects` |
| `tools/ios_gl_stubs.py` | New host import name |

## Expected log evidence

- `native scene object list filter: N calls, M items, ...` appears.
- `native scene invalid inputs: 0` and zero unexpected datum fallbacks.
- Lower `object render callbacks` upgrade count and CPU time on equivalent a10 scenes when any objects are invisible or shadowless.
- Menu and a10 progression remain correct.

## Next targets (still bounded helpers)

1. Update-path datum / object iteration (currently ~330 ms / 120 k upgrades).
2. Further bulk helpers inside `render_object` for node-matrix / LOD / lighting setup if the prefilter alone is insufficient.
3. Full static pointer conversion (item 4) when ready for larger architectural change.
