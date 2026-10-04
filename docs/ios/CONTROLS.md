# Controls

You can play with the on-screen touch controls, a physical controller, or both. Options live in **Settings → Controls**; see the
[Settings reference](SETTINGS.md#controls).

## Touch controls

The on-screen controls follow the original Xbox controller: the D-pad, both sticks, LT and RT, A, B, X and Y in their usual colours, Black and White,
Back and Start, and the stick clicks. In the default layout:

| Control | Action |
| --- | --- |
| Left stick | Move |
| Right stick / drag | Look |
| RT | Fire weapon |
| LT | Throw grenade |
| Left stick click | Crouch |
| Right stick click | Zoom |
| Start | Pause |
| Back | Scoreboard and game stats |
| Black, White | Grenade swap and flashlight (shown with their own icons) |

**Visibility.** *Auto* hides the touch controls while a controller is connected and shows them again when it is not. *Always show* and *Hide* override this.
Opening a native screen or leaving the app releases any held touch input.

### Five control schemes

Each scheme keeps its own layout, look settings, HUD link and cheat recipe. You can rename them and reset a scheme to the Xbox layout. The first scheme is
**Classic Xbox UI** and the second is **Playstation UI**, which shows the PlayStation symbols (×, ○, □, △) while sending the same positional actions as Xbox A, B, X and Y.

### Editing the layout

**Edit button layout…** opens a drag-to-edit mode over the game. Drag a control to move it; use the toolbar to select a control, change its size, show or hide it,
set its opacity, and reset the selected control or the whole layout. It is also reachable from Settings → Display.

### Looking

- **Drag to look** turns on touch look in the open screen area. **Look speed**, **look acceleration** and **invert look** tune it.
- **Floating sticks** place the move stick where your thumb lands. **Dead zone** and **move stick response** tune it.
- **Button opacity** and **haptic feedback** are per scheme.

### Left-handed layout

Mirrors the whole layout: move with the right thumb, with look and the face buttons on the left. You still edit the layout in its normal orientation;
the mirror is applied when it is drawn.

### Toggle crouch and zoom

One tap on the stick click crouches or zooms, and the next tap releases it, instead of holding the button down.

### Gyro aiming

Fine aim comes from turning and tilting the device while you hold it; use the stick or a drag for big turns. **Gyro speed** sets the sensitivity. If the view moves the wrong way
in either direction, turn on **Flip left and right** or **Flip up and down**. Gyro also moves the view in menus, and it is saved per scheme.

### Touch aiming

Three independent options, all off by default and saved per scheme:

- **Auto-fire on enemies** holds the normal trigger while a living hostile unit is the first thing under your aim, up to 128 world units away. A wall, a friendly or a dead unit blocks it,
  and it needs a living player holding a weapon. It does not change how semi-automatic or charged weapons fire.
- **Aim with the Fire button** lets you hold Fire and drag to aim.
- **Fire with the right stick** holds Fire while the look stick is pushed past its dead zone and releases it when you return to centre or lift your finger.

Auto-fire needs a finger on the touch controls, and a connected controller turns it off.

## Physical controllers

Controllers supported by Apple's GameController framework work, including Xbox and PlayStation controllers. PlayStation schemes use L2, R2, L3 and R3. Controller input is read directly and is not
changed by the touch options.

**Settings → Controls → Controller** (shared by all schemes):

- **Stick dead zone** removes a small centre area; the dead zone is subtracted, so movement still starts from zero.
- **Stick response** (1.0 to 3.0) gives finer control near the centre when raised above 1.0.
- **Controller button remap** lets you choose what each of 14 buttons does (A, B, X, Y, White, Black, Start, Back, both stick clicks and the D-pad). Two buttons can do the same thing, and **Reset to the standard layout** undoes it.

The defaults pass everything through unchanged.

## Menus

Move through the menus with the on-screen D-pad (or a controller) and press **A** to select and **B** to go back. The PC menus are designed for a mouse and keyboard; touch behaviour in them has not been fully validated, and the Xbox menus
remain available in Settings → Display → Menus.
