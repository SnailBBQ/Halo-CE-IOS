# M2.6.47 — Options and visual polish

- Black uses a segmented grenade, fuse lever and pin with circular swap arrows,
  based on the supplied reference. White uses an angled flashlight with a handle,
  lens, switch and upward light beams. Both controller schemes share these icons.
- Options sits directly above Advanced. It offers Settings gear size (75–175%),
  size/position reset, and Blue, Green, Purple, Amber and Rose accent schemes.
  Preferences persist. The gear retains a minimum 44-point touch target, safe-area
  clamping and priority over gameplay controls at every size. Themes apply to
  Settings selections, buttons, switches and sliders; gameplay colors stay separate.
- Mods' empty-library text now uses a padded card and the scrolling library stays
  inside the safe area. Map previews trim outer pure-black/transparent texture
  padding, preserve internal pixels, remain centered, and increase from 110 to
  190 points high. Gray image backgrounds and rounded image borders are removed.
  All-black previews keep their original dimensions. Custom thumbnails remain
  unchanged.
- Direct boot no longer renders the Ready to play setup state before starting.
  The Starting Halo indicator remains until the first game frame; real engine
  initialization still takes time. Missing maps and recovery mode retain setup.

Settings tests cover defaults, persistence and hostile size/theme values. The
actual map parser test covers padded and fully black previews in addition to its
existing format/bounds checks. CI builds the engine and UIKit app and packages
`HaloCE.ipa`. Device visual checks remain pending: both utility icons at normal
and reduced control sizes, theme changes, gear scaling/dragging at screen edges,
map preview framing, and cold direct boot.
