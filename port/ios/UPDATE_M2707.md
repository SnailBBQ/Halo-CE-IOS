# M2.6.107 - internet play join fix

**Problem:** On M2.6.106 the game starts, but joining a multiplayer game freezes. The log ends with `Internet play: joining ...` and `secondary guest thread aborted, reason=3` (a missing host import).

**Cause:** OpenCE build 182 added nine host imports for internet play with browsers: `hostposix_dtls_*` (8) and `hostposix_hmac_sha1`. The iOS runner mapped none of them, so the first call stopped the network thread. The gate only checked the shorter `host_imports.list`, not the `hostposix_*` imports generated from `posix.h`.

**Fix:**
- `hmac_sha1` is implemented with CommonCrypto.
- `dtls_*` report "unavailable" (no DTLS fingerprint), because Mbed TLS is not part of the iOS build. Joining from the iPhone uses the native path; browser peers over WebRTC are not supported on iOS yet.
- `tools/tests/test_ios_import_coverage.py` (in the strict gate) now fails if any `posix_*` helper in `posix.h` has no mapping.

Not yet confirmed on a device.
