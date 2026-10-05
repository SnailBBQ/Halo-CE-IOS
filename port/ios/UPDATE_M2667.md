# M2.6.67 — OpenCE build 101 and SpringBoard icon

Baseline: OpenCommunityEdition/OpenCE tag build-101, commit 685bf260a0a648a1d898928a99b17428a2549b92.
Reviewed against the exact Universal build 98 archive and merged with the iOS tree.

## Upstream changes

- An in-progress game's preview now supports adding local players before JOIN GAME,
  shows the profiles joining from this device and supports leaving individually.
- Either co-op controller can navigate shared level and difficulty selection.
- A missing network client in the menu frame resets the connection and restores
  player queues instead of continuing through the absent client.
- Upstream updater/download links now point to OpenCommunityEdition/OpenCE.

Ten upstream files changed: README.md (mirrored in docs/UPSTREAM_README.md while
preserving our iOS landing page), Android Updater.java, the lobby XML, Linux README,
menu_functions.c, menu_tags.c, updater.c, ui_widget.c, network_game_globals.c and
port_settings.py. Three-way merges preserve iOS callbacks and settings synchronization.

Official and Mod Test retain separate identifiers, data containers and workflows.
iOS still supports two native local input slots, not four. No online campaign
co-op support is claimed. Keep other clients and map content compatible.

## Icon update

The supplied white Spartan artwork is retained. The previous compiled icon used
AppIcon with the same app version as the earlier green icon; the screenshots show
TrollStore displaying white while SpringBoard still displays green. This is consistent
with stale installed icon caching, not proof that the artwork was absent from the IPA.
The catalog is now AppIconM2667, used by Debug and Release. M2.6.67 also bumps the
app version. Packaging validates the iPhone/iPad primary icon metadata, compiled
PNG resources and Assets.car before signing. Bundle identifiers and save directories
stay unchanged. Install over the existing app; do not delete it to refresh an icon.
A device icon cache may still require a system/installer refresh if it persists.

## Preserved / validation

M2.6.66's looping-sound lifetime fix and cache assertion diagnostics remain. Its
reported multiplayer halt still needs device retesting. Mod Test retains signing
and debugger observations; SideStore/Sideloadly support is not yet established.
Guest arena mapping, PAGEZERO bridge, signing requests and resolution settings
are unchanged by this integration.

Local: test_ios_upstream101.py exercises the actual controller routing and preview
add/leave/join paths, including full/missing games and preserving multiple local
players. It checks menu wiring and the missing-client recovery branch. Existing
sound lifecycle, upstream 98, source structure and declaration checks also pass.
Apple builds validate the complete engine and host; CI runs the new test and icon
packaging check. Device checks: both icons after installing over the previous build,
co-op level selection with controller 2, in-progress multiplayer with two local
players, cancel/leave/rejoin and ordinary one-player invites/LAN/browser joining.
