#!/usr/bin/env python3
"""Regression checks for the OpenCE acceptance gate's iOS flags-off view."""
from __future__ import annotations
import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/ios_upstream_acceptance.py"
spec = importlib.util.spec_from_file_location("ios_upstream_acceptance", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

cases = {
    "ifdef": (
        "#ifdef HALO_IOS_GUEST\nIOS\n#else\nUPSTREAM\n#endif\nTAIL",
        "UPSTREAM\nTAIL",
    ),
    "ifndef": (
        "#ifndef HALO_IOS_GUEST\nUPSTREAM\n#else\nIOS\n#endif\nTAIL",
        "UPSTREAM\nTAIL",
    ),
    "nested": (
        "#ifdef HALO_IOS_GUEST\nIOS\n#else\n#if FEATURE\nUP1\n#else\nUP2\n#endif\n#endif\nTAIL",
        "#if FEATURE\nUP1\n#else\nUP2\n#endif\nTAIL",
    ),
    "no_else": (
        "HEAD\n#ifdef HALO_IOS_GUEST\nIOS\n#endif\nTAIL",
        "HEAD\nTAIL",
    ),
}
for name, (source, expected) in cases.items():
    actual = module.flags_off_view(source)
    assert actual == expected, f"{name}: {actual!r} != {expected!r}"

for broken in ("#ifdef HALO_IOS_GUEST\nIOS", "#endif\n"):
    try:
        module.flags_off_view(broken)
    except ValueError:
        pass
    else:
        raise AssertionError("malformed preprocessor structure was not rejected")


assert module.IOS_OWNED_EXTRA_FILES == {"port/include/ios_render_scan.h", "port/include/ios_scene_scan.h"}
baseline = module.approved_baseline_deltas({"tag":"build-125","commit":"13c14df"})
assert len(baseline) == 27 and "port/linux/src/d3d8_gl.c" in baseline
assert module.approved_baseline_deltas({"tag":"build-126","commit":"deadbeef"}) == {}
assert module.flags_off_digest("#ifdef HALO_IOS_GUEST\nIOS\n#else\nUPSTREAM\n#endif\n") == module.hashlib.sha256(b"UPSTREAM\n").hexdigest()
print("PASS: upstream acceptance strips only HALO_IOS_GUEST branches, preserves upstream/nested preprocessing, and excludes iOS-owned helper headers")
