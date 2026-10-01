"""Verify iOS direct pointer conversion with assembled ARM64 instructions.

Run: python tools/tests/test_ios_pointer_fastpath.py
Requires unicorn==2.1.4 and keystone-engine==0.9.2 (CI uses a temporary venv).
"""
import sys, importlib.util, random, struct
from pathlib import Path
from keystone import Ks, KS_ARCH_ARM64, KS_MODE_LITTLE_ENDIAN
from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM, UcError
from unicorn.arm64_const import *
p=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('converter',p/'tools/android_asm_convert.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.print=lambda *args,**kwargs:None
ks=Ks(KS_ARCH_ARM64,KS_MODE_LITTLE_ENDIAN)
arena=0x400000000;code=arena+0x88000000;slot=code+0x1080;stack=arena+0xed001000
regs=[globals()[f'UC_ARM64_REG_X{i}'] for i in range(29)]+[UC_ARM64_REG_FP,UC_ARM64_REG_LR]
path='build/android/guest/obj/port/linux/src/d3d8_gl.o.darwin.s'
def assemble(s):
    s=s.replace('halo_ios_arena_base',hex(slot & ~0xfff)).replace(':lo12:'+hex(slot & ~0xfff),'#128')
    return bytes(ks.asm(s,addr=code)[0])
def run(binary, values, nzcv, memory, target, expect_fault=False):
    u=Uc(UC_ARCH_ARM64,UC_MODE_ARM)
    for address in [code,stack-0x1000,target & ~0xfff]:u.mem_map(address,0x2000)
    u.mem_write(code,binary);u.mem_write(slot,struct.pack('<Q',arena))
    u.mem_write(stack-128,b'R'*128);u.mem_write(target & ~0xfff,memory)
    for r,v in zip(regs,values):u.reg_write(r,v)
    for i in range(32):u.reg_write(globals()[f'UC_ARM64_REG_Q{i}'],(0x1020304050607080+i)<<64|i)
    u.reg_write(UC_ARM64_REG_SP,stack);u.reg_write(UC_ARM64_REG_NZCV,nzcv)
    fault=False
    try:u.emu_start(code,code+len(binary),count=100)
    except UcError:fault=True
    assert fault==expect_fault,(fault,expect_fault)
    assert u.reg_read(UC_ARM64_REG_SP)==stack
    assert bytes(u.mem_read(stack-128,128))==b'R'*128,'Darwin leaf red zone corrupted'
    return ([u.reg_read(r) for r in regs],[u.reg_read(globals()[f'UC_ARM64_REG_Q{i}']) for i in range(32)],u.reg_read(UC_ARM64_REG_NZCV),bytes(u.mem_read(target & ~0xfff,4096)))
random.seed(2620);checks=0
for rn in range(31):
    instructions=[f'ldr w0, [x{rn}, #12]',f'str w1, [x{rn}, #12]',f'ldr x16, [x{rn}, #8]',f'str x17, [x{rn}, #8]',f'ldr q0, [x{rn}, #16]',f'str q0, [x{rn}, #16]',f'ldursw x0, [x{rn}, #-4]']
    if rn not in [0,1,16,17]:
        instructions += [f'ldp x16, x17, [x{rn}, #16]', f'stp x16, x17, [x{rn}, #-16]',f'ldr w0, [x{rn}], #8', f'str w1, [x{rn}, #8]!']
    if rn != 2:
        instructions += [f'ldr w0, [x{rn}, x2]',f'str w1, [x{rn}, w2, uxtw #2]']
    for instruction in instructions:
        fast=m.ios_pointer_fastpath(instruction+'\n',path);binary=assemble(fast);original=assemble(instruction)
        for kind in ['guest','arena','native','null']:
            target=arena+0x90000100 if kind!='native' else 0x600001100
            values=[random.getrandbits(64) for _ in regs]
            if rn != 2:values[2]=4
            values[rn]=0 if kind=='null' else (target & 0xffffffff if kind=='guest' else target)
            reference=values.copy()
            if kind=='guest':reference[rn]+=arena
            memory=random.randbytes(4096);flags=random.randrange(16)<<28
            assert run(binary,values,flags,memory,target,kind=='null')==run(original,reference,flags,memory,target,kind=='null'),(rn,instruction,kind)
            checks+=1
# Nonselected objects, SP operands, literal loads, atomics and Android output.
for path2 in ['source/math/geometry.o.darwin.s','port/android/guest/runtime/guest_start.o.darwin.s']:
    assert m.ios_pointer_fastpath('ldr w0, [x1]\n',path2)=='ldr w0, [x1]\n'
assert m.ios_pointer_fastpath('ldr w0, [sp, #16]\n',path)=='ldr w0, [sp, #16]\n'
try:m.ios_pointer_fastpath('ldxr x0, [x1]\nstxr w2, x0, [x1]\n',path)
except m.ConvertError:pass
else:raise AssertionError('exclusive sequences must fail closed')
assert m.Converter(['.text','_test:','ldr w0, [x1]','ret']).run()=='\t.text\ntest:\n\tldr w0, [x1]\n\tret\n'
print(f'PASS: {checks} actual AArch64 emulations; registers, NZCV, red zone, wide/null bases, stores and writeback preserved')
