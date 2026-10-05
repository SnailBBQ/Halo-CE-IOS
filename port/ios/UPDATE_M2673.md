# M2.6.73 — Non-Jailbreak Version is a diagnostics build again; a better address-space probe

Regular app 0.2.73 / 2673. The Mod Test app derives its version from it (0.2.73.1 / 267301). OpenCE build 101 is unchanged.

## What changed

- **The signed-code experiment is removed (M2.6.71 and 72).** It linked the guest's executable bytes into the signed app and remapped them. It is gone from the
  Non-Jailbreak Version for three reasons. The extractor stopped every build: it refused a read-only segment that starts inside the last page of the code and runs past it,
  which is what the real guest has, and its test only covered tidy layouts. It also could not help the failure on a stock install: the address-space reservation runs first and
  fails, so the remap would never have been reached. And the log from a stock Sideloadly install showed writable pages becoming executable, so it was not shown to be the blocker.
  The Non-Jailbreak Version is back to what M2.6.69 made: the official app plus address-space and JIT diagnostics and the fixed-window fallback. It still requests no kernel
  memory entitlements. The extractor, its test and the SideStore entitlements file are deleted.
- **A better probe.** Every Non-Jailbreak boot now logs the process's own address-space map before anything is reserved: the range the system allows, how many ranges are mapped,
  the largest free gaps, and whether any whole 4 GiB-aligned 4 GiB window is free. The same log from a TrollStore install gives a baseline to compare against.
  The fixed-window probe now also tries 4 GiB, and a fixed request that the system placed elsewhere is described in words instead of as `error -1`.
- **Mod Test (from M2.6.70) is kept, with its loose ends fixed.** Its version is derived from the official one instead of being typed in, so the next version bump cannot ship a stale
  number. The build now proves, as the Non-Jailbreak build does, that Mod Test code exists in a Mod Test build and in no other. The Mod Test options in Actions are named
  **Mod Test app** and **Non-Jailbreak Version** again.

## What the evidence says, and what it does not

The M2.6.69 log from a Sideloadly install on an iPhone 14 Plus (iOS 16.2): single reservations up to 4 GiB worked and 6 GiB did not, at most 5 GiB could be held at once, and 0 of 24 fixed
windows could be reserved. The guest needs a 4 GiB-aligned 4 GiB window. That is an address-space limit, not a memory limit, and no change to how the code is signed or loaded alters
it. Whether any such window exists on a stock install is what the new map shows.

## Device checklist

1. Build the Non-Jailbreak Version (Actions, **Non-Jailbreak Version** ticked). Install it with Sideloadly.
2. Collect `ios-boot.log` right after the launch. It opens with the Non-Jailbreak line, the executable-memory line and the address-space map.
3. Send it with the installer, iOS version and device. If you can, collect the same log from a TrollStore install of this build as a baseline.

## What the map decides

| What it shows | Next step |
| --- | --- |
| A whole free aligned window exists but the reservation was refused | Reserve that address directly |
| Only free gaps smaller than 4 GiB | Map only the guest's real ranges inside what is free (needs an audit), or a guest build with inline address translation |
| The allowed range is smaller than 4 GiB above the app | The identity design cannot work there; an inline-translation guest build is the only route |

## Files to delete in the repository

`tools/ios_signed_guest.py`, `tools/tests/test_ios_signed_guest.py` and `port/ios/HaloIOS/HaloIOS-Sidestore.entitlements`.

## Validation

`test_ios_va_map.c` checks the map analysis against made-up maps (merging, gaps, whole free windows, an unknown range, hostile input, safe formatting) and `test_ios_va_plan.c` the
planner, including the new wording. The flag-isolation tests check that none of this code exists in an ordinary build, and a new `test_ios_mod_test_flag.py` does the same for Mod Test.
The workflow policy test checks the build menu, the flavor flags, the version derivation and the marker proofs. The memory-map collection is Apple-only code that has not been compiled here:
CI is the first check of it, and a device run the second.
