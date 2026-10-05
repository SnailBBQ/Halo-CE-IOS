"""The signed-code extractor keeps executable bytes and refuses a writable overlap."""
import importlib.util
import struct
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "signed", Path(__file__).resolve().parents[1] / "ios_signed_guest.py")
signed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signed)


def elf(segments):
    header = bytearray(64)
    header[:4] = b"\x7fELF"
    header[4] = 2
    phoff = 64
    struct.pack_into("<Q", header, 32, phoff)
    struct.pack_into("<HH", header, 54, 56, len(segments))
    headers = bytearray()
    data = bytearray()
    cursor = phoff + 56 * len(segments)
    for flags, vaddr, payload, memsz in segments:
        headers += struct.pack("<IIQQQQQQ", 1, flags, cursor, vaddr, vaddr, len(payload), memsz, 0x4000)
        data += payload
        cursor += len(payload)
    return bytes(header + headers + data)


code = b"\x1f\x20\x03\xd5" * 4
ro = b"RODATA!!"
data = b"WRITABLE"
image = elf([
    (5, 0x88000000, code, len(code)),
    (4, 0x88000000 + len(code), ro, len(ro)),
    (6, 0x88010000, data, len(data) + 16),
])
start, blob = signed.extract_from_bytes(image)
assert start == 0x88000000, hex(start)
assert len(blob) == 0x4000, hex(len(blob))
assert blob[:len(code)] == code
assert blob[len(code):len(code) + len(ro)] == ro
assert b"WRITABLE" not in blob

overlap = elf([
    (5, 0x88000000, code, len(code)),
    (6, 0x88000000 + 0x2000, data, len(data)),
])
try:
    signed.extract_from_bytes(overlap)
except SystemExit as error:
    assert "writable" in str(error)
else:
    raise SystemExit("writable overlap was accepted")

unaligned = elf([(5, 0x88000010, code, len(code))])
try:
    signed.extract_from_bytes(unaligned)
except SystemExit as error:
    assert "aligned" in str(error)
else:
    raise SystemExit("unaligned executable segment was accepted")

print("PASS: signed guest blob keeps code and rodata, and rejects a writable page overlap")
