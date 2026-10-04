"""The OpenGL timing wrappers in halo_ios_gl_host.m must change nothing but the counters. This extracts the real wrapper block,
compiles it against stub GL types and fake GL functions, and checks that every wrapper forwards every argument unchanged, is
counted, is only returned by the resolver when the real function exists, and that the runner reports every category."""
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "port/ios/HaloIOS/halo_ios_gl_host.m"
RUNNER = ROOT / "port/ios/HaloIOS/halo_guest_runner.m"


def balanced(text, start):
    """text[start] == '(' -> index just past the matching ')'."""
    depth = 0
    for index in range(start, len(text)):
        depth += text[index] == "("
        depth -= text[index] == ")"
        if depth == 0:
            return index + 1
    raise ValueError("unbalanced")


def split_top(text):
    parts, depth, current = [], 0, ""
    for char in text:
        if char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
            continue
        depth += char == "("
        depth -= char == ")"
        current += char
    if current.strip():
        parts.append(current.strip())
    return parts


def wrapped_functions(source):
    found = []
    for match in re.finditer(r"^HALO_TIMED_GL\(", source, re.M):
        end = balanced(source, match.end() - 1)
        category, name, params, args = split_top(source[match.end():end - 1])
        params, args = params[1:-1].strip(), args[1:-1].strip()
        declarations = [] if params in ("", "void") else split_top(params)
        names = [re.search(r"(\w+)$", d).group(1) for d in declarations]
        found.append({"category": category, "name": name, "params": params, "declarations": declarations,
                      "param_names": names, "arg_names": [a for a in (x.strip() for x in args.split(",")) if a]})
    return found


class GlTimingWrapperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = HOST.read_text(encoding="utf-8").replace("\r\n", "\n")
        cls.functions = wrapped_functions(cls.source)

    def test_wrappers_pass_their_parameters_through_in_order(self):
        self.assertGreaterEqual(len(self.functions), 16)
        names = [f["name"] for f in self.functions]
        self.assertEqual(len(names), len(set(names)), "a GL function is wrapped twice")
        for f in self.functions:
            self.assertEqual(f["param_names"], f["arg_names"], f["name"] + " must forward exactly its own parameters, in order")
            self.assertRegex(f["category"], r"^HALO_GLW_(DRAW|BUFFER|TEXTURE|PROGRAM|FLUSH|READBACK|QUERY|CLEAR|FENCE)$")

    def test_every_wrapper_is_resolved_and_nothing_else_is(self):
        resolved = re.findall(r"^    HALO_RESOLVE_TIMED\((\w+)\)$", self.source, re.M)
        self.assertEqual(sorted(resolved), sorted(f["name"] for f in self.functions))
        # the custom wrappers that already existed keep priority
        resolver = self.source[self.source.index("void *halo_ios_gl_resolve_import"):]
        self.assertLess(resolver.index('"glBlitFramebuffer"'), resolver.index("HALO_RESOLVE_TIMED(glDrawElements)"))
        self.assertLess(resolver.index("HALO_RESOLVE_TIMED(glClear)"), resolver.index("void *function = dlsym(RTLD_DEFAULT, name);"))

    def test_the_fence_wait_is_timed_and_still_waits(self):
        wait = self.source[self.source.index("void halo_ios_gl_wait_frame"):]
        begin, call, end = (wait.index(t) for t in ("halo_gl_wait_begin(&g_gl_wait", "glClientWaitSync(g_frame_fences[slot]", "halo_gl_wait_end(&g_gl_wait, wait_timer"))
        self.assertLess(begin, call)
        self.assertLess(call, end)
        self.assertIn("1000000000ull", wait[call:end])
        self.assertIn("GL_SYNC_FLUSH_COMMANDS_BIT", wait[call:end])

    def test_runner_reports_every_category_and_names_the_map(self):
        runner = RUNNER.read_text(encoding="utf-8").replace("\r\n", "\n")
        self.assertIn("for(int c=0;c<HALO_GLW_COUNT;c++)", runner)
        self.assertLess(runner.index("static void ios_report_gl_waits(void)"), runner.index("ios_report_gl_waits();"))
        self.assertLess(runner.index("static void ios_note_opened_path"), runner.index("ios_note_opened_path(path);"))
        self.assertLess(runner.index("static int ios_last_map_copy"), runner.index("else if(ios_last_map_copy(frame->map"))
        self.assertIn("map source=%s", runner)
        openat = runner[runner.index("case 56: /* openat */"):]
        self.assertLess(openat.index("open(path, flags"), openat.index("ios_note_opened_path(path)"))
        self.assertLess(openat.index("ios_note_opened_path(path)"), openat.index("return fd < 0"))

    def test_actual_wrapper_block_forwards_every_argument(self):
        block = self.source[self.source.index("/* Timing wrappers (telemetry only)."):self.source.index("static uint64_t halo_gl_unavailable(void)")]
        fakes, checks, resolves = [], [], []
        for index, f in enumerate(self.functions):
            values = []
            for position, declaration in enumerate(f["declarations"]):
                values.append(f"(uintptr_t)0x{0x1000 + index * 16 + position:x}ull" if "*" in declaration else f"{index * 16 + position + 1}")
            record = "".join(f"    recorded[{p}] = (unsigned long long)(uintptr_t){n};\n" for p, n in enumerate(f["param_names"]))
            fakes.append(f"static void fake_{f['name']}({f['params'] or 'void'})\n{{\n    recorded_calls++;\n    memset(recorded, 0, sizeof(recorded));\n{record}}}\n")
            call_args = ", ".join(f"({d.rsplit(None, 1)[0] if '*' not in d else d.rsplit('*', 1)[0].strip() + ' *'}){v}" for d, v in zip(f["declarations"], values))
            expected = ", ".join(f"(unsigned long long)(uintptr_t)({v})" for v in values)
            cast = f"void (*)({f['params'] or 'void'})"
            checks.append(f"""    resolved = resolve("{f['name']}");
    if (resolved != (void *)halo_timed_{f['name']}) {{ printf("resolver did not return the wrapper for {f['name']}\\n"); return 1; }}
    recorded_calls = 0;
    (({cast})resolved)({call_args});
    {{
        unsigned long long want[] = {{ {expected + ', ' if values else ''}0 }};
        for (unsigned i = 0; i < {len(values)}; i++)
            if (recorded[i] != want[i]) {{ printf("{f['name']}: argument %u changed (%llx != %llx)\\n", i, recorded[i], want[i]); return 1; }}
        if (recorded_calls != 1) {{ printf("{f['name']}: real function called %u times\\n", recorded_calls); return 1; }}
    }}
""")
            resolves.append(f"    HALO_RESOLVE_TIMED({f['name']})\n")
        shims = "".join(f'    if (!strcmp(n, "{f["name"]}")) return (void *)fake_{f["name"]};\n' for f in self.functions)
        harness = f"""
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef unsigned int GLenum; typedef int GLint; typedef int GLsizei; typedef long GLsizeiptr; typedef long GLintptr;
typedef unsigned int GLuint; typedef unsigned int GLbitfield;
#include "halo_gl_wait_stats.h"
#include <time.h>
#define CLOCK_UPTIME_RAW CLOCK_MONOTONIC
static unsigned long long clock_gettime_nsec_np(int which) {{ struct timespec t; clock_gettime((clockid_t)which, &t); return (unsigned long long)t.tv_sec * 1000000000ull + (unsigned long long)t.tv_nsec; }}
#define RTLD_DEFAULT ((void *)0)
static int hide_flush;
static unsigned long long recorded[16]; static unsigned recorded_calls;
{''.join(fakes)}
static void *dlsym(void *handle, const char *n)
{{
    (void)handle;
    if (hide_flush && !strcmp(n, "glFlush")) return NULL;
{shims}    return NULL;
}}
{block}
static void *resolve(const char *name)
{{
{''.join(resolves)}    return NULL;
}}
int main(void)
{{
    void *resolved;
    HaloGlWaitSnapshot snapshot;
{''.join(checks)}
    halo_gl_wait_take(&g_gl_wait, &snapshot);
    {{
        unsigned long long total = 0;
        for (int c = 0; c < HALO_GLW_COUNT; c++) total += snapshot.calls[c];
        if (total != {len(self.functions)}) {{ printf("expected {len(self.functions)} counted calls, got %llu\\n", total); return 1; }}
    }}
    if (snapshot.calls[HALO_GLW_DRAW] != 2 || snapshot.calls[HALO_GLW_FLUSH] != 2 || snapshot.calls[HALO_GLW_TEXTURE] != 5 || snapshot.calls[HALO_GLW_PROGRAM] != 2) {{ printf("category counts are wrong\\n"); return 1; }}
    hide_flush = 1;
    if (resolve("glFlush") != NULL) {{ printf("the wrapper was returned although the real function is missing\\n"); return 1; }}
    if (resolve("glNotWrapped") != NULL) {{ printf("an unlisted function was resolved\\n"); return 1; }}
    puts("ok");
    return 0;
}}
"""
        with tempfile.TemporaryDirectory() as folder:
            source_path, exe = Path(folder) / "harness.c", Path(folder) / ("harness.exe" if os.name == "nt" else "harness")
            source_path.write_text(harness, encoding="utf-8")
            built = subprocess.run([os.environ.get("CC", "cc"), "-std=gnu11", "-Wall", "-Wextra", "-Wno-misleading-indentation", "-I" + str(ROOT / "port/ios/HaloIOS"), str(source_path), "-o", str(exe)],
                                   capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr[-3000:])
            ran = subprocess.run([str(exe)], capture_output=True, text=True)
            self.assertEqual((ran.returncode, ran.stdout.strip()), (0, "ok"), ran.stdout + ran.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=0)
