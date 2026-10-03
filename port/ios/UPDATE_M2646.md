# M2.6.46 — Settings access, profiles and mods

Settings returns to the top center. It stays above gameplay controls for drawing
and touch input. Hold the gear for 0.35 seconds, drag it, and release to save its
position. The button remains within the screen's safe area after rotation.

Display groups Show FPS with Frame rate, removes the duplicate touch editor, uses
a blue Edit game HUD button, and replaces diagnostic first-person-view wording.
Controls remains the place to edit touch layouts. PlayStation profiles use L2,
R2, L3 and R3. Both schemes show centered vector grenade-swap and flashlight
icons without changing their input mappings.

Each control profile can select Default or one of the three named Game HUD
presets. Selecting a profile loads that HUD recipe; editing a control profile
does not alter saved HUD recipes. Default restores standard HUD placement,
scale, opacity and visibility. HUD recipes are saved separately in the HUD
editor. Each control profile also saves its startup choice: direct boot (the
default), or Start Halo. Advanced exposes the same startup preference. Missing
maps and recovery mode still stop at setup. Restart is removed; Quit remains.

## Mods

Mods replaces the Maps sidebar. Import/export uses Files, including iCloud.
Imported mods start disabled. Enable/disable them and reorder the list; later
enabled entries override earlier entries sharing a filename. Changes apply
before engine startup on the next launch, never against a running map. Original
maps are preserved and restored when all replacements for that filename are
disabled. Newly added maps are removed on unload. Files are checked for a
compatible Xbox v5 header, size and import hash. A durable journal and recovery
copies allow interrupted installs to roll back before retrying.

This engine loads compiled map caches containing tags. Supported mods therefore
include maps with compiled weapon, character, scenery and other tag changes.
Loose editor tags, PC-format maps and executable plugins are **not supported**;
they must not be presented as loadable. Header validation cannot prove asset
correctness. Only use compatible maps, and keep multiplayer participants on
matching content. Base game files remain visible within Mods and continue to
use `Documents/Halo/maps`.

Mod library originals and recovery copies use app support storage and consume
additional space. Export imported mods individually for archival; the existing
optional map backup includes installed maps, not the mod-library catalog.
Unload map replacements before restoring or replacing their base files.

## Verification

- Settings serialization tests cover startup/HUD links, saved gear position,
  bounded input and PlayStation labels.
- Foundation store tests cover linked HUD selection and recipe independence.
- Foundation mod tests cover ordering, original restoration, new-map unloading,
  hash rejection and interrupted-install recovery.
- Existing campaign, powerup, source-structure and build-configuration checks
  remain in place. CI compiles the actual UIKit app and packages `HaloCE.ipa`.

Device checks: overlap gear with RT and confirm Settings still opens; drag and
rotate; save profile 3 linked to HUD 3; test both launch preferences; import two
compatible replacements, reverse their order, then unload and confirm originals.
Device visual and gameplay validation remains pending.
