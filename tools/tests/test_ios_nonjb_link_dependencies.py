"""Non-Jailbreak Apple-only link dependency guard for the Stage-2 runtime."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = (ROOT / "port/ios/HaloIOS/halo_guest_runtime.c").read_text()
WF = (ROOT / ".github/workflows/ios.yml").read_text()

assert "#include <libkern/OSCacheControl.h>" in RUNTIME
assert "static void nonjb_flush_instruction_cache" in RUNTIME
helper = RUNTIME[RUNTIME.index("static void nonjb_flush_instruction_cache"):RUNTIME.index("static int nonjb_flex_range")]
assert "#if defined(__APPLE__)" in helper
assert "sys_icache_invalidate(start, size);" in helper
assert "#else" in helper and "__builtin___clear_cache" in helper
assert RUNTIME.count("__builtin___clear_cache") == 2, "one mention is the explanatory comment and one is the non-Apple fallback"
assert "nonjb_flush_instruction_cache(exec_host, sizeof(exec_code));" in RUNTIME

# CI must keep Apple-only tooling out of the Ubuntu guest job, then compile
# the Stage-2 runtime for the actual iPhoneOS arm64 target in the macOS app
# job before the Xcode device build.
guest_job = WF.split("  build-arm64_32-guest:", 1)[1].split("\n  build-ios-app:", 1)[0]
app_job = WF.split("  build-ios-app:", 1)[1]
assert "xcrun --sdk iphoneos" not in guest_job, "Ubuntu guest job must not invoke Apple xcrun"
assert "halo-flex-runtime-ios.o" not in guest_job, "iPhoneOS object preflight belongs in macOS job"
assert "halo-flex-runtime.o" in guest_job, "portable Non-JB Stage-2 compile stays in Ubuntu job"
for token in (
    "Verify Non-JB iPhoneOS runtime dependencies",
    "if: ${{ inputs.non_jailbreak }}",
    "xcrun --sdk iphoneos --show-sdk-path",
    "-target arm64-apple-ios15.0",
    "halo-flex-runtime-ios.o",
    "xcrun nm -u",
    "sys_icache_invalidate",
    "clear_cache",
):
    assert token in app_job, token
assert app_job.index("Verify Non-JB iPhoneOS runtime dependencies") < app_job.index("- name: Build device host app")
print("PASS: Non-JB Stage-2 uses Apple's sys_icache_invalidate; Ubuntu stays Apple-tool-free and the macOS job audits the real iPhoneOS object before Xcode")
