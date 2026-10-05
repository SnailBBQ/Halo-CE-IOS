"""The Non-Jailbreak Version's code must exist only in HALO_NON_JAILBREAK builds. Checks that every new identifier sits inside the
flag's conditional blocks, that the runtime compiles with the flag off, on and undefined, and that the flag-off object contains none of
the new symbols while the flag-on object does."""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "port/ios/HaloIOS"
FLAGGED_FILES = ["halo_guest_runtime.c", "halo_guest_runtime.h", "halo_boot_integration.m"]
NEW_TOKENS = ["halo_va_plan", "halo_va_", "HaloVaProbe", "HaloVaReserver", "HaloJitProbe", "nonjb_", "exec_report", "csops", "boot_non_jailbreak_diagnostics", "say_block", "Non-Jailbreak"]   # not kinfo_proc: Mod Test's own S1 logging uses it unconditionally


def outside_flag_blocks(text):
    """Lines that are not inside a #if that tests HALO_NON_JAILBREAK."""
    stack, outside = [], []
    for line in text.replace("\r\n", "\n").split("\n"):
        stripped = line.strip()
        if re.match(r"#\s*if", stripped):
            stack.append("HALO_NON_JAILBREAK" in stripped)
        elif re.match(r"#\s*(else|elif)", stripped):
            if stack and stack[-1]:
                raise AssertionError("an #else inside a flag block would make the flag-off build take new code")
        elif re.match(r"#\s*endif", stripped):
            stack.pop()
        elif not any(stack):
            outside.append(line)
    assert not stack, "unbalanced preprocessor conditionals"
    return outside


class NonJailbreakFlagTests(unittest.TestCase):
    def test_new_code_is_only_inside_the_flag(self):
        for name in FLAGGED_FILES:
            outside = outside_flag_blocks((HOST / name).read_text(encoding="utf-8"))
            for line in outside:
                for token in NEW_TOKENS:
                    self.assertNotIn(token, line, f"{name}: '{token}' appears outside the HALO_NON_JAILBREAK blocks: {line.strip()}")

    def test_no_other_source_pulls_the_planner_in(self):
        for path in list(HOST.glob("*.[chm]")) + list((ROOT / "port/ios").glob("*.c")):
            if path.name in ("halo_va_plan.h", "halo_guest_runtime.c"):
                continue
            self.assertNotIn("halo_va_plan.h", path.read_text(encoding="utf-8", errors="replace"), path.name)

    def compile(self, folder, flag, extra, output):
        cmd = [os.environ.get("CC", "cc"), "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-I" + str(HOST)] + (["-DHALO_NON_JAILBREAK=" + flag] if flag is not None else []) + extra + [str(HOST / "halo_guest_runtime.c")]
        return subprocess.run(cmd + (["-o", str(Path(folder) / output)] if output else []), capture_output=True, text=True)

    def test_runtime_compiles_with_the_flag_off_on_and_undefined(self):
        with tempfile.TemporaryDirectory() as folder:
            for flag in (None, "0", "1"):
                built = self.compile(folder, flag, ["-fsyntax-only"], None)
                self.assertEqual(built.returncode, 0, f"flag={flag}: {built.stderr[-1500:]}")

    def test_flag_off_object_has_none_of_the_new_symbols(self):
        nm = shutil.which("nm")
        if not nm:
            self.skipTest("nm is not available")
        with tempfile.TemporaryDirectory() as folder:
            symbols = {}
            for label, flag in (("off", "0"), ("undefined", None), ("on", "1")):
                built = self.compile(folder, flag, ["-c"], f"{label}.o")
                self.assertEqual(built.returncode, 0, built.stderr[-1500:])
                symbols[label] = subprocess.run([nm, str(Path(folder) / f"{label}.o")], capture_output=True, text=True).stdout
            for label in ("off", "undefined"):
                for new in ("nonjb", "exec_report", "halo_va_", "csops"):
                    self.assertNotIn(new, symbols[label], f"flag {label}: symbol '{new}' leaked into the ordinary build")
            for new in ("halo_guest_runtime_nonjb_report", "halo_guest_runtime_exec_report"):
                self.assertIn(new, symbols["on"], f"flag on: {new} is missing")
            self.assertEqual(symbols["off"].replace("_off", ""), symbols["undefined"].replace("_undefined", ""), "flag=0 and no flag must build identically")

    def test_marker_strings_exist_only_when_flagged(self):
        nm = shutil.which("strings")
        if not nm:
            self.skipTest("strings is not available")
        with tempfile.TemporaryDirectory() as folder:
            for flag, expected in (("0", False), ("1", True)):
                built = self.compile(folder, flag, ["-c"], f"{flag}.o")
                self.assertEqual(built.returncode, 0, built.stderr[-1500:])
                text = subprocess.run([nm, "-a", str(Path(folder) / f"{flag}.o")], capture_output=True, text=True).stdout
                self.assertEqual("Address-space probe (nothing stays reserved)" in text, expected, f"flag={flag}")


if __name__ == "__main__":
    unittest.main(verbosity=0)
