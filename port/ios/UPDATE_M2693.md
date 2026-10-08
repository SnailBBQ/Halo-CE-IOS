# M2.6.93 — Non-Jailbreak Apple-preflight placement fix

Regular app **0.2.93 / 2693**. The Mod Test app derives **0.2.93.1 / 269301**. OpenCE remains **build 146** (`314f576515585560ea6b375b0d5b8a02fd8991af`), **network version 22**. The maintainer reports the regular M2.6.91 build green. This update changes workflow placement/tests/version documentation only; runtime code is unchanged from M2.6.92.

## Why the Non-Jailbreak M2.6.92 workflow failed

M2.6.92 correctly changed the Stage-2 Apple instruction-cache flush to `sys_icache_invalidate()`, but its new arm64-iPhoneOS object preflight was accidentally inserted into the Ubuntu **Build Halo engine guest** job. Ubuntu does not provide `xcrun` or an iPhoneOS SDK, so the workflow stopped at `xcrun: command not found` before the guest build or Apple linker could test the actual fix.

M2.6.93 keeps the portable Non-JB Stage-2 compile in the Ubuntu job and moves the Apple-only object/symbol audit into the macOS **Build and package iOS app** job immediately after the Apple toolchain is shown and before **Build device host app**. The macOS preflight runs only for the Non-Jailbreak flavor, compiles `halo_guest_runtime.c` for `arm64-apple-ios15.0`, checks its undefined symbols with `xcrun nm`, requires `sys_icache_invalidate`, and rejects any `clear_cache` dependency.

Regression tests now explicitly fail if `xcrun --sdk iphoneos` or `halo-flex-runtime-ios.o` ever appears in the Ubuntu guest job again.

## Scope

No Halo/OpenCE runtime source changes are made in this milestone. Custom Edition maps, MP4 movie fallback, the regular build, Mod Test, saves, networking, renderer, and Non-JB Stage-2 behavior are unchanged.

## Validation before packaging

Local checks cover workflow structure, Non-JB link-dependency source guards, the full available iOS Python regression suite, strict OpenCE build-146 flags-off acceptance, host-import coverage, portable Stage-2 compilation/model tests, and a clean apply simulation. The real iPhoneOS preflight and final Non-JB Xcode link remain GitHub Actions responsibilities because the local Linux environment has no Apple SDK.
