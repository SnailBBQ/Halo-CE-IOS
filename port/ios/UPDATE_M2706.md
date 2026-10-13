# M2.6.106 - guest ABI fix

**Problem:** M2.6.104 and M2.6.105 (builds 182 and 201) would not start. The log ended with `FULL GUEST: image header mismatch.`

**Cause:** OpenCE moved the guest/host contract to `HALO_GUEST_ABI_VERSION 2` and added `thread_detach` to `struct halo_guest_header`. The iOS runner still expected version 1, so it rejected the freshly built game. The acceptance gate only checked host imports, so it did not catch this. M2.6.103 and earlier are not affected.

**Fix:**
- `halo_guest_runner.m`: ABI version 2, `thread_detach` added to the header, and secondary guest threads call it on exit (as upstream's host does) to free their thread block.
- `tools/tests/test_ios_import_coverage.py` (part of the strict gate) now also compares the magic, ABI version and header field order between `port/android/include/halo_android_abi.h` and the runner, and fails on any difference.

OpenCE build 201 / network 28 are unchanged. Not yet confirmed on a device; check Regular first, then Non-Jailbreak.
