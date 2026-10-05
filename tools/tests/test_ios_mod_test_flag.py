"""The Mod Test app is a build option (HALO_MOD_TEST), not a branch. Its code must exist only in builds that ask for it: the cache limit is the
stock one without the flag, each Mod Test hunk sits inside a condition that names the flag, and the workflow passes the define only for the
Mod Test option. (The conditions test whether the macro is defined, so the workflow defines it only for a Mod Test build.)"""
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "source/cache/cache_mod_test_policy.h"
GATED = {
    "source/cache/cache_files.c": ["halo_mod_test_header(", "halo_mod_test_bsp(", "MOD TEST:"],
    "port/ios/HaloIOS/halo_cache_runtime.m": ["halo_mod_test_header(", "HALO_MOD_TEST_CACHE_FILE_LIMIT", "scenario_type"],
    "port/ios/HaloIOS/halo_boot_integration.m": ["Mod Test build:"],
    "port/ios/HaloIOS/halo_guest_runner.m": ["Startup memory detail", "STARTUP BLOCKED: GUEST"],
}


def live_without_the_flag(text):
    """Lines that are live in a build WITHOUT the flag: not in the #if branch of a condition that names HALO_MOD_TEST."""
    stack, live = [], []                      # entries: [flagged, in_else]
    for line in text.replace("\r\n", "\n").split("\n"):
        stripped = line.strip()
        if re.match(r"#\s*if", stripped):
            stack.append(["HALO_MOD_TEST" in stripped, False])
        elif re.match(r"#\s*else", stripped):
            if stack:
                stack[-1][1] = True
        elif re.match(r"#\s*endif", stripped):
            stack.pop()
        elif not any(flagged and not in_else for flagged, in_else in stack):
            live.append(line)
    assert not stack, "unbalanced preprocessor conditionals"
    return live


class ModTestFlagTests(unittest.TestCase):
    def engine_limit(self, defines):
        source = f'#include <stdio.h>\n#include "{POLICY.as_posix()}"\nint main(void){{printf("%08x",(unsigned)HALO_ENGINE_CACHE_FILE_LIMIT);return 0;}}\n'
        with tempfile.TemporaryDirectory() as folder:
            src, exe = Path(folder) / "probe.c", Path(folder) / "probe"
            src.write_text(source)
            built = subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror"] + defines + [str(src), "-o", str(exe)], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr[-1500:])
            return subprocess.run([str(exe)], capture_output=True, text=True).stdout.strip()

    def test_the_limit_is_stock_unless_the_flag_asks_otherwise(self):
        self.assertEqual(self.engine_limit([]), "11600000", "an ordinary build")
        self.assertEqual(self.engine_limit(["-DHALO_IOS_GUEST=1"]), "11600000", "an ordinary iOS guest build")
        self.assertEqual(self.engine_limit(["-DHALO_IOS_GUEST=1", "-DHALO_MOD_TEST=1"]), "18000000", "the Mod Test guest")

    def test_mod_test_code_is_only_inside_its_gates(self):
        for rel, tokens in GATED.items():
            for line in live_without_the_flag((ROOT / rel).read_text(encoding="utf-8")):
                for token in tokens:
                    self.assertNotIn(token, line, f"{rel}: '{token}' is live in a build without HALO_MOD_TEST: {line.strip()}")

    def test_workflow_passes_the_define_only_for_the_mod_test_option(self):
        wf = (ROOT / ".github/workflows/ios.yml").read_text(encoding="utf-8").replace("\r\n", "\n")
        self.assertEqual(wf.count("-DHALO_MOD_TEST=1"), 2, "the guest compile (once, conditional) and the host flags (once)")
        self.assertIn("if [ \"$COMPATIBILITY_TEST\" = true ]; then\n            HOST_FLAGS=('OTHER_CFLAGS=$(inherited) -DHALO_ALIGNED_ARENA_TEST=1 -DHALO_MOD_TEST=1')\n          elif", wf)
        self.assertNotIn("ios/modtest", wf)
        self.assertGreaterEqual(wf.count("COMPATIBILITY_TEST: ${{ inputs.compatibility_test || false }}"), 2)

    def test_mod_test_files_and_docs_live_on_main(self):
        for rel in ("source/cache/cache_mod_test_policy.h", "tools/tests/test_ios_mod_cache_policy.c", "docs/ios/MOD_TEST.md"):
            self.assertTrue((ROOT / rel).exists(), rel)


if __name__ == "__main__":
    unittest.main(verbosity=0)
