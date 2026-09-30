# iOS Port Status

Branch baseline: Halo CE Universal build 34 user-provided source.

Current milestone: **M0 - physical-device address-space feasibility**.

Build/test workflow: **Windows -> GitHub Actions macOS/Xcode runner -> unsigned IPA -> Sideloadly -> physical iPhone/iPad**.

Existing Windows/Linux/Android ports are intentionally unchanged. See `port/ios/README.md` and `.github/workflows/ios-m0.yml`.

## M0.1 - Physical-device address-space survey
M0 installed and ran on a physical iPhone. The device reported a 64-bit process and 16 KiB pages, while the original fixed mappings at 0x80000000 (128 MiB) and 0x88000000 (32 MiB) failed. M0.1 expands the probe to test non-fixed address hints, Mach fixed allocations, iOS-selected contiguous 128/32/160 MiB arenas, and representative one-page fixed allocations throughout the low 4 GiB. Guest integration remains gated on these results.
