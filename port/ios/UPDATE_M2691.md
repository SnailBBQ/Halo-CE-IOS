# M2.6.91 — Apple host-link / CoreMedia hotfix

Regular app **0.2.91 / 2691**. The Mod Test app derives **0.2.91.1 / 269101**. OpenCE remains **build 146** (`314f576515585560ea6b375b0d5b8a02fd8991af`), **network version 22**. The M2.6.88 Custom Edition map manager and user-supplied MP4 movie fallback, the M2.6.89/M2.6.90 Apple test-harness fixes, and M2.6.86 Non-Jailbreak Stage-2 diagnostics are otherwise unchanged.

## Why M2.6.90 still failed

M2.6.90 passed the recovered arm64_32 guest build and the Apple-side Custom Edition and disc-install test harnesses, then reached the real **Build device host app** step. The Objective-C files compiled, but the final arm64 iOS link failed with one unresolved symbol:

```text
Undefined symbols for architecture arm64:
  "_kCMTimeZero", referenced from HaloMovieStartPath ... in HaloMods.o
```

`kCMTimeZero` is a CoreMedia symbol. M2.6.88 imported AVFoundation for `AVPlayer`/`AVPlayerLayer`, but the Xcode target linked AVFoundation without linking CoreMedia explicitly. The existing `test_ios_frameworks_linked.py` also did not recognize CoreMedia symbols, so its preflight incorrectly passed.

M2.6.91 makes the dependency explicit in both places:

- `HaloMods.m` imports `<CoreMedia/CoreMedia.h>` rather than relying on an AVFoundation umbrella include;
- Debug and Release `OTHER_LDFLAGS` both link `-framework CoreMedia`;
- the framework audit recognizes CoreMedia imports and common CoreMedia symbols such as `kCMTimeZero` and `CMTime*`, and continues to require identical framework sets in both build configurations.

No guest, Custom Edition, MP4 state-machine, renderer, networking, save, XISO, loader, or Non-Jailbreak runtime behavior changes in this hotfix.

## Review performed before packaging

The M2.6.88-to-M2.6.91 Apple integration was re-audited as a whole rather than only patching the linker line. The review checks that every Apple framework imported by the iOS host is represented in either the Xcode Frameworks phase or both configurations' `OTHER_LDFLAGS`; the movie guest imports are present in the generated import list and mapped by `halo_guest_runner.m`; `HaloMods.m` and the other M2.6.88 production files are already members of the device target; the strict OpenCE build-146 flags-off gate remains exact; and the previous Apple harness collision guards remain active.

The final Apple/Xcode link and physical-device MP4/Custom Edition behavior still require GitHub Actions and device testing.
