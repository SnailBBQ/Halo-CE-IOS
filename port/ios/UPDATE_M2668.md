# M2.6.68 — Clearer campaign checkpoint editing

Built on OpenCE build 101. Official and Mod Test share these editor changes; app identifiers, save locations, signing, guest loading and multiplayer are unchanged.

- The selected save card shows the filename, distinguishing folder and campaign map name/code. Custom map codes remain visible when no built-in title is known.
- Health and shields accept 1–999% and 0–999%, respectively. Existing overshield values are displayed without reducing them to 100%.
- Frag and Plasma grenades accept 0–127. The guest stores each count as a signed byte; 999 cannot be represented without changing the save format and engine layout.
- Ammo fields are named **Current Magazine** (ready to fire) and **Reserve Ammo** (for reloads), with values from 0–999. Ammo Pool 1 and Ammo Pool 2 are separate magazine records, not two weapons or loaded/reserve pairs. The second pool only affects weapons whose definitions use it; energy weapons may use a separate charge system.
- Each field rejects values outside its displayed range. Edited checkpoints can be reopened and edited again at the new limits.

These are finite saved values, not infinite-health or infinite-ammo cheats. Normal gameplay can consume, refill or clamp them. Recovery backups and staged restoration on the next launch are retained.

## Validation

`tools/tests/test_ios_checkpoint.c` verifies expanded upper bounds, overflow/non-finite rejection without mutation, both ammo pools, checksum regeneration, reopening edited checkpoints and unchanged bytes outside the selected fields/checksum. It passed against synthetic data and an in-memory copy of a real campaign checkpoint; the original file was not overwritten. iOS source/declaration/workflow checks passed locally.

Device checklist: confirm the selected filename/folder/map, edit and resume a checkpoint with the new limits, check ammo/reloads on a ballistic weapon, and verify recovery restoration. These gameplay checks remain unverified until tested on an iPhone.
