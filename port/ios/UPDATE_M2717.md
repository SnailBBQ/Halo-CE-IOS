# M2.6.117 - map-aware weapon and vehicle spawners

OpenCE remains on **build 235** (network version 29). This iOS-only change discovers weapon and vehicle tags loaded by the current map, so the Cheats pickers can offer compatible Custom Edition assets as well as stock content. It does not change the network protocol.

## What changed

- Weapon Giver and Vehicle Spawner choices are read from the active map's exact `weap` and `vehi` tag groups instead of fixed stock-name lists.
- The pickers display each loaded tag's full name, so custom assets with similar short names remain distinguishable.
- Weapon Giver keeps **Drop in front**, **Replace in hand**, and **Add to backpack** behavior. Vehicle choices spawn in front of the player.
- Player 1, Player 2, and Both targeting continues through the existing campaign action routing. Global cheats remain global.
- Asset tokens are temporary and cleared at map boundaries. A stale selection is rejected with a prompt to reopen the picker.
- Only assets loaded by the current map appear; importing a Custom Edition map does not add its assets to other maps.
- App identity is **0.2.117 / build 2717**; Mod Test is **0.2.117.1**. The iOS build workflow remains manually triggered; no IPA was built as part of this source update.

## Local checks

- `python tools/tests/test_ios_campaign_policy.py`
- `python tools/tests/test_ios_campaign_target_routing.py`
- `python tools/tests/test_ios_build_identity.py`
- `python tools/tests/test_ios_map_load_recovery.py`

The targeting harness checks that map-asset actions apply to the selected local player or each active player under Both. The asset-catalog path checks exact tag groups and map-scoped IDs. C runtime tests run in the Ubuntu diagnostics workflow; this Windows checkout has no C compiler, so the runtime harness could not be executed locally.

## Device checklist

1. On a stock multiplayer map in a solo campaign, open both pickers and confirm stock weapons and vehicles are listed.
2. Load a compatible Custom Edition map containing custom `weap` and `vehi` tags. Confirm those map-specific names appear and spawn correctly.
3. Exercise all three weapon modes, including Add to backpack with both slots occupied and Replace in hand while holding each slot.
4. Test the Player 1, Player 2, and Both targets in splitscreen; a Both selection should give each player the selected weapon or spawn one vehicle per active player.
5. Change maps while Settings is open or after opening a picker. Confirm old selections are rejected and a newly opened picker reflects the new map.
6. Confirm the features remain unavailable in multiplayer and network games, and that an asset missing from the loaded map is not spawned.

This source update has not yet been built into an IPA or validated on a device.
