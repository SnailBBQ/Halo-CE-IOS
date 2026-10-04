> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# M2.6.50 — Picture options and touch aiming

The same feature commit is integrated into the regular app and the separate mod-test branch.
App identity, private storage, map ceilings, multiplayer protocol and the existing execution bridge are preserved.
Mod conversion remains paused.

## Display

Settings > Display > Game picture offers Default (4:3), Widescreen (16:9) and Fullscreen (device aspect).
The existing engine widescreen camera/viewport path is used, including centring the legacy 640-wide UI;
the game image is not stretched. Logical height remains 480, with 480/720/960-line render-target choices
using the renderer's established target and viewport scaling. Default remains 640x480. Fullscreen logical
width is even and bounded to 640–1600. Scale is restricted to 1, 1.5 or 2. Options apply on the next app launch.
Safe Start forces 640x480. Startup logs print the logical dimensions and target scale; the renderer prints
actual target dimensions. Higher detail increases GPU work and memory; no FPS improvement is claimed.

AirPlay instructions are in Display. Connect through Control Center > Screen Mirroring or a supported display
adapter. This uses system mirroring and shows the controls on both screens. A separate external-screen game
window with phone-only controls is not implemented. A controller and Auto controls visibility can hide touch
buttons on both screens. AirPlay discovery, quality and delay depend on the receiver/network.

## Touch aiming

Controls > Touch aiming contains three independent, initially disabled options, persisted per control profile
(and therefore included in preferences exports/backups):

- Auto-fire on enemies: one projectile collision query along the actual camera ray, up to 128 world units.
  Requires a living hostile unit hit first, a living local player with a weapon, active camera/input control,
  and no cinematic or fire-button inhibition. A wall, friendly unit or dead unit blocks firing. It does not
  use the aim-assist cone. It holds the normal weapon trigger; semi-automatic and charge weapons keep their
  ordinary trigger behavior, with no rapid-fire override.
- Aim with the Fire button: hold Fire and drag, using the existing look sensitivity, curve and inversion.
- Fire with the right stick: deflect the touch look stick outside its dead zone to hold Fire; return to centre
  or lift to release. Its hold ownership is independent of a manually held Fire button.

Auto-fire requires a finger using the touch layer. The gate resets on last-finger release/cancel, Settings,
layout changes, app backgrounding and input reset. A connected physical controller disables auto-fire even
when touch buttons are set to Always. Physical controller inputs themselves are unchanged.

## Integration

- Host settings/persistence/UI: `halo_settings_core.h`, `HaloSettingsViewController.m`.
- Input: `halo_ios_controls.m`; host gate/environment/import map in `halo_guest_runner.m/.h`.
- Engine: `aim_assist.c/.h` exact-ray query, `player_control.c` guarded local input augmentation.
- Graphics: `port/linux/src/d3d8_gl.c` reads bounded iOS render scale and Settings-owned logical width.
- Import generator: `tools/ios_gl_stubs.py` emits `host_touch_auto_fire`; omitting this would fail guest linking.
- Tests: `tools/tests/test_ios_settings_core.c` covers dimensions, defaults, hostile imports, round-trip and legacy backups.

## Rebuild and device verification

1. Build the regular branch and `ios/cursed-a10-mod-test` with their own existing workflows; install both apps
   side-by-side. Regular remains `HaloCE.ipa`; mod-test retains its own artifact and bundle identifier.
2. First test unchanged defaults: menu, stock a10, multiplayer host/client, audio and profile switching.
3. Relaunch for each aspect/detail choice. Check menus, HUD, camera shape, post-processing, weapon models and
   multiplayer; watch FPS/heat/memory. Verify Safe Start falls back to 640x480. Do not infer gameplay FPS from menus.
4. Test touch options individually: manual Fire + stick Fire release/cancel, enemy behind a wall, friendly,
   dead target, death/respawn, zoom, charged plasma pistol, menus, cinematics and connected controller.
5. Mirror to an actual AirPlay receiver and verify orientation, sound, touch/controller input and foreground
   resume. Screen Mirroring alone is not proof of a separate external-display renderer.

Local checks cannot validate UIKit/EAGL, on-device GPU allocation or AirPlay latency. Apple CI and device results
must pass before treating this update as a tested release. No actual casting or gameplay performance claim is made yet.
