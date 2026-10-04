"""Exercise the actual C reader with synthetic XDVDFS images; no game assets.
Python is only the host test harness, never part of the iOS extractor.
"""
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MAGIC = b"MICROSOFT*XBOX*MEDIA"


def header(build="01.10.12.2276", version=5):
    data = bytearray(2048)
    struct.pack_into("<III", data, 0, 0x68656164, version, 600000)
    data[32:36] = b"a10\0"
    data[64:64 + len(build)] = build.encode()
    struct.pack_into("<I", data, 2044, 0x666F6F74)
    return data


def entry(name, sector, size, directory=False, right=0):
    return struct.pack("<HHIIBB", 0, right, sector, size, 16 if directory else 0,
                       len(name)) + name.encode()


class XisoTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        cls.exe = Path(cls.build.name) / ("xiso.exe" if os.name == "nt" else "xiso")
        subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror",
                        "-I" + str(ROOT / "port/ios/HaloIOS"),
                        str(ROOT / "port/ios/HaloIOS/halo_xiso.c"),
                        str(ROOT / "tools/tests/ios_xiso_driver.c"), "-o", str(cls.exe)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.stage = self.root / "stage"
        self.stage.mkdir()
        self.image = self.root / "arbitrary-label.iso"

    def tearDown(self):
        self.tmp.cleanup()

    def image_make(self, base=0, build="01.10.12.2276", bad=False, cycle=False, duplicate=False):
        descriptor = bytearray(2048)
        descriptor[:20] = MAGIC
        descriptor[2028:2048] = MAGIC
        struct.pack_into("<II", descriptor, 20, 40, 2048)
        table = bytearray(2048)
        first = entry("a10.map", 50, 600000, right=8)
        table[:len(first)] = first
        second = entry("a10.map" if duplicate else "UI.MAP", 400, 2048)
        table[32:32 + len(second)] = second
        if cycle:
            struct.pack_into("<H", table, 34, 8)
        with self.image.open("wb") as f:
            f.seek(base + 65536)
            f.write(descriptor)
            f.seek(base + 40 * 2048)
            f.write(entry("maps", 41, 2048, directory=True))
            f.write(bytes(2048 - f.tell() % 2048))
            f.seek(base + 41 * 2048)
            f.write(table)
            f.seek(base + 50 * 2048)
            f.write(header(build, 7 if bad else 5))
            f.write(bytes(600000 - 2048))
            f.seek(base + 400 * 2048)
            f.write(header(build))

    def run_reader(self, cancel=False):
        return subprocess.run([str(self.exe), str(self.image), str(self.stage), str(int(cancel))],
                              text=True, capture_output=True)

    def test_ntsc_and_pal_and_partition_offsets(self):
        for base in (0, 0x18300000, 0x02080000, 0x0FD90000):
            for build in ("01.10.12.2276", "01.01.14.2342"):
                self.image_make(base, build)
                result = self.run_reader()
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual((self.stage / "a10.map").stat().st_size, 600000)
                self.assertEqual((self.stage / "ui.map").read_bytes(), header(build))
                shutil.rmtree(self.stage)
                self.stage.mkdir()

    def test_pc_iso_rejected(self):
        self.image.write_bytes(b"CD001" + bytes(100000))
        r = self.run_reader()
        self.assertEqual(r.returncode, 1)
        self.assertIn("PC, MCC", r.stdout)
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_invalid_v5_rejects_before_any_write(self):
        self.image_make(bad=True)
        r = self.run_reader()
        self.assertEqual(r.returncode, 1)
        self.assertIn("v5", r.stdout)
        self.assertFalse((self.stage / "ui.map").exists())
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_wrong_build(self):
        self.image_make(build="01.00.00.0000")
        self.assertEqual(self.run_reader().returncode, 1)
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_wrong_game_or_missing_ui(self):
        self.image_make()
        with self.image.open("r+b") as f:
            f.seek(40 * 2048 + 14)
            f.write(b"data")
        self.assertEqual(self.run_reader().returncode, 1)
        self.assertEqual(list(self.stage.iterdir()), [])
        self.image_make()
        with self.image.open("r+b") as f:
            f.seek(41 * 2048 + 32 + 14)
            f.write(b"XX.MAP")
        self.assertEqual(self.run_reader().returncode, 1)
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_invalid_footer_and_unsafe_name(self):
        self.image_make()
        with self.image.open("r+b") as f:
            f.seek(400 * 2048 + 2044)
            f.write(bytes(4))
        self.assertEqual(self.run_reader().returncode, 1)
        self.assertEqual(list(self.stage.iterdir()), [])
        self.image_make()
        with self.image.open("r+b") as f:
            f.seek(41 * 2048 + 14)
            f.write(b"../.map")
        self.assertEqual(self.run_reader().returncode, 1)
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_corrupt_tree_and_duplicates(self):
        self.image_make(cycle=True)
        self.assertEqual(self.run_reader().returncode, 1)
        self.image_make(duplicate=True)
        self.assertEqual(self.run_reader().returncode, 1)

    def test_cancel_leaves_only_private_partial_file(self):
        self.image_make()
        self.assertEqual(self.run_reader(True).returncode, 3)
        self.assertFalse((self.stage / "ui.map").exists())
        self.assertLess((self.stage / "a10.map").stat().st_size, 600000)
        self.assertFalse((self.root / "maps").exists())

    def test_truncated_image(self):
        self.image_make()
        with self.image.open("r+b") as f:
            f.truncate(400 * 2048 + 100)
        self.assertEqual(self.run_reader().returncode, 1)
        self.assertEqual(list(self.stage.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
