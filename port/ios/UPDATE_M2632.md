> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# M2.6.32 — game first, audio, touch-look, control schemes, multiplayer, readable log

## What you see now

- The game is the first thing on screen. Setup (import maps, start) only shows when `ui.map` is missing.
- Top centre there are two small buttons: **⚙** (settings) and **Log**. The loading box is gone. The
  "SAVING… please don't turn off your Xbox console" box is the game's own message.
- If the engine stops, the readable log opens by itself.

## Controls

- **Floating sticks:** the move stick appears where your thumb lands on the left side. The look stick can float too.
- **Touch-look:** drag anywhere on the right part of the screen to look. Look speed, acceleration and invert are in Settings.
- **Stick feel:** dead zone, response curve, opacity, haptics.
- **Five control schemes** with names you choose. Each one remembers where every button is, how big it is,
  which are hidden, and the aim settings.
- **Layout editor** (Settings → Edit button layout): drag a control, select it, `−`/`+` to resize, Hide/Show, Reset all, Done.
  Controls are always kept on screen.
- Physical controllers (Xbox, PlayStation, MFi) still work and hide the on-screen controls.

## Audio

The game's own mixer (the one every platform uses) now feeds an output ring that Core Audio plays through
`AVAudioEngine`. Volume and a Sound switch are in Settings. The log reports `audio: playing through the speaker`
and the number of buffer underruns. Silent mode does not mute it (category Playback), like a game.

## Multiplayer

The invite system was already in the game (`halo://join/<44 hex digits>`, signalling over public MQTT brokers, STUN, a
reliable UDP stream) but every network call was stubbed to fail on iOS. Now:

- `halo_ios_net.c` implements the sockets: Winsock address layout, Winsock error codes and options, non-blocking connect,
  select. Tested on Linux over loopback (`tools/tests/test_ios_net.c`).
- Hosting: Multiplayer → System Link. The game puts the invite link on the clipboard. Settings → **Share my invite link** opens the share sheet.
- Joining: open a `halo://` link (the app registers the scheme), or Settings → **Join invite from clipboard**.
  "Join links on the clipboard automatically" is off by default because reading the pasteboard makes iOS ask permission.
- Same protocol as the Linux, Windows and Android builds, so crossplay is intended. **Not tested between two real devices.**
- Not available on iOS: UPnP and the Discord client. Internet play uses STUN and falls back accordingly.
- `Info.plist` gains the `halo` URL scheme and the local-network permission text (system link on Wi-Fi).

## Log

The log button opens four tabs: **Summary** (status, speed in plain words, where the time goes, sound, problems, multiplayer),
**Problems** (errors and warnings only), **Full log** (colour-coded, with a filter box) and **Game log** (`debug.txt`).
Messages that are normal on iOS (videos, Xbox hard-disk files) are greyed out and counted, not listed as problems.
Share still sends the three raw files.

## Performance

- The rewrite now also covers exclusive and acquire/release instructions (mutexes, malloc locks), which accounted for
  most of the remaining pointer faults in the M2.6.31 log.
- New **profiler**: every 2 ms the game thread's program counter is sampled; the log reports the share of time in game
  functions by name and in iOS libraries by module. This shows whether the remaining cost is the graphics driver or game code.
  It costs about 1% of one core and has a switch in Settings.
- Timing lines are in microseconds (they were rounded to 0.1 ms).

## Checks that run in the workflow

`test_ios_settings_core.c`, `test_ios_log_classify.c`, `test_ios_sdl_events.c`, `test_ios_audio_ring.c`, `test_ios_net.c`,
the extended `test_ios_arena_fastpath.py`, and `test_ios_sdl_event_numbers.c`, which compiles against the real SDL3 headers
and fails the build if the event numbers or field offsets the host writes are wrong.

## Not yet verified on a device

The Objective-C (controls, settings and log screens, audio engine, clipboard and URL handling) has only been
read for syntax; the macOS job is its first compile. Touch-look, audio and multiplayer have never run on a device.
