"""M2.6.86 Non-Jailbreak Stage-2 flexible-base isolation and wiring guards."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "port/ios/HaloIOS"
RUNTIME = (HOST / "halo_guest_runtime.c").read_text()
HEADER = (HOST / "halo_guest_runtime.h").read_text()
FLEX = (HOST / "halo_flex_base.h").read_text()
BOOT = (HOST / "halo_boot_integration.m").read_text()
APP = (HOST / "AppDelegate.m").read_text()
WF = (ROOT / ".github/workflows/ios.yml").read_text()

# The model must be explicit base + zero-extended 32-bit VA; it must be able to
# prove that the legacy low32 identity is false at a hostile base.
for token in (
    "HALO_FLEX_GUEST_SPAN",
    "model->host_base + (uintptr_t)start",
    "address - model->host_base",
    "halo_flex_base_is_hostile",
    "halo_flex_legacy_low32_matches",
):
    assert token in FLEX, token
assert "low32(host_pointer) == guest_virtual_address" not in FLEX

# Stage 2 is compiled only in the Non-Jailbreak flavor, and the real arena is
# never replaced with the synthetic arena.
block = RUNTIME[RUNTIME.index("/* ---- Stage 2 flexible-base synthetic guest"):RUNTIME.index("#endif\n\nint halo_guest_runtime_init")]
for token in (
    "halo_guest_runtime_nonjb_flex_stage2",
    "mmap(NULL, (size_t)HALO_FLEX_GUEST_SPAN",
    "halo_flex_base_is_hostile(&model)",
    "halo_flex_guest_va(&model",
    "halo_flex_legacy_low32_matches(&model",
    "pthread_create",
    "atomic_fetch_add_explicit",
    "nonjb_flex_decommit",
    "PROT_READ | PROT_EXEC",
    "nonjb 522 flex stage2 memory and remap passed",
    "nonjb 523 flex stage2 atomics and thread passed",
    "nonjb 524 flex stage2 imports and callbacks passed",
    "nonjb 525 flex stage2 exec canary entering",
    "nonjb 526 flex stage2 exec canary returned",
    "nonjb 527 flex stage2 synthetic guest passed",
):
    assert token in block, token
assert "g_guest_base =" not in block, "synthetic arena must never become the real Halo guest arena"
assert "start(context.boot_va)" not in block and "halo_guest_runner" not in block
assert "The real OpenCE guest is still deliberately disabled" in block

# The Stage-2 call happens only after aligned-arena initialization failed.
fail_branch = BOOT[BOOT.index('line("FATAL: 4-GiB-aligned original-address guest runtime failed.")'):BOOT.index("[1/3] Loading real ui.map")]
assert "halo_guest_runtime_nonjb_flex_stage2" in fail_branch
assert fail_branch.index("halo_guest_runtime_nonjb_flex_stage2") < fail_branch.index("return;")
assert "STARTUP BLOCKED: REAL GUEST FLEX-BASE CONVERSION NOT ENABLED" in fail_branch

# CI must compile the Non-JB runtime and run the host arithmetic model before
# spending the macOS build on an IPA.
assert "test_ios_flex_stage2.py" in WF
assert "test_ios_flex_base_model.c" in WF
assert "-DHALO_NON_JAILBREAK=1" in WF and "halo-flex-runtime.o" in WF
assert "FLEXIBLE-BASE STAGE 2:" in WF
assert "flex-base-stage2+exec-trace-v2" in WF

assert "Stage 2 never launches the real Halo guest" in APP
assert "Stage 2" in HEADER
print("PASS: Stage 2 uses a hostile 4-GiB base+uint32 model, exercises representative memory/thread/import/RX paths, stays isolated from g_guest_base, and is CI-gated")
