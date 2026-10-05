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
assert '--ios-pointer-fastpath' not in wf, 'shipping workflow must not activate pointer rewriting'
body=wf.split("python3 - <<'PY'\n",1)[1].split('\n          PY',1)[0]
body='\n'.join(line[10:] for line in body.splitlines())
temporary=tempfile.TemporaryDirectory();scratch=Path(temporary.name)
import os
for text in [generated,generated.replace('\n','\r\n')]:
    for mode in ['true','false']:
        (scratch/'build.ninja').write_bytes((text+'\n-DHALO_ANDROID=1\n--target=arm64_32-apple-watchos\nld.lld -m aarch64linux -static\ntools/android_gl_stubs.py\n').encode())
        subprocess.run([sys.executable,'-c',body],cwd=scratch,check=True,env={**os.environ,'ARENA_FASTPATH':mode})
        patched=(scratch/'build.ninja').read_text()
        assert '--ios-pointer-fastpath' not in patched
        assert '--wrap=memcpy --wrap=memmove --wrap=memset' in patched
        assert '-DHALO_ANDROID=1 -DHALO_IOS_GUEST=1' in patched
        assert '$\n' not in patched
        if mode=='true':
            assert 'tools/android_asm_convert.py --ios-arena-fastpath $out.darwin.s $out.s' in patched
            assert '--target=arm64_32-apple-watchos -ffixed-x15' in patched
        else:
            assert 'tools/android_asm_convert.py $out.darwin.s $out.s' in patched
            assert '--ios-arena-fastpath' not in patched and 'ffixed-x15' not in patched
# the default (variable unset) must also enable the rewrite
env={k:v for k,v in os.environ.items() if k!='ARENA_FASTPATH'}
(scratch/'build.ninja').write_bytes((generated+'\n-DHALO_ANDROID=1\n--target=arm64_32-apple-watchos\nld.lld -m aarch64linux -static\ntools/android_gl_stubs.py\n').encode())
subprocess.run([sys.executable,'-c',body],cwd=scratch,check=True,env=env)
assert '--ios-arena-fastpath' in (scratch/'build.ninja').read_text()
# an unrecognised guest target must fail loudly instead of silently dropping -ffixed-x15
(scratch/'build.ninja').write_bytes((generated+'\n-DHALO_ANDROID=1\nld.lld -m aarch64linux -static\ntools/android_gl_stubs.py\n').encode())
assert subprocess.run([sys.executable,'-c',body],cwd=scratch,env=env,capture_output=True).returncode!=0
print('PASS: real android_guest_cc command emitted by repository Ninja writer, LF/CRLF continuation matching and full workflow transformation (arena fast path on/off/default/missing target)')

# Only regular-app main pushes may spend hosted build time. Keep expensive
# jobs behind diagnostics and cancel obsolete builds on replacement pushes.
assert "  push:\n    branches: [main]\n    paths:" in wf
assert "  group: halo-ios-${{ inputs.non_jailbreak && 'non-jailbreak' || inputs.compatibility_test && 'modtest' || 'main' }}\n  cancel-in-progress: true" in wf, 'official pushes must keep the halo-ios-main group; manual flavors get their own'
assert "    needs: diagnostics" in wf
assert "    uses: ./.github/workflows/ios-memory-tests.yml" in wf
assert wf.count("if: github.ref == 'refs/heads/main'") == 3
assert 'pull_request:' not in wf and 'schedule:' not in wf
memory=(r/'.github/workflows/ios-memory-tests.yml').read_text()
assert '  workflow_call:' in memory and '  push:' not in memory
assert "if: github.ref == 'refs/heads/main'" in memory
assert not (r/'.github/workflows/build.yml').exists(), 'this fork does not build the Linux, Windows or Android ports'
assert 'guest_pgo' not in wf and 'ios/modtest' not in wf and '--pgo=off' in wf
assert 'gh release' not in wf and 'gh release' not in memory
# The Non-Jailbreak build is a manual flag on the official app. It never changes an ordinary run.
assert "      non_jailbreak:\n        description:" in wf and "        type: boolean\n        default: false\n      arena_fastpath:" in wf
assert wf.count('-DHALO_NON_JAILBREAK=1') == 1 and "if [ \"$NON_JAILBREAK\" = true ]; then" in wf
assert "sidestore:" not in wf and "com.haloceuniversal.ios.sidestore" not in wf and "HaloCE-iOS-Sidestore" not in wf
assert "tools/ios_signed_guest.py" in wf and "HaloIOS-NonJailbreak.entitlements" in wf and "--require-absent-memory" in wf
assert wf.count('uses: actions/checkout@v4') == 2 and 'ref:' not in wf, 'every iOS build uses the commit you started, not another branch'
identity=wf.split("if [ \"$COMPATIBILITY_TEST\" = true ]; then\n            /usr/libexec/PlistBuddy",1)[1].split('\n          fi',1)[0]
assert 'NON_JAILBREAK' not in identity and 'com.haloceuniversal.ios.modtest' in identity, 'only Mod Test changes the bundle identifier'
assert '-DHALO_MOD_TEST=1' in wf and '-DHALO_ALIGNED_ARENA_TEST=1 -DHALO_MOD_TEST=1' in wf
assert wf.index('Reject conflicting build flavors') < wf.index('- name: Install Ninja') and 'not both' in wf
assert "inputs.non_jailbreak && 'HaloCE-iOS-NonJailbreak' || inputs.compatibility_test && 'HaloCE-iOS-ModTest' || 'HaloCE-iOS'" in wf
assert "Address-space probe (nothing stays reserved)" in wf and "elif grep -q -e 'Non-Jailbreak Version (' -e 'Address-space probe (nothing stays reserved)' -e 'SIGNED GUEST:'" in wf
assert 'va_plan' in memory and 'test_ios_non_jailbreak_flag.py' in memory and 'test_ios_mod_cache_policy.c' in memory
print('PASS: main-only automatic IPA, diagnostics dependency, per-flavor cancellation, no native-port workflow, no profile-guided option, and Mod Test and Non-Jailbreak flavors that cannot touch an ordinary run')
