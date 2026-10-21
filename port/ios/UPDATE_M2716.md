# M2.6.116 - recover from rejected Custom Edition map loads

OpenCE remains on **build 235** (network version 29). This is an iOS recovery and diagnostics update, not an upstream engine promotion.

## What changed

- A rejected map load now cleans up the partial scenario/cache state, clears delayed errors from that attempt, and returns to the main menu instead of entering the blue fatal-error loop.
- The cleanup path no longer tries to deregister vertex/index buffers when a failed map load never installed a valid tag header.
- Map validation remains strict. This does **not** make Guardian H3 or Templo load; it lets the app recover after those maps are rejected.
- The texture-check diagnostic now reports the configured **48 MiB** snapshot budget instead of the stale 8 MiB label.
- Regular app version: **0.2.116**, build **2716**. Mod Test version: **0.2.116.1**.

## Device checklist

1. Open the Custom Edition map list and attempt `Guardian-H3_MultiJugador.map`. Confirm the rejection reason is logged and the main menu returns without a blue-screen hang.
2. Attempt `Templo-En-Guerra_Maurix Mapper.map`. Confirm the geometry validation message remains and the main menu returns.
3. Load Bigass V2 and The Cage again. Confirm successful loads and texture appearance are unchanged.
4. Test Cursed Halo A10 separately; the supplied logs did not establish that this specific map loaded.
5. Check the diagnostic line says `snapshot budget 48 MiB`.

## Not verified here

The source changes have not been compiled against the iOS SDK or run on a physical device in this environment. This update is not proof that the two rejected maps are now playable or that the FPS issue is fixed. The change is limited to safe recovery and diagnostics; rendering performance remains a separate investigation.
