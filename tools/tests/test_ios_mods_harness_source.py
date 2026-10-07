"""M2.6.89 guards the Apple-clang syntax fixes in test_ios_mods.m."""
from pathlib import Path
p=Path(__file__).with_name('test_ios_mods.m')
s=p.read_text()
assert '#define CHECK(...)' in s
assert 'static unsigned char ReadMarker(' in s
assert 'static unsigned char Marker(' not in s
assert 'CHECK(ReadMarker(target)==1)' in s
assert 'CHECK([@[@{' in s  # collection literal remains covered by variadic CHECK
print('PASS: Objective-C mods harness avoids Apple Marker collision and accepts comma-containing literals')
