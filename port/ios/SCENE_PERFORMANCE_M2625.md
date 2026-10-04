> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# M2.6.25 scene traversal update

## Measured baseline and attribution

The supplied M2.6.24 logs confirm about 12.3 FPS in the main menu. Early a10 gameplay remains 0.38–0.96 FPS. The final sample reports 1665.6 ms rendering and 480,771 thread pointer upgrades per render call; update averages 691.2 ms and 238,379 upgrades. Native M2.6.24 helpers report zero upgrades and zero invalid inputs.

| Scene category | Final sample | Selected bounded loops |
| --- | --- | --- |
| Objects/shadows | 233.4 ms, 57,482 upgrades/call | Shared datum lookup and next/iterator scans used by object headers and cached render states. `object_get_cached_render_state` uses `data_next_index`/`datum_get`; object rendering and other engine consumers use the same data layer. |
| Structure passes | 82.8 ms, 21,215 upgrades/call | Surface-index sorting, triangle gathering from indices/bitvectors, and contiguous material-range scanning. |
| Visibility | 85.0 ms, 22,827 upgrades/call | Subcluster surface-list dedup/marking and BSP leaf surface-reference filtering. |

These timings are per call/pass and overlap nested drawing. They identify expensive parent paths, not instruction-level attribution proving that any single selected loop accounts for most upgrades. M2.6.25 adds object discovery and object-render callback measurements to distinguish the remaining object work. Large callback-driven object rendering, portal recursion, geometric culling and update logic remain in the guest. A dramatic overall improvement cannot be promised before device measurement.

## Implemented native work

- `halo_scene_datum`: fresh metadata and salt validation; datum lookup/try lookup, next-index hole scans and iterator scans. Guest layout offsets and signature constants are supplied explicitly. No datum is prefetched across an engine callback, and same-address salt/data changes are visible on the next call. Invalid metadata returns to the original guest assertion/diagnostic path. Iterator writeback updates only absolute index and datum index, preserving the previous datum on exhaustion.
- `halo_scene_sorted_triangles`: validate indices, sort using the same pure signed integer ordering as `compare_surface_indices`, then gather six-byte surface vertex triplets. Identical indices make stable-sort order immaterial. The native sort calls no recovered callback.
- `halo_scene_bit_triangles`: traverse selected surfaces in ascending index order; ignore trailing bits beyond the surface count; preserve vertex-index bits and leave unwritten output capacity unchanged. Capacity is checked before any triangle output write.
- `halo_scene_material_run`: preserve the original do/while's mandatory first increment and exact stop at the material end or remaining input boundary.
- `halo_scene_mark`: preserve subcluster list order, duplicate handling and capacity early-outs. Outer frustum tests and cluster ordering stay unchanged.
- `halo_scene_leaf`: filter leaf references through the environment whitelist, deduplicate against the current seen bitset, and preserve first-eligible ordering and partial output capacity.

## Safety and integration

All packets, layouts, metadata, rows, reference arrays, bitsets and output spans use the existing arena resolver. Address products/additions use wide arithmetic before guest address narrowing. Unsafe source/output overlap is rejected for BSP output and visibility lists. Invalid scene inputs abort through the existing host diagnostic path; datum operations preserve the legacy fallback. No native cache or guest pointer persists across calls, so there is no new renderer invalidation state. Updated bitsets, counts, sorted indices, triangles and iterator fields are returned/written into their existing guest locations.

The PAGEZERO bridge, arena runtime, pointer counters, memory-watch/protection functions and 16 KB page behavior are untouched. Static rewriting and register reservation remain disabled. Resolution remains 640×480; audio and networking are unchanged. Arena bounds checks do not commit inaccessible guest pages; valid engine inputs must still name committed storage. On malformed visibility input, already completed bit writes may remain before diagnostic abort, as with the original ordered walk; normal capacity early-outs remain supported.

## Exact changed files/functions

| File | Change |
| --- | --- |
| `port/include/ios_scene_scan.h` | Fixed-width scene packet and helper declarations. |
| `port/ios/HaloIOS/halo_scene_scan_native.h` | Bounded datum, sorted/bitvector triangle, material-run and visibility kernels. |
| `port/ios/HaloIOS/halo_guest_runner.m` | `ios_scene_datum`, `ios_scene_scan`, validation, import registration, six helper counters, 20 timing slots. |
| `source/memory/data.c` | iOS fast branches in `datum_get`, `datum_try_and_get`, `data_next_index`, `data_iterator_next`; guest layout assertions/offset table; original diagnostic paths retained. |
| `source/structures/structure_render.c` | `structure_render_dynamic_triangles_from_bitvector`, `structure_render_dynamic_triangles_from_indices`, inner material run in `structure_render_pass`. |
| `source/structures/structure_visibility.c` | Inner marking loop in `structure_visibility_traverse_subclusters`, reference loop in `structure_visibility_build_surfaces_traverse_leaf`. |
| `source/render/render_objects.c` | Timing wrappers for `find_rendered_objects` and `process_rendered_objects`; callback order unchanged. |
| `tools/ios_gl_stubs.py` | Two imports through the existing guest/host mechanism. |
| `tools/tests/test_ios_scene_scans.c` | 30,000 randomized comparisons, mutation/salts, sort order, duplicate/capacity/trailing behavior. |
| `tools/tests/test_ios_scene_adapters.py` | Compile actual host adapter bodies: span/overlap checks, iterator writeback, fallbacks and counters. |
| `tools/tests/test_ios_render_adapters.py` | Keep the existing M2.6.24 test extraction scoped to its renderer adapter block. |
| `.github/workflows/ios.yml` | Run scene tests before the guest build. |

Version metadata and current status guides are updated to M2.6.25.

## Validation and rebuild checklist

Local randomized kernel tests and actual host-adapter tests passed. Actual 32-bit guest data wrappers compiled and passed layout, salt, mutation, iterator writeback and fallback tests. Existing renderer adapters still pass. These checks do not replace Apple compilation or physical-device testing.

1. Build **Halo CE iOS — Build IPA** from `main`; keep static pointer rewriting disabled. Scene tests should pass before the full guest build.
2. Install/re-sign **HaloCE.ipa** and confirm **M2.6.25** at startup. The bundle ID and Documents/maps location are unchanged.
3. Repeat menu and a10 intro/skip/tutorial scenes. Confirm visible geometry, shadows, normal culling, advancing simulation and presentation. Check moving/animating objects, not just one static view.
4. Share boot and game logs, including the new object discovery/callback categories. Existing persistent-storage checksum warnings still require separate investigation.

## Expected logs

`native scene datum lookup/iteration`, `BSP index triangles`, `BSP bit triangles`, `material ranges`, `visibility surface lists` and `visibility leaf references` should accumulate when their paths execute; not every map/render mode exercises every helper. `native scene invalid inputs: 0` is expected. Datum fallbacks should be zero or explained by calls requiring the original diagnostic path; unexpected sustained growth warrants investigation. `native renderer helper thread upgrades: 0` must remain zero.

Successful performance evidence is lower scene object/structure/visibility upgrade counts and CPU time in equivalent a10 scenes, plus lower overall render/update time and higher presentation FPS while gameplay progresses. This update removes per-element guest reads/comparator calls from the selected loops, but remaining callbacks, culling and GL submissions still contribute upgrades. No exact percentage/FPS prediction is supported by the aggregate measurements. If the scene totals remain high, use discovery versus callback timing and helper item counts to choose the next larger loop.
