from pathlib import Path
import ast,importlib.util,io,subprocess,sys,tempfile
r=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('ninja_syntax',r/'tools/ninja_syntax.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
tree=ast.parse((r/'tools/android_build.py').read_text(encoding='utf-8'))
call=next(n for n in ast.walk(tree) if isinstance(n,ast.Call) and any(k.arg=='name' and isinstance(k.value,ast.Constant) and k.value.value=='android_guest_cc' for k in n.keywords))
command=next(k.value for k in call.keywords if k.arg=='command')
cmd=eval(compile(ast.Expression(command),'actual build rule','eval'),{'compile_launcher':lambda _: '', 'sln':None,'python':'/usr/bin/python3'})
out=io.StringIO();w=m.Writer(out);w.rule('android_guest_cc',command=cmd)
generated=out.getvalue()
assert 'tools/android_asm_convert.py $out.darwin.s $out.s' not in generated,generated
assert '$\n' in generated
wf=(r/'.github/workflows/ios.yml').read_text(encoding='utf-8')
body=wf.split("python3 - <<'PY'\n",1)[1].split('\n          PY',1)[0]
body='\n'.join(line[10:] for line in body.splitlines())
temporary=tempfile.TemporaryDirectory();scratch=Path(temporary.name)
for text in [generated,generated.replace('\n','\r\n')]:
    (scratch/'build.ninja').write_bytes((text+'\n-DHALO_ANDROID=1\nld.lld -m aarch64linux -static\ntools/android_gl_stubs.py\n').encode())
    subprocess.run([sys.executable,'-c',body],cwd=scratch,check=True)
    patched=(scratch/'build.ninja').read_text()
    assert 'tools/android_asm_convert.py --ios-pointer-fastpath $out.darwin.s $out.s' in patched
    assert '--ios-pointer-fastpath' in patched
    assert '--wrap=memcpy --wrap=memmove --wrap=memset' in patched
    assert '-DHALO_ANDROID=1 -DHALO_IOS_GUEST=1' in patched
    assert '$\n' not in patched
print('PASS: real android_guest_cc command emitted by repository Ninja writer, LF/CRLF continuation matching and full workflow transformation')
