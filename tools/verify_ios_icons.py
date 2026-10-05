"""Verify the packaged primary icon uses the current asset identity on both devices."""
from pathlib import Path
import plistlib,sys
app=Path(sys.argv[1]);info=plistlib.loads((app/'Info.plist').read_bytes())
for key in ('CFBundleIcons','CFBundleIcons~ipad'):
 primary=info[key]['CFBundlePrimaryIcon']
 assert primary['CFBundleIconName']=='AppIconM2667',(key,primary)
 names=primary['CFBundleIconFiles'];assert names
 for name in names:
  assert name.startswith('AppIconM2667'),(key,name)
  assert list(app.glob(name+'*.png')),(key,'missing compiled icon',name)
assert (app/'Assets.car').is_file()
print('PASS: packaged iPhone and iPad primary icons use AppIconM2667 and have compiled PNG resources')
