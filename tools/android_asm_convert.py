"""Convert arm64_32 (Apple ILP32) assembly into AArch64 ELF assembly.

The Android port runs the game as ILP32 code: native AArch64 instructions
with 32-bit pointers, so the game's data formats (which embed 32-bit
pointers, exactly as on the Xbox) keep their layout. Clang only offers such
a target as ``arm64_32-apple-watchos``, which emits Mach-O. The generated
*code* is ordinary AArch64 though; only the assembly syntax, section names,
symbol decoration and relocation operators are Darwin-specific. This script
rewrites them for the ELF assembler, so the objects can be linked by ld.lld
into an image that the Android loader maps into the low 4 GB of the process.

Usage: android_asm_convert.py [--ios-pointer-fastpath] [--ios-arena-fastpath] input.s output.s
"""

import re
import sys

IDENT = re.compile(r'"[^"]*"|[A-Za-z_.$][\w.$]*')

DROP_DIRECTIVES = {
    ".subsections_via_symbols", ".build_version", ".watchos_version_min",
    ".ios_version_min", ".macosx_version_min", ".tvos_version_min", ".loh",
    ".data_region", ".end_data_region", ".linker_option", ".indirect_symbol",
    ".addrsig", ".addrsig_sym", ".no_dead_strip", ".alt_entry", ".ident",
    ".desc", ".cfi_startproc", ".cfi_endproc", ".cfi_def_cfa",
    ".cfi_offset", ".cfi_def_cfa_offset", ".cfi_def_cfa_register",
    ".cfi_personality", ".cfi_lsda", ".cfi_remember_state",
    ".cfi_restore_state", ".cfi_restore", ".cfi_adjust_cfa_offset",
    ".cfi_same_value", ".cfi_escape",
}

RODATA_SECTIONS = {
    "__cstring", "__const", "__literal4", "__literal8", "__literal16",
    "__ustring",
}


class ConvertError(Exception):
    pass


def strip_comment(line: str) -> str:
    out = []
    in_string = False
    i = 0
    while i < len(line):
        c = line[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < len(line):
                out.append(line[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
        else:
            if c == '"':
                in_string = True
            elif c == ";" or line.startswith("//", i):
                break
            out.append(c)
        i += 1
    return "".join(out).rstrip()


class Converter:
    def __init__(self, lines):
        self.lines = lines
        self.local_labels = set()
        self.out = []
        self.in_dropped_section = False
        for line in lines:
            text = strip_comment(line).strip()
            m = re.match(r'^([A-Za-z_.$][\w.$]*|"[^"]*"):', text)
            if m and m.group(1)[0] in "lL":
                self.local_labels.add(m.group(1))

    def sym(self, name: str) -> str:
        if name.startswith('"'):
            inner = name[1:-1]
            if inner.startswith("_"):
                inner = inner[1:]
            return '"' + inner + '"'
        if name.startswith("_"):
            return name[1:]
        if name in self.local_labels:
            return ".L" + name
        return name

    def operands(self, text: str) -> str:
        # relocation operators first
        text = re.sub(r'([\w.$"]+)@GOTPAGE\b', r"\1", text)
        text = re.sub(r'([\w.$"]+)@PAGE\b', r"\1", text)
        text = re.sub(r'(\([^)]*\)|[\w.$"]+(?:[+-]\d+)?)@PAGEOFF\b', r":lo12:\1", text)
        if "@" in text and not re.search(r'"[^"]*@[^"]*"', text):
            raise ConvertError("unsupported relocation operator: " + text)

        def repl(m):
            tok = m.group(0)
            if tok.startswith(".") and not tok.startswith(".L"):
                return tok
            if tok.startswith("lo12"):
                return tok
            return self.sym(tok)
        # rename identifiers outside :lo12: markers
        parts = re.split(r'(:lo12:)', text)
        return "".join(p if p == ":lo12:" else IDENT.sub(repl, p) for p in parts)

    def emit(self, s: str):
        self.out.append(s)

    def section(self, segment: str, name: str):
        self.in_dropped_section = False
        if segment == "__DWARF" or segment == "__LD" or name in ("__compact_unwind", "__eh_frame"):
            self.in_dropped_section = True
            return
        if name == "__guest_header":
            self.emit('\t.section .guest_header,"a",@progbits')
        elif name == "__mod_init_func":
            self.emit('\t.section .guest_init,"aw",@progbits')
        elif name == "__mod_term_func":
            self.emit('\t.section .guest_fini,"aw",@progbits')
        elif segment == "__TEXT" and name == "__text":
            self.emit("\t.text")
        elif segment == "__TEXT" and name in RODATA_SECTIONS:
            self.emit('\t.section .rodata,"a",@progbits')
        elif segment == "__TEXT":
            self.emit("\t.text")
        elif name in ("__bss", "__common"):
            self.emit("\t.bss")
        else:
            self.emit("\t.data")

    def zerofill(self, args):
        parts = [a.strip() for a in args.split(",")]
        if len(parts) < 4:
            return
        segment, name, symbol, size = parts[:4]
        align = int(parts[4]) if len(parts) > 4 else 0
        symbol = self.sym(symbol)
        # a definition in either section: tentative definitions (-fcommon)
        # are emitted as .comm, and __common here only holds zero-initialized
        # ones
        self.emit("\t.pushsection .bss")
        self.emit(f"\t.p2align {align}")
        self.emit(f"{symbol}:")
        self.emit(f"\t.zero {size}")
        self.emit("\t.popsection")

    def convert_line(self, raw: str):
        text = strip_comment(raw)
        stripped = text.strip()
        if not stripped:
            return
        # labels
        m = re.match(r'^([A-Za-z_.$][\w.$]*|"[^"]*"):(.*)$', stripped)
        if m:
            if not self.in_dropped_section:
                self.emit(self.sym(m.group(1)) + ":")
            rest = m.group(2).strip()
            if rest:
                self.convert_line(rest)
            return
        # symbol assignment (aliases)
        m = re.match(r'^([A-Za-z_.$][\w.$]*)\s*=\s*(.+)$', stripped)
        if m:
            if not self.in_dropped_section:
                self.emit(f"\t.set {self.sym(m.group(1))}, {self.operands(m.group(2))}")
            return
        parts = stripped.split(None, 1)
        op = parts[0]
        args = parts[1] if len(parts) > 1 else ""

        if op == ".section":
            seg, _, rest = args.partition(",")
            name = rest.split(",")[0].strip()
            self.section(seg.strip(), name)
            return
        shorthand = {
            ".text": ("__TEXT", "__text"), ".data": ("__DATA", "__data"),
            ".const": ("__TEXT", "__const"), ".cstring": ("__TEXT", "__cstring"),
            ".literal4": ("__TEXT", "__literal4"), ".literal8": ("__TEXT", "__literal8"),
            ".literal16": ("__TEXT", "__literal16"), ".const_data": ("__DATA", "__const"),
            ".static_data": ("__DATA", "__data"), ".mod_init_func": ("__DATA", "__mod_init_func"),
            ".mod_term_func": ("__DATA", "__mod_term_func"),
        }
        if op in shorthand:
            self.section(*shorthand[op])
            return
        if op == ".zerofill":
            self.zerofill(args)
            return
        if self.in_dropped_section:
            return
        if op in DROP_DIRECTIVES or op.endswith("_version_min"):
            return
        if op in (".tbss", ".tlv", ".tdata") or "@TLVP" in args:
            raise ConvertError("thread-local storage is not supported: " + stripped)
        if op == ".globl":
            self.emit(f"\t.globl {self.sym(args.strip())}")
            return
        if op == ".private_extern":
            s = self.sym(args.strip())
            self.emit(f"\t.hidden {s}")
            return
        if op in (".weak_definition", ".weak_reference", ".weak_def_can_be_hidden", ".weak"):
            self.emit(f"\t.weak {self.sym(args.strip())}")
            return
        if op == ".comm" or op == ".lcomm":
            a = [x.strip() for x in args.split(",")]
            s = self.sym(a[0])
            align = 1 << int(a[2]) if len(a) > 2 else 1
            if op == ".lcomm":
                self.emit(f"\t.local {s}")
            self.emit(f"\t.comm {s},{a[1]},{align}")
            return
        if op == ".align":
            self.emit(f"\t.p2align {args}")
            return
        if op.startswith("."):
            self.emit(f"\t{op} {self.operands(args)}" if args else f"\t{op}")
            return
        # instructions
        if "@GOTPAGEOFF" in args:
            # ldr wN/xN, [xM, sym@GOTPAGEOFF] -> add xN, xM, :lo12:sym (the
            # image is linked statically below 4 GB, so every GOT load can be
            # relaxed to the address itself)
            gm = re.match(r'^\s*([wx])(\d+|zr)\s*,\s*\[\s*(x\d+|sp)\s*,\s*([\w.$"]+)@GOTPAGEOFF\s*\]\s*$', args)
            if op != "ldr" or not gm:
                raise ConvertError("unsupported GOT access: " + stripped)
            self.emit(f"\tadd x{gm.group(2)}, {gm.group(3)}, :lo12:{self.sym(gm.group(4))}")
            return
        self.emit(f"\t{op} {self.operands(args)}" if args else f"\t{op}")

    def run(self):
        for i, raw in enumerate(self.lines):
            try:
                self.convert_line(raw)
            except ConvertError as e:
                raise ConvertError(f"line {i + 1}: {e}") from None
        # a weak symbol is already global; a second directive only warns
        weak = {line.split(None, 1)[1] for line in self.out if line.startswith("\t.weak ")}
        out = [line for line in self.out
               if not (line.startswith("\t.globl ") and line.split(None, 1)[1] in weak)]
        return "\n".join(out) + "\n"



# This pass is selected explicitly by the iOS workflow. Android's converted
# assembly is unchanged. Limit the first device trial to measured hot objects.
IOS_POINTER_OBJECTS = (
    '/port/linux/src/d3d8_gl.o.darwin.s',
    '/source/physics/collision_bsp.o.darwin.s',
    '/source/structures/structure_visibility.o.darwin.s',
    '/source/structures/structure_render.o.darwin.s',
)

def ios_pointer_fastpath(assembly: str, input_path: str) -> str:
    path = '/' + input_path.replace('\\', '/').lstrip('/')
    if not path.endswith(IOS_POINTER_OBJECTS):
        return assembly
    # Never insert scratch-stack accesses inside an exclusive-access sequence.
    if re.search(r'^\s*(?:ldax?r|ldx[pr]|ldax[pr]|stlx?r|stx[pr]|stlx[pr])\b', assembly, re.M):
        raise ConvertError('iOS fast path cannot instrument an exclusive-access object')
    if '.Lhalo_ios_pointer_' in assembly:
        raise ConvertError('iOS fast-path label collision')
    out = []
    count = 0
    for line in assembly.splitlines():
        instruction = re.match(r'^\s*(ldr[bs]?|ldur[bs]?|ldrs[whb]|ldurs[whb]|ldp|ldpsw|str[bs]?|stur[bs]?|stp)\s+', line)
        address = re.search(r'\[\s*x(\d+)\b', line) if instruction else None
        if address and int(address[1]) < 31:
            rn = int(address[1])
            scratch = 17 if rn == 16 else 16
            label = f'.Lhalo_ios_pointer_{count}'
            # Match the signal bridge: nonzero 32-bit bases become arena+VA;
            # already-wide addresses and null bases retain their original value.
            # Preserve NZCV, scratch register and stack alignment. Spill below
            # the 128-byte Darwin leaf red zone so live leaf locals survive.
            # Restore SP before executing the original instruction, including
            # indexed, pre/post-indexed and register-overlap forms.
            out.extend([
                f'\tstr x{scratch}, [sp, #-144]!',
                f'\tlsr x{scratch}, x{rn}, #32',
                f'\tcbnz x{scratch}, {label}',
                f'\tcbz x{rn}, {label}',
                f'\tadrp x{scratch}, halo_ios_arena_base',
                f'\tldr x{scratch}, [x{scratch}, :lo12:halo_ios_arena_base]',
                f'\tadd x{rn}, x{rn}, x{scratch}',
                label + ':',
                f'\tldr x{scratch}, [sp], #144',
            ])
            count += 1
        out.append(line)
    # Build logs make the scope reviewable without per-access runtime counters.
    print(f'iOS pointer fast path: {count} memory sites in {input_path}')
    return '\n'.join(out) + '\n'


# ---------------------------------------------------------------------------
# iOS arena fast path (M2.6.30)
#
# Guest code always executes at arena + VA (the signal bridge redirects any
# low-VA fetch there and the host enters the guest through halo_guest_ptr), and
# the arena is exactly 4-GiB aligned. Every guest pointer is therefore either a
# zero-extended 32-bit VA (which faults in PAGEZERO) or already an arena
# address. Both give the same host address as
#
#     (pc & 0xffffffff00000000) + zero_extend(low32(base))
#
# so a load/store can be made fault-free with three flag-free ALU instructions
# and one scratch register, without touching the original base register:
#
#     adr  x15, .
#     and  x15, x15, #0xffffffff00000000
#     add  x15, x15, wN, uxtw
#     ldr  w0, [x15, <original offset>]
#
# x15 must never be live in the instrumented code: the guest build reserves it
# (-ffixed-x15) and this pass refuses to touch any object whose assembly names
# x15/w15 anywhere. Sites it does not understand are left alone and keep using
# the signal bridge, so a missed site costs speed, never correctness.
# ---------------------------------------------------------------------------

ARENA_SCRATCH = 15
ARENA_MASK = '0xffffffff00000000'
ARENA_SKIP_PATHS = ('/port/android/guest/',)
ARENA_MEM_OPS = (r'ldrsb|ldrsh|ldrsw|ldrb|ldrh|ldr|ldursb|ldursh|ldursw|ldurb|ldurh|ldur|'
                 r'ldpsw|ldnp|ldp|strb|strh|str|sturb|sturh|stur|stnp|stp')
ARENA_MEM_RE = re.compile(
    r'^(?P<ind>\s*)(?P<op>' + ARENA_MEM_OPS + r')\s+(?P<regs>[^\[\]]+?)\s*,\s*'
    r'\[\s*x(?P<rn>\d+)\s*(?:,\s*(?P<off>[^\]]*?))?\s*\](?P<wb>!)?'
    r'(?:\s*,\s*(?P<post>#\s*-?(?:0x[0-9a-fA-F]+|\d+)))?\s*$')
ARENA_IMM_RE = re.compile(r'^#\s*(-?(?:0x[0-9a-fA-F]+|\d+))$')
ARENA_REGOFF_RE = re.compile(
    r'^(?P<r>[xw])(?P<n>\d+)\s*(?:,\s*(?P<ext>[a-z]+)\s*(?:#\s*(?P<amt>\d+))?)?$')
ARENA_BLR_RE = re.compile(r'^(?P<ind>\s*)blr\s+x(?P<rn>\d+)\s*$')
ARENA_COMPRESSED_RE = re.compile(
    r'^\s*\.(?:byte|hword|short|2byte)\s+\(?\s*[\w.$]*?BB(?P<f>\d+)_\d+\s*-\s*[\w.$]*?BB\d+_\d+\s*\)?\s*>>\s*2')
ARENA_BB_LABEL_RE = re.compile(r'^(?:\.L|L)?[\w.$]*?BB(\d+)_\d+$')


def _arena_address(rn):
    return [
        f'\tadr x{ARENA_SCRATCH}, .',
        f'\tand x{ARENA_SCRATCH}, x{ARENA_SCRATCH}, #{ARENA_MASK}',
        f'\tadd x{ARENA_SCRATCH}, x{ARENA_SCRATCH}, w{rn}, uxtw',
    ]


def _arena_adjust(rn, imm):
    if imm == 0:
        return []
    if abs(imm) > 4095:
        return None
    if imm > 0:
        return [f'\tadd x{rn}, x{rn}, #{imm}']
    return [f'\tsub x{rn}, x{rn}, #{-imm}']


def arena_rewrite_line(line, label):
    """Return replacement lines for one instruction, or None to keep it."""
    m = ARENA_MEM_RE.match(line)
    if m:
        rn = int(m['rn'])
        # x15 is the scratch register; x29/x30 hold stack/return addresses
        # that are always arena-wide already.
        if rn >= 29 or rn == ARENA_SCRATCH:
            return None
        off = (m['off'] or '').strip()
        wb, post = m['wb'], m['post']
        imm = None
        if off:
            im = ARENA_IMM_RE.match(off)
            if im:
                imm = int(im[1], 0)
            else:
                # Register offsets only where the roles are unambiguous: the
                # base register is the pointer, the other one is the index.
                ro = ARENA_REGOFF_RE.match(off)
                if not ro or wb or post:
                    return None
                ext, amt = ro['ext'], ro['amt']
                if ro['r'] == 'w':
                    if ext not in ('uxtw', 'sxtw'):
                        return None
                elif not (ext == 'lsl' and amt and int(amt) > 0):
                    return None
        if wb and imm is None:
            return None
        if post and off:
            return None
        out = []
        if wb:
            adj = _arena_adjust(rn, imm)
            if adj is None:
                return None
            out += adj
            access_off = ''
        else:
            access_off = f', {off}' if off else ''
        out += _arena_address(rn)
        out.append(f"{m['ind']}{m['op']} {m['regs'].strip()}, [x{ARENA_SCRATCH}{access_off}]")
        if post:
            adj = _arena_adjust(rn, int(ARENA_IMM_RE.match(post.strip())[1], 0))
            if adj is None:
                return None
            out += adj
        return out
    b = ARENA_BLR_RE.match(line)
    if b:
        rn = int(b['rn'])
        if rn >= 30 or rn == ARENA_SCRATCH:
            return None
        s = f'x{ARENA_SCRATCH}'
        # Wide targets (host stubs, arena addresses) are called unchanged.
        return [
            f'\tlsr {s}, x{rn}, #32',
            f'\tcbnz {s}, {label}_w',
            *_arena_address(rn),
            f'\tblr {s}',
            f'\tb {label}_e',
            f'{label}_w:',
            f'\tblr x{rn}',
            f'{label}_e:',
        ]
    return None


def ios_arena_fastpath(assembly: str, input_path: str) -> str:
    path = '/' + input_path.replace('\\', '/').lstrip('/')
    if any(part in path for part in ARENA_SKIP_PATHS):
        return assembly
    if re.search(r'\b[xw]15\b', assembly):
        print(f'iOS arena fast path: {input_path} names x15/w15; left on the signal bridge',
              file=sys.stderr)
        return assembly
    if '.Lhalo_ios_arena_' in assembly:
        raise ConvertError('iOS arena fast-path label collision')
    lines = assembly.splitlines()
    # Compressed (.byte/.hword) jump tables store (target-anchor)>>2 in a fixed
    # width, and the inserted instructions could overflow it. Leave those
    # functions untouched; functions are identified by their BB<n>_ numbering.
    unsafe = set()
    for line in lines:
        cm = ARENA_COMPRESSED_RE.match(line)
        if cm:
            unsafe.add(int(cm['f']))
    out, sites, blr_sites, skipping = [], 0, 0, False
    for line in lines:
        label_match = re.match(r'^([A-Za-z_.$][\w.$]*):\s*$', line)
        if label_match:
            name = label_match.group(1)
            bb = ARENA_BB_LABEL_RE.match(name)
            if bb:
                skipping = int(bb.group(1)) in unsafe
            elif not name.startswith(('.L', 'L')):
                skipping = False  # a new function symbol
        if skipping:
            out.append(line)
            continue
        replacement = arena_rewrite_line(line, f'.Lhalo_ios_arena_{sites + blr_sites}')
        if replacement is None:
            out.append(line)
            continue
        if ARENA_BLR_RE.match(line):
            blr_sites += 1
        else:
            sites += 1
        out.extend(replacement)
    print(f'iOS arena fast path: {sites} memory sites, {blr_sites} indirect calls in {input_path}')
    return '\n'.join(out) + '\n'


def main():
    args = sys.argv[1:]
    ios_fastpath = False
    ios_arena = False
    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag == "--ios-pointer-fastpath":
            ios_fastpath = True
        elif flag == "--ios-arena-fastpath":
            ios_arena = True
        else:
            print(__doc__)
            sys.exit(2)
    if len(args) != 2:
        print(__doc__)
        sys.exit(2)
    with open(args[0], "r", encoding="utf-8", errors="surrogateescape") as f:
        lines = f.read().split("\n")
    try:
        result = Converter(lines).run()
        if ios_fastpath:
            result = ios_pointer_fastpath(result, args[0])
        if ios_arena:
            result = ios_arena_fastpath(result, args[0])
    except ConvertError as e:
        print(f"{args[0]}: {e}", file=sys.stderr)
        sys.exit(1)
    with open(args[1], "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(result)


if __name__ == "__main__":
    main()
