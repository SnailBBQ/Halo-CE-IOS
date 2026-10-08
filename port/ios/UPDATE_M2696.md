# M2.6.96 — Non-Jailbreak Stage-3 x27 preservation guard hotfix

Regular app **0.2.96 / 2696**. The Mod Test app derives **0.2.96.1 / 269601**. OpenCE remains **build 146** (`314f576515585560ea6b375b0d5b8a02fd8991af`), **network version 22**. Regular and Mod Test runtime behavior is unchanged.

## What M2.6.95 exposed

M2.6.95 fixed the first legal register-offset form and advanced the real flexible-base guest build from object **50/1492** to **63/1492**. The next stop was musl `scandir.o`:

```text
flexible-base guest source names reserved x15/x27
```

The guard was intentionally fail-closed, but this specific stop was a false positive. With the real `arm64_32-apple-watchos` target and both `-ffixed-x15` and `-ffixed-x27`, LLVM may still preserve the callee-saved x27 register in a normal host-stack prologue/epilogue pair, for example:

```asm
stp x28, x27, [sp, #16]
...
ldp x28, x27, [sp, #16]
```

That does **not** allocate x27 for guest computation. x27 already contains the immutable 64-bit flexible-arena base, the prologue saves that exact value to the real host stack, and the epilogue restores it unchanged.

## Fix

M2.6.96 replaces the blanket whole-file `x15/x27` text rejection with an instruction-level reserved-register guard.

Allowed x27 use is deliberately narrow:

- only the compiler-generated 64-bit `stp/ldp x28, x27, [sp, ...]` (or reversed register order) callee-save preservation/restoration pattern
- assembler metadata/directives and comments, which do not execute

Everything else remains fatal:

- any source use of x15/w15
- arithmetic or moves involving x27
- branches through x27
- guest-memory addressing through x27
- any w27 use, including a 32-bit spill that would truncate the arena base

The x27 arena-base / x15 scratch ABI, register-offset rewrites from M2.6.95, real arbitrary-base arena activation and phases 600–609 are otherwise unchanged.

## Regression coverage

`tools/tests/test_ios_flex_stage3.py` now checks both sides of the rule:

- safe x27 host-stack preservation is retained unchanged
- computational x27/w27 and source x15 uses still fail conversion
- a real arm64_32 Clang register-pressure probe is compiled with `-ffixed-x15 -ffixed-x27`, passed through the complete converter, then assembled as AArch64 ELF when Clang is available
- an additional local 80-function register-pressure stress compile produced 160 x27 occurrences, all of them the same x28/x27 `stp/ldp` preservation family; its converted output assembled successfully

The local probe reproduces LLVM's `stp/ldp ... x27 ... [sp]` behavior and verifies that the converted output still assembles.

## Validation limit

The local environment still lacks the Android NDK used by Actions for the complete 1,492-object OpenCE guest build. GitHub Actions remains the authority for the next real compiler-emitted form. The converter remains fail-closed: unsupported register use or memory addressing still stops CI before an IPA is produced.

## Test target

Run the manual **Non-Jailbreak Version**. The immediate success criterion is that `Build recovered Halo guest ELF` progresses past musl `scandir.o` / object 63 and continues further through the 1,492-object guest build. Only after the flexible guest links should the IPA be device-tested for phases 600–609.
