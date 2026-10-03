"""A function defined in one iOS host file and called from another must be declared in a header the caller actually includes
(directly or through other local headers). The device build has no implicit declarations (Xcode's compiler makes them errors), and
an `extern` line that exists only in a test branch does not count: the CI test build uses it, the device build does not.

Reads every .m and .c file in port/ios/HaloIOS. For each, the declarations it can see are the prototypes and `extern` lines in the
headers it reaches by #import / #include "..." (recursively, local files only), those in the file itself, with the HALO_SETTINGS_TEST
branch of a file removed (the device build is the one that must compile). Fails on a call to a project function nothing in
view declares. Run: python tools/tests/test_ios_header_declarations.py
"""
import re
import sys
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parents[2] / "port" / "ios" / "HaloIOS"
KEYWORDS = {"if", "for", "while", "switch", "return", "sizeof", "defined", "else", "do", "case"}


def clean(source):
    def blank(m):
        return re.sub(r"[^\n]", " ", m.group(0))

    text = re.sub(r"/\*.*?\*/", blank, source, flags=re.S)
    text = re.sub(r"//[^\n]*", blank, text)
    return re.sub(r'@?"(?:\\.|[^"\\\n])*"', lambda m: '""' if not m.group(0).startswith("@") else '@""', text)


def device_view(source):
    """The file as the device build sees it: the HALO_SETTINGS_TEST branch (up to #else) is removed."""
    match = re.search(r"#ifdef HALO_SETTINGS_TEST\n", source)
    if not match:
        return source
    else_at = source.find("\n#else", match.end())
    end = source.find("\n#endif", else_at)
    if else_at < 0 or end < 0:
        return source
    return source[:match.start()] + source[else_at + len("\n#else"):end] + source[end + len("\n#endif"):]


def imports(source):
    return re.findall(r'#\s*(?:import|include)\s+"([^"]+)"', source)


def reachable_headers(path, seen=None):
    seen = set() if seen is None else seen
    for name in imports(device_view(path.read_text(encoding="utf-8", errors="replace"))):
        header = DIRECTORY / name
        if header.exists() and header not in seen:
            seen.add(header)
            reachable_headers(header, seen)
    return seen


PROTOTYPE = re.compile(r"(?:^|[;\n}])\s*(?:extern\s+)?(?:static\s+)?(?:inline\s+)?(?:const\s+)?[A-Za-z_][\w\s\*]*?\b([A-Za-z_]\w*)\s*\([^;{}()]*(?:\([^)]*\)[^;{}()]*)*\)\s*[;{]", re.S)


def declared_names(text):
    return {m.group(1) for m in PROTOTYPE.finditer(text) if m.group(1) not in KEYWORDS}


def main():
    files = sorted(list(DIRECTORY.glob("*.m")) + list(DIRECTORY.glob("*.c")))
    views = {f: clean(device_view(f.read_text(encoding="utf-8", errors="replace"))) for f in files}
    # project functions: defined (not static) in some .m/.c
    defined_in = {}
    for f, text in views.items():
        for m in re.finditer(r"(?:^|\n)(?!static\b)(?:[A-Za-z_][\w\s\*]*?)\b((?:halo_|Halo)\w+)\s*\([^;{}]*\)\s*\{", text):
            defined_in.setdefault(m.group(1), set()).add(f)
    problems = []
    for f, text in views.items():
        visible = declared_names(text)
        for header in reachable_headers(f):
            visible |= declared_names(clean(header.read_text(encoding="utf-8", errors="replace")))
        for name in sorted(set(re.findall(r"\b((?:halo_|Halo)\w+)\s*\(", text))):
            if name in defined_in and f not in defined_in[name] and name not in visible:
                problems.append(f"{f.name}: calls {name}(), defined in {sorted(d.name for d in defined_in[name])[0]}, but no header it includes declares it")
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print(f"PASS: every project function called across {len(files)} iOS host files is declared in a header the caller includes")


if __name__ == "__main__":
    main()
