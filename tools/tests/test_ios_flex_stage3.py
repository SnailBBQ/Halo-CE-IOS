"""M2.6.95 Non-Jailbreak real-guest flexible-base Stage 3 guards.

The test stays host-portable: it validates the correctness-critical assembly
rewrite on representative arm64_32 output and checks that only the Non-JB
workflow enables the x27 ABI. Device execution is still proven by Actions and
physical logs.
"""
from pathlib import Path
import importlib.util
import re
import shutil
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "port/ios/HaloIOS"

spec = importlib.util.spec_from_file_location("converter", ROOT / "tools/android_asm_convert.py")
conv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(conv)
conv.print = lambda *a, **k: None

sample = """\
\t.text
foo:
\tstp x29, x30, [sp, #-16]!
\tmov x29, sp
\tadrp x8, global_data
\tadd x8, x8, :lo12:global_data
\tldr w9, [x8]
\tsub x0, x29, #4
\tldr w10, [x0]
\tblr x11
\tldp x29, x30, [sp], #16
\tret
"""
out = conv.ios_flex_base_fastpath(sample, "build/android/guest/obj/source/foo.o.darwin.s")
assert "adrp x8, global_data\n\tsub x8, x8, x27\n\tadd x8, x8, :lo12:global_data" in out
assert "sub x0, x29, #4\n\tsub x0, x0, x27" in out
assert "add x15, x27, w8, uxtw\n\tldr w9, [x15]" in out
assert "add x15, x27, w0, uxtw\n\tldr w10, [x15]" in out
assert "add x15, x27, w11, uxtw" in out and "blr x15" in out

# Broad addressing-form coverage. Every ordinary general-register base must
# translate through x27+x15; SP/x29 accesses remain native host-stack accesses.
forms = [
    'ldr w0, [x{rn}]', 'ldr w0, [x{rn}, #12]', 'str w1, [x{rn}, #-12]',
    'ldr x3, [x{rn}, #4096]', 'ldrb w3, [x{rn}, #1]', 'ldrsh x3, [x{rn}, #2]',
    'ldrsw x3, [x{rn}, #4]', 'ldur w3, [x{rn}, #-3]', 'stur x3, [x{rn}, #-9]',
    'ldr q0, [x{rn}, #16]', 'str d0, [x{rn}, #8]', 'ldp x3, x4, [x{rn}, #16]',
    'stp w3, w4, [x{rn}, #-8]', 'ldpsw x3, x4, [x{rn}, #8]',
    'ldr w0, [x{rn}, w2, uxtw #2]', 'ldrb w0, [x{rn}, w2, sxtw]',
    # Clang uses all of these legal X-register offset spellings.  Bare Xm is
    # the default LSL #0 form and is the exact shape that towctrans.o exposed
    # in the first real Stage-3 guest build.
    'ldrb w16, [x{rn}, x16]', 'ldr w0, [x{rn}, x2, lsl #0]',
    'str x0, [x{rn}, x2, lsl #3]', 'ldr x0, [x{rn}, x2, sxtx]',
    'ldr x0, [x{rn}, x2, sxtx #3]',
    'ldaxr w0, [x{rn}]', 'stlxr w5, w0, [x{rn}]',
    'ldar w0, [x{rn}]', 'stlr w1, [x{rn}]', 'ldaxp x3, x4, [x{rn}]',
    'stlxp w5, x3, x4, [x{rn}]',
]
checked = 0
for rn in range(29):
    if rn in (15, 27):
        continue
    for template in forms:
        line = '\t' + template.format(rn=rn) + '\n'
        rewritten = conv.ios_flex_base_fastpath(line, f'forms-{rn}.o.darwin.s')
        assert f'add x15, x27, w{rn}, uxtw' in rewritten, (rn, template, rewritten)
        import re as _re
        assert not _re.search(r'\[x' + str(rn) + r'(?:,|\])', rewritten), (rn, template, rewritten)
        checked += 1
for stack_line in ('\tldr w0, [sp, #16]\n', '\tldr w0, [x29, #-8]\n', '\tstp x29, x30, [sp, #-16]!\n'):
    assert conv.ios_flex_base_fastpath(stack_line, 'stack.o.darwin.s') == stack_line
assert checked >= 500


# M2.6.95 regression from the first real Stage-3 guest build: musl's
# towctrans.o emitted a bare X-register offset.  AArch64 defines ``[Xn, Xm]``
# as the ordinary LSL #0 register-offset form, so translate only the guest
# pointer base and preserve the index register verbatim.
towctrans = conv.ios_flex_base_fastpath(
    "\tldrb w16, [x12, x16]\n", "towctrans.o.darwin.s")
assert towctrans == "\tadd x15, x27, w12, uxtw\n\tldrb w16, [x15, x16]\n"

# Also make the ELF assembler accept the representative register-offset
# output when a clang driver is available.  This checks the full
# converter->AArch64-assembler boundary without needing the Android NDK.
clang = shutil.which("clang")
if clang:
    asm = "\t.text\n\t.globl flex_regoff_probe\nflex_regoff_probe:\n" + towctrans + "\tret\n"
    with tempfile.TemporaryDirectory() as td:
        src = Path(td) / "probe.s"
        obj = Path(td) / "probe.o"
        src.write_text(asm)
        subprocess.run(
            [clang, "--target=aarch64-linux-android", "-c", str(src), "-o", str(obj)],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert obj.is_file() and obj.stat().st_size > 0

# Register-offset validation remains fail-closed for invalid width/extension
# pairings rather than accepting arbitrary bracket syntax.
for bad_regoff in (
    "\tldr w0, [x8, w9]\n",
    "\tldr w0, [x8, x9, uxtw #2]\n",
    "\tldr w0, [x8, w9, lsl #2]\n",
):
    try:
        conv.ios_flex_base_fastpath(bad_regoff, "bad-regoff.o.darwin.s")
    except conv.ConvertError as exc:
        assert "unconverted flexible-base memory access" in str(exc)
    else:
        raise AssertionError(f"invalid register-offset form was accepted: {bad_regoff!r}")

# Tail-call function pointers use BR rather than BLR at -O2. They must be
# translated directly instead of depending on a PAGEZERO instruction-fetch
# fault to redirect the low guest target.
tail = conv.ios_flex_base_fastpath("\tbr x1\n", "tail.o.darwin.s")
assert "add x15, x27, w1, uxtw" in tail and "br x15" in tail and "br x1" in tail
assert "adr x15" not in out and "0xffffffff00000000" not in out

# Direct symbol PAGEOFF loads/stores are common in arm64_32 clang output.
# They must keep the low-12 relocation while the page base is translated
# through x27, rather than slipping through as an untranslated memory access.
pageoff = "\tadrp x9, g\n\tldr w10, [x9, :lo12:g]\n\tstr w10, [x9, :lo12:g]\n"
pageoff_out = conv.ios_flex_base_fastpath(pageoff, "pageoff.o.darwin.s")
assert "adrp x9, g\n\tsub x9, x9, x27" in pageoff_out
assert "add x15, x27, w9, uxtw\n\tldr w10, [x15, :lo12:g]" in pageoff_out
assert "add x15, x27, w9, uxtw\n\tstr w10, [x15, :lo12:g]" in pageoff_out

# Any bracketed guest memory form the converter cannot translate must fail
# loudly.  The flexible ABI cannot safely rely on the old pointer-upgrade
# signal fallback.
unhandled = "\tldr w0, [x8, x9, uxtw #2]\n"
try:
    conv.ios_flex_base_fastpath(unhandled, "unhandled.o.darwin.s")
except conv.ConvertError as exc:
    assert "unconverted flexible-base memory access" in str(exc)
else:
    raise AssertionError("unsupported guest memory access was silently retained")

# Startup/thread objects are correctness-critical now; unlike the aligned path,
# they must be transformed rather than intentionally left on the signal bridge.
startup = "\t.text\n__guest_start:\n\tldr w0, [x0]\n\tret\n"
startup_out = conv.ios_flex_base_fastpath(
    startup, "build/android/guest/obj/port/android/guest/runtime/guest_start.o.darwin.s")
assert "add x15, x27, w0, uxtw" in startup_out

# x15 is always converter-owned. x27 is guest-base state, but LLVM may still
# preserve a fixed callee-saved x27 in a normal host-stack prologue/epilogue.
# That save/reload is safe and must not be mistaken for register allocation.
preserve_x27 = """\
\tstp x28, x27, [sp, #16]
\tldp x28, x27, [sp, #16]
"""
preserve_out = conv.ios_flex_base_fastpath(preserve_x27, "scandir-like.o.darwin.s")
assert preserve_out == preserve_x27

# The three forms real arm64_32 LLVM emits (offset, pre-index prologue, post-index
# epilogue), in either register order, plus CFI metadata and comments naming x27.
real_forms = """\
\t.cfi_offset w27, -24
\tstp x28, x27, [sp, #-96]!        ; 16-byte Folded Spill
\tstp x28, x27, [sp, #16]          ; 16-byte Folded Spill
\tldp x28, x27, [sp, #16]          ; 16-byte Folded Reload
\tldp x28, x27, [sp], #96          ; 16-byte Folded Reload
\tstp x27, x28, [sp, #0x20]
\tldp x27, x28, [sp]
\t; x27 and w15 only mentioned in a comment
\tadd x0, x0, #1 ; scratch x27 note
"""
real_out = conv.ios_flex_base_fastpath(real_forms, "forms.o.darwin.s")
for form in ("[sp, #-96]!", "[sp], #96", "[sp, #16]"):
    assert form in real_out, form

# Near misses must still fail: wrong base, register offset, other partner register,
# wrong width, non-literal offset, writeback on the wrong side, x15 in any width.
for bad in (
    "\tstp x28, x27, [x8, #16]\n",
    "\tstp x28, x27, [x29, #16]\n",
    "\tstp x28, x27, [sp, x1]\n",
    "\tstp x26, x27, [sp, #16]\n",
    "\tstp w28, w27, [sp, #16]\n",
    "\tstp x28, x27, [sp, #foo]\n",
    "\tstp x28, x27, [sp, #16]!, #8\n",
    "\tstp x28, x27, [sp]!\n",
    "\tstp x28, x27, [sp, #16]\n\tldr x0, [x27]\n",
    "\tmov x15, x0\n",
    "\tldr w0, [x15]\n",
    "\tadd x0, x15, #4\n",
    "\tstp x15, x28, [sp, #16]\n",
):
    try:
        conv.ios_flex_base_fastpath(bad, "near-miss.o.darwin.s")
    except conv.ConvertError:
        pass
    else:
        raise AssertionError(f"near-miss reserved-register use did not fail: {bad!r}")

# Reproduce the real M2.6.95 scandir-class failure with arm64_32 clang when the
# target is available. Under register pressure LLVM may pair fixed x27 with x28
# for a callee-save spill even though it never allocates x27 for computation.
if clang:
    pressure_c = r"""
extern int ext(int);
int flex_x27_spill_probe(int *p, int n, int (*cb)(int)) {
    int a0=p[0],a1=p[1],a2=p[2],a3=p[3],a4=p[4];
    int a5=p[5],a6=p[6],a7=p[7],a8=p[8],a9=p[9];
    int s=0;
    for (int i=0;i<n;i++) {
        s += cb(a0+i)+ext(a1+i)+ext(a2+i)+ext(a3+i)+ext(a4+i);
        s += ext(a5+i)+ext(a6+i)+ext(a7+i)+ext(a8+i)+ext(a9+i);
    }
    return s;
}
"""
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        csrc = td / "x27_spill.c"
        darwin = td / "x27_spill.darwin.s"
        elfasm = td / "x27_spill.s"
        obj = td / "x27_spill.o"
        csrc.write_text(pressure_c)
        subprocess.run([
            clang, "--target=arm64_32-apple-watchos", "-ffixed-x15", "-ffixed-x27",
            "-mllvm", "-aarch64-enable-compress-jump-tables=false",
            "-O2", "-std=c99", "-ffreestanding", "-fno-common",
            "-S", str(csrc), "-o", str(darwin),
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        # The probe must really reproduce the x27 preservation pair, otherwise this
        # regression would pass vacuously if LLVM stopped emitting it.
        assert re.search(r"^\s*(stp|ldp)\s+x28, x27, \[sp", darwin.read_text(), re.M), \
            "register-pressure probe no longer emits an x28/x27 stack pair"
        subprocess.run([
            sys.executable, str(ROOT / "tools/android_asm_convert.py"),
            "--ios-flex-base-fastpath", str(darwin), str(elfasm),
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        subprocess.run([
            clang, "--target=aarch64-linux-android", "-c", str(elfasm), "-o", str(obj),
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert obj.is_file() and obj.stat().st_size > 0

# Any executable use beyond host-stack preservation remains fatal. A 32-bit
# w27 spill is also forbidden because it would truncate the 64-bit arena base.
for bad in (
    "\tmov x27, x0\n",
    "\tadd x0, x27, #4\n",
    "\tldr w0, [x27]\n",
    "\tbr x27\n",
    "\tstr w27, [sp, #4]\n",
    "\tstr x27, [sp, #8]\n",
    "\tldp x26, x27, [sp, #16]\n",
    "\tmov w15, #1\n",
):
    try:
        conv.ios_flex_base_fastpath(bad, "bad.o.darwin.s")
    except conv.ConvertError:
        pass
    else:
        raise AssertionError(f"unsafe reserved-register use did not fail: {bad!r}")
# M2.6.99-class gap seen on a real iPhone 14 Plus (M2.6.98 log): LLVM saves the link
# register and, under register pressure, reuses x30 as an ordinary register holding a
# guest pointer (monocypher's mod_l: "ldr w9, [x30]"). The flexible model has no
# signal-bridge fallback, so a memory access through x30 must be translated like any
# other base register. The return address (ret, ldp/stp x29,x30 on SP) must not change.
x30_in = (
    "\tldr w9, [x30]\n"
    "\tstr w11, [x30, #8]\n"
    "\tldr x0, [x30, #16]!\n"
    "\tldr x1, [x2, x30]\n"
)
x30_out = conv.ios_flex_base_fastpath(x30_in, "x30.o.darwin.s")
assert "add x15, x27, w30, uxtw\n\tldr w9, [x15]" in x30_out, x30_out
assert "add x15, x27, w30, uxtw\n\tstr w11, [x15, #8]" in x30_out, x30_out
assert "add x30, x30, #16\n\tadd x15, x27, w30, uxtw\n\tldr x0, [x15]" in x30_out, x30_out
assert "add x15, x27, w2, uxtw\n\tldr x1, [x15, x30]" in x30_out, x30_out    # x30 as an index stays an index
assert "[x30" not in x30_out, x30_out

x30_branches = conv.ios_flex_base_fastpath("\tblr x30\n\tbr x30\n", "x30br.o.darwin.s")
assert x30_branches.count("lsr x15, x30, #32") == 2 and x30_branches.count("add x15, x27, w30, uxtw") == 2, x30_branches
assert "\tblr x30\n" in x30_branches and "\tbr x30\n" in x30_branches      # a wide (host) value is used unchanged

x30_addr = conv.ios_flex_base_fastpath("\tadrp x30, g\n\tadd x30, sp, #16\n\tmov x30, x29\n", "x30adr.o.darwin.s")
assert x30_addr.count("sub x30, x30, x27") == 3, x30_addr

keep = "\tstp x29, x30, [sp, #-16]!\n\tldr w0, [x29, #8]\n\tldp x29, x30, [sp], #16\n\tret\n"
assert conv.ios_flex_base_fastpath(keep, "keep.o.darwin.s") == keep

# The regular aligned converter translates x30 too (M2.6.100): the unconverted ADPCM loop in
# stream_process cost 16 million signal-bridge faults in the M2.6.98 regular log.
aligned_x30 = conv.ios_arena_fastpath("\tldr w9, [x30]\n\tblr x30\n", "/x/aligned.o.darwin.s")
assert "w30, uxtw" in aligned_x30 and "[x30]" not in aligned_x30 and "blr x15" in aligned_x30, aligned_x30

if clang:
    x30_c = r"""
typedef struct { int a; short b; char c; double d; float f[4]; void *next; } S;
extern S *getS(int);
extern int ext(int);
int flex_x30_probe(int x) {
    S *p0=getS(x+0),*p1=getS(x+1),*p2=getS(x+2),*p3=getS(x+3),*p4=getS(x+4),*p5=getS(x+5),*p6=getS(x+6),*p7=getS(x+7);
    S *p8=getS(x+8),*p9=getS(x+9),*p10=getS(x+10),*p11=getS(x+11),*p12=getS(x+12),*p13=getS(x+13),*p14=getS(x+14);
    S *p15=getS(x+15),*p16=getS(x+16),*p17=getS(x+17),*p18=getS(x+18),*p19=getS(x+19),*p20=getS(x+20),*p21=getS(x+21);
    unsigned long long acc = 0;
    for (int i = 0; i < x; i++) {
#define T(p,q) acc += p->a * p->b + (unsigned long long)p->c + (unsigned long long)p->d; p->f[i & 3] += acc; p->a = (int)acc ^ i; p->next = q;
        T(p0,p1) T(p1,p2) T(p2,p3) T(p3,p4) T(p4,p5) T(p5,p6) T(p6,p7) T(p7,p8) T(p8,p9) T(p9,p10) T(p10,p11)
        T(p11,p12) T(p12,p13) T(p13,p14) T(p14,p15) T(p15,p16) T(p16,p17) T(p17,p18) T(p18,p19) T(p19,p20) T(p20,p21) T(p21,p0)
        acc += ext(i);
    }
    return (int)acc;
}
"""
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        (td / "x30.c").write_text(x30_c)
        subprocess.run([
            clang, "--target=arm64_32-apple-watchos", "-ffixed-x15", "-ffixed-x27",
            "-mllvm", "-aarch64-enable-compress-jump-tables=false", "-mcpu=cortex-a53",
            "-O2", "-std=gnu11", "-ffreestanding", "-fno-common", "-fno-omit-frame-pointer", "-w",
            "-S", str(td / "x30.c"), "-o", str(td / "x30.darwin.s"),
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        probe_asm = (td / "x30.darwin.s").read_text()
        # Non-vacuous: LLVM must really be using x30 as a memory base here.
        if not re.search(r"^\s*(ld|st)[a-z0-9]*\s[^\n]*\[x30", probe_asm, re.M):
            # A different LLVM may allocate registers differently; the unit cases above still pin the rule.
            print("NOTE: x30 register-pressure probe no longer reuses x30 as a pointer register in this clang")
        subprocess.run([
            sys.executable, str(ROOT / "tools/android_asm_convert.py"),
            "--ios-flex-base-fastpath", str(td / "x30.darwin.s"), str(td / "x30.s"),
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        converted = (td / "x30.s").read_text()
        for line in converted.splitlines():
            m = re.match(r"^\s*(?:%s)\b[^\[]*\[\s*(x\d+|sp)\b" % conv.ARENA_MEM_OPS, line)
            assert not m or m.group(1) in ("x15", "sp", "x29"), f"untranslated guest memory base: {line.strip()}"
        subprocess.run([clang, "--target=aarch64-linux-android", "-c", str(td / "x30.s"), "-o", str(td / "x30.o")],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

compressed = """\
\t.text
f:
.LLBB1_1:
\tldr w0, [x0]
\t.section .rodata,"a",@progbits
.LLJTI1_0:
\t.byte (.LLBB1_1-.LLBB1_1)>>2
"""
try:
    conv.ios_flex_base_fastpath(compressed, "compressed.o.darwin.s")
except conv.ConvertError:
    pass
else:
    raise AssertionError("compressed jump table did not fail flexible-base conversion")

runtime = (HOST / "halo_guest_runtime.c").read_text()
header = (HOST / "halo_guest_runtime.h").read_text()
bridge = (HOST / "halo_guest_exec_bridge.c").read_text()
runner = (HOST / "halo_guest_runner.m").read_text()
boot = (HOST / "halo_boot_integration.m").read_text()
guest_start = (ROOT / "port/android/guest/runtime/guest_start.c").read_text()
workflow = (ROOT / ".github/workflows/ios.yml").read_text()

for token in (
    "Stage 3 real-guest fallback: reserved 4 GiB",
    "g_guest_base = (uint8_t *)flex",
    "g_guest_flexible_base = hostile",
    "halo_guest_runtime_is_flexible_base",
):
    assert token in runtime + header, token
assert "if (halo_guest_runtime_is_flexible_base())" in bridge
assert "abort_guest_from_signal" in bridge

for token in (
    "halo_nonjb_guest_call_u32",
    "mov x27, x2",
    "HALO_IOS_FLEX_BASE_GUEST_V1",
    "nonjb 600 flex real guest arena active",
    "nonjb 601 flex guest ABI marker verified",
    "nonjb 602 flex real guest ELF segments loaded",
    "nonjb 603 flex real guest imports resolved",
    "nonjb 604 flex real guest boot built",
    "nonjb 605 flex real guest stack ready",
    "nonjb 606 flex real guest branch __guest_start",
    "nonjb 607 flex real guest entered __guest_start",
    "nonjb 608 flex real guest thread pointer initialized",
    "nonjb 609 flex real guest entering OpenCE main",
):
    assert token in runner, token
assert "Host-side map/scenario bootstrap and the real flexible-base halo_guest.elf will be attempted" in boot
assert "HALO_IOS_FLEX_BASE" in guest_start and "HALO_IOS_FLEX_BASE_GUEST_V1" in guest_start
assert "HALO_IOS_FLEX_STAGE3_MAIN" in guest_start


# Generated host-import stubs are assembled directly rather than passed through
# the C-object converter. That is intentional: ADRP resolves the import table
# relative to the relocated host PC, LDR obtains a real 64-bit host function
# address, and BR must branch to that wide address without guest-base mapping.
imports = (ROOT / "tools/android_imports.py").read_text()
for token in (
    r'f"\tadrp x16, __host_import_table+{offset}"',
    r'f"\tldr x16, [x16, :lo12:__host_import_table+{offset}]"',
    r'"\tbr x16"',
):
    assert token in imports, token

# The special guest ABI must exist only for the manual Non-JB flavor.
for token in (
    "-DHALO_IOS_FLEX_BASE=1",
    "--ios-flex-base-fastpath",
    "-ffixed-x27",
    "Non-Jailbreak Stage 3 requires compressed jump tables to be disabled",
    "HALO_IOS_FLEX_BASE_GUEST_V1",
    "flex-base-stage3-real-guest+exec-trace-v3",
):
    assert token in workflow, token

print("PASS: Stage 3 reserves the real hostile arena, builds a distinct x27 flexible-base guest, canonicalizes PC/SP/FP-derived pointers, aborts unsafe missed pointer faults, and persists real-guest phases 600-609")
