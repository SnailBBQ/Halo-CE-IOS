"""Voice chat's microphone on iOS: the permission text exists (iOS ends the app at the first use without it), the runner serves
the guest's callback-less F32 mono stream from the phone, Bluetooth headsets are allowed, and capture ends back at playback only.
Run: python tools/tests/test_ios_voice_microphone.py"""
import plistlib
import re
import sys
from pathlib import Path

HOST = Path(__file__).resolve().parents[2] / "port/ios/HaloIOS"
info = plistlib.loads((HOST / "Info.plist").read_bytes())
runner = (HOST / "halo_guest_runner.m").read_text(encoding="utf-8")
audio = (HOST / "halo_ios_audio.m").read_text(encoding="utf-8")
problems = []
if len(info.get("NSMicrophoneUsageDescription", "")) < 40:
    problems.append("Info.plist has no NSMicrophoneUsageDescription")
for needle in ("halo_ios_mic_open(s[2])", "if (callback) return 0;", "s[0] != 0x8120u || s[1] != 1u",
               "halo_ios_mic_read(out", "halo_ios_mic_available()", "halo_ios_mic_close()"):
    if needle not in runner:
        problems.append(f"runner: missing {needle}")
for needle in ("AVAudioSessionCategoryPlayAndRecord", "AVAudioSessionCategoryOptionAllowBluetooth",
               "AVAudioSessionCategoryOptionDefaultToSpeaker", "installTapOnBus", "AVAudioConverter",
               "AVAudioEngineConfigurationChangeNotification", "requestRecordPermission",
               "setCategory:AVAudioSessionCategoryPlayback"):
    if needle not in audio:
        problems.append(f"audio: missing {needle}")
# the permission is asked for only inside mic open, never at launch
if re.search(r"requestRecordPermission", runner + (HOST / "AppDelegate.m").read_text(encoding="utf-8")):
    problems.append("microphone permission must only be requested from halo_ios_mic_open")
if problems:
    print("\n".join(problems))
    sys.exit(1)
print("PASS: microphone permission text, F32 mono stream served from the phone, Bluetooth headsets allowed, playback restored on close")
