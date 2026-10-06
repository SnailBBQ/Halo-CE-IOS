"""The checkpoint editor reads a snapshot of the engine's whole game state, whose size upstream changes (16 MiB in build 115, 20 MiB since the pools
grew). The reader must take the size and base address from the engine's own header, never from a number written beside it, so an upstream change
cannot silently make every new checkpoint unreadable again."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
READER = ROOT / "port/ios/HaloIOS/halo_checkpoint.h"
EDITOR = ROOT / "port/ios/HaloIOS/HaloCheckpointEditor.m"
CAPACITY = ROOT / "port/linux/include/halo_port_capacity.h"


class CheckpointSizeTests(unittest.TestCase):
    def setUp(self):
        self.reader = READER.read_text(encoding="utf-8")
        self.editor = EDITOR.read_text(encoding="utf-8")

    def test_the_reader_takes_the_size_and_base_from_the_engine(self):
        self.assertIn('#include "../../linux/include/halo_port_capacity.h"', self.reader)
        self.assertRegex(self.reader, r"#define HC_SIZE \(\(size_t\)HALO_PORT_GAME_STATE_SIZE\)")
        self.assertRegex(self.reader, r"#define HC_BASE \(\(uint32_t\)HALO_PORT_GAME_STATE_BASE_ADDRESS\)")

    def test_no_size_or_base_is_written_as_a_number(self):
        code = "\n".join(line for line in self.reader.splitlines() if not line.strip().startswith(("/*", "*", "//")))
        for number in (r"16u\s*\*\s*1024u", r"0x1000000\b", r"0x1400000\b", r"0x81a00000", r"16777216", r"20971520"):
            self.assertIsNone(re.search(number, code, re.I), "the reader writes %s instead of using the engine's constant" % number)

    def test_the_editor_does_not_name_a_size(self):
        self.assertIn("HC_SIZE", self.editor)
        self.assertNotRegex(self.editor, r"\b16 MB\b", "the message names a size that changes with upstream")

    def test_the_engine_constants_exist_and_add_up(self):
        text = CAPACITY.read_text(encoding="utf-8", errors="replace")
        for name in ("HALO_PORT_GAME_STATE_BASE_ADDRESS", "HALO_PORT_GAME_STATE_CPU_SIZE", "HALO_PORT_GAME_STATE_GPU_SIZE"):
            self.assertRegex(text, r"#define %s 0x[0-9A-Fa-f]+" % name)
        self.assertRegex(text, r"#define HALO_PORT_GAME_STATE_SIZE \(HALO_PORT_GAME_STATE_CPU_SIZE\+HALO_PORT_GAME_STATE_GPU_SIZE\)")


if __name__ == "__main__":
    unittest.main(verbosity=0)
