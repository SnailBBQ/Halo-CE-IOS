# M2.6.54 — Universal build 94

Regular app 0.2.54; separate ModTest app 0.2.54.1. Upstream tag: `d578f88bd0ef447b9039353a3f04affea55295a5`.

## Fixes

- Campaign unarmed melee checks for an available multiplayer weapon before using it as fallback damage/response. This fixes the empty tag-block assertion observed during the a10 cryotube aiming tutorial. It preserves the engine assertion rather than suppressing it.
- Weapon swaps drop the selected weapon, including when a network weapon switch is still in progress.
- Multiplayer automatically picks up a second approved weapon into an empty inventory slot. Clients ready picked-up weapons once the host inventory arrives, with a bounded timeout and without interrupting primary fire.
- In-game scoreboards exclude players who have left; postgame statistics retain their original behavior.
- Server-browser rows show the focused frame. Listings sanitize names and omit names with no valid characters; accented Latin letters use their plain-letter equivalents.

## Integration and validation

All eight changed upstream files were three-way merged against build 89; no upstream files were deleted. Existing iOS rendering, touch controls, checkpoint tools, private invites and multiplayer protocol are preserved. The regular and ModTest apps retain separate identities and storage. Only main builds the official IPA automatically.

Source checks and an Apple workflow build are required. A successful build does not replace device gameplay validation.

## Device checklist

1. Load normal a10 at 720p/fullscreen, climb out of the cryotube, complete the flashing-light test and attempt melee while unarmed. Verify no empty tag-block blue screen, then continue to armed gameplay.
2. Host and join with build-94 clients. Pick up a second weapon, swap while changing weapons, and verify host/client inventories agree.
3. Leave/rejoin and check in-game versus postgame scoreboards. Check browser row focus and lobby names.
4. Verify existing saves, profiles, private invites and settings. Test ModTest separately when built; mod conversion remains paused.
