# M2.6.105 - OpenCE build 201

Source update: OpenCE build 182 -> build 201 (commit b1ef7f7e7aff00f0efdca4d575f7d9196d0b1590).

**The network version is now 28 (it was 25).** An iPhone on this build cannot see or join hosts on build 182 or older, and the reverse, until both run build 201 or later. The Info.plist, the About screen and the shared logs report 28. Version 26 added browser (WebRTC) signalling to internet play, 27 added map sharing, and 28 holds a player who is still downloading the map out of the game, keeps a multiplayer map's first scripted BSP, leaves dynamic lights and the flashlight on past the Xbox's player and vehicle limits, and readies a second weapon picked up while firing.

## What changed upstream (from the file diff and `NETCODE.md`; the upstream changelog was not in the archive)
- **Map sharing** (`map_share.c`, `map_share_files.c`): a client without a Custom Edition map asks the host for it, and players send pieces to each other on port 5153. Maps in `custom_maps` are renamed `<name>_<8 hex digits>.map` after their contents. Settings: `network.map_download`, `network.map_share`, `network.map_share_upload`, `network.map_seed_upload`, `network.map_seed` (downloading and sharing default to on).
- Shield glow (lights the surroundings in the shield's colour, with a Light Show intensity) and eighteen multiplayer armor colors; first-person legs; an object mesh helper.
- Internet play: WebRTC and DTLS so that browsers can join (`p2p_webrtc.c`, `posix_dtls.c`); the Android build gains an mbedTLS host.
- A **web (browser) port** (`port/web/`). iOS does not use it.
- Menus and settings lists gain a "web" platform; wire format notes in `port/linux/network_format.txt`.

## How it was merged
- 175 files were identical to build 182 in the repo and were taken from build 201 byte for byte; none were removed.
- 18 files carry HALO_IOS_GUEST adaptations and were three-way merged against the flags-off view of the repo file. 16 merged cleanly. `d3d8_gl.c` (5 places) and `xbox_textures.c` (1 place) conflicted because iOS hooks sit next to upstream's new web-only code; each was resolved by keeping both (the iOS hooks stay, upstream's `HALO_WEB` code stays, and the iOS `setup_streams` rename and wireframe early-out follow upstream's new blocks). The strict gate confirms both files are exactly upstream when the iOS code is switched off.
- The repo's own README and workflow were kept.

## iOS host
No host import changed (62 are covered), so `halo_guest_runner.m` is unchanged. Map sharing uses the guest's existing socket imports; the iPhone may also send maps to other players while it plays.

## Local validation
- Strict upstream gate: 10/10; flags-off equivalence exact 46/46; build identity (build-201, commit, network 28, game state 20,971,520 bytes) matches the source.
- Of the changed and new game sources, the ones that compile in this sandbox (49 files in each mode) convert and assemble in aligned and flexible-base modes with no untranslated flexible-base access and no new compile failure against build 182. About 28 others (including `p2p_webrtc.c`) need system headers that this sandbox lacks and were not locally checked.
- All our Python tests pass except `test_ios_pointer_fastpath.py`, which needs `keystone`. Upstream's own pytest tests for build 201 were not run.

## Not validated
- The full guest build, the Xcode build and everything on a device, including map sharing and play against a network-28 host. The earlier Non-Jailbreak device confirmation is for M2.6.101.
- Imported Custom Edition maps will be renamed with a hash suffix once the game scans them; the Mods list shows the new names.
- Test Regular first, then Non-Jailbreak.
