> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# M2.6.41 — geometry mirror coherence

The M2.6.40 recording shows obstructed multiplayer first-person meshes, a normally rendered campaign assault rifle/hands, and later corrupted a10 world geometry. CPU pose diagnostics show finite matrices and scale 1.0. Device logs show approximately 60 FPS before an execution fault at guest_glUniform4fv with guest address 0x10. The fault is real, but the logs do not establish whether the weapon cheat caused it. This release does not claim to resolve that separate fault.

## Correctness fix

The contiguous vertex/index GPU mirror trusted memory-watch generations. iOS currently implements those imports as no-ops and always returns generation zero. The mirror therefore reused uploaded geometry indefinitely, including after writes, respawns and map-memory reuse. On iOS, every requested mirror range is now refreshed before drawing. This includes writes within a frame; merely refreshing once per frame would still be incorrect. Live pages use synchronized glBufferSubData, preserving queued draws. Other platforms keep their existing generation-based cache. Mirror bounds checks also reject unsigned range overflow.

This is a correctness fallback with potentially greater upload/synchronization cost. Measure FPS and render CPU again; do not assume the previous 60 FPS persists. A future optimization requires reliable content comparison or write tracking, not treating zero generations as proof of immutability. Resolution, shaders, bone animation, arena rewriting, signal bridge, networking and audio are unchanged.

## App closure

Info.plist requests no background execution mode. iOS terminates the process, including guest threads, when it is swiped away. A suspended app may receive no termination callback. The optional termination callback resets input, requests owned-invite cleanup and records an exited breadcrumb; this is best-effort only. Existing next-launch conditional cleanup remains necessary and preserves a PC-supplied invite. There is no exit() call and no forced termination when switching apps.

## Validation and device test

A regression harness extracts the production mirror implementation and simulates the iOS zero-generation host. It checks repeated changes on the same page within one frame, respawn/map address reuse, mixed pages, a range longer than the 256-page refresh batch, segment crossings, and overflow rejection. CI compiles the arm64_32 engine and native iOS app.

Install HaloCE.ipa (0.2.41 / 2641). Start multiplayer, compare Both/Weapon/Hands/Hidden, die and respawn, then leave and load a10, acquire/spawn weapons and progress through several rooms. Report whether both mesh and world corruption improve, FPS, and any new stop. For another crash, share fresh logs plus last-crash.txt/crash.txt if present and the iPhone Analytics HaloIOS crash report. Test swipe-away and fresh relaunch; distinguish it from simply opening the app switcher, which does not terminate the app.
