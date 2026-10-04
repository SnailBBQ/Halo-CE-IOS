# M2.6.62 — Shortcuts, cheats and controls

- Dedicated themed shortcut editor: choose a cheat, tap touch buttons or record
  a physical gamepad sequence, adjust gap/total duration, Save or Cancel. Maximum
  16 buttons; recording input is withheld from gameplay. No text sequence entry.
- Cheat module headers show active names. All Equipment Spawns is removed from
  app dispatch and UI. Retired shortcut ID 29 is disabled without renumbering
  IDs 30/31; retired campaign action 12 does nothing.
- Weapon Giver moves to Weapons, above Projectile Swapping; includes one-shot
  frag/plasma inventory refills to the map's configured grenade capacity. The
  ring action follows Projectile Swapping. Spawn is vehicles only.
- Controls are grouped into Touch Controls, Gamepad Controls and Halo Controller
  Settings. Deadzone/response changes reapply held axes without synthetic presses.
  Default gyro yaw is corrected; pitch and inversion controls are preserved.
- Startup Help and Share logs are present in both official and Mod Test builds.
  Optional manual `compatibility_test=true` uses the maintained Mod Test source
  and bundle ID, not a third app. The official allocator and signing stay unchanged.

## Validation

Controller shaping/gyro, settings/shortcut persistence, retired-action migration,
world-action behavior and grenade capacity/error cases are covered by native tests.
Apple CI must compile the UIKit editor and full guest. Device testing remains
necessary for controller feel, gyro orientation, touch recording and grenade HUD
updates. Stock signing compatibility is not claimed.

## Device checklist

1. Edit each shortcut: select a cheat, tap or record buttons, adjust timing, Save;
   reopen to verify persistence. Cancel must discard changes.
2. Try the sequence in solo campaign, then multiplayer: only campaign activates it.
3. Hold a physical stick while changing deadzone/response. Confirm immediate changes
   and no dropped held buttons during unrelated settings changes.
4. Turn the phone left/right in both landscape orientations; verify pitch unchanged.
5. Give both grenade types: counts refill to the map capacity, never increase further.
6. Check Startup Help in both app identities; importing maps and invites remain intact.
