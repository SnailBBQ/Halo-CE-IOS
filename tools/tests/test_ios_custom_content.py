"""M2.6.88 Custom Edition map manager and user-supplied MP4 Bink fallback wiring."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
HOST=ROOT/'port/ios/HaloIOS'
mods=(HOST/'HaloMods.m').read_text()
header=(HOST/'HaloMods.h').read_text()
library=(HOST/'HaloLibrary.m').read_text()
app=(HOST/'AppDelegate.m').read_text()
disc=(HOST/'HaloDiscImport.m').read_text()
backup=(HOST/'HaloBackupArchive.m').read_text()
runner=(HOST/'halo_guest_runner.m').read_text()
stubs=(ROOT/'tools/ios_gl_stubs.py').read_text()
bink=(ROOT/'source/bink/bink_playback.c').read_text()
attract=(ROOT/'source/interface/attract_mode.c').read_text()

# Replacement mods are retired from the public UI; the old transaction exists
# only to unwind an installed overlay safely at the next launch.
assert 'Mod library' not in library and 'Import mods' not in library
assert 'Custom Edition Maps' in library and 'Import Custom Edition content' in library
assert 'HaloModsLegacyExists' in header and 'HaloModsRetireLegacy' in header
for retired in ('HaloModsImport','HaloModsSetEnabled','HaloModsMove','HaloModsExport','HaloModsPlanBaseImport'):
    assert retired not in header and retired not in mods
assert 'HaloModsRetireLegacy(&error)' in app and 'HaloModsPlanBaseImport' not in disc
assert 'version == 609' in mods and 'custom_maps_disabled' in mods
for name in ('bitmaps.map','sounds.map','loc.map'):
    assert name in mods and name in library
assert 'OpenSauce maps are not supported' in mods and 'OpenSauce maps are intentionally unsupported upstream' in library
assert 'custom_maps/' in backup and 'custom_maps_disabled/' in backup

# MP4 media is supplied by the user; iOS maps the logical Bink stem to AVPlayer.
assert 'Movies (MP4 fallback)' in library and 'Import MP4 movies' in library
for stem in ('intro','credits','attract1','attract2','attract3'):
    assert stem in mods
assert 'AVPlayer playerWithURL' in mods and 'AVPlayerLayer' in mods
assert 'videos/' in backup and 'mp4' in backup
for name in ('host_movie_available','host_movie_start','host_movie_active','host_movie_stop'):
    assert name in stubs and f'MAP("{name}"' in runner
    assert (name in bink) or (name == 'host_movie_available' and name in attract)
assert '#ifdef HALO_IOS_GUEST' in bink and '#ifdef HALO_IOS_GUEST' in attract
assert 'host_movie_available(bss_00453ae8)' in attract
assert 'host_movie_start(full_pathname, flags)' in bink and 'host_movie_active()' in bink
print('PASS: M2.6.88 retires replacement-map UI, installs CE v609 content beside Xbox maps, and wires user-supplied MP4 Bink fallback through the iOS host')
