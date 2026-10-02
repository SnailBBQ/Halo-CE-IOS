# M2.6.33 — sound, multiplayer, Share logs, frame rate

Found from the M2.6.32 device logs.

## Why there was no sound and no internet play

The iOS host started the game with `HALO_NO_AUDIO=1`, `HALO_NET_ONLINE=false` and `HALO_INTERPOLATION=false` in its
environment (`halo_guest_runner.m`). Those were safe defaults from the early milestones and they switched off exactly
the three things M2.6.32 had just built: the audio path, the internet-play invites, and 60 FPS. They are gone.
Sound and internet play are on; 60 FPS is the **Smooth 60 FPS** switch in Settings (read at launch).

If sound still does not start, the log now says why: `audio: could not open output ... - <reason>` (Summary tab → Sound).

## System link (finding games on the same Wi-Fi)

Your game log showed `sent out a broadcast game search packet` followed by `write_endpoint() returned error
'transport_error_endpoint_io'`, no UDP traffic at all in the traffic logs, and the game joining itself on 127.0.0.1:5150.
So the search never left the phone. Two likely causes, both handled:

- iOS refuses a send to 255.255.255.255 from a socket that is not tied to an interface. The search is now also sent to each
  Wi-Fi network's own broadcast address (for example 192.168.1.255). Tested with a fake interface list.
- If **Local Network** permission for Halo CE is off, iOS refuses every local send. The first failures are now written to the
  log with the system error, and a message tells you to turn it on: Settings → Privacy & Security → Local Network → Halo CE.

Internet play (invite links): host from Multiplayer → System Link on either device. On iPhone use Settings →
**Share my invite link**; to join, paste a link into the **Paste an invite link** box in Settings and tap **Join this invite**
(or open a `halo://` link). Pasting into that box does not trigger the iOS "Allow paste" question.

## Share logs

The Log and Settings screens cover the app's root screen, and iOS silently ignores a share sheet presented from a screen that is
not on top, so the button did nothing. It now presents from the top screen.

## Performance

- The profile showed 97% of the game thread inside clock reads: the 30 FPS frame limiter was a busy-wait. It now sleeps (1 ms steps).
  That frees a CPU core, cuts heat (a hot phone slows itself down, which was the stability problem) and saves battery.
- 25-28% of the remaining time was the texture hash (byte-at-a-time). The replacement reads 32 bytes per step and is 16 times
  faster in `tools/tests/test_ios_hash.c`, which also checks stability, sensitivity to every bit and collisions.
- 60 FPS: the original game logic runs at 30 ticks a second; Smooth 60 FPS draws a frame for every display refresh and blends
  between ticks. It was switched off before; it is on by default now and can be turned off in Settings.

## Not verified on a device

Everything above except the tests has not run on an iPhone. In particular: whether the broadcast reaches your PC, whether sound
starts, and the real frame rate with Smooth 60 FPS.
