"""Structure check for every C file that has HALO_IOS_GUEST blocks.

The guest is compiled with HALO_IOS_GUEST defined, the Linux/Windows/Android builds without it. A merge
that leaves a `}` or `#endif` on the wrong side of an iOS block breaks one of the two and nothing but the
real compile (minutes into CI) notices. This reads each file as the compiler would, in both views, and
fails when the iOS view is not structured like the plain view:

  * the brace depth at the end of the file is the same in both views, and
  * no function-style opening brace (a `{` alone at column 0) sits inside another block in the iOS view
    when it does not in the plain view.

Run: python tools/tests/test_ios_source_structure.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCAN = ("source", "port/linux", "port/android/guest", "port/include")


def view(text, ios):
    out, stack = [], []

    def live():
        return not any(kind == "ios" and in_else == ios for kind, in_else in stack)

    for line in text.split("\n"):
        s = line.strip()
        m = re.match(r"#\s*(ifdef|ifndef)\s+HALO_IOS_GUEST\b", s)
        if m:
            stack.append(["ios", m.group(1) == "ifndef"])
            continue
        if re.match(r"#\s*(if|ifdef|ifndef)\b", s):
            if live():
                out.append(line)
            stack.append(["other", False])
            continue
        if re.match(r"#\s*else\b", s):
            if stack and stack[-1][0] == "ios":
                stack[-1][1] = not stack[-1][1]
                continue
            if live():
                out.append(line)
            continue
        if re.match(r"#\s*endif\b", s):
            if not stack:
                raise ValueError("#endif without #if")
            top = stack.pop()
            if top[0] == "ios":
                continue
            if live():
                out.append(line)
            continue
        if live():
            out.append(line)
    if stack:
        raise ValueError("unterminated #if")
    return out


def depths(lines):
    depth, rows, cond, in_block = 0, [], [], False
    for number, line in enumerate(lines, 1):
        rows.append((number, depth, line))
        s = line.strip()
        if not in_block and s.startswith("#"):
            if re.match(r"#\s*(if|ifdef|ifndef)\b", s):
                cond.append([depth, None])
                continue
            if re.match(r"#\s*(else|elif)\b", s):
                if cond:
                    if cond[-1][1] is None:
                        cond[-1][1] = depth
                    depth = cond[-1][0]
                continue
            if re.match(r"#\s*endif\b", s):
                if cond:
                    top = cond.pop()
                    if top[1] is not None:
                        depth = top[1]
                continue
        i, n = 0, len(line)
        while i < n:
            c = line[i]
            if in_block:
                j = line.find("*/", i)
                if j < 0:
                    i = n
                else:
                    in_block, i = False, j + 2
                continue
            if line.startswith("/*", i):
                in_block, i = True, i + 2
                continue
            if line.startswith("//", i):
                break
            if c in "\"'":
                q = c
                i += 1
                while i < n and line[i] != q:
                    i += 2 if line[i] == "\\" else 1
                i += 1
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
    return rows, depth


def analyse(text):
    result = {}
    for ios in (True, False):
        rows, final = depths(view(text, ios))
        result[ios] = (final, {line for _, d, line in rows if line == "{" and d != 0}, [n for n, d, _ in rows if d < 0][:1])
    return result


def main():
    failures, checked = [], 0
    for base in SCAN:
        for path in sorted((ROOT / base).rglob("*")):
            if path.suffix not in (".c", ".h") or not path.is_file():
                continue
            text = path.read_text(encoding="utf-8", errors="surrogateescape")
            if "HALO_IOS_GUEST" not in text:
                continue
            checked += 1
            rel = path.relative_to(ROOT).as_posix()
            try:
                r = analyse(text)
            except ValueError as error:
                failures.append(f"{rel}: {error}")
                continue
            (fi, bad_i, neg_i), (fp, bad_p, neg_p) = r[True], r[False]
            if fi != fp:
                failures.append(f"{rel}: brace depth at the end is {fi} with HALO_IOS_GUEST and {fp} without")
            if bad_i - bad_p:
                failures.append(f"{rel}: a function-style '{{' sits inside another block only in the iOS view")
            if neg_i and not neg_p:
                failures.append(f"{rel}: a '}}' closes more than was opened (line {neg_i[0]} of the iOS view)")
    if failures:
        print("\n".join(failures))
        sys.exit(1)
    print(f"PASS: {checked} files with HALO_IOS_GUEST blocks have the same structure with and without it")


if __name__ == "__main__":
    main()
