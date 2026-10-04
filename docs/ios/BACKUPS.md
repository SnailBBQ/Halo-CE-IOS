# Backups

**Settings → Advanced → Backups → Manage backups** saves your profiles, progress and preferences to a single file you can keep in Files or iCloud Drive,
and restores it later.

## What a backup contains

| Part | Included by default |
| --- | --- |
| Saved progress and profiles (everything in `Documents/Halo/save`) | Yes |
| Preferences, control schemes, touch layouts, HUD layouts and recipes | Yes |
| Maps | Optional |
| Map pictures | Optional |

You can switch each part on or off before you export, and again before you restore, so you can bring back only your layouts, for example.

**Never included:** the active invite file, temporary networking state, log files and running cheat toggles. A backup captures progress that is
saved on disk, not a live snapshot of a game in progress. The mod library's catalogue is not part of the optional map backup, so export
important mods individually from Settings → Mods. Disable active map replacements before restoring base maps so the mod library can restore its originals first.

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

- Before anything is overwritten, the old files are copied to recovery storage, and a recovery archive can be exported.
- If a restore fails, the app blocks the game from starting and tries to roll back, rather than starting with half-restored data.
- Backups are checked for unsafe paths, links, duplicates, the wrong format and oversized manifests before anything is written.

## Other ways to move your setup

- **Settings → Profiles** exports and imports your settings (not saves) as a small `.haloprofile` file. See [Settings → Profiles](SETTINGS.md#profiles).
- **Settings → Mods** exports an individual mod.
- Removing the app deletes its data, so export a backup first.
