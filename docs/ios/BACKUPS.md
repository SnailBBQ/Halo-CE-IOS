# Backups

**Settings → Advanced → Backups → Manage backups** saves your profiles, progress and preferences to a single file you can keep in Files or iCloud Drive,
and restores it later.

## What a backup contains

| Part | Included by default |
| --- | --- |
| Campaign saves (persistent checkpoints and save metadata) | Yes, separately selectable |
| Halo player profiles and playlists | Yes, separately selectable |
| Preferences, control schemes, touch layouts, HUD layouts and recipes | Yes |
| Xbox maps, Custom Edition maps/resources and user-supplied MP4 movies | Optional |
| Map pictures / CE sidecars | Optional |

You can switch each part on or off before you export, and again before you restore, so you can bring back only your layouts, for example.

**Never included:** temporary map caches (`save/z/cache*.map`), the volatile `save/z/savegame.bin` checkpoint, the active invite file, temporary networking state, log files and running cheat toggles. A backup captures progress that is
saved on disk, not a live snapshot of a game in progress. The optional Maps section includes `maps/`, `custom_maps/`, `custom_maps_disabled/`, `videos/` and map thumbnails. M2.6.88 no longer has a user-facing replacement-map catalogue. Existing legacy replacement overlays are restored and retired before the engine starts.

## Exporting

1. Open **Manage backups** and choose what to include.
2. Export. The backup is written through the Files picker, so you can send it to iCloud Drive, On My iPhone or any other storage provider.

The file has the extension `.halobackup`. It is versioned and is written in 1 MiB blocks with a SHA-256 check, so even a backup that
includes large maps does not have to fit in memory. It is not compressed and can be up to 32 GiB. Keep enough free storage for it.

## Restoring

1. Open **Manage backups**, choose the `.halobackup` file and the parts to restore.
2. The restore is prepared now and **applied the next time you open the app**, before the game starts. It never changes files while a game is running.

A restore merges the chosen parts into the app: files with matching names are replaced, and files the backup does not list are left alone.

## Safety

- Since M2.6.80, Halo records a stable OpenCE/save-compatibility identity (OpenCE revision, network/game-state ABI, guest architecture and iOS adaptation). The first start establishes the baseline. If a later installed build changes that identity and persistent saves/profiles exist, Halo creates a normal verified saves/profiles `.halobackup` **before the guest is allowed to open them**. If the automatic backup fails, the game does not start. The exact guest ELF SHA stays in build diagnostics but is not the backup trigger, because otherwise identical CI builds can contain different compile timestamps. Manage backups can export the last engine-change archive.
- `.halobackup` manifests also record the engine identity and source milestone that created them; format 1 remains backward compatible.
- Before anything is overwritten, the old files are copied to recovery storage, and a recovery archive can be exported.
- If a restore fails, the app blocks the game from starting and tries to roll back, rather than starting with half-restored data.
- Backups are checked for unsafe paths, links, duplicates, the wrong format and oversized manifests before anything is written.

## Other ways to move your setup

- **Settings → Profiles → Back up or move your profile** opens this screen with app settings, layouts, campaign saves and Halo player profiles (your in-game name and armor color) ticked together, so one `.halobackup` file holds the whole profile. Older settings-only `.haloprofile` files can still be opened from there. See [Settings → Profiles](SETTINGS.md#profiles).
- **Settings → Mods** manages Custom Edition content and user-supplied MP4 movies; include the Maps section when exporting a `.halobackup` if you want them preserved.
- Removing the app deletes its data, so export a backup first.

## Keep saves when deleting Halo

iOS does not let Halo intercept app deletion or add a keep-saves prompt. Deleting the app removes its local container. To retain progress, use Advanced → Backups → Manage backups → Saves outside the app. Choose a folder in iCloud Drive or another location outside Halo, save in the game, and select **Back up saves and profiles now**. These are manual, versioned `.halobackup` files; maps and active invites are excluded. Confirm the file has uploaded before deleting the app. Previous backups are kept.

After reinstalling, select the external folder again and choose **Restore external saves…**. Pick a backup, stage the restore, then close and reopen Halo. The existing validated restore flow places files back under `Documents/Halo/save` and creates a recovery backup before replacing matching files. With no backup, start normally.

Installing an update over the existing app keeps the same save path and app identity. Do not delete the app first, and preserve the signing identity when updating. The regular and ModTest apps keep separate storage and distinctly named external backups. External folder permissions must be selected again after deletion; the app cannot silently rediscover an arbitrary Files folder.

## Separate saves and player profiles

Campaign saves and Halo player profiles have separate export/restore switches. On a fresh installation, restore the matching player profile as well as its checkpoint so Halo can associate the saved progress with the correct profile. App settings profiles (`.haloprofile`) remain separate. The external-folder quick backup keeps both progress and Halo profiles.

Older backups remain readable, but their temporary cache files are no longer restored. These caches are rebuilt by the engine; they previously made a save/profile backup hundreds of megabytes larger than necessary. Installed map files remain an explicit optional backup section.

## Campaign checkpoint editor

Settings → Profiles → Edit campaign checkpoint validates the Xbox 2342 header, checksum, bounded guest references and local-player inventory. It edits finite health/shields, grenade counts and the magazine records of weapons already in the save. It queues the replacement for the next launch and creates recovery archives; it never writes into a live game. A checkpoint without a living local player or with an unsupported layout is rejected. Energy weapons can use a separate charge system; this editor does not create or replace weapon objects.

The editor identifies the selected filename, folder and campaign map. Health accepts 1–999%, shields 0–999%, and each grenade type 0–127 (the signed-byte storage limit). Current Magazine and Reserve Ammo each accept 0–999 per ammo pool. Pool 2 is a second weapon-defined magazine, not a second weapon; most weapons use only Pool 1. These values are finite and gameplay can consume or clamp them.

Unlock/completion data belongs to Halo player profiles, not this checkpoint editor. Runtime invincibility, gravity, time, HUD colors, projectile swaps and camera modes are not exposed as fictitious save fields. Skulls and a consumable vehicle-boost system are not established in this recovered build.
