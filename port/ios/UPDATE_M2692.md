# M2.6.92 — Non-Jailbreak Stage-2 Apple cache-flush link hotfix

Regular app **0.2.92 / 2692**. The Mod Test app derives **0.2.92.1 / 269201**. OpenCE remains **build 146** (`314f576515585560ea6b375b0d5b8a02fd8991af`), **network version 22**. The maintainer reports that the regular M2.6.91 build completed green; this update changes only the Non-Jailbreak Stage-2 host path plus CI/version documentation.

## Why the Non-Jailbreak M2.6.91 build failed

The Non-Jailbreak flavor reached the real device-host link after the guest and Apple packaging harnesses had passed. Its only unresolved symbol was `__clear_cache`, referenced by `halo_guest_runtime.o`. M2.6.86's Stage-2 arbitrary-base RX canary called Clang's `__builtin___clear_cache()`. On the arm64 iPhoneOS object Clang lowered that builtin to an external helper, while the device target does not provide that symbol. The ordinary build excludes Stage 2, which is why the regular M2.6.91 build could link successfully while Non-JB failed.

M2.6.92 uses Apple's existing instruction-cache API instead:

- Apple builds include `<libkern/OSCacheControl.h>` and call `sys_icache_invalidate(start, size)`;
- non-Apple host-test builds retain `__builtin___clear_cache()` only as a portable fallback;
- the Stage-2 canary now validates its translated executable pointer once before copying/flushing it;
- CI compiles `halo_guest_runtime.c` for the actual `arm64-apple-ios15.0` target with the iPhoneOS SDK before Xcode;
- CI inspects that object's undefined symbols, requires `sys_icache_invalidate`, and fails if any `clear_cache` dependency appears.

The production guest, OpenCE source, Custom Edition manager, MP4 fallback, renderer, networking, saves, XISO path, Mod Test and Regular behavior are unchanged. The real Halo guest still does not run from the arbitrary Stage-2 arena.

## Validation before packaging

Local validation covers the Stage-2 source/model tests, Non-JB execution-trace isolation, workflow configuration, Linux host compilation of the Non-JB runtime, full iOS Python regression suite where dependencies are available, strict OpenCE build-146 flags-off acceptance, portable runtime tests and package-apply checks. The actual iPhoneOS object-symbol assertion and final Apple linker remain GitHub Actions responsibilities because the iPhoneOS SDK is not available in the local Linux environment.

## Device test

After Actions produces a Non-Jailbreak IPA, test the iPhone 14 Plus first. If aligned startup still fails but a hostile 4 GiB span is available, export the problem report and `launch-phase.txt`. A successful Stage-2 run should reach phase 527; this update does not enable the real arbitrary-base OpenCE guest.
