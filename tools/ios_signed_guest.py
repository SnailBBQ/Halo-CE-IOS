"""Copy the guest ELF's executable bytes into one 16 KiB-aligned blob.

SideStore, Sideloadly and AltStore can run code that was inside the signed app.
They cannot mark a freshly copied ELF executable. The Non-Jailbreak IPA links
this blob into __TEXT and vm_remap's it over the guest addresses. Writable
segments stay out of it.
"""
import argparse
import struct
from pathlib import Path

PAGE = 0x4000
PT_LOAD = 1
PF_X, PF_W = 1, 2


def page_down(value):
    return value & ~(PAGE - 1)


def page_up(value):
    return (value + PAGE - 1) & ~(PAGE - 1)


def load_segments(blob):
    if len(blob) < 64 or blob[:4] != b"\x7fELF" or blob[4] != 2:
        raise SystemExit("signed guest: file is not an ELF64 image")
    e_phoff = struct.unpack_from("<Q", blob, 32)[0]
    e_phentsize, e_phnum = struct.unpack_from("<HH", blob, 54)
    if e_phentsize < 56:
        raise SystemExit("signed guest: unexpected program-header size")
    end = e_phoff + e_phentsize * e_phnum
    if end > len(blob):
        raise SystemExit("signed guest: program headers run past the file")
    segments = []
    for index in range(e_phnum):
        off = e_phoff + index * e_phentsize
        p_type, p_flags, p_offset, p_vaddr, _, p_filesz, p_memsz = struct.unpack_from("<IIQQQQQ", blob, off)
        if p_type != PT_LOAD:
            continue
        if p_offset + p_filesz > len(blob) or p_filesz > p_memsz:
            raise SystemExit(f"signed guest: segment {index} is outside the file")
        if p_vaddr > 0xFFFFFFFF or p_vaddr + p_memsz > 0x100000000:
            raise SystemExit(f"signed guest: segment {index} is outside the 4 GiB guest space")
        segments.append({
            "index": index,
            "flags": p_flags,
            "offset": p_offset,
            "vaddr": p_vaddr,
            "filesz": p_filesz,
            "memsz": p_memsz,
        })
    return segments


def signed_span(segments):
    executable = [segment for segment in segments if segment["flags"] & PF_X]
    if not executable:
        raise SystemExit("signed guest: the ELF has no executable segment")
    start = min(page_down(segment["vaddr"]) for segment in executable)
    end = max(page_up(segment["vaddr"] + segment["memsz"]) for segment in executable)
    # A segment may begin inside a 16 KiB page. vm_remap needs the whole page,
    # so the blob starts at the page base and the code keeps its offset.
    for segment in segments:
        seg_end = segment["vaddr"] + segment["memsz"]
        overlaps = segment["vaddr"] < end and start < seg_end
        if not overlaps:
            continue
        if segment["flags"] & PF_W:
            raise SystemExit(
                "signed guest: a writable segment shares a 16 KiB page with executable code; "
                "refusing to sign a page that must also be writable")
        if segment["vaddr"] < start or seg_end > end:
            raise SystemExit(
                f"signed guest: segment {segment['index']} crosses the signed code span")
    return start, end


def build_blob(blob, segments, start, end):
    image = bytearray(end - start)
    for segment in segments:
        seg_end = segment["vaddr"] + segment["memsz"]
        if segment["vaddr"] < end and start < seg_end:
            offset = segment["vaddr"] - start
            image[offset:offset + segment["filesz"]] = blob[segment["offset"]:segment["offset"] + segment["filesz"]]
    return image


def extract_from_bytes(blob):
    segments = load_segments(blob)
    start, end = signed_span(segments)
    return start, build_blob(blob, segments, start, end)


def extract(elf_path):
    return extract_from_bytes(Path(elf_path).read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    start, image = extract(args.elf)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    blob_path = args.output_dir / "halo_signed_guest.bin"
    blob_path.write_bytes(image)
    assembly = (
        ".section __TEXT,__halo_guest,regular,pure_instructions\n"
        ".globl _halo_signed_guest_code\n"
        ".p2align 14\n"
        "_halo_signed_guest_code:\n"
        f'.incbin "{blob_path.resolve()}"\n'
    )
    (args.output_dir / "halo_signed_guest.S").write_text(assembly)
    meta = (
        "#include <stdint.h>\n"
        f"const uint32_t halo_signed_guest_va = 0x{start:08x}u;\n"
        f"const uint32_t halo_signed_guest_size = 0x{len(image):x}u;\n"
    )
    (args.output_dir / "halo_signed_guest_meta.c").write_text(meta)
    print(f"signed guest: va=0x{start:08x} size=0x{len(image):x} ({len(image) / (1024 * 1024):.1f} MiB)")


if __name__ == "__main__":
    main()
