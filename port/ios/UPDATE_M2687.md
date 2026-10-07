# M2.6.87 — OpenCE build 146

Regular app **0.2.87 / 2687**. The Mod Test app derives **0.2.87.1 / 268701**. This update moves the engine from OpenCE build 144 (`76b1898ee14e6fb58e0412acc183da509c10e001`, network 21) to **OpenCE build 146** (`314f576515585560ea6b375b0d5b8a02fd8991af`), **network version 22**. The 20 MiB game-state capacity, Apple OpenGL ES renderer, aligned-arena real guest and the M2.6.86 Non-Jailbreak Stage-2 synthetic flexible-base diagnostics are retained.

## Upstream changes integrated

Build 146 is nine commits ahead of build 144. The supplied archive changes/adds **69 upstream paths**. The main upstream work is:

- Halo Custom Edition cache/map loading, checking and execution support.
- Custom Edition maps listed in the menus as custom single-player or multiplayer maps.
- Custom Edition cache-format/BMP helpers and reporting tools.
- OpenSauce maps are explicitly refused by the final upstream design.
- Additional hostile-map hardening.
- A joining player can be told which map is missing; the network version rises to 22.
- Desktop OpenCE receives a 512 MiB memory window and larger texture cache. The Android/mobile path remains smaller; this iOS guest still follows the mobile/Android guest rules, so M2.6.87 does not claim that large Custom Edition maps are playable on iOS.

## iOS merge

Of the 69 upstream paths, **65** were taken directly from build 146 and **4** overlap iOS-adapted files (`port/linux/game/menu_functions.c`, `port/linux/src/xbox_textures.c`, `source/interface/ui_widget.c`, `source/main/main.c`). Those four were three-way merged from exact build 144 / M2.6.86 / build 146 with no textual conflicts. iOS-only behavior stays inside `HALO_IOS_GUEST`; with that guard disabled, the adapted upstream set must reduce exactly to build 146.

M2.6.86's Non-Jailbreak Stage-2 path is unchanged: it can reserve a hostile non-4-GiB-aligned 4 GiB span and test the base+uint32 synthetic guest model, but it still does not launch the real OpenCE guest from that arena.

## Validation

Local promotion requires:

- exact OpenCE build-146 metadata and network version 22;
- no merge-conflict markers;
- complete iOS host-import coverage;
- strict **43/43** flags-off equality against the supplied build-146 tree;
- the existing iOS Python/C/XISO regression suites; and
- an audit that every build-144→146 upstream path is either byte-for-byte build 146 or an explicitly iOS-adapted file whose flags-off view is build 146.

GitHub Actions remains authoritative for the actual arm64_32 guest compile/link and Xcode package. Device tests are required before calling the build confirmed.

## Device checklist

1. Build/install the **Regular** M2.6.87 IPA and confirm About/logs show build 146, commit `314f576…`, network 22 and the correct flavor.
2. Import and boot stock Xbox maps first. Exercise main menu, campaign start/checkpoint reload, HUD, first-person weapons, audio and controller/touch input.
3. Cross-play only against OpenCE clients using **network version 22**. Confirm a missing-map join reports the missing map rather than failing ambiguously.
4. Treat Custom Edition support as **experimental on iOS**. Try a small known-good Custom Edition map before large maps; capture rejection/loading logs. OpenSauce maps should be refused.
5. For stock-iOS investigation, build the Non-Jailbreak flavor separately and confirm the M2.6.86 Stage-2 phases remain available.
