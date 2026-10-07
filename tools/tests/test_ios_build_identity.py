"""M2.6.84 build identity, build-138 promotion, save protection and acceptance wiring."""
from pathlib import Path
import json, plistlib, re
ROOT=Path(__file__).resolve().parents[2]
HOST=ROOT/'port/ios/HaloIOS'
with (HOST/'Info.plist').open('rb') as f: info=plistlib.load(f)
up=json.loads((ROOT/'port/ios/upstream.json').read_text())
assert info['CFBundleShortVersionString']=='0.2.84' and info['CFBundleVersion']=='2684'
assert info['HaloSourceMilestone']=='M2.6.84'
assert info['HaloOpenCERelease']==up['tag'] and info['HaloOpenCECommit']==up['commit']
limits=(ROOT/'port/linux/include/halo_port_limits.h').read_text()
network=int(re.search(r'#define\s+HALO_PORT_NETWORK_VERSION\s+(\d+)',limits).group(1))
capacity=(ROOT/'port/linux/include/halo_port_capacity.h').read_text()
cpu=int(re.search(r'#define\s+HALO_PORT_GAME_STATE_CPU_SIZE\s+(0x[0-9A-Fa-f]+|\d+)',capacity).group(1),0)
gpu=int(re.search(r'#define\s+HALO_PORT_GAME_STATE_GPU_SIZE\s+(0x[0-9A-Fa-f]+|\d+)',capacity).group(1),0)
assert info['HaloNetworkVersion']==network and info['HaloGameStateBytes']==cpu+gpu
assert info['HaloGuestArchitecture']=='aligned-arena-v1' and info['HaloGuestAdaptation']=='ios-guarded-v1' and info['HaloRenderer']=='Apple OpenGL ES'
backup=(HOST/'HaloBackupArchive.m').read_text()
header=(HOST/'HaloBackupArchive.h').read_text()
app=(HOST/'AppDelegate.m').read_text()
settings=(HOST/'HaloSettingsViewController.m').read_text()
boot=(HOST/'halo_boot_integration.m').read_text()
library=(HOST/'HaloLibrary.m').read_text()
for token in ('HaloEngineIdentity','HaloBuildIdentityText','HaloProtectEngineChange'):
    assert token in header and token in backup
assert 'HaloBackupExportIdentity(1,previous)' in backup and '@"engine_identity":engineIdentity?:HaloEngineIdentity()' in backup
assert 'HaloGuestAdaptation' in backup and '|guest=%@' not in backup[backup.index('NSString *HaloEngineIdentity'):backup.index('NSString *HaloBuildIdentityText')]
assert 'HaloGuestSHA256' in backup[backup.index('NSString *HaloBuildIdentityText'):backup.index('static unsigned Section')]
assert 'HaloProtectEngineChange(&protectionError)' in app and 'Protecting saves' in app and 'Could not protect your saves' in app
assert 'Export last engine-change backup' in library
assert 'HaloBuildIdentityText()' in settings and 'Guest SHA-256' in settings
assert 'static void boot_build_identity' in boot and 'HaloBuildIdentityText() componentsSeparatedByString' in boot and 'boot_build_identity(line);' in boot
baseline=json.loads((ROOT/'port/ios/upstream_baseline_deltas.json').read_text())
assert baseline['upstream']['tag']=='build-125' and baseline['upstream']['commit']=='13c14df95c63156429e96a9694bb9cecd0379228' and len(baseline['approved_flags_off_deltas'])==27
acceptance=(ROOT/'tools/ios_upstream_acceptance.py').read_text()
assert '--require-clean-flags-off' in acceptance and 'status="warn"' in acceptance and 'IOS_OWNED_EXTRA_FILES' in acceptance
workflow=(ROOT/'.github/workflows/ios.yml').read_text()
for token in ('Set :HaloBuildFlavor $FLAVOR','Set :HaloGuestSHA256 $GUEST_SHA','Set :HaloSourceCommit ${GITHUB_SHA:-local}','DIAGNOSTICS=flex-base+exec-trace-v1','python3 tools/ios_upstream_acceptance.py --json'):
    assert token in workflow, token
print('PASS: M2.6.84 metadata matches OpenCE build-138/source constants; logs/About expose it; engine changes use .halobackup; the historical build-125 delta baseline remains isolated; workflow stamps identity and runs acceptance gates')
