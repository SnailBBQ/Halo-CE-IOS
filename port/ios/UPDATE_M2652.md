# M2.6.52 — Release preparation and settings polish

Regular version 0.2.52; separate ModTest version 0.2.52.1. Universal build 84 remains the engine baseline.

- Sidebar ends with Cheats, Profiles, Options, Mods, Advanced and Logs.
- Game HUD preset and editor share a card. AirPlay is last in Display; Heat and battery is below Startup in Advanced.
- Resolution choices are 480p, 720p, 960p and 1080p. Existing settings keep their meaning; 480p remains the default. The 2.25 render scale is passed without decimal rounding and remains explicitly bounded in the guest renderer. Safe Start still uses 480p.
- The FPS/performance overlay measures its current text before positioning. Drag it in Edit Button Layout; FPS / Stats opens its size, opacity and visibility controls. Its memory estimate is not a termination threshold.
- An explicit Bonjour Local Network permission check complements existing UDP LAN discovery. Final signed-device validation is required; raw broadcast signing restrictions are not bypassed.
- Backups remembers an external Files folder and writes manual, versioned saves/profile archives. Restore uses the existing validation, recovery backup and next-launch flow, preserving Halo/save paths. App deletion cannot be intercepted; back up and confirm cloud upload before deleting. Reinstallation requires selecting the folder again. Maps and invites are excluded from save-only archives.

## Device checklist

1. Verify section order, Game HUD card and touch-layout overlay dragging, scale, opacity and visibility. Confirm no gameplay touch is intercepted outside editing.
2. Test 1080p with 4:3, widescreen and fullscreen; compare FPS, memory and temperature with 480p. Verify older settings and Safe Start.
3. On a fresh install, request Local Network access, accept/deny, and verify the system settings entry and actual LAN discovery with another client.
4. Save progress, export externally, verify upload, reinstall a test copy, select the folder and restore. Check save/profile integrity and recovery behavior. Confirm an in-place IPA update preserves saves.
5. Confirm regular and ModTest remain separate. Verify private invites and build 84 discovery.

No Apple compilation or device validation is claimed by local source checks.
