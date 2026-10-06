#!/usr/bin/env python3
"""Acceptance gates for integrating a newer OpenCE build into Halo CE iOS.

Local mode checks repository consistency, build identity, the fingerprinted
known-good build-125 transition deltas and the iOS guardrails. The PC updater
can additionally pass --upstream-root with the exact candidate OpenCE tree.
Upstream-owned files are compared after removing only HALO_IOS_GUEST blocks;
--require-clean-flags-off makes zero differences mandatory when promoting a new
OpenCE integration.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = ("source", "port/linux", "port/android/guest", "port/include")
IOS_OWNED_EXTRA_FILES = {"port/include/ios_render_scan.h", "port/include/ios_scene_scan.h"}
BASELINE_DELTA_PATH = ROOT / "port/ios/upstream_baseline_deltas.json"
CONFLICT_ROOTS = ("source", "port", "tools", ".github")
TEXT_SUFFIXES = {".c", ".h", ".m", ".mm", ".py", ".yml", ".yaml", ".json", ".plist", ".md", ".txt", ".sh"}


def flags_off_view(text: str) -> str:
    """Remove only HALO_IOS_GUEST conditional branches, preserving all other text."""
    out: list[str] = []
    stack: list[list[object]] = []

    def live() -> bool:
        return not any(kind == "ios" and in_else is False for kind, in_else in stack)

    for line in text.replace("\r\n", "\n").split("\n"):
        stripped = line.strip()
        match = re.match(r"#\s*(ifdef|ifndef)\s+HALO_IOS_GUEST\b", stripped)
        if match:
            # in_else means the currently selected branch is the non-iOS branch.
            stack.append(["ios", match.group(1) == "ifndef"])
            continue
        if re.match(r"#\s*(if|ifdef|ifndef)\b", stripped):
            if live():
                out.append(line)
            stack.append(["other", False])
            continue
        if re.match(r"#\s*else\b", stripped):
            if stack and stack[-1][0] == "ios":
                stack[-1][1] = not stack[-1][1]
                continue
            if live():
                out.append(line)
            continue
        if re.match(r"#\s*endif\b", stripped):
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
    return "\n".join(out)


def flags_off_digest(text: str) -> str:
    return hashlib.sha256(flags_off_view(text).encode("utf-8", errors="surrogateescape")).hexdigest()


def approved_baseline_deltas(upstream: dict) -> dict[str, str]:
    if not BASELINE_DELTA_PATH.is_file():
        return {}
    baseline = json.loads(BASELINE_DELTA_PATH.read_text(encoding="utf-8"))
    base_upstream = baseline.get("upstream", {})
    want_tag = str(upstream.get("tag", ""))
    want_commit = str(upstream.get("commit", ""))
    have_tag = str(base_upstream.get("tag", ""))
    have_commit = str(base_upstream.get("commit", ""))
    commit_matches = bool(want_commit and have_commit and (want_commit.startswith(have_commit) or have_commit.startswith(want_commit)))
    if want_tag != have_tag or not commit_matches:
        return {}
    deltas = baseline.get("approved_flags_off_deltas", {})
    return {str(path): str(digest) for path, digest in deltas.items()} if isinstance(deltas, dict) else {}


def read_define(path: Path, name: str) -> int:
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(rf"^\s*#\s*define\s+{re.escape(name)}\s+([^/\r\n]+)", text, re.M)
    if not match:
        raise ValueError(f"{name} not found in {path.relative_to(ROOT)}")
    value = match.group(1).strip()
    return int(value, 0)


def run_test(relative: str) -> tuple[bool, str]:
    proc = subprocess.run([sys.executable, str(ROOT / relative)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return proc.returncode == 0, proc.stdout.strip()


def add(results: list[dict], name: str, ok: bool, detail: str, status: str | None = None) -> None:
    results.append({"name": name, "status": status or ("pass" if ok else "fail"), "detail": detail})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream-root", type=Path, help="exact candidate OpenCE source tree")
    parser.add_argument("--require-upstream", action="store_true", help="fail unless exact flags-off comparison runs")
    parser.add_argument("--require-clean-flags-off", action="store_true", help="reject even approved known-good baseline deltas; use for promotion of a new OpenCE candidate")
    parser.add_argument("--json", type=Path, help="also write a machine-readable report")
    args = parser.parse_args()
    results: list[dict] = []

    upstream = json.loads((ROOT / "port/ios/upstream.json").read_text(encoding="utf-8"))
    with (ROOT / "port/ios/HaloIOS/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    network = read_define(ROOT / "port/linux/include/halo_port_limits.h", "HALO_PORT_NETWORK_VERSION")
    cpu = read_define(ROOT / "port/linux/include/halo_port_capacity.h", "HALO_PORT_GAME_STATE_CPU_SIZE")
    gpu = read_define(ROOT / "port/linux/include/halo_port_capacity.h", "HALO_PORT_GAME_STATE_GPU_SIZE")
    state_bytes = cpu + gpu
    metadata_ok = (
        info.get("HaloOpenCERelease") == upstream.get("tag")
        and info.get("HaloOpenCECommit") == upstream.get("commit")
        and int(info.get("HaloNetworkVersion", -1)) == network
        and int(info.get("HaloGameStateBytes", -1)) == state_bytes
    )
    add(results, "build_identity_matches_source", metadata_ok,
        f"{upstream.get('tag')} {upstream.get('commit')}, network {network}, game state {state_bytes} bytes")

    conflicts: list[str] = []
    for base in CONFLICT_ROOTS:
        root = ROOT / base
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            if re.search(r"(?m)^(<<<<<<< |>>>>>>> )", text):
                conflicts.append(path.relative_to(ROOT).as_posix())
    add(results, "no_merge_conflict_markers", not conflicts, "none" if not conflicts else ", ".join(conflicts[:20]))

    approved = approved_baseline_deltas(upstream)
    if approved:
        drift: list[str] = []
        for rel, expected in sorted(approved.items()):
            path = ROOT / rel
            if not path.is_file():
                drift.append(f"{rel}: missing")
                continue
            current = path.read_text(encoding="utf-8", errors="surrogateescape")
            try:
                digest = flags_off_digest(current)
            except ValueError as error:
                drift.append(f"{rel}: {error}")
                continue
            if digest != expected:
                drift.append(f"{rel}: fingerprint changed")
        add(results, "known_good_delta_fingerprints", not drift,
            f"{len(approved)} approved M2.6.79/build-125 transition deltas unchanged" if not drift else "; ".join(drift[:20]))
    else:
        add(results, "known_good_delta_fingerprints", True, "no legacy delta baseline applies to this upstream identity", status="not-run")

    for name, script in (
        ("ios_guard_structure", "tools/tests/test_ios_source_structure.py"),
        ("host_import_coverage", "tools/tests/test_ios_import_coverage.py"),
        ("workflow_configuration", "tools/tests/test_ios_workflow_configuration.py"),
        ("header_declarations", "tools/tests/test_ios_header_declarations.py"),
        ("checkpoint_metadata", "tools/tests/test_ios_checkpoint_size.py"),
        ("acceptance_parser", "tools/tests/test_ios_upstream_acceptance.py"),
    ):
        ok, detail = run_test(script)
        add(results, name, ok, detail[-1200:] if detail else "passed")

    compared = 0
    exact_matches = 0
    mismatches: list[dict[str, str]] = []
    if args.upstream_root:
        candidate = args.upstream_root.resolve()
        if not candidate.is_dir():
            add(results, "flags_off_upstream_equivalence", False, f"not a directory: {candidate}")
        else:
            for base in SCAN_ROOTS:
                for path in sorted((ROOT / base).rglob("*")):
                    if path.suffix not in (".c", ".h") or not path.is_file():
                        continue
                    current = path.read_text(encoding="utf-8", errors="surrogateescape")
                    if "HALO_IOS_GUEST" not in current:
                        continue
                    relative = path.relative_to(ROOT)
                    rel = relative.as_posix()
                    if rel in IOS_OWNED_EXTRA_FILES:
                        continue
                    other = candidate / relative
                    compared += 1
                    if not other.is_file():
                        mismatches.append({"path": rel, "reason": "missing upstream file", "digest": ""})
                        continue
                    try:
                        plain = flags_off_view(current)
                    except ValueError as error:
                        mismatches.append({"path": rel, "reason": str(error), "digest": ""})
                        continue
                    upstream_text = other.read_text(encoding="utf-8", errors="surrogateescape").replace("\r\n", "\n")
                    if plain == upstream_text:
                        exact_matches += 1
                    else:
                        digest = hashlib.sha256(plain.encode("utf-8", errors="surrogateescape")).hexdigest()
                        mismatches.append({"path": rel, "reason": "flags-off view differs", "digest": digest})
            if not mismatches:
                add(results, "flags_off_upstream_equivalence", True, f"exact: {exact_matches}/{compared} adapted upstream files")
            else:
                unapproved = [m for m in mismatches if not m["digest"] or approved.get(m["path"]) != m["digest"]]
                detail = f"exact {exact_matches}/{compared}; {len(mismatches)} difference(s)"
                if unapproved:
                    detail += "; unapproved: " + "; ".join(f"{m['path']}: {m['reason']}" for m in unapproved[:20])
                    add(results, "flags_off_upstream_equivalence", False, detail)
                elif args.require_clean_flags_off:
                    detail += "; all are approved M2.6.79 baseline deltas, but strict promotion mode requires zero"
                    add(results, "flags_off_upstream_equivalence", False, detail)
                else:
                    detail += "; all match the fingerprinted M2.6.79/build-125 legacy baseline (transition debt; strict mode rejects it)"
                    add(results, "flags_off_upstream_equivalence", True, detail, status="warn")
    else:
        required = args.require_upstream or args.require_clean_flags_off
        add(results, "flags_off_upstream_equivalence", not required,
            "not run: pass --upstream-root with the exact candidate OpenCE tree", status="not-run" if not required else "fail")

    failed = [row for row in results if row["status"] == "fail"]
    warned = [row for row in results if row["status"] == "warn"]
    report = {
        "schema": 1,
        "status": "pass" if not failed else "fail",
        "known_good": upstream,
        "build_identity": {
            "milestone": info.get("HaloSourceMilestone"),
            "release": info.get("HaloOpenCERelease"),
            "commit": info.get("HaloOpenCECommit"),
            "network_version": network,
            "game_state_bytes": state_bytes,
            "guest_architecture": info.get("HaloGuestArchitecture"),
            "guest_adaptation": info.get("HaloGuestAdaptation"),
            "renderer": info.get("HaloRenderer"),
        },
        "gates": results,
        "flags_off": {"compared": compared, "exact_matches": exact_matches, "differences": len(mismatches), "approved_baseline_differences": len(mismatches) if mismatches and not [m for m in mismatches if not m["digest"] or approved.get(m["path"]) != m["digest"]] else 0},
    }
    for row in results:
        prefix = {"pass": "PASS", "fail": "FAIL", "warn": "WARN", "not-run": "SKIP"}[row["status"]]
        print(f"{prefix}: {row['name']}: {row['detail']}")
    print(f"Acceptance: {report['status'].upper()} ({len(failed)} failed, {len(warned)} warning, {len(results)} total)")
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
