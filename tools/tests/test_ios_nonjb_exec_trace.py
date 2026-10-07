"""M2.6.84 Non-Jailbreak execution canary and persistent handoff trace guards."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
RUNNER = (ROOT / "port/ios/HaloIOS/halo_guest_runner.m").read_text()
APP = (ROOT / "port/ios/HaloIOS/AppDelegate.m").read_text()
STATE = (ROOT / "port/ios/HaloIOS/halo_launch_state.h").read_text()

# The canary is deliberately tiny and deterministic: movz w0,#0x4841; ret.
assert "CANARY_GUEST_VA = 0x0FFF0000u" in RUNNER
assert "0x52890820u" in RUNNER and "0xD65F03C0u" in RUNNER
assert "halo_guest_commit(CANARY_GUEST_VA, page)" in RUNNER
assert "sys_icache_invalidate(host, sizeof(code))" in RUNNER
assert "halo_guest_protect(CANARY_GUEST_VA, page, PROT_READ | PROT_EXEC)" in RUNNER
assert "halo_guest_decommit(CANARY_GUEST_VA, page)" in RUNNER
assert "result == CANARY_MAGIC" in RUNNER

# Persistent breadcrumbs must bracket the actual instruction fetch and real guest handoff.
for marker in (
    "nonjb 401 guest bridge installed",
    "nonjb 402 exec canary mapping",
    "nonjb 403 exec canary entering",
    "nonjb 404 exec canary returned",
    "nonjb 405 real guest image protected",
    "nonjb 408 guest main stack ready",
    "nonjb 410 main guest thread entered",
    "nonjb 411 execution guard armed",
    "nonjb 412 guest start pointer resolved",
    "nonjb 413 calling __guest_start",
    "nonjb 416 first host import host_set_tp",
):
    assert marker in RUNNER, marker

assert RUNNER.index('halo_crash_phase("nonjb 403 exec canary entering")') < RUNNER.index("result = entry();")
assert RUNNER.index("result = entry();") < RUNNER.index('halo_crash_phase("nonjb 404 exec canary returned")')
assert RUNNER.index('halo_crash_phase("nonjb 413 calling __guest_start")') < RUNNER.index("start(context.boot_va);")
assert RUNNER.index("start(context.boot_va);") < RUNNER.index('halo_crash_phase("nonjb 418 __guest_start returned")')

# The first host callback is evidence that real guest code progressed through __guest_start.
set_tp = RUNNER[RUNNER.index("static void ios_host_set_tp"):RUNNER.index("static HgCache g_geometry_cache")]
assert "g_nonjb_first_host_import_logged" in set_tp
assert "pthread_equal(pthread_self(), g_main_host_thread)" in set_tp
assert "first guest host import reached" in set_tp

# Everything diagnostic must stay out of ordinary/Mod-Test host source after preprocessing.
def active_lines(text: str, nonjb: bool):
    active = [True]
    branch = []
    out = []
    for line in text.splitlines():
        s = line.strip()
        if re.match(r"#\s*if", s):
            parent = active[-1]
            if "HALO_NON_JAILBREAK" in s:
                cond = nonjb
            else:
                cond = True
            branch.append((parent, cond))
            active.append(parent and cond)
        elif re.match(r"#\s*else", s):
            parent, cond = branch[-1]
            active[-1] = parent and not cond
        elif re.match(r"#\s*endif", s):
            active.pop(); branch.pop()
        elif active[-1]:
            out.append(line)
    return "\n".join(out)

ordinary = active_lines(RUNNER, False)
nonjb = active_lines(RUNNER, True)
assert "NON-JB EXECUTION TRACE" not in ordinary
assert "nonjb_guest_arena_exec_canary" not in ordinary
assert "NON-JB EXECUTION TRACE" in nonjb and "nonjb_guest_arena_exec_canary" in nonjb

assert '"nonjb "' in STATE, "launch-state classifier must preserve silent-stop breadcrumbs"
assert "keeps the M2.6.84 execution trace" in APP and "Stage 2 runs an isolated synthetic 32-bit guest model" in APP
print("PASS: Non-JB uses the real guest-arena RW->RX path for an execution canary, persists numbered guest-handoff breadcrumbs, records the first host import, and leaves ordinary builds untouched")
