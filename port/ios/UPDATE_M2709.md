# M2.6.109 - OpenCE build 206 (network 29)

Integrates OpenCE build 206 (commit 8102e711c353068d22d62efe6bf67ebc8a90a22e) over build 201.

**What changed upstream**
- Network version 29 (was 28): builds 206 and 201 cannot join each other's games.
- Custom Edition maps keep their names. A game is on a map by its name and says which version it is by the first 32 bits of the map's hash. Build 201's renaming of every map to `name_<hash>.map` is gone; a map that build renamed gets its name back when no other map has it.
- A downloaded map that cannot be played is deleted; a stopped download keeps one `.part` file; the host also shares maps in a Custom Edition install folder.
- New map-share restart and trust handling, a peer-address reuse fix for internet play (`p2p.c`), `snprintf` for map and tag names (`main.c`, `hud.c`), and Custom Edition cache/geometry/sound fixes.
- `stb_vorbis` moved to `port/third_party/stb_vorbis` and is built into the guest from there.

**iOS work**
- 37 files taken byte for byte, 4 merged (`p2p.c`, `xbox_sound_cache.c`, `hud.c`, `main.c`) with our `HALO_IOS_GUEST` blocks kept, `port/linux/game/stb_vorbis.c` removed.
- No change to the guest ABI (still version 2), the host import list or the `posix_*` helpers, so the runner is unchanged. The ABI and `hostposix_*` checks added in M2.6.106/107 pass.
- Strict acceptance gate (flags-off equivalence against the build 206 tree) and the local arm64_32 compile, convert and assemble checks for every changed file pass, for both guest architectures.
- Version strings, the Library/Mods text and docs now say build 206 / network 29.

Not run on a device. Remove with `git rm`: `port/linux/game/stb_vorbis.c`. To check: start, host and join a game with a PC build 206 host, and import a Custom Edition map.
