# M2.6.110 - OpenCE build 211, map sharing off by default

**OpenCE build 211** (commit 19d84ce7756f5f8c9bdf6f43207e74ce6bb3e206) over build 206. The network version is unchanged (29), so build 206 and build 211 play together.
- New high-resolution HUD work: selectable controller button style (`display.hud_button_style`: classic, gems, menu_gems), vehicle wrench and passenger-health meters, a sniper diamond, HUD sheet upscaling, new button art.
- Voice chat drops a packet that is not one 20 ms frame before the decoder sees it.
- The converter (`tools/android_asm_convert.py`) keeps string literals intact and handles quoted names with escapes; it has its own new test.
- iOS work: 60 files taken byte for byte, 2 merged (`menu_functions.c`, `xbox_textures.c`), the converter merged with our iOS fast-path options (its new test passes, and the iOS options are unchanged). No change to the guest ABI, the host import list or the `posix_*` helpers, so the runner is unchanged; the ABI and import checks pass. Strict gate against the build 211 tree passes.

**Map sharing is off by default on iOS.**
- `network.map_share` (host sends maps) and `network.map_seed` (helps others send them) default to false on iOS (`port_config.c`, behind `HALO_IOS_GUEST`). Downloading a map a game needs (`network.map_download`) stays on.
- A config.toml written by an earlier version already contains `true` for both. On the first launch of this version the app sets those two lines to false, once. A later choice is never undone.
- **Settings > Multiplayer > Network setup > Share maps with other players** turns both on or off by editing only those two lines of `Documents/Halo/config.toml` (comments and your other edits stay). It takes effect the next time the game starts. The in-game map sharing screens change the same file.
- `halo_toml_flags.h` is the editor; `tools/tests/test_ios_toml_flags.py` compiles and tests it.

Not run on a device. Local compile checks could not cover `hud_hires.c`, `voice_audio.c`, `port_config.c` and `xbox_textures.c` (they include headers that clash with the Linux headers used for the check); Actions compiles them with the iOS SDK. Remove with `git rm`: nothing new this time.
