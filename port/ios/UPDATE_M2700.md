# M2.6.100 — Regular/Mod Test performance: translate x30 in the aligned converter

Regular app **0.2.100 / 2700**. The Mod Test app derives **0.2.100.1 / 270001**. OpenCE stays on **build 155 / network 24**. The Non-Jailbreak flavor is unchanged by this update (it already translated x30 from M2.6.99).

## What the Regular device log showed

A Regular-app log (14 reporting windows) showed frame rate collapsing to 10–33 FPS in windows where the SIGSEGV "PAGEZERO bridge" upgraded more than about 2.5 million faulting low pointers. Across the run the bridge handled **16.18 million faults**, and **99.7% came from one function, `stream_process`** (the DirectSound-emulation ADPCM/PCM decode loop in `port/linux/src/dsound_sdl.c`). Each fault costs roughly 7 µs (kernel trap, handler, register fix-up, return), so about 25,000 faults per frame is about 175 ms, which matches the 170–200 ms render hitches in the log. Outside those windows 15–20% of frames still took 18–25 ms.

## Cause

The aligned converter rewrites each `ldr/str [xN]` guest access to go through the arena scratch register, but it skipped x30 on the assumption that x30 only holds a return address. LLVM saves the link register and then reuses x30 as an ordinary register under pressure. In `stream_process` it keeps the ADPCM input pointer in x30 and issues two `ldrb [x30]` per nibble byte. Those pointers are valid 32-bit guest addresses, so every one faulted into the bridge, which upgraded it correctly but slowly. M2.6.99 fixed the same gap for the Non-Jailbreak converter because that model aborts instead of recovering.

## Fix (tools/android_asm_convert.py)

- Memory accesses with base x30 are translated like any other base register in the aligned model (`ldr w0, [x30]` becomes `ldr w0, [x15]` with x15 formed from w30 in the arena address, with offset, writeback and register-offset forms handled as for other bases).
- `blr x30` is translated; x30 used as an index stays an index; `ret`, `ldp/stp x29, x30` and x29 handling are unchanged.
- The bridge stays as the safety net. Nothing is removed; a pointer that really was a host address is still handled the old way.

## Tests

- `tools/tests/test_ios_arena_fastpath.py`: x30 added to the base-register loops and a new regression that compiles the real `decode_adpcm` loop with the Regular guest flags, converts it with `--ios-arena-fastpath`, asserts every memory base is x15, sp or x29, and assembles it. It fails on the M2.6.99 converter (`ldr w0, [x30]` left in place).
- `tools/tests/test_ios_flex_stage3.py`: the old "aligned converter leaves x30 alone" pin was flipped to expect translation in the aligned model, and the flexible-model x30 cases remain.

## Expected effect, and what is not proven

The change removes the dominant source of bridge faults, so the 10–33 FPS windows and 170–200 ms hitches tied to audio decoding should go away. It does not address everything in the log: the remaining 18–25 ms frames in normal windows are render-side (GL work and first-use shader/texture uploads, scene/native scan costs) and online play adds 210–290 ms ping. Those need a fresh Regular log from this build.

The 1,492-object guest build, the Xcode build and the actual frame rate run only on GitHub Actions and on the device. Locally the converter was checked on the real compiler output, the unit and instruction-form tests, and about 90 guest-flag sources.
