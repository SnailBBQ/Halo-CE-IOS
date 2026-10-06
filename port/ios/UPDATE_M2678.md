# M2.6.78 — Logs that are easy to send, and a start history

Regular app 0.2.78 / 2678. The Mod Test app derives its version from it (0.2.78.1 / 267801). The engine is as in M2.6.77 (OpenCE build 125). Nothing here has been built on Apple hardware or tested on a device.

## Why

A tester whose iPhone started the Non-Jailbreak Version and then closed it on its own could not get the logs out of the app. **Share logs** sent up to six raw files in one share sheet, the app had no way to copy the text, and the one step that says where a run stopped, `launch-phase.txt`, is overwritten as soon as the app is opened again. The log he finally sent by hand ended in "app launched", the step of the reopening, not of the run that died.

## What changed

- **Share logs sends one text file** (`Halo logs <date>.txt`) instead of the raw files. It is the same report as Settings > Report a problem: app version, device, iOS version, thermal state, memory, your settings (never running cheats) and the end of each log. The log files themselves stay in `Documents/Halo`.
- **Copy logs** puts the same report on the clipboard, shortened so that it pastes into a message (the boot log keeps its last 60 KB, the full report 200 KB). It is on the start screen next to Share logs, on the Diagnostics screen, and in Settings > Advanced as **Copy logs as text**.
- **A start history.** Each launch now reads where the previous run ended, as it already did, and also adds one line to `start-history.txt` when that run crashed, stopped during startup without a report, or was running normally and then stopped without one. The newest 20 lines are kept and they come first in the shared and copied logs, so opening the app again, or several times, cannot erase where a run stopped. Going to the background and a normal exit are not recorded.
- This is in all three apps (the regular app, the Mod Test app and the Non-Jailbreak Version). It is shared app code, not behind a build option.

## What was checked here, and what was not

- The history logic is plain C and has tests (`tools/tests/test_ios_launch_state.c`): which endings are recorded, the line's wording, keeping the newest 20, and never overflowing a buffer.
- `tools/tests/test_ios_log_export.py` reads the sources for the mistakes an edit like this can make: one report builder used by every way of sending logs, Share logs sending a single file, the new button in the row and styled with the others, the callbacks declared and assigned, and the history written before the launch overwrites the phase file.
- **Not checked:** nothing here can compile Objective-C, so the Apple workflow is the first compile of the changed screens. Neither the extra button's fit on the start screen (its title shrinks to fit like the others) nor any of this on a device has been seen.

## Device checklist

1. The start screen shows Import maps, Import disc image, Play Halo CE, Share logs and Copy logs, all readable.
2. **Copy logs** shows "Logs copied". Pasting into Notes gives text that starts "HALO CE iOS - problem report" and includes the end of the boot log. On a fresh install with no logs it says "No logs yet".
3. **Share logs** opens the share sheet with one text file, and sending it (Messages, AirDrop, Save to Files) works.
4. Diagnostics has Copy logs and Share logs. Settings > Advanced has Share log files, Copy logs as text and Report a problem.
5. After a start that ends without a report, open the app again: `Documents/Halo/start-history.txt` has a line naming the last step. Open it a second time: the line is still there. Copy logs shows it first.
