# M2.6.55 — Input shortcuts and shared settings

Regular app 0.2.55; separate ModTest app 0.2.55.1. Halo CE Universal remains at build 94.

- Options adds a customizable Settings visibility sequence, defaulting to the Konami Code. Maximum gap and total time are adjustable. Three-finger double-tap and relaunch provide recovery. The floating icon also supports opacity and built-in/custom images.
- Cheats adds three campaign-only programmable input shortcuts for toggles and one-time actions. Binding preferences persist, active cheats do not. Inputs continue to reach gameplay.
- Jetpack now applies upward thrust while Jump is held on foot, matching the touch UI. Existing campaign/ownership checks remain intact.
- Profiles distinguishes app settings, Halo player profiles and campaign checkpoints. Separate save/profile import and export use the existing verified backup format and recovery-before-restore workflow.
- Name, armor color and controller preferences edit the active Halo profile through engine APIs. Default built-in profiles remain temporary. Current-session network identity may require rejoining.
- Shared audio, VSync, interpolation and network preferences synchronize on the game thread through bounded 64-byte scalar slots. Profile identity changes discard pending edits to the previous profile. No guest pointers are retained. Recovery-launch overrides stay temporary.
- iOS audio gains apply once, avoiding doubled attenuation. Dialogue/Ambient remain extra iOS channels. VSync preference cannot bypass iOS presentation timing. Original/smooth mode transitions still require relaunch.
- Controller rumble now uses compatible GameController haptics. No controller support is inferred from the phone's vibration hardware.

## Validation

Automated checks cover sequence completion, incorrect inputs, timing expiry, malformed bindings, settings round trips, bounded numeric conversion, campaign isolation, source structure, imports and framework linkage. Apple compilation and device validation are required; no performance improvement is claimed.

## Device checklist

1. Toggle the icon with the Konami Code on touch and a controller, then test a custom sequence and expired timers. Hide it and recover with three-finger double-tap.
2. Test all three cheat shortcuts in campaign, then host/join multiplayer and verify none execute. Hold Jump with Jetpack on, release it and switch it off.
3. Change shared audio settings in both menus; verify matching values and undoubled gain. Test vibration on a compatible controller.
4. Select a named Halo profile, edit name/color/controller preferences, relaunch and verify persistence. Switch profiles while editing; changes must not land in the previous profile.
5. Export/import saves and player profiles separately, confirm restore recovery and next-launch loading. Check custom icon backup/restore.
6. Verify a10, crossplay, Safe Start, existing layouts and both app identities. Only main automatically builds the official IPA; ModTest remains separate.
