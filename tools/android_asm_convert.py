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
FLEX_BASE = 27
ARENA_MASK = '0xffffffff00000000'
# Early start-up and thread entry code stays on the signal bridge; everything else is rewritten.
ARENA_SKIP_PATHS = ('/guest/runtime/guest_start.', '/guest/runtime/guest_thread.')
ARENA_MEM_OPS = (r'ldrsb|ldrsh|ldrsw|ldrb|ldrh|ldr|ldursb|ldursh|ldursw|ldurb|ldurh|ldur|'
                 r'ldpsw|ldnp|ldp|strb|strh|str|sturb|sturh|stur|stnp|stp|'
                 r'ld1r|ld2r|ld3r|ld4r|ld1|ld2|ld3|ld4|st1|st2|st3|st4|'
                 # exclusive / acquire-release forms (mutexes, malloc locks): the inserted
                 # instructions are plain ALU, which is allowed inside an exclusive sequence
                 r'ldaxrb|ldaxrh|ldaxr|ldxrb|ldxrh|ldxr|ldaxp|ldxp|stlxrb|stlxrh|stlxr|stxrb|stxrh|stxr|'
                 r'stlxp|stxp|ldarb|ldarh|ldar|stlrb|stlrh|stlr')
ARENA_ATOMIC_OPS = frozenset('ldaxrb ldaxrh ldaxr ldxrb ldxrh ldxr ldaxp ldxp stlxrb stlxrh stlxr stxrb stxrh stxr '
                             'stlxp stxp ldarb ldarh ldar stlrb stlrh stlr'.split())
ARENA_NEON_OPS = frozenset('ld1r ld2r ld3r ld4r ld1 ld2 ld3 ld4 st1 st2 st3 st4'.split())
ARENA_MEM_RE = re.compile(
    r'^(?P<ind>\s*)(?P<op>' + ARENA_MEM_OPS + r')\s+(?P<regs>(?:[^\[\]]|\[\d+\])+?)\s*,\s*'
    r'\[\s*x(?P<rn>\d+)\s*(?:,\s*(?P<off>[^\]]*?))?\s*\](?P<wb>!)?'
    r'(?:\s*,\s*(?P<post>#\s*-?(?:0x[0-9a-fA-F]+|\d+)|x\d+))?\s*$')
ARENA_IMM_RE = re.compile(r'^#\s*(-?(?:0x[0-9a-fA-F]+|\d+))$')
ARENA_LO12_RE = re.compile(r'^:lo12:(?:[\w.$]+|"[^"]+")(?:[+-]\d+)?$')
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


def arena_rewrite_line(line, label, address_builder=None, allow_lo12=False, flex_register_offsets=False):
    """Return replacement lines for one instruction, or None to keep it.

    address_builder defaults to the aligned-arena normalization. The Non-JB
    flexible-base converter supplies a builder that uses reserved x27.

    x30: LLVM saves the link register in the prologue and, under register
    pressure, then allocates x30 as an ordinary register that can hold a guest
    pointer (monocypher's mod_l and the inlined ADPCM decoder in dsound_sdl.c's
    stream_process both do). Both models therefore treat [x30] like any other
    base register: the flexible model has no fallback (it aborted on mod_l), and
    in the aligned model every such access that is left alone is a SIGSEGV on
    the signal bridge (the M2.6.98 log showed 16 million of them from the ADPCM
    loop, each costing about 7 us). x29 is the Darwin frame pointer and is never
    a data pointer; a real return address in x30 is only ever used by ret.
    """
    if address_builder is None:
        address_builder = _arena_address
    m = ARENA_MEM_RE.match(line)
    if m:
        rn = int(m['rn'])
        # x15 is the scratch register; x29 is the frame pointer and always a real
        # host stack address. x30 is translated (see above).
        if rn > 30 or rn == 29 or rn == ARENA_SCRATCH:
            return None
        off = (m['off'] or '').strip()
        wb, post = m['wb'], m['post']
        imm = None
        if off:
            im = ARENA_IMM_RE.match(off)
            if im:
                imm = int(im[1], 0)
            elif allow_lo12 and ARENA_LO12_RE.match(off) and not wb and not post:
                # A converted Darwin ``sym@PAGEOFF`` memory operand becomes
                # ``:lo12:sym``.  The guest ELF symbols retain their original
                # 32-bit VAs, and every iOS arena base is at least page aligned,
                # so the low 12-bit relocation remains valid after mapping the
                # canonical page VA through either the aligned or x27 base.
                pass
            else:
                # Register offsets only where the roles are unambiguous: the
                # base register is the pointer, the other one is the index.
                ro = ARENA_REGOFF_RE.match(off)
                if not ro or wb or post:
                    return None
                ext, amt = ro['ext'], ro['amt']
                # AArch64 register-offset addressing accepts an X-register
                # index with no explicit modifier; that spelling means the
                # normal LSL #0 form (for example ``ldrb w0, [x1, x2]``).
                # Clang also emits explicit LSL/SXTX X-register offsets and
                # UXTW/SXTW W-register offsets.  Preserve the complete offset
                # expression verbatim after translating only the guest base
                # register through x27.  The input assembly has already been
                # accepted by Clang, so we only need to reject forms whose
                # register-width/extension pairing is not meaningful here.
                if ro['r'] == 'w':
                    if ext not in ('uxtw', 'sxtw'):
                        return None
                elif flex_register_offsets:
                    # Stage 3 must accept the full compiler-emitted X-register
                    # offset family. Bare Xm is LSL #0; SXTX is also legal.
                    if ext not in (None, 'lsl', 'sxtx'):
                        return None
                elif not (ext == 'lsl' and amt and int(amt) > 0):
                    # Preserve the historical aligned-arena rewrite exactly:
                    # bare/zero-shift X-register offsets remain on its signal
                    # bridge rather than changing the regular app in this
                    # Non-JB-only hotfix.
                    return None
                if amt is not None and int(amt) < 0:
                    return None
        if wb and imm is None:
            return None
        if post and off:
            return None
        post_register = None
        if post and not post.startswith('#'):
            # register post-increment exists only for NEON structure loads/stores
            if m['op'] not in ARENA_NEON_OPS:
                return None
            post_register = int(post[1:])
            if post_register in (ARENA_SCRATCH, rn):
                return None
        if m['op'] in ARENA_NEON_OPS and (wb or off):
            return None  # NEON accesses take [xN] or [xN], post-increment only
        if m['op'] in ARENA_ATOMIC_OPS and (wb or post or off not in ('', '#0')):
            return None  # exclusive and acquire/release accesses take a bare [xN]
        out = []
        if wb:
            adj = _arena_adjust(rn, imm)
            if adj is None:
                return None
            out += adj
            access_off = ''
        else:
            access_off = f', {off}' if off else ''
        out += address_builder(rn)
        out.append(f"{m['ind']}{m['op']} {m['regs'].strip()}, [x{ARENA_SCRATCH}{access_off}]")
        if post_register is not None:
            out.append(f'\tadd x{rn}, x{rn}, x{post_register}')
        elif post:
            adj = _arena_adjust(rn, int(ARENA_IMM_RE.match(post.strip())[1], 0))
            if adj is None:
                return None
            out += adj
        return out
    b = ARENA_BLR_RE.match(line)
    if b:
        rn = int(b['rn'])
        if rn > 30 or rn == ARENA_SCRATCH:
            return None
        s = f'x{ARENA_SCRATCH}'
        # Wide targets (host stubs, arena addresses) are called unchanged.
        return [
            f'\tlsr {s}, x{rn}, #32',
            f'\tcbnz {s}, {label}_w',
            *address_builder(rn),
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



# ---------------------------------------------------------------------------
# iOS flexible-base fast path (M2.6.94, Non-Jailbreak guest only)
#
# The aligned fast path can recover the arena base from the high 32 bits of
# the executing PC. That identity disappears when a stock-iOS process can only
# reserve a 4 GiB span at an arbitrary base such as 0x2a0000000.
#
# The flexible guest therefore reserves x27 for the real 64-bit arena base and
# x15 for address scratch. Ordinary arm64_32 pointers remain canonical 32-bit
# guest VAs. Every memory access through a general register becomes:
#
#     add x15, x27, wN, uxtw
#     ldr ..., [x15, ...]
#
# arm64_32 clang can also materialize addresses from PC/SP/FP as 64-bit host
# addresses (for example &static or &local). On a true <=4 GiB process those
# are already valid 32-bit pointer values; in a relocated arena they are not.
# Canonicalize those address-producing instructions back to guest VAs by
# subtracting x27 immediately after the materialization. This keeps pointer
# values stored in guest memory 32-bit and prevents low32(host) from leaking.
#
# Unlike the aligned fast path, this mode is correctness-critical: no function
# may silently fall back to PAGEZERO pointer upgrading because truncating an
# arbitrary host address would corrupt the guest pointer. Compressed jump-table
# functions and objects that already name x15/x27 therefore fail conversion.
# ---------------------------------------------------------------------------

FLEX_ADR_RE = re.compile(r'^(?P<ind>\s*)adr(?P<page>p?)\s+x(?P<rd>\d+)\s*,\s*.+$')
FLEX_STACK_ADD_RE = re.compile(
    r'^(?P<ind>\s*)(?P<op>add|sub)\s+x(?P<rd>\d+)\s*,\s*(?P<src>sp|x29)\s*,\s*.+$')
FLEX_STACK_MOV_RE = re.compile(
    r'^(?P<ind>\s*)mov\s+x(?P<rd>\d+)\s*,\s*(?P<src>sp|x29)\s*$')
FLEX_BR_RE = re.compile(r'^(?P<ind>\s*)br\s+x(?P<rn>\d+)\s*$')
# A frame-chain walk (__builtin_return_address(1) and friends) loads the caller's saved frame
# pointer from [x29]. That slot holds a HOST address (x29 = sp), unlike every other pointer
# the guest keeps in memory, which is a 32-bit guest VA. Loaded raw it would be truncated by
# the later uxtw translation (M2.6.100 Non-JB log: get_return_eip faulted at x27 + low32(sp)).
FLEX_FRAME_LOAD_RE = re.compile(
    r'^(?P<ind>\s*)ldr\s+x(?P<rt>\d+)\s*,\s*\[\s*x29\s*(?:,\s*#\s*0\s*)?\]\s*(?:[;@].*)?$')
FLEX_FRAME_LDP_RE = re.compile(
    r'^(?P<ind>\s*)ldp\s+x(?P<rt>\d+)\s*,\s*x(?P<rt2>\d+)\s*,\s*\[\s*x29\s*(?:,\s*#\s*0\s*)?\]\s*(?:[;@].*)?$')


def _flex_address(rn):
    return [f'\tadd x{ARENA_SCRATCH}, x{FLEX_BASE}, w{rn}, uxtw']


def _flex_rewrite_br(line, label):
    """Map a 32-bit guest tail-call target without changing LR."""
    match = FLEX_BR_RE.match(line)
    if not match:
        return None
    rn = int(match['rn'])
    # x30 is already the real host return address. x15/x27 are reserved and
    # rejected at object scope, so only ordinary general registers need help.
    # x30 is allowed: a real return address is wide (non-zero high half) and
    # takes the unchanged branch below, a reused x30 guest pointer is mapped.
    if rn > 30 or rn in (ARENA_SCRATCH, FLEX_BASE):
        return None
    scratch = f'x{ARENA_SCRATCH}'
    return [
        f'\tlsr {scratch}, x{rn}, #32',
        f'\tcbnz {scratch}, {label}_w',
        *_flex_address(rn),
        f'\tbr {scratch}',
        f'{label}_w:',
        f'\tbr x{rn}',
    ]


def _flex_canonicalized(lines):
    """Canonicalize clang-created host addresses back to 32-bit guest VAs."""
    out = []
    for line in lines:
        out.append(line)
        m = FLEX_ADR_RE.match(line)
        if m:
            rd = int(m['rd'])
            if rd in (ARENA_SCRATCH, FLEX_BASE):
                raise ConvertError(f'flex-base reserved register x{rd} used by address materialization')
            if rd < 29 or rd == 30:
                out.append(f"{m['ind']}sub x{rd}, x{rd}, x{FLEX_BASE}")
            continue
        m = FLEX_FRAME_LOAD_RE.match(line) or FLEX_FRAME_LDP_RE.match(line)
        if m:
            rt = int(m['rt'])
            if (rt < 29 or rt == 30) and rt not in (ARENA_SCRATCH, FLEX_BASE):
                out.append(f"{m['ind']}sub x{rt}, x{rt}, x{FLEX_BASE}")
            continue
        m = FLEX_STACK_ADD_RE.match(line) or FLEX_STACK_MOV_RE.match(line)
        if m:
            rd = int(m['rd'])
            # x29 is the live frame pointer and x30 the link register; never
            # rewrite them. Any other x-register materialized from SP/FP is a
            # pointer value in arm64_32 and must become a guest VA.
            if (rd < 29 or rd == 30) and rd not in (ARENA_SCRATCH, FLEX_BASE):
                out.append(f"{m['ind']}sub x{rd}, x{rd}, x{FLEX_BASE}")
    return out


_FLEX_IMM = r'#\s*-?(?:0x[0-9a-fA-F]+|\d+)'
# Exactly the three forms real arm64_32 LLVM emits (verified by stress compile at
# -O0/-O1/-O2/-Os, with and without frame pointers):
#     stp x28, x27, [sp, #N]      ldp x28, x27, [sp, #N]
#     stp x28, x27, [sp, #N]!     (pre-index prologue)
#     ldp x28, x27, [sp], #N      (post-index epilogue)
# plus the plain [sp] spelling. The base must be sp and the offset a literal.
FLEX_X27_STACK_PAIR_RE = re.compile(
    r'^(?:stp|ldp)\s+(?:x28\s*,\s*x27|x27\s*,\s*x28)\s*,\s*(?:'
    r'\[\s*sp\s*\]'
    r'|\[\s*sp\s*,\s*' + _FLEX_IMM + r'\s*\]!?'
    r'|\[\s*sp\s*\]\s*,\s*' + _FLEX_IMM +
    r')$')


def _flex_reserved_register_violation(line):
    """Return an unsafe reserved-register token from one assembly line.

    arm64_32 clang honors -ffixed-x27 for allocation, but LLVM's callee-save
    layout can still pair x28 with fixed x27 in the host-stack prologue and
    epilogue.  Stress-compiling the real target produces only that x28/x27
    STP/LDP preservation pattern. It is safe: x27 already contains the arena
    base, the spill saves that exact 64-bit value, and the reload restores it.
    No other executable source use of x27 is accepted. x15 is always reserved
    for converter scratch and is never accepted in source instructions.
    """
    # Darwin clang comments use ';'. Ignore comments and assembler directives
    # so literals/CFI metadata cannot trip the executable-register guard.
    code = line.split(';', 1)[0].strip()
    if not code or code.startswith('.') or code.endswith(':'):
        return None
    if re.search(r'\b[xw]15\b', code):
        return 'x15'
    if not re.search(r'\b[xw]27\b', code):
        return None
    # Any 32-bit w27 use would truncate the high half of the arena base.
    if re.search(r'\bw27\b', code):
        return 'w27'
    # The one compiler-generated exception we can justify from the real target:
    # x28/x27 64-bit callee-save preservation/restoration on the host SP.
    if FLEX_X27_STACK_PAIR_RE.match(code):
        return None
    return 'x27'


def ios_flex_base_fastpath(assembly: str, input_path: str) -> str:
    for source_line in assembly.splitlines():
        token = _flex_reserved_register_violation(source_line)
        if token:
            raise ConvertError(
                f'{input_path}: flexible-base guest source uses reserved {token}: '
                f'{source_line.strip()}')
    if '.Lhalo_ios_flex_' in assembly:
        raise ConvertError('iOS flexible-base fast-path label collision')

    lines = assembly.splitlines()
    for line in lines:
        if ARENA_COMPRESSED_RE.match(line):
            raise ConvertError(
                f'{input_path}: compressed jump table remains in flexible-base guest; '
                'the Non-JB build must disable compressed jump tables')

    lines = _flex_canonicalized(lines)
    out, sites, blr_sites = [], 0, 0
    flex_gpr_mem_re = re.compile(
        r'^\s*(?:' + ARENA_MEM_OPS + r')\b.*\[\s*x(?P<rn>\d+)\b')
    for line in lines:
        label = f'.Lhalo_ios_flex_{sites + blr_sites}'
        replacement = _flex_rewrite_br(line, label)
        if replacement is None:
            replacement = arena_rewrite_line(
                line, label, _flex_address, allow_lo12=True, flex_register_offsets=True)
        if replacement is None:
            # Flexible-base correctness cannot fall back to PAGEZERO pointer
            # upgrading: a host pointer truncated through a W register would no
            # longer equal the guest VA. Reject any remaining guest memory
            # access through a general register so CI exposes unsupported
            # addressing forms before they reach a device. SP/FP are real host
            # stack/frame pointers and are intentionally left untouched.
            mm = flex_gpr_mem_re.match(line)
            if mm:
                rn = int(mm['rn'])
                if (rn < 29 or rn == 30) and rn not in (ARENA_SCRATCH, FLEX_BASE):
                    raise ConvertError(
                        f'{input_path}: unconverted flexible-base memory access '
                        f'through x{rn}: {line.strip()}')
            out.append(line)
            continue
        if ARENA_BLR_RE.match(line) or FLEX_BR_RE.match(line):
            blr_sites += 1
        else:
            sites += 1
        out.extend(replacement)
    print(f'iOS flexible-base fast path: {sites} memory sites, {blr_sites} indirect branches in {input_path}')
    return '\n'.join(out) + '\n'

def main():
    args = sys.argv[1:]
    ios_fastpath = False
    ios_arena = False
    ios_flex = False
    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag == "--ios-pointer-fastpath":
            ios_fastpath = True
        elif flag == "--ios-arena-fastpath":
            ios_arena = True
        elif flag == "--ios-flex-base-fastpath":
            ios_flex = True
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
        if ios_arena and ios_flex:
            raise ConvertError('choose either aligned-arena or flexible-base fast path')
        if ios_arena:
            result = ios_arena_fastpath(result, args[0])
        if ios_flex:
            result = ios_flex_base_fastpath(result, args[0])
    except ConvertError as e:
        print(f"{args[0]}: {e}", file=sys.stderr)
        sys.exit(1)
    with open(args[1], "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(result)


if __name__ == "__main__":
    main()
