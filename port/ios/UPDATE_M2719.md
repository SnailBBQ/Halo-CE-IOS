# M2.6.119 - OpenCE build 246

**OpenCE build 246** (commit 9f04a5125991e1f937b33325c92e85b9781fe998) over build 244 (M2.6.118). Regular app 0.2.119 / 2719, Mod Test 0.2.119.1.
Includes everything in M2.6.115 and its follow-ups (settings overhaul, cheat targets, 22 MiB to 64 MiB texture cache and 256 MiB memory window,
per-frame texture check).

## Crossplay: the network version is now 32
Build 235 was network version 29; build 246 is **32**. Players on builds 235 and earlier cannot join builds 246 and later, and the other way round.
The Windows, Linux and Android builds you play against must be build 246 as well.

## The license changed
From build 246 OpenCE is free software under the **GNU Affero General Public License 3.0 or later** (`LICENSE`); the source of earlier builds stays
CC0 (`LICENSES/CC0-1.0.txt`). This repository's README, `docs/UPSTREAM.md` and the app's bundled notices (`tools/ios_notices.py`) say so now.
The AGPL's network clause (section 13) asks anyone who changes the game and lets others play it over a network to offer them the source;
this public repository is that source, and Settings > About links to it.

## What build 246 brings
182 files changed and 102 were added. The ones that matter to players:
- **Bots** in multiplayer lobbies, and online co-op campaign changes (scaling, shared pickups, vehicles, script players).
- A **latency meter**, **network aim assist**, a **passenger camera**, an overshield effect, model detail and structure culling.
- More particles and dynamic lights drawn per frame on the desktop builds (the iOS guest keeps the Xbox's limits, as Android does).
- The maps folder is checked to hold the Xbox maps (not on the iOS guest, which builds with the Android switch and skips that check).
- IP addresses are shortened in the log unless `debug.log_addresses` is set; a built-in broker list is used when `brokers.txt` cannot be read.
- New menus (Video settings > Extra effects, Multiplayer > Player options > Port); the text chat and Mods from earlier builds are unchanged.

## How it was merged
Of the 182 changed files, 148 are files this port does not change and were taken byte for byte. 31 are files with iOS edits and were merged:
24 without conflicts and 7 by hand:
`source/interface/hud.c` (the HUD options block kept beside the new match timer), `source/camera/director.c` (the third-person cheat kept in front of
the new passenger test), `port/linux/src/dsound_sdl.c` (the iOS guard kept around the silent clock's buffer, which is now sized
`MAXIMUM_OUTPUT_CHANNELS`), `port/linux/src/sdl_platform.c` (the settings sync moved to where the event pump now checks its thread),
`port/linux/src/p2p.c` (the iOS invite sharing kept above the new shortened invite log), `port/linux/src/d3d8_gl.c` (the render scale kept, and the host's
frame-phase marker kept after the new height-fade uniform) and `tools/android_asm_convert.py` (the new SIMD float-to-integer rewrite taken, the iOS
flags kept in the usage line). `LICENSE.md` is gone (see the license above); the extract-xiso notices stay because the app still ships that code.
The strict check (`python3 tools/ios_upstream_acceptance.py --upstream-root <build 246> --require-clean-flags-off`) passes: with the iOS switches
off, all 50 adapted files equal build 246.

## Tests changed
`test_ios_public_lobby.py` stubs the new shortened-invite log function; `test_ios_upstream98.py` expects the new built-in broker list when
`brokers.txt` is missing; `test_ios_build_identity.py` and the workflow test follow the new version.

## Not tested
Nothing was compiled or run on Apple hardware or on a device. The engine C could not be compiled here, so a Build IPA run on GitHub Actions is the
first compile of the merged files. Send the first error if one appears. `test_ios_pointer_fastpath.py` needs `keystone`, which is not available
here; it runs in the Actions job.
