> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# M2.6.24 bounded renderer helpers

## Evidence and limits

The supplied baseline is about 0.38 FPS in tutorial gameplay, roughly 1.8–2.1 seconds of render CPU time and over 600,000 thread pointer upgrades per render call. Earlier M2.6.22 samples reported:

| Candidate | Observed pointer upgrades per call | Interpretation |
| --- | ---: | --- |
| Vertex preparation | 261–263 | Repeated stream/declaration work; M2.6.23 already moves attribute state into native code. |
| Texture binding/cache | 118–125 | Includes texture lookup/upload; these categories overlap. |
| Texture lookup/upload | 32–33 | Thousands of calls per interval; linked-list lookup and palette hashing are bounded candidates. |
| Index bounds/cache | 59–60 | Many repeated calls; the scan and cache-field accesses can move natively. |

Shader lookup/link and uniform/state setup are also existing measured categories, but a current per-category sample is not available here. They are architectural candidates, not proven top-ranked hotspots. The current input gives an overall M2.6.23 performance assessment; the earlier iCloud log path was no longer available during this iteration. No numerical improvement is claimed before device testing.

These GL setup categories do not explain all of the render total. M2.6.24 adds scene visibility, objects/shadows, structure passes, particles/transparency, lights and interface categories to locate the remaining engine-side work. Their averages are per wrapped call/pass, not per entire frame. They include nested GL work; do not sum overlapping categories.

## Implemented families

1. **Shader cache walks and word hashing:** ordered fragment/program bucket searches and fragment last-key comparison execute natively. Allocations, compilation/linking, GL program binding and cache ownership stay in the existing renderer. The last-key check examines exactly one node; it cannot accidentally follow its next link.
2. **Texture palette hashing and bucket walks:** native lookup preserves the first matching entry, palette variant count, and first stalest variant including tie ordering. Resource decoding, uploads, texel hashing, recent-cache/drop serials and dirty checks remain unchanged. This does not introduce a native texture cache or assume working iOS write tracking.
3. **Index bounds:** a native ordered u16 scan returns min/max, including empty-range 65535/0. iOS rescans rather than trusting its placeholder generation value; changing the index data at the same address is observed. This does not fix the separate existing vertex-mirror write-tracking limitation.
4. **Uniform comparison/update/upload:** comparisons and shadow writes run natively before the original GL upload. Float bits, negative locations and zero-count no-ops are preserved. There is no retained native uniform cache, program binding change, or guest GL-state side effect to reconcile.

## Exact integration points

| File | Functions / purpose |
| --- | --- |
| `port/ios/HaloIOS/halo_render_scan_native.h` | `halo_scan_indices`, `halo_scan_palette`, `halo_scan_hash_words`, `halo_scan_shader`, `halo_scan_texture`: bounded native kernels. |
| `port/include/ios_render_scan.h` | Fixed-width packet layout and two helper declarations; no change to the guest execution ABI. |
| `port/ios/HaloIOS/halo_guest_runner.m` | `ios_render_scan`, `ios_uniform_apply`, import resolution, native counters and expanded phase reporting. |
| `port/linux/src/d3d8_gl.c` | `index_extent`, `hash_words`, `native_shader_find`, `fragment_shader_get`, `program_get`, `uniform_vec4`, `uniform_float`. |
| `port/linux/src/xbox_textures.c` | `palette_hash`, ordered bucket walk in `xgpu_texture_get`. |
| `source/render/render.c` | `IOS_SCENE_PHASE` wrappers around existing calls, preserving call order and non-iOS behavior. |
| `tools/ios_gl_stubs.py` | Register `host_render_scan` and `host_uniform_apply` using the existing host-import mechanism. |
| `tools/tests/test_ios_render_scans.c` | 12,000 differential cases plus malformed spans/cycles and ordering tests. |
| `tools/tests/test_ios_render_adapters.py` | Compile extracted actual host adapters with mock GL/arena, verifying validation, write order and counters. |
| `.github/workflows/ios.yml` | Run the retained tests before building. |

Every packet and complete input/output span is checked through the existing arena resolver. Walkers validate node layout offsets and each whole node, and stop with a diagnostic on malformed spans or lists exceeding 65,536 visited nodes. No output is committed on failed scans. Shader/texture keys have explicit byte/count limits and guest layout assertions. Partially overlapping uniform input/output is rejected because the original memcpy did not support it.

No helper retains a guest pointer or adds a native cache. Renderer invalidation and texture-drop ownership therefore remain where they already were. The signal bridge, pointer-upgrade implementation, page size/protection helpers, static-rewrite settings, 640×480 resolution, audio and networking are unchanged. Arena-span validation does not turn an uncommitted/inaccessible page into readable memory; valid renderer inputs must still refer to committed guest storage, as before.

## Rebuild and test checklist

1. Build from `main` with **Halo CE iOS — Build IPA**. Guest configuration must still omit `--ios-pointer-fastpath`. New tests run before guest compilation.
2. Confirm both guest and Apple host jobs pass. Local C checks cannot replace Apple SDK compilation and device launch validation.
3. Install/re-sign the artifact's **HaloCE.ipa**, preserving the existing bundle ID and maps. Check startup says **M2.6.24**.
4. Run the same menu and a10 tutorial scenes. Confirm intro/skip, advancing simulation, visible scene content and presentation continue.
5. Share the boot/game logs. Compare equivalent scenes, not loading versus tutorial. Check saved-game/checksum warnings separately.

## Expected log shape and acceptance

The new cumulative counters should show nonzero `native scan indices`, `shader cache`, `texture cache`, `shader hash` and `native uniforms` when those paths are used. Palette counts may remain zero for non-palettized assets. Uniform uploads may be fewer than comparisons because unchanged values are skipped.

`invalid native inputs 0` and `native renderer helper thread upgrades: 0` are the expected successful values: the helper bodies touch host-translated spans without guest fault upgrades. Entry/packet creation and remaining guest logic still contribute to the existing phase and heartbeat counts. These counters measure actual helper work; they do not fabricate an estimate of avoided faults.

Index, shader and uniform category upgrade counts should fall where the replaced loops previously ran; texture lookup gains depend on bucket length/palette usage. The decisive result is a lower **render CPU upgrades/call** than the roughly 600,000+ baseline and lower **render CPU ms/call**, with presentation FPS and gameplay progress increasing. No specific percentage or target FPS can be predicted from the current overlapping measurements. If global render cost stays near two seconds, use the new scene categories to select a larger native engine loop rather than treating successful helper execution as success for the overall performance goal.

## Validation performed

Local differential kernel tests passed, as did tests compiling the actual host adapters and actual 32-bit guest wrappers (packet passing, index timing balance, hashing, shader lookup and uniform forwarding). Workflow configuration and documentation checks are also required before commit. Apple build and physical-device correctness/performance remain unverified until the next test.
