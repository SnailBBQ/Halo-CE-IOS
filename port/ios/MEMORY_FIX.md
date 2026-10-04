> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# Memory leak in the guest allocator, and a backtrace for the next crash

## What the a10 log showed

`FULL GUEST STOPPED: reason=2` after about three minutes of a10, with `EXECUTION FAULT ... fault=0x300000010`. 0x300000010 is the guest's own address
0x10: the game read or wrote through a NULL pointer plus 0x10. The usual cause of that in C is a memory allocation that failed and returned NULL, which the
game does not check. The "map stops loading" screenshot (level surfaces missing while objects still draw) fits the same cause: a failed allocation while the
renderer or the loader was building something leaves it half made.

## The leak

Two things in `halo_guest_runner.m` / `halo_guest_runtime.c`:

1. **Address space.** `guest_alloc` was a bump pointer over 0xA0000000..0xD0000000 (768 MiB). `munmap` never gave a range back, so every mmap the game's `malloc`
   made, even for memory it freed a moment later, was gone for good. A long session used the whole region and `mmap` returned ENOMEM.
2. **Physical memory.** `munmap` was `mprotect(PROT_NONE)`: the pages stayed resident and kept their contents. Freed memory was never returned to iOS.

## The fix

- `halo_guest_vm.h`: an address-space allocator with a sorted list of freed holes, merged with their neighbours, first fit, and the used area shrinking back when
  the end of it is freed. `munmap` now returns the range to it and `mmap` reuses holes before taking new space.
- `halo_guest_decommit` (used by `munmap`) now maps fresh anonymous pages over the range, which releases the memory and makes the next use of the range zeroed,
  as mmap promises.
- `tools/tests/test_ios_guest_vm.c`: 200,000 random allocations and frees checked against a page-by-page model, an endless allocate/free loop (the old allocator
  runs out after about 1,200 pairs of 0.6 MiB), exhaustion and recovery, a full hole table, and that freed memory comes back zeroed.

## New in the log (so a crash explains itself)

- Every 10 seconds: `guest memory: N of 768 MiB of the game's address space in use (highest ..., .. free in holes), .. failed requests` and
  `device memory: app footprint .. MiB, .. MiB left before iOS ends the app`. Diagnostics > Summary has a Memory card with them.
- When an allocation fails: `guest memory: out of address space (the game asked for .. KiB; ..)`; the first six are logged, and Problems lists it as an error.
- At a fatal fault: `FAULT FUNCTION` with the function the program counter was in, the link register and the frame-pointer chain. The old "FAULT PC SYMBOL" is
  only the last indirect call the bridge translated, a neighbour of the crash. Diagnostics > Summary shows "Where it stopped".

## If it still crashes or the walls still vanish

Send the log. The memory lines will say whether memory ran short (a high "in use" figure, failed requests, or little left before iOS ends the app), and the backtrace
names the function. If memory looks healthy at the moment of the fault, the cause is somewhere else and the backtrace says where.
