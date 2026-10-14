# M2.6.108 - voice chat microphone, notices, release documentation

**Voice chat microphone.** You could already hear other players; now you can talk.
- In the game, **Settings > Audio > Voice Chat**: choose **OPEN MIC** to talk, **OFF** to never use the microphone. (The default, PUSH TO TALK, needs a keyboard key.) The app asks iOS for microphone access only when OPEN MIC first opens the microphone in a voice-chat game.
- Headphones with a microphone (AirPods, other Bluetooth or wired headsets) are used automatically. The audio session switches to play-and-record with Bluetooth allowed while the microphone is open and returns to playback only when it closes. If the input changes (headset connected or removed), capture follows it.
- iOS lowers Bluetooth headphone quality while the microphone is open; OFF restores it.
- `Info.plist` gained `NSMicrophoneUsageDescription` (without it iOS ends the app on first microphone use).

**Notices.** The packaging workflow now writes `THIRD_PARTY_NOTICES.txt` (project license, Overpass and OpenCE font licenses, every bundled component's license) into the app and checks that it is in the IPA.

**Documentation.** INSTALL.md no longer says free-account sideloading is unsupported while describing a working Non-Jailbreak device; MULTIPLAYER.md has voice chat and map sharing / data use sections; PUBLIC_RELEASE.md describes the notices.

Not run on a device. Test with OPEN MIC on speaker, with AirPods, and with the headset disconnected during a game.
