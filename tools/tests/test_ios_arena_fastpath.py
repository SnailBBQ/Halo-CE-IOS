"""Check the iOS arena fast-path rewrite of android_asm_convert.py.

Pure Python (no unicorn/keystone): a small model executes the emitted ALU
sequence and compares the resulting host address / writeback with what the
signal bridge produces today.

Run: python tools/tests/test_ios_arena_fastpath.py
"""
import importlib.util, random, re, subprocess, sys, tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('converter', root / 'tools/android_asm_convert.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.print = lambda *a, **k: None

ARENA = 0x400000000
CODE_PC = ARENA + 0x88001230
M64 = (1 << 64) - 1
ALLOWED = {'adr', 'and', 'add', 'sub', 'lsr', 'cbnz', 'b', 'blr'}
FLAG_SETTERS = re.compile(r'^\s*(adds|subs|ands|cmp|cmn|tst|ccmp|ccmn|fcmp)\b')


def bridge_upgrade(v):
    """What the signal handler does to a faulting base register."""
    return v + ARENA if 0 < v < (1 << 32) else v


def sext32(v):
    v &= 0xffffffff
    return v - (1 << 32) if v & 0x80000000 else v


def reg_value(regs, token):
    if token in ('xzr', 'wzr'):
        return 0
    n = int(token[1:])
    return regs[n] & (M64 if token[0] == 'x' else 0xffffffff)


def offset_value(regs, off):
    off = off.strip()
    if not off:
        return 0
    if off.startswith('#'):
        return int(off[1:], 0)
    ro = m.ARENA_REGOFF_RE.match(off)
    value = regs[int(ro['n'])]
    ext, amt = ro['ext'], int(ro['amt'] or 0)
    if ro['r'] == 'w':
        value = sext32(value) if ext == 'sxtw' else value & 0xffffffff
    return (value << amt) & M64


def parse_mem(line):
    mm = m.ARENA_MEM_RE.match(line)
    assert mm, line
    return mm


def execute(lines, regs):
    """Run the replacement; returns (effective address, registers, call target)."""
    regs = list(regs)
    labels = {l.strip()[:-1]: i for i, l in enumerate(lines) if l.strip().endswith(':')}
    i, target, ea = 0, None, None
    steps = 0
    while i < len(lines):
        steps += 1
        assert steps < 64
        line = lines[i]
        text = line.strip()
        if text.endswith(':'):
            i += 1
            continue
        assert not FLAG_SETTERS.match(line), line
        op = text.split()[0]
        if op in m.ARENA_MEM_OPS.split('|') or m.ARENA_MEM_RE.match(line):
            mm = parse_mem(line)
            assert int(mm['rn']) == 15 and not mm['wb'] and not mm['post'], line
            ea = (regs[15] + offset_value(regs, mm['off'] or '')) & M64
            i += 1
            continue
        assert op in ALLOWED, line
        args = [a.strip() for a in text[len(op):].split(',')]
        if op == 'adr':
            assert args == ['x15', '.']
            regs[15] = CODE_PC
        elif op == 'and':
            assert args[0] == args[1] == 'x15' and int(args[2][1:], 0) == 0xffffffff00000000
            regs[15] &= 0xffffffff00000000
        elif op == 'add' and len(args) == 4:
            assert args[0] == args[1] == 'x15' and args[3] == 'uxtw'
            regs[15] = (regs[15] + (regs[int(args[2][1:])] & 0xffffffff)) & M64
        elif op in ('add', 'sub'):
            d, s_ = int(args[0][1:]), int(args[1][1:])
            assert d == s_
            imm = regs[int(args[2][1:])] if args[2].startswith('x') else int(args[2][1:])
            regs[d] = (regs[d] + (imm if op == 'add' else -imm)) & M64
        elif op == 'lsr':
            regs[15] = regs[int(args[1][1:])] >> int(args[2][1:])
        elif op == 'cbnz':
            if regs[15]:
                i = labels[args[1]]
                continue
        elif op == 'b':
            i = labels[args[0]]
            continue
        elif op == 'blr':
            target = regs[int(args[0][1:])]
        i += 1
    return ea, regs, target


def check_memory(instruction, rn_values, index_choices=(5, 0x1000, 0xfffffff0)):
    original = parse_mem(instruction)
    lines = m.arena_rewrite_line(instruction, '.Lhalo_ios_arena_0')
    assert lines, instruction
    rn = int(original['rn'])
    off = (original['off'] or '').strip()
    rnd = random.Random(hash(instruction) & 0xffff)
    for v in rn_values:
        for idx in index_choices:
            regs = [rnd.getrandbits(64) for _ in range(31)]
            regs[rn] = v
            if rn != 2:
                regs[2] = idx
            ro = m.ARENA_REGOFF_RE.match(off) if off and not off.startswith('#') else None
            if ro and int(ro['n']) == rn:
                continue
            ea, after, _ = execute(lines, regs)
            # Reference: bridge upgrades the faulting base, then the instruction runs.
            imm = int(original['post'][1:], 0) if original['post'] else None
            if original['wb']:
                imm = int(off[1:], 0)
            if original['wb']:
                base = bridge_upgrade(v)  # base unchanged by the aborted instruction
                expected_ea = (base + imm) & M64
                expected_rn = (v + imm) & M64
            elif original['post']:
                expected_ea = bridge_upgrade(v)
                expected_rn = (v + imm) & M64
            else:
                regs2 = list(regs)
                regs2[rn] = bridge_upgrade(v)
                expected_ea = (regs2[rn] + offset_value(regs2, off)) & M64
                expected_rn = v
            if v == 0:
                # Null base: both forms fault (guard page vs unmapped arena page 0).
                if (not off or off.startswith('#')) and not original['wb']:
                    assert abs(ea - ARENA) < 0x20000, (instruction, hex(ea))
                continue
            assert ea == expected_ea, (instruction, hex(v), hex(ea), hex(expected_ea))
            assert after[rn] & 0xffffffff == expected_rn & 0xffffffff, (instruction, hex(after[rn]), hex(expected_rn))
            assert (after[rn] >> 32) in (0, expected_rn >> 32), (instruction, hex(after[rn]))
            for other in range(31):
                if other not in (rn, 15):
                    assert after[other] == regs[other], (instruction, other)
            assert FLAG_SETTERS.search('\n'.join(lines)) is None


narrow = [0x90000100, 0x1000, 0xec001ff8, 0x7ffffff0]
wide = [ARENA + 0x90000100, ARENA + 0xed001ff0]
checks = 0
for rn in [r for r in range(29) if r != 15]:
    forms = [
        f'\tldr w0, [x{rn}]', f'\tldr w0, [x{rn}, #12]', f'\tstr w1, [x{rn}, #-12]',
        f'\tldr x3, [x{rn}, #4096]', f'\tldrb w3, [x{rn}, #1]', f'\tldrsh x3, [x{rn}, #2]',
        f'\tldrsw x3, [x{rn}, #4]', f'\tldur w3, [x{rn}, #-3]', f'\tstur x3, [x{rn}, #-9]',
        f'\tldr q0, [x{rn}, #16]', f'\tstr d0, [x{rn}, #8]', f'\tldp x3, x4, [x{rn}, #16]',
        f'\tstp w3, w4, [x{rn}, #-8]', f'\tldpsw x3, x4, [x{rn}, #8]',
        f'\tldr w0, [x{rn}, w2, uxtw #2]', f'\tldrb w0, [x{rn}, w2, sxtw]',
        f'\tstr x0, [x{rn}, x2, lsl #3]',
        f'\tldaxr w0, [x{rn}]', f'\tldxr x3, [x{rn}]', f'\tstlxr w5, w0, [x{rn}]', f'\tstxr w5, x3, [x{rn}]',
        f'\tldar w0, [x{rn}]', f'\tstlr w1, [x{rn}]', f'\tldaxrb w0, [x{rn}]', f'\tstlxrh w5, w1, [x{rn}]',
        f'\tldaxp x3, x4, [x{rn}]', f'\tstlxp w5, x3, x4, [x{rn}]',
    ]
    if rn not in (0, 1, 3, 4):
        forms += [f'\tldr w0, [x{rn}], #8', f'\tstr w1, [x{rn}], #-4', f'\tldr w0, [x{rn}, #8]!',
                  f'\tstr w1, [x{rn}, #-16]!', f'\tldp x3, x4, [x{rn}], #16',
                  f'\tstp x3, x4, [x{rn}, #-32]!']
    for form in forms:
        check_memory(form, narrow + wide + [0])
        checks += 1

# A compare-and-swap loop keeps working: the inserted ALU instructions sit inside the exclusive pair.
loop = '\n'.join(['\tmov w9, #1', '.Lspin:', '\tldaxr w8, [x0]', '\tcbnz w8, .Lspin', '\tstlxr w10, w9, [x0]', '\tcbnz w10, .Lspin', '\tret'])
rewritten = m.ios_arena_fastpath(loop + '\n', 'x/source/lock.o.darwin.s')
assert rewritten.count('adr x15, .') == 2 and 'ldaxr w8, [x15]' in rewritten and 'stlxr w10, w9, [x15]' in rewritten
between = rewritten.split('ldaxr w8, [x15]')[1].split('stlxr w10, w9, [x15]')[0]
assert not any(w in between for w in ('ldr', 'str', 'ldp', 'stp', 'ld1', 'st1', 'bl ')), 'only ALU/branch between exclusives'

# Sites that must stay on the signal bridge.
keep = [
    '\tldr w0, [sp, #16]', '\tstp x29, x30, [sp, #-16]!', '\tldr w0, [x29, #-8]', '\tldr x0, [x30]',
    '\tldr w0, [x15, #4]', '\tldr w8, [x8, :lo12:g_value]', '\tldr w0, [x1, x2]',
    '\tldr w0, [x1, x2, lsl #0]', '\tldr w0, [x1, x2, sxtx #2]', '\tldr w0, [x1, w2, lsl #2]',
    '\tldr w0, [x1, #sym]', '\tldr w0, [x1], x2', '\tld1 { v0.4s }, [x1, #16]', '\tld1 { v0.4s }, [x1]!',
    '\tld1 { v0.4s }, [x1], x15', '\tld1 { v0.4s }, [x1], x1',
    '\tprfm pldl1keep, [x1, #64]', '\tldaxr w0, [x1, #4]', '\tstlxr w2, w0, [x1], #4', '\tldr w0, =lit', '\tldr w0, Lpool', '\tldr w0, [x1, #8]!!', '\tbr x8',
    '\tblr x30', '\tblr x15', '\tadd x0, x1, x2', '\tstr w0, [x1, #8], #4',
]
for line in keep:
    assert m.arena_rewrite_line(line, '.Lx') is None, line

# NEON structure loads/stores: plain, lane, post-increment by immediate and by register.
neon = ['\tld1 { v0.4s }, [x{rn}]', '\tld1 { v0.4s, v1.4s }, [x{rn}]', '\tld1 { v0.s }[1], [x{rn}]',
        '\tst1 { v0.16b }, [x{rn}]', '\tld1r { v0.4s }, [x{rn}]', '\tst2 { v0.4s, v1.4s }, [x{rn}]',
        '\tld1 { v0.4s }, [x{rn}], #16', '\tst1 { v0.4s }, [x{rn}], #16', '\tld1 { v0.4s }, [x{rn}], x9']
for rn in [r for r in range(29) if r not in (9, 15)]:
    for template in neon:
        line = template.replace('{rn}', str(rn))
        lines = m.arena_rewrite_line(line, '.Lx')
        assert lines, line
        for v in narrow + wide:
            regs = [1] * 31
            regs[9] = 48
            regs[rn] = v
            ea, after, _ = execute(lines, regs)
            assert ea == bridge_upgrade(v), (line, hex(ea))
            expected = v + (16 if '#16' in line else 48 if ', x9' in line else 0)
            assert after[rn] == expected, (line, hex(after[rn]))
            assert after[9] == 48
        checks += 1

# Indirect calls: narrow function pointers are translated, wide ones are unchanged.
for rn in range(0, 30):
    if rn == 15:
        continue
    lines = m.arena_rewrite_line(f'\tblr x{rn}', '.Lhalo_ios_arena_9')
    for v, expect in [(0x88003210, CODE_PC & 0xffffffff00000000 | 0x88003210),
                      (ARENA + 0x88003210, ARENA + 0x88003210),
                      (0x600001234, 0x600001234)]:
        regs = [0] * 31
        regs[rn] = v
        _, after, target = execute(lines, regs)
        assert target == expect, (rn, hex(v), hex(target or 0))
        assert after[rn] == v
    assert len({l.strip() for l in lines if l.strip().endswith(':')}) == 2
    checks += 1

# Whole-object behaviour.
sample = '''\t.text
foo:
\tstp x29, x30, [sp, #-16]!
\tmov x29, sp
\tadrp x8, g_value
\tldr w9, [x8, :lo12:g_value]
\tldr w0, [x0, #4]
\tldr w8, [x0], #8
\tblr x8
\tldp x29, x30, [sp], #16
\tret
'''
out = m.ios_arena_fastpath(sample, 'build/android/guest/obj/source/foo/bar.o.darwin.s')
assert 'ldr w9, [x8, :lo12:g_value]' in out and 'stp x29, x30, [sp, #-16]!' in out
assert out.count('adr x15, .') == 3 and 'ldr w0, [x15, #4]' in out and 'ldr w8, [x15]' in out
assert 'add x0, x0, #8' in out
labels = re.findall(r'^(\.Lhalo_ios_arena_\d+_[we]):', out, re.M)
assert len(labels) == len(set(labels)) == 2, labels
assert m.ios_arena_fastpath(sample + '\tmov x15, #1\n', 'x/source/a.o.darwin.s') == sample + '\tmov x15, #1\n'
assert m.ios_arena_fastpath(sample + '\tmov w15, #1\n', 'x/source/a.o.darwin.s') == sample + '\tmov w15, #1\n'
for skipped in ['build/android/guest/obj/port/android/guest/runtime/guest_start.o.darwin.s',
                'build/android/guest/obj/port/android/guest/runtime/guest_thread.o.darwin.s']:
    assert m.ios_arena_fastpath(sample, skipped) == sample, skipped
for instrumented in ['build/android/guest/obj/port/android/guest/runtime/guest_misc.o.darwin.s',
                     'build/android/guest/obj/musl/build/android/third_party/musl-1.2.5/src/string/strlen.o.darwin.s']:
    assert m.ios_arena_fastpath(sample, instrumented) != sample, instrumented
assert m.ios_arena_fastpath('\tldr w0, [x1]\n\tldr w2, [x3_x15]\n', 'x/a.o.darwin.s').count('adr x15') == 1

# Compressed jump tables: the function that owns one is left alone, others are not.
tables = '''\t.text
f1:
\tldr w0, [x1]
.LLBB1_1:
\tldr w2, [x3]
\tadr x10, .LLBB1_2
\tldrb w11, [x9, x8]
\tbr x10
.LLBB1_2:
\tldr w4, [x5]
\t.section .rodata,"a",@progbits
.LLJTI1_0:
\t.byte (.LLBB1_2-.LLBB1_1)>>2
\t.text
f2:
\tldr w6, [x7]
.LLBB2_1:
\tldr w8, [x7, #4]
'''
res = m.ios_arena_fastpath(tables, 'x/source/t.o.darwin.s')
assert 'ldr w0, [x15]' in res, 'entry block before the first numbered block is not inside the table span'
assert 'ldr w2, [x3]' in res and 'ldr w4, [x5]' in res, 'functions with compressed tables must stay untouched'
assert 'ldr w6, [x15]' in res and 'ldr w8, [x15, #4]' in res, 'the next function is instrumented again'

# Command line: both flags, ordering, and an unknown flag.
with tempfile.TemporaryDirectory() as tmp:
    src, dst = Path(tmp) / 'a.o.darwin.s', Path(tmp) / 'a.o.s'
    src.write_text('\t.text\n_foo:\n\tldr w0, [x0, #4]\n\tret\n')
    run = subprocess.run([sys.executable, str(root / 'tools/android_asm_convert.py'),
                          '--ios-arena-fastpath', str(src), str(dst)], capture_output=True, text=True)
    assert run.returncode == 0, run.stderr
    assert 'ldr w0, [x15, #4]' in dst.read_text()
    run = subprocess.run([sys.executable, str(root / 'tools/android_asm_convert.py'), str(src), str(dst)],
                         capture_output=True, text=True)
    assert run.returncode == 0 and 'x15' not in dst.read_text()
    run = subprocess.run([sys.executable, str(root / 'tools/android_asm_convert.py'), '--bogus', str(src), str(dst)],
                         capture_output=True, text=True)
    assert run.returncode == 2

print(f'PASS: {checks} instruction forms checked for address, writeback and register preservation; skip rules, blr, jump tables, CLI')
