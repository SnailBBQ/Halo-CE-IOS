"""Binary assets must reach the build byte for byte. A line-ending conversion once damaged two HUD sheets: the PNG signature ends in a
line feed that became a carriage return and line feed, and tools/embed_assets.py rejects the file. This checks every PNG's chunks and
CRCs, the encoding the embedded HUD and title sheets require, every JPEG's markers, and that .gitattributes protects binary files."""
import struct
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SIGNATURE = b"\x89PNG\r\n\x1a\n"
# folders whose PNGs are embedded as 8-bit RGBA, non-interlaced sheets (tools/embed_assets.py, port/linux/src/hud_hires.c)
SHEET_FOLDERS = ("port/assets/hud", "port/assets/titles")
SKIP = ("research/", ".git/", "build/")


def png_problems(data):
    """Why these bytes are not an intact PNG (an empty list if they are), and the header fields."""
    if data[:8] != SIGNATURE:
        return ["the signature is wrong (a line-ending conversion?)"], None
    position, first, header, end = 8, True, None, False
    while position + 12 <= len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        body = data[position + 8:position + 8 + length]
        if len(body) != length or position + 12 + length > len(data):
            return ["a chunk runs past the end of the file"], header
        if struct.unpack(">I", data[position + 8 + length:position + 12 + length])[0] != zlib.crc32(kind + body) & 0xFFFFFFFF:
            return ["the checksum of chunk %s is wrong" % kind.decode("latin1")], header
        if first:
            if kind != b"IHDR" or length != 13:
                return ["the first chunk is not a 13-byte IHDR"], None
            header = struct.unpack(">IIBBBBB", body)
            first = False
        if kind == b"IEND":
            end = True
            position += 12 + length
            break
        position += 12 + length
    if not end:
        return ["there is no IEND chunk"], header
    if position != len(data):
        return ["there is data after IEND"], header
    return [], header


def jpeg_problems(data):
    if data[:2] != b"\xff\xd8":
        return ["it does not start with the JPEG marker"]
    if data[-2:] != b"\xff\xd9":
        return ["it does not end with the JPEG end marker"]
    return []


def tracked_files(*suffixes):
    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT).as_posix()
        if path.is_file() and path.suffix.lower() in suffixes and not relative.startswith(SKIP) and "__pycache__" not in relative:
            yield relative, path


class AssetIntegrityTests(unittest.TestCase):
    def test_every_png_is_intact(self):
        count = 0
        for relative, path in tracked_files(".png"):
            problems, _ = png_problems(path.read_bytes())
            self.assertEqual(problems, [], "%s: %s" % (relative, "; ".join(problems)))
            count += 1
        self.assertGreater(count, 100, "the PNG assets were not found")

    def test_embedded_sheets_have_the_required_encoding(self):
        for folder in SHEET_FOLDERS:
            for relative, path in tracked_files(".png"):
                if not relative.startswith(folder + "/"):
                    continue
                problems, header = png_problems(path.read_bytes())
                self.assertEqual(problems, [], relative)
                width, height, depth, color, _, _, interlace = header
                self.assertEqual((depth, color, interlace), (8, 6, 0), "%s must be 8-bit RGBA and not interlaced" % relative)
                self.assertTrue(0 < width <= 8192 and 0 < height <= 8192, "%s is outside the 8192 limit" % relative)

    def test_every_jpeg_is_intact(self):
        for relative, path in tracked_files(".jpg", ".jpeg"):
            self.assertEqual(jpeg_problems(path.read_bytes()), [], relative)

    def test_the_checker_catches_the_damage_that_happened(self):
        def chunk(kind, body):
            return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        good = SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(b"\0" + bytes(8) + b"\0" + bytes(8))) + chunk(b"IEND", b"")
        self.assertEqual(png_problems(good)[0], [])
        converted = good.replace(b"\n", b"\r\n")
        self.assertNotEqual(png_problems(converted)[0], [], "a line-ending conversion must be detected")
        self.assertNotEqual(png_problems(good[:-5])[0], [], "a truncated file must be detected")
        flipped = bytearray(good)
        flipped[40] ^= 1
        self.assertNotEqual(png_problems(bytes(flipped))[0], [], "a changed byte must be detected by a checksum")
        self.assertNotEqual(png_problems(good + b"x")[0], [], "trailing data must be detected")

    def test_gitattributes_protects_binary_files(self):
        text = (ROOT / ".gitattributes").read_text(encoding="utf-8")
        for pattern in ("*.png", "*.jpg", "*.jpeg", "*.ogg", "*.ttf", "*.otf", "*.ico"):
            self.assertIn(pattern + " binary", text.splitlines(), pattern)
        active = "\n".join(line for line in text.splitlines() if not line.startswith("#"))
        self.assertNotIn("text=auto", active, "text=auto would rewrite this repository's mixed line endings")


if __name__ == "__main__":
    unittest.main(verbosity=0)
