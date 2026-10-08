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

# CI must compile the Stage-2 runtime for the actual iPhoneOS arm64 target,
# inspect its undefined-symbol set, and reject any compiler-emitted clear-cache
# helper before spending time on the full Xcode build.
for token in (
    "test_ios_nonjb_link_dependencies.py",
    "xcrun --sdk iphoneos --show-sdk-path",
    "-target arm64-apple-ios15.0",
    "halo-flex-runtime-ios.o",
    "nm -u",
    "sys_icache_invalidate",
    "clear_cache",
):
    assert token in WF, token
assert WF.index("halo-flex-runtime-ios.o") < WF.index("- name: Build device host app")
print("PASS: Non-JB Stage-2 uses Apple's sys_icache_invalidate and CI audits the real iPhoneOS object for forbidden __clear_cache lowering before Xcode")
