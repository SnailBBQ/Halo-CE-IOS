# M2.6.111

Settings additions on top of M2.6.110 (OpenCE build 211, network 29, unchanged).

- **Voice chat** (Settings > Audio): Off, Open mic or Push to talk. It writes `audio.voice_chat` in `config.toml`, so it matches the in-game
  Audio > Voice Chat setting. Open mic sends your voice whenever you speak; Push to talk needs a keyboard or controller button; Off keeps the
  microphone closed (you still hear others). Headsets with a microphone are used when connected. iOS asks for microphone access the first time.
  Takes effect the next time the game starts.
- **Big multiplayer games** (Settings > Multiplayer): an optional "Original player animations" switch (`game.enhanced_animations`) that skips the
  engine's extra animation work. It is a possible small saving with 20 or more players, not a measured fix.

## Frame rate in 20 to 30 player games

The log from a 20 to 30 player match showed the game falling behind the host's clock by about 48 ticks (about 1.6 s) the whole match, and the
phone at thermal state "serious". That points at the phone's processor and heat, not the network. A cause cannot be named from that log: the
frame-time and "Where the time goes" lines live in the boot log of the run, which starts over when the app is reopened.

To capture them: play the big match, leave the app open, then Settings > Advanced > Share log files, with Performance profiler on.

## Device checklist

- Settings > Audio shows Voice chat; pick Open mic, restart, join a game and speak; pick Off, restart, confirm others cannot hear you.
- Settings > Multiplayer shows the animations switch and it stays set after a restart.
