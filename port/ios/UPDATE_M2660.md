# M2.6.60 — Preserve input during settings synchronization

Settings notifications previously cancelled every active touch and cleared physical
controller snapshots, even when only audio, video or profile metadata changed.
Touch ownership now survives unrelated updates. Changing the active touch scheme
still cancels obsolete holds before applying the new layout. Touch cancellation
no longer clears physical controller buttons or axes; full runtime resets retain
their previous behavior.

The regression tests cover synchronized settings, inactive scheme edits, active
stick geometry, fire ownership and profile switching. The guest loader, pointer
bridge, signing, controller routing and engine gameplay preferences are unchanged.

## Device checklist

- Hold movement and look while changing audio or synchronized engine settings.
- Repeat with a controller, including a stationary held stick and held trigger.
- Switch control schemes: old touch holds must release without sticking.
- Test simultaneous move/look/fire, background/resume and local co-op.

Local tests cannot establish device input feel. Signing diagnostics from M2.6.59
remain available; this input fix does not solve missing signing capabilities.
