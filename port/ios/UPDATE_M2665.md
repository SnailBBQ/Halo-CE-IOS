# M2.6.65 — Universal build 98 and in-game Quit

Official app 0.2.65 / 2665; Mod Test 0.2.65.1 / 266501. Integrates
[Universal build 98](https://github.com/cybersecurity/halo-ce-universal/releases/tag/build-98),
upstream commit `ffc1512`, against the exact build 95 source baseline.

## Review and integration

All 24 changed/new upstream files were reviewed and integrated. Three-way merges
preserve iOS edits. The two conflicts were in menu functions and SDL controller
routing: the new split-player lobby logic is retained, while native iOS still
owns its logical input ports. Native ownership changes now wait for released
physical buttons and resting axes, preventing held input becoming a new press
on another player's port. No upstream workflow changes were present in the
supplied archive; main-only official builds and manual Mod Test builds remain.

- Multiplayer lobby Add Player/START/profile selection and per-player leaving.
- Correct controller attribution for menu events and no automatic rejoin for a
  local player who left while others remain.
- Updated lobby artwork and menu-generation data.
- Public signalling broker list moved to `network.brokers_file`.
- Upstream Android/desktop broker packaging and config reader changes.

The iOS IPA includes brokers.txt, copied atomically to Documents/Halo/brokers.txt
before engine startup. The default file is replaced at launch, matching upstream
updates; custom lists must use another filename selected in config.toml. This
is required for existing invites and the server browser to continue working.
The old network.signalling_brokers config string is retired upstream.

## In-game Quit

Confirming the existing main-menu Exit Halo dialog now uses the existing host
exit import. After the guest unwinds through its normal zero-code exit path,
the host invokes the same app quit routine as Settings: clear campaign/input
state, request invite cleanup, mark the run exited, flush streams and terminate.
On-device this should return to the Home Screen. BACK cancels through the
existing menu. Nonzero exits and fault aborts keep their diagnostic behavior.
This does not use a private SpringBoard API or add a guest import.

Process termination does not await remote invite cleanup; abandoned public
listings remain subject to broker/session expiration. Device testing is needed
to verify the visible transition and persistence. Mid-game quit/unjoin actions
remain distinct from the main-menu Exit Halo action.

## Preserved behavior and limits

Claude's M2.6.64 GL wall-time wrappers and map-source hints were reviewed and
retained. Local wrapper tests pass. GL wall time is not GPU execution time;
sampled totals are estimates and last-opened map names are hints.

Signing, arena allocation, ELF loading, execution bridge, resolution, renderer
reuse validation and campaign cheat gating are unchanged. Mod Test remains a
separate app. iOS currently exposes two local input slots; upstream's four-player
network split-screen support is not a claim of four-controller support here.

## Validation

Actual-function native tests cover broker comments/path selection/missing files,
iOS/Android/desktop quit dispatch and shared split-player routing. Native input
tests cover idle-only transfers, button holds, axis thresholds and INT32_MIN.
Renderer/scene adapter tests, public/private invite rotation, GL timing wrappers,
source guards, declarations and workflow configuration are checked locally.
Apple CI must compile the complete guest and host; gameplay still needs a device.

## Device checklist

1. Install over the corresponding app and verify maps/profiles/saves persist.
2. Confirm the bundled broker list is available; test public discovery and manual
   invitations with a build-98 client, private hosting and rejoining.
3. Try two local multiplayer players: Add Player, START, profile selection, team
   changes, one player leaving and the remaining player starting the next match.
   Test touch plus one controller and two controllers; release buttons/sticks
   when changing ownership. Repeat existing local campaign co-op.
4. Main menu Exit Halo: BACK stays in the app; OK returns to Home Screen. Relaunch
   and verify saves/preferences remain and no false crash-recovery notice appears.
5. Compare a10/multiplayer performance at fullscreen 720p and save logs. No FPS
   gain or new stock-signing compatibility is claimed by this upstream update.
