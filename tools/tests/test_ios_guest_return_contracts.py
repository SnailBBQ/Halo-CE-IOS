"""Guard iOS guest early-return contracts that changed in OpenCE build 138."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
textures = (ROOT / 'port/linux/src/xbox_textures.c').read_text()

signature = 'static BOOL decode_level(const struct xgpu_texture_description *description, unsigned long level,'
assert signature in textures, 'build-138 decode_level must remain BOOL'
start = textures.index(signature)
end = textures.index('\n#ifdef HALO_ANDROID', start)
body = textures[start:end]

assert 'if (host_texture_decode_texels((unsigned int)packet)) return TRUE;' in body, \
    'successful native texel decode must return TRUE from build-138 BOOL decode_level'
assert 'if (host_texture_decode_texels((unsigned int)packet)) return;' not in body, \
    'stale pre-build-138 bare return reintroduced in BOOL decode_level'
assert 'if (!x_offsets)\n\t\t\treturn FALSE;' in body, \
    'upstream build-138 allocation failure must still propagate FALSE'
assert body.rstrip().endswith('return TRUE;\n}'), \
    'guest texture converter must still report successful completion'

runner = (ROOT / 'port/ios/HaloIOS/halo_guest_runner.m').read_text()
assert 'static int ios_texture_decode_texels(uint32_t packet_va)' in runner
assert 'return result;' in runner[runner.index('static int ios_texture_decode_texels(uint32_t packet_va)'):runner.index('static void ios_frame_counts', runner.index('static int ios_texture_decode_texels(uint32_t packet_va)'))]

print('PASS: build-138 BOOL decode_level preserves TRUE/FALSE semantics across the iOS native texel shortcut')
