> Historical milestone note. Features, limits and validation statements describe this update when written. For current behaviour, use the [Settings guide](../../docs/ios/SETTINGS.md) and [project status](../../IOS_PORT_STATUS.md).

# iOS performance migration review

Grok's proposal correctly identifies repeated guest-pointer fault handling as a major candidate for improvement. Current device logs show rendering dominating CPU time; small native color conversion has not materially improved FPS. This evidence supports moving repeated work into native helpers, but does not identify every remaining cost.

## Applied in M2.6.23

Vertex attribute state comparisons and setup now use one native call per attribute, retaining the existing guest execution bridge, renderer invalidation points and buffer-binding shadow. No guest pointers are retained by the native cache. Tests exercise field changes, constant-value transitions, bounds and invalidation. Actual iPhone benefit remains unverified.

## Full static conversion requires a coordinated ABI change

The [reference converter](https://github.com/NicholasDominici/halo-ce-ios/blob/ios-port/tools/ios_asm_convert.py) reserves x15 for scratch and x27 for the arena base. Its guest build reserves these registers and disables compressed jump tables; its entry assembly sets the arena register. This is an experimental architecture reference, not a measured performance guarantee for this fork.

Before enabling an equivalent rewrite here:

1. Reserve registers for every compiled guest object and audit handwritten assembly, relocations, jump tables, PC-relative address normalization, pre/post-index addressing and stack accesses.
2. Set and preserve the arena register at every entry, worker, callback and guest re-entry. Audit host-call stubs separately: native function addresses cannot be truncated and arena-adjusted like guest branch targets.
3. Validate memory and indirect-branch transformations with instruction emulation and full guest builds, then test signed device launch, menu, campaign loading and sustained gameplay. Keep a known working recovery build. The previous selective rewrite passed instruction tests but still caused a launch regression; its precise cause is unresolved.
4. Implement coherent dirty tracking before depending on it for mutable buffers. Current iOS memory-watch helpers are placeholders. Apple-page-size protection, the fault handler, native writes, invalidation and concurrent workers must agree; enabling protection alone is insufficient.

The current runtime loads and protects the guest image; vm_remap is not an existing feature to preserve here. No JIT, memory-layout migration or static conversion is enabled by M2.6.23. Replacing the converter alone would leave incompatible runtime assumptions.

## Next evidence

Compare the same scenes and separate loading, update and rendering measurements. Renderer sub-phase timings overlap and must not be summed as independent costs. If vertex-state savings are small, use the remaining phase measurements to select the next bounded native loop. A full static migration should be a separately validated architecture change.
