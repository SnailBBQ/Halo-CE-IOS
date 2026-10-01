# M2.6.29 — object filtering correctness and focused performance measurements

This update repairs M2.6.26 object filtering and synchronizes the desktop workflow with GitHub's M2.6.28 cleanup. It establishes a reliable a10 performance comparison; a numeric FPS gain has not been measured on a device.

## Behavior

- The original rendered-object array and count are never compacted by the engine's filter call. Each shadow callback uses one scratch index immediately before rendering, so earlier callbacks can change later eligibility.
- Normal rendering keeps the original callback list. Invisible parents, child objects and widgets remain eligible for the original renderer's checks.
- The native helper only rejects explicitly shadowless objects on shadow passes. Invisible objects are retained. First-person camera checks and all remaining render logic stay in the guest.
- Invalid layouts, rows, salts or object addresses return to the original callback/diagnostic path. Native output is staged until every requested input is validated; failure leaves indices and output count unchanged. The engine only requests one entry per call.
- Guest compile-time assertions verify the ILP32 object header, datum flags offset and shadowless bit used by the helper. Every layout offset is bounds checked, and every row/object read uses the arena resolver. No cache or live guest pointer persists between calls.

## Measurements

Four overlapping categories now separate `object lighting/cache`, `object lighting refresh`, `object model/widget traversal`, and `object simulation update`. Existing render/update, object discovery/callback timings and pointer-upgrade counters remain. Model/widget timing covers the outermost traversal and includes its children. Timings are per wrapped call, so compare calls and total cost as well as averages; do not add overlapping categories together.

`native shadow filter` reports skipped entries and diagnostic fallbacks separately from ordinary datum fallbacks. `native renderer helper thread upgrades: 0` and `native scene invalid inputs: 0` are still expected. A map with no shadowless entries can legitimately report zero skipped entries.

## Constraints

The shipping workflow does not enable `--ios-pointer-fastpath`; a regression assertion enforces this. Unneeded arena-base publication for that experiment was removed from startup. The PAGEZERO signal bridge, arena memory protection, resolution (640×480), audio and networking are unchanged. Existing experimental converter files remain disabled. The app version is 0.2.29 / M2.6.29, with the same bundle identifier and Documents/maps location.

## Validation

- Existing 30,000 randomized datum/BSP/visibility cases passed.
- Actual extracted native adapter tests passed, including invisible retention, normal/shadow filtering, malformed layouts, late failure without mutation, same-address flag mutation and rejected legacy mask.
- Actual extracted 32-bit guest callback-loop tests passed for repeated normal/shadow passes, unchanged shared lists, invisible retention, callback mutation and late fallback.
- Shipping workflow configuration test passed. Apple compilation and physical-device FPS remain to be checked.

## Device checklist

1. Build **Halo CE iOS — Build IPA** from main, then install/re-sign **HaloCE.ipa**. Confirm M2.6.29 at startup.
2. Repeat the same menu and a10 intro/skip/tutorial route. Check children, widgets and shadows, as well as progression and responsiveness.
3. Capture 30–60 seconds of gameplay plus boot/game logs. Compare render CPU, update CPU, FPS, upgrades and the four new categories in equivalent scenes.
4. Select the next larger bounded native loop from those measurements. This update does not promise a large FPS increase; its priority is correct rendering and useful attribution before larger optimizations.
