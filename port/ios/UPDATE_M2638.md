> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# M2.6.38 — active invites and campaign tools

Updated October 2, 2026. Built on M2.6.37 / Halo CE Universal build 73 (network protocol 10).

## Device evidence entering this update

The supplied M2.6.37 logs show a running session, a successful protocol-10 multiplayer join, approximately 3.4 ms of render CPU time, 0.64 ms of update time, about two render pointer upgrades per call, and audio without underruns. The user reports smooth 60 FPS menus. These samples are not a benchmark of every campaign scene. The screenshot confirms severely distorted first-person plasma-pistol geometry despite the earlier rendering fixes.

## Weapon rendering test

The iOS first-person weapon now uses its authoritative animation pose without the added cross-tick bone blending. World and camera interpolation remain enabled; internal resolution stays 640×480. This isolates one suspected source of incompatible poses. It is a testable mitigation, not a device-confirmed diagnosis or repair. Weapon animation advances at the engine's 30 Hz tick rate. Compare the plasma pistol (including charge), assault rifle and pistol, switching weapons, zoom, respawn, vehicles and campaign cinematics. If geometry remains distorted, investigate vertex data and shader skinning rather than widening this workaround.

## Active invite file

`Documents/Halo/game_invite.txt` is created empty at app launch. Hosting start atomically replaces it with the active `halo://join/` link plus a newline. Hosting stop or a guarded engine exit empties it. Clipboard copies neither create nor prolong its lifetime. Starting another hosted game republishes the current supported invite even if the engine does not copy to the clipboard again. No history is stored. Export failures are logged and the old file is removed when possible.

The engine may reuse its token within a running app session; the file still goes empty between hosted games. A forcibly terminated process cannot clean up files at termination: the next launch clears the previous session before starting Halo. A previously shared copy is outside the app's control and no longer joins when its host is unavailable. Build-73 invites have 64 hexadecimal digits; the iOS input validator now rejects obsolete 44-digit links and malformed suffixes.

## Campaign cheats

Settings → Cheats adds:

- Weapon pickup selection: pistol, assault rifle, shotgun, sniper rifle, rocket launcher, plasma pistol, plasma rifle, needler, flamethrower and gravity rifle.
- Vehicle selection: Warthog, Ghost, Banshee and Scorpion.
- Overshield and active-camouflage pickups, plus direct active camouflage.
- One-hit kills for hostile units damaged by the local player; friendly units and the player are excluded.
- Unlimited flashlight battery, no fall damage, rapid fire, no recoil, third person and noclip.
- Jump multiplier 1–10 and local-player movement multiplier 1–5, each with sliders and numeric input. 1 restores normal movement.
- Vertical FOV input: 0 uses the normal setting; 20–90 degrees overrides the unzoomed campaign view and preserves weapon zoom.
- **Bottomless clip** is the clearer name for the existing no-reloading option; saved settings remain compatible. Infinite ammo remains a separate option.

Spawners use only tags already loaded by the current map. They create pickups in front of the player, not a replacement inventory; walk over a weapon to equip it normally. Unavailable assets and failed creation report a message. A living campaign player is required. Rapid fire removes rate and latch delays while preserving charge, heat and weapon state transitions. No recoil removes the firing kick and pushback; projectile spread and the weapon's normal firing animation remain.

Noclip uses the existing flying/no-collision biped physics without changing shared tag data: aim and move, jump to rise, crouch to descend. It does not apply while seated, dead or suspended. Disable it inside clear space. Damage/movement tools recheck local ownership and campaign state at the hook, so a multiplayer transition immediately rejects cached flags. One-shot requests are consumed once and discarded outside campaign. Settings persist; campaign effects do not apply to network or multiplayer games.

## Integration and validation

New guest imports are `host_active_invite` and `host_campaign_options`; both are registered by the iOS stub generator and native runner. The campaign packet is fixed-width, 20 bytes, and its native destination is validated against the guest arena. Spawn work stays on the game thread. The existing arena rewrite, signal bridge, audio, simulation tick and presentation pacing are unchanged.

Local checks: settings round-trip/bounds/backward compatibility, actual campaign-gate harness, source structure with iOS on/off, workflow transformations, and 32-bit syntax checks of all eight changed engine translation units. GitHub Actions also runs the new campaign-gate test. The local syntax check uses Windows compatibility declarations; it is not an Apple SDK build or device test.

Rebuild **both** guest and host from this commit through Actions → Halo CE iOS — Build IPA. Download **HaloCE-iOS**, extract **HaloCE.ipa**, re-sign and install. Test in this order:

1. Launch and verify M2.6.38; compare menu performance and the plasma pistol with cheats off.
2. Host, share the invite file, stop hosting, verify the file is empty, then host again. Verify it contains the same supported link used by Share my invite link. Relaunch and check stale-session cleanup.
3. Test each campaign tool separately, then disable it and verify normal behavior. Check hostile versus friendly targets for one-hit kills; check NPC movement is unchanged.
4. Join a protocol-10 multiplayer session with campaign settings enabled and confirm no cheat effects or delayed spawns apply. Check sound and world/camera smoothing.

M2.6.38 requires CI and device confirmation before calling the weapon problem fixed or the new gameplay tools fully validated.
