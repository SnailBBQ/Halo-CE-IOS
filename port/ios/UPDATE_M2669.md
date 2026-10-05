# M2.6.69 — Non-Jailbreak Version: finding out what a stock install allows

Official app 0.2.69 / 2669; separate Mod Test app 0.2.69.1 / 266901. Universal build and OpenCE build 101 are unchanged. This update adds
a **manual build flavor of the official app** and changes nothing in ordinary builds.

## Why

Installs that are not jailbroken or TrollStore-signed stop before the first map with `FATAL: 4-GiB-aligned original-address guest runtime
failed`. The goal is for those players to join the same multiplayer games as everyone else, so this is the **official app** with the same
bundle identifier, Universal build, multiplayer protocol and map content, not a separate fork. Nothing about the flavor is put into network
traffic or lobby listings.

What the DolphiniOS source (reviewed, not copied: it is GPLv2+) showed: its non-jailbreak build ships without the address-space entitlement
and falls back from a 14 GiB reservation, and it never enables JIT itself on a stock install; an external tool attaches a debugger. Both
apply to Halo: our loader also makes loaded code executable, so a stock install needs a JIT-enabling tool even if the address-space problem
is solved. Neither is proven for Halo yet.

## How it is built

One source tree: everything is behind `HALO_NON_JAILBREAK`. In **Actions → Halo CE iOS — Build IPA → Run workflow**, run it on `main` with
`non_jailbreak` set. It produces the artifact `HaloCE-iOS-NonJailbreak` containing `HaloCE-NonJailbreak.ipa`. It cannot be combined with
`compatibility_test` (Mod Test), and automatic builds of `main` never enable it. It has its own cancellation group, so a manual flavor build
and an official push build do not cancel each other. The official bundle identifier is kept, so saves, backups and profiles are shared; the
installer may still rewrite the identifier.

## What the flavor adds

Only in that build:

- A boot-log marker, the compile time, and whether a debugger is attached at boot (observation only).
- An executable-memory report: whether a debugger has enabled JIT for the process, and whether a writable page can be made executable, mapped
  executable directly, or mapped with `MAP_JIT`. Pages are only mapped and re-protected, never executed.
- If the production 8 GiB reservation is **refused**: an address-space survey (single reservations of 1–16 GiB, how many 1 GiB reservations can
  be held at once, which fixed 4 GiB-aligned windows can be reserved), then a try at a fixed 4 GiB-aligned window (24 candidates from 8 GiB). If
  one is free, boot continues with it; the window is exactly what the production path would have kept (`low32(host_pointer) == guest_address`
  still holds). If none is, the report and a plain-language explanation are logged before the usual startup block.
- When the production reservation works, the flavor behaves like the official app, with the diagnostics above in the log.

## Not changed, and not proven

Ordinary builds, TrollStore and jailbreak installs are untouched: the new code is compiled out, and CI checks the executable of an ordinary
build for its absence. The production allocation, the 4 GiB-aligned arena, the guest loader and execution bridge, signing and entitlements
are unchanged. Nothing here makes a stock install work; at most it may get past the address-space step, and the loader's need for executable
memory may then stop it. The fixed window is only a try: another mapping may occupy it.

## Validation

`test_ios_va_plan.c` runs the planner against simulated address spaces (3, 6 and 100 GiB ceilings, occupied windows, a reserver that answers at
the wrong address) and checks exact results, that nothing is leaked or misplaced, safe formatting and the JIT verdicts.
`test_ios_non_jailbreak_flag.py` checks that every new identifier is inside the flag, that the runtime compiles with it off, on and undefined,
and that the ordinary object has none of the new symbols or strings; it was confirmed to fail on two deliberate leaks. The workflow policy test
checks that the flavor cannot touch an ordinary run, the conflict guard, artifact names and the cancellation groups. Apple compilation and
device behavior are separate checks.

## Device checklist

1. Build the flavor as above and install the same IPA with each installer you want to compare, on a device that is not jailbroken.
2. Right after a launch, collect `ios-boot.log` and `launch-phase.txt`. Note the installer and version, the iOS version, whether any JIT tool
   or debugger was used, and whether a cold launch after a reboot reaches gameplay.
3. Read the log for: the address-space survey, whether the fixed window was used, and the executable-memory line.
4. Check the official IPA's log contains none of these lines.

## What the results decide

| Finding | Next step |
| --- | --- |
| A fixed window is reserved and the game reaches gameplay | Make it the default fallback, in the official app |
| Only 1–3 GiB can be reserved | A sparse identity mapping of just the guest's ranges (needs an audit) on a short-lived branch |
| Almost nothing can be reserved | A guest build with inline address translation (large, slower) |
| Executable memory is refused | JIT enabling is needed before anything else matters |
