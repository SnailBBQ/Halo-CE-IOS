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
(scratch/'port/android/guest').mkdir(parents=True)
(scratch/'port/android/guest/guest.ld').write_text((r/'port/android/guest/guest.ld').read_text())
for text in [generated,generated.replace('\n','\r\n')]:
    for mode in ['true','false']:
        (scratch/'build.ninja').write_bytes((text+'\n-DHALO_ANDROID=1\n--target=arm64_32-apple-watchos\nld.lld -m aarch64linux -static -T port/android/guest/guest.ld\ntools/android_gl_stubs.py\n').encode())
        subprocess.run([sys.executable,'-c',body],cwd=scratch,check=True,env={**os.environ,'ARENA_FASTPATH':mode,'NON_JAILBREAK':'false','COMPATIBILITY_TEST':'false'})
        patched=(scratch/'build.ninja').read_text()
        assert '--ios-pointer-fastpath' not in patched
        assert '--wrap=memcpy --wrap=memmove --wrap=memset' in patched
        assert '-DHALO_ANDROID=1 -DHALO_IOS_GUEST=1' in patched
        assert '$\n' not in patched
        assert '-T build/ios_guest.ld' in patched and 'port/android/guest/guest.ld' not in patched
        assert '. = 0x90000000;' in (scratch/'build/ios_guest.ld').read_text()
        if mode=='true':
            assert 'tools/android_asm_convert.py --ios-arena-fastpath $out.darwin.s $out.s' in patched
            assert '--target=arm64_32-apple-watchos -ffixed-x15' in patched
        else:
            assert 'tools/android_asm_convert.py $out.darwin.s $out.s' in patched
            assert '--ios-arena-fastpath' not in patched and 'ffixed-x15' not in patched
# the default (variable unset) must also enable the rewrite
env={k:v for k,v in os.environ.items() if k not in ('ARENA_FASTPATH','NON_JAILBREAK','COMPATIBILITY_TEST')}
env.update({'NON_JAILBREAK':'false','COMPATIBILITY_TEST':'false'})
(scratch/'build.ninja').write_bytes((generated+'\n-DHALO_ANDROID=1\n--target=arm64_32-apple-watchos\nld.lld -m aarch64linux -static -T port/android/guest/guest.ld\ntools/android_gl_stubs.py\n').encode())
subprocess.run([sys.executable,'-c',body],cwd=scratch,check=True,env=env)
assert '--ios-arena-fastpath' in (scratch/'build.ninja').read_text()
# Non-Jailbreak Stage 3 gets a distinct guest ABI: x15 scratch + x27 arena base,
# flexible-base converter, and an explicit HALO_IOS_FLEX_BASE define.
(scratch/'build.ninja').write_bytes((generated+'\n-DHALO_ANDROID=1\n--target=arm64_32-apple-watchos\nld.lld -m aarch64linux -static -T port/android/guest/guest.ld\ntools/android_gl_stubs.py\n').encode())
nonjb_result=subprocess.run([sys.executable,'-c',body],cwd=scratch,capture_output=True,text=True,
                            env={**os.environ,'ARENA_FASTPATH':'true','NON_JAILBREAK':'true','COMPATIBILITY_TEST':'false'})
if nonjb_result.returncode:
    # Some local clang builds lack LLVM's compressed-jump-table switch. The
    # production transformation must reject that compiler for Stage 3; CI's
    # supported clang continues through the full output assertions below.
    assert 'Non-Jailbreak Stage 3 requires compressed jump tables to be disabled' in nonjb_result.stderr, nonjb_result.stderr
else:
    nonjb=(scratch/'build.ninja').read_text()
    assert '-DHALO_IOS_GUEST=1 -DHALO_IOS_FLEX_BASE=1' in nonjb
    assert 'tools/android_asm_convert.py --ios-flex-base-fastpath $out.darwin.s $out.s' in nonjb
    assert '--target=arm64_32-apple-watchos -ffixed-x15 -ffixed-x27' in nonjb
    assert '-aarch64-enable-compress-jump-tables=false' in nonjb
    assert '--ios-arena-fastpath' not in nonjb
# Stage 3 is correctness-critical and must not build with the rewrite disabled.
(scratch/'build.ninja').write_bytes((generated+'\n-DHALO_ANDROID=1\n--target=arm64_32-apple-watchos\nld.lld -m aarch64linux -static -T port/android/guest/guest.ld\ntools/android_gl_stubs.py\n').encode())
assert subprocess.run([sys.executable,'-c',body],cwd=scratch,
    env={**os.environ,'ARENA_FASTPATH':'false','NON_JAILBREAK':'true','COMPATIBILITY_TEST':'false'},
    capture_output=True).returncode!=0
# an unrecognised guest target must fail loudly instead of silently dropping -ffixed-x15
(scratch/'build.ninja').write_bytes((generated+'\n-DHALO_ANDROID=1\nld.lld -m aarch64linux -static -T port/android/guest/guest.ld\ntools/android_gl_stubs.py\n').encode())
assert subprocess.run([sys.executable,'-c',body],cwd=scratch,env=env,capture_output=True).returncode!=0
print('PASS: real android_guest_cc command emitted by repository Ninja writer, LF/CRLF continuation matching and full workflow transformation (regular aligned and Non-JB flexible-base guest ABIs)')

# Keep IPA builds manual so pushes cannot spend hosted macOS minutes.
assert "  workflow_dispatch:" in wf
assert "\n  push:" not in wf, 'the iOS IPA workflow must not start automatically on pushes'
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
assert wf.count('-DHALO_NON_JAILBREAK=1') == 3 and "if [ \"$NON_JAILBREAK\" = true ]; then" in wf
guest_job=wf.split('  build-arm64_32-guest:',1)[1].split('\n  build-ios-app:',1)[0]
app_job=wf.split('  build-ios-app:',1)[1]
assert 'halo-flex-runtime.o' in guest_job and 'halo-flex-runtime-ios.o' not in guest_job, 'Ubuntu keeps only the portable Stage-2 compile'
assert 'xcrun --sdk iphoneos' not in guest_job, 'Ubuntu guest job must never require the Apple toolchain'
assert 'Verify Non-JB iPhoneOS runtime dependencies' in app_job and 'halo-flex-runtime-ios.o' in app_job and 'xcrun --sdk iphoneos' in app_job, 'real iPhoneOS preflight belongs in macOS app job'
assert app_job.index('Verify Non-JB iPhoneOS runtime dependencies') < app_job.index('- name: Build device host app')
assert "sidestore:" not in wf and "com.haloceuniversal.ios.sidestore" not in wf and "HaloCE-iOS-Sidestore" not in wf
assert "ios_signed_guest" not in wf and "HALO_SIGNED_GUEST" not in wf and "SIGNED GUEST" not in wf and "HaloIOS-NonJailbreak.entitlements" in wf and "--require-absent-memory" in wf
assert "elif [ \"$NON_JAILBREAK\" = true ]; then\n            HOST_FLAGS=('OTHER_CFLAGS=$(inherited) -DHALO_NON_JAILBREAK=1')" in wf, 'the Non-Jailbreak flag links nothing into the app'
assert wf.count('uses: actions/checkout@v4') == 2 and 'ref:' not in wf, 'every iOS build uses the commit you started, not another branch'
identity=wf.split("if [ \"$COMPATIBILITY_TEST\" = true ]; then\n            /usr/libexec/PlistBuddy",1)[1].split('\n          fi',1)[0]
assert 'NON_JAILBREAK' not in identity and 'com.haloceuniversal.ios.modtest' in identity, 'only Mod Test changes the bundle identifier'
assert '-DHALO_MOD_TEST=1' in wf and '-DHALO_ALIGNED_ARENA_TEST=1 -DHALO_MOD_TEST=1' in wf
assert wf.index('Reject conflicting build flavors') < wf.index('- name: Install Ninja') and 'not both' in wf
assert "inputs.non_jailbreak && 'HaloCE-iOS-NonJailbreak' || inputs.compatibility_test && 'HaloCE-iOS-ModTest' || 'HaloCE-iOS'" in wf
assert "python3 tools/ios_upstream_acceptance.py --json" in wf, 'every candidate runs the reusable upstream acceptance gates'
assert "Set :HaloBuildFlavor $FLAVOR" in wf and "Set :HaloGuestSHA256 $GUEST_SHA" in wf and "Set :HaloSourceCommit ${GITHUB_SHA:-local}" in wf
assert "DIAGNOSTICS=flex-base-stage3-real-guest+exec-trace-v3" in wf and "DIAGNOSTICS=direct-aligned-arena-test" in wf
assert "GUEST_ARCHITECTURE=flexible-base-x27-v1" in wf and "GUEST_ADAPTATION=ios-flex-x27-v1" in wf
assert "Set :HaloGuestArchitecture $GUEST_ARCHITECTURE" in wf and "Set :HaloGuestAdaptation $GUEST_ADAPTATION" in wf
assert "Address-space probe (nothing stays reserved)" in wf and "Flexible 4 GiB ANYWHERE:" in wf and "NON-JB EXECUTION TRACE:" in wf and "NON-JB FLEX STAGE 3:" in wf and "HALO_IOS_FLEX_BASE_GUEST_V1" in wf and "-e 'Flexible 4 GiB ANYWHERE:'" in wf
assert 'va_plan' in memory and 'va_map' in memory and 'test_ios_non_jailbreak_flag.py' in memory and 'test_ios_mod_test_flag.py' in memory and 'test_ios_asset_integrity.py' in memory and 'test_ios_checkpoint_size.py' in memory and 'test_ios_mod_cache_policy.c' in memory
assert memory.index('          done\n          cc -std=c11 -Wall -Wextra -Werror tools/tests/test_ios_mod_cache_policy.c') > memory.index('for t in settings_core'), 'mod-cache policy test must run once, after the generated-test loop'
# Mod Test: its version follows the official one, and its code is proved absent from every other build.
assert "Set :CFBundleShortVersionString ${OFFICIAL_SHORT}.1" in wf and "Set :CFBundleVersion ${OFFICIAL_BUILD}01" in wf and '0.2.70.1' not in wf and '267001' not in wf
assert "elif grep -q -e 'MOD TEST:'" in wf and "'Mod Test build:'" in wf
assert "Mod Test app: " in wf and "Non-Jailbreak Version: " in wf and "Pointer rewrite (recommended)" in wf
print('PASS: main-only automatic IPA, diagnostics dependency, per-flavor cancellation, no native-port workflow, no profile-guided option, and Mod Test and Non-Jailbreak flavors that cannot touch an ordinary run')
