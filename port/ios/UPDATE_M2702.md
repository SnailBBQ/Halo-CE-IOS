# M2.6.102 - OpenCE build 159 (voice chat, vote-kick)

Source update: OpenCE build 155 -> build 159 (commit 84cf2f8f1928927ec925c7aabdb7dac8cce52988). Network version is still 24.

## What changed upstream
- Voice chat (Opus 1.5.2): `network_voice.c`, `voice_audio.c`, new `audio.*` and `network.voice_*` settings, push-to-talk (V).
- Player vote-kick (`network_votekick.c`).
- Three new host imports for the microphone capture stream.
- New menu XML and `port_settings.py` rows.
- Opus is compiled into the guest by `android_build.py` (`opus_sources()` / `opus_cflags()`); the tree is under `port/third_party/opus`.
- Tool changes.

## How it was merged
- Clean upstream files were taken byte for byte.
- Files carrying HALO_IOS_GUEST adaptations were three-way merged (`git merge-file`) against the flags-off view of the repo file.
- Gate: `tools/ios_upstream_acceptance.py --require-clean-flags-off --require-upstream` passes 10/10 (54 host imports covered, flags-off equivalence exact 46/46).

## iOS host behaviour
`halo_guest_runner.m` answers the three new microphone imports (`host_sdl_get_audio_stream_data`, `host_sdl_get_audio_stream_available`, `host_sdl_destroy_audio_stream`) as "no stream". The guest therefore sees no microphone: the iPhone can hear other players' voices through the game's own audio mix but cannot talk. Capturing the mic would need AVAudioEngine plus a microphone permission and is not part of this update.

## Local validation
- All 131 Opus sources and 12 game sources convert and assemble in both aligned and flex modes with 0 untranslated flex bases.
- Python test suite passes, except `test_ios_pointer_fastpath.py` which needs `keystone` (not available in the build environment).

## Not validated
- The full guest build, the Xcode build and device behaviour can only be confirmed by GitHub Actions and a phone.
- Voice chat and vote-kick are untested on iOS.
- The Opus BSD licence notice is not bundled in the IPA.

## Suggested test order
Regular first, then Non-Jailbreak. Check boot, a campaign level, then a multiplayer lobby if possible.
