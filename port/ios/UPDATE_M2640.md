# M2.6.40 — first-person isolation and iCloud invites

Updated October 2, 2026. Based on M2.6.39 / Halo CE Universal build 73, protocol 10.

## Device evidence

The M2.6.39 recording shows stretched geometry while alive and an unobstructed death camera with a normally rendered Spartan. It recurs on respawn. This points toward the first-person weapon/hands path, but does not distinguish the meshes or prove a player-body bug. Settings now shows its complete heading. Logs show about 60 FPS, approximately 5.5 ms render CPU, two render pointer upgrades per call, no skipped shader links, no invalid native-helper inputs and no audio underruns. The previous shader mapping correction did not resolve this device's obstruction. The user reports an unobstructed opening of a10, before acquiring a weapon; that does not establish correctness with an equipped weapon.

## First-person rendering

Settings > Display > First-person view offers Both (default), Weapon, Hands and Hidden. Changes apply immediately and persist. These only select the first-person draw calls; attacks, animation/muzzle updates, HUD, remote players and world objects continue. Hidden is a workaround and diagnostic, not a repaired model. Independent modes identify whether the weapon or hands obstruct the view; if Hidden still obstructs it, investigation must move to the world/local-body path.

Remapping now rejects out-of-range bone indices/counts and nonfinite matrices on iOS instead of reading invalid data or submitting nonfinite bones. Valid poses are unchanged. Bounded ten-second samples in debug.txt identify model/animation-graph IDs, node counts, maximum scale, camera-relative L1 distance and nonfinite count. They distinguish malformed CPU poses from later vertex/skin/shader conversion. No speculative shader, ABI, signal-bridge, resolution or interpolation changes are included.

## iCloud Drive invite file

In Settings > Multiplayer, choose **Choose iCloud Drive folder**. In Apple's Files picker, select iCloud Drive itself or a folder there. The app saves that folder's security-scoped bookmark and writes **game_invite.txt** there instead of maintaining a second local export. Until a folder is selected, Documents/Halo remains the fallback. This uses document-picker access and file coordination, not a new app-specific iCloud entitlement, so it works with the existing sideloading build.

Hosting publishes the current invite. Leaving or next-launch cleanup clears a file only when its contents match the last invite this app wrote. A different PC invite pasted into the file survives cleanup. **Join from game_invite.txt** reads and validates the current file on demand; it never automatically joins when the PC edits it. Files contain one link and reads are limited to 1024 bytes. File-provider I/O runs on a serial background queue; it cannot wait on the game thread. Failed writes preserve the file and show an error. Revoked access can be repaired by choosing the folder again. If the old folder has become inaccessible, remove its stale file manually in Files; no app can clear it after its access is revoked.

iCloud syncing is eventual. Allow the PC/iPhone changes to sync before joining. Forced app termination/offline providers may defer cleanup until next launch and sync. An exported file is not an invite history; once hosting ends that code cannot join its former game. The app stores only its last owned code for conditional cleanup and removes it after cleanup or detecting a different incoming code.

## Build and focused test

Build **Halo CE iOS — Build IPA**, install **HaloCE.ipa** from **HaloCE-iOS**, version 0.2.40 / 2640. Existing bundle ID, maps, audio, protocol and performance baseline are retained.

1. Multiplayer with the obstructing weapon: compare Both, Weapon, Hands, Hidden and respawn in each. Record the result and share fresh debug.txt/ios-boot.log. Test a10 again after acquiring a weapon.
2. Select an iCloud Drive folder once. Start hosting; verify the PC sees the current file after sync. Stop hosting and confirm its owned code goes empty.
3. Paste a supported PC invite into that file while the phone is not hosting. Reopen Halo; confirm it survives cleanup and use Join from game_invite.txt. Check empty/malformed input, offline sync and reselecting a folder after access changes.

Local tests exercise the actual remapping function for copy order, bone/count bounds and repeated nonfinite rejection, plus persistent visibility modes, backward-compatible defaults and owned-file cleanup policy. CI compiles both the arm64_32 guest and Apple host and runs existing bridge/renderer regression checks. Visual correctness and provider behavior still require device tests.

File-provider access follows [Apple’s directory-access guidance](https://developer.apple.com/documentation/uikit/providing-access-to-directories).
