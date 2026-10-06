# M2.6.79 — Baseline cleanup before the next upstream merge

Regular app 0.2.79 / 2679. The Mod Test app derives its version from it (0.2.79.1 / 267901). The engine and app runtime are otherwise unchanged from M2.6.78: OpenCE build 125, network version 16. Nothing here has been built on Apple hardware or tested on a device.

## Why

Before using M2.6.78 as the base for another OpenCE merge, a small audit found stale release metadata and two CI/test-harness issues. None required an engine or gameplay change. Cleaning them now makes the repository a clearer baseline and avoids spending Actions time on work that cannot affect the IPA.

## What changed

- **Current-version documentation is consistent.** The project status, release notes, public-release page, history and Mod Test version table now identify M2.6.79 / 0.2.79 correctly.
- **`port/ios/upstream.json` records the actual integration milestone.** OpenCE build 125 was integrated in M2.6.76, not M2.6.77. The tag and commit remain `build-125` / `13c14df`.
- **Notes-only iOS documentation no longer starts an automatic IPA build.** The `ios.yml` push filter still watches `port/ios/**`, but excludes top-level `port/ios/*.md` notes. Source, project and workflow changes continue to trigger the build. Manual workflow runs are unaffected.
- **The mod-cache policy test runs once.** In the reusable Linux diagnostics workflow it had accidentally been placed inside the 12-item C-test loop, so it compiled and ran 12 times. It now runs once after the loop.
- **The XISO test driver is warning-clean under GCC and Clang.** The old one-line `if` form triggered GCC's `-Wmisleading-indentation` under `-Werror`. The driver was reformatted only; disc-image import code and behavior are unchanged.
- **Workflow configuration tests guard the cleanup.** They now check the Markdown exclusion and that the mod-cache test remains outside the loop.

## What was checked here, and what was not

- The Linux-compatible iOS tests and structural guards available in this environment were run after the edits, including workflow configuration, XISO extraction tests, source structure, import coverage and asset integrity. Thirty of the 31 Python iOS test files ran and passed; `test_ios_pointer_fastpath.py` could not be rerun locally because its `keystone` / `unicorn` packages are not installed and this environment cannot download them. GitHub Actions installs those packages before running that unchanged test.
- The XISO test suite was compiled with both GCC and Clang.
- The workflow YAML was parsed/inspected by the repository's own configuration test; the build-ninja transformation test still covers LF and CRLF input with arena fast path on, off and default.
- **Not checked:** only GitHub Actions can compile the real arm64_32 guest and Objective-C host. No M2.6.79 IPA has been installed or run on an iPhone.

## Build impact

This update **will start the automatic iOS build** when pushed because it changes `Info.plist`, `ios.yml`, the reusable diagnostics workflow and test sources. Future pushes that change only a top-level Markdown note under `port/ios/` should not start the automatic IPA build.

## Device checklist

There is no new gameplay feature to validate. After the Apple build is green:

1. Confirm the regular app reports version **0.2.79 (2679)**.
2. If you build Mod Test manually, confirm it reports **0.2.79.1 (267901)** and still installs separately.
3. Open the app, import or use existing maps, and launch Halo once as a smoke test.
4. Confirm Share logs / Copy logs from M2.6.78 still appear and work.
5. For any future OpenCE merge, use this M2.6.79 tree as the iOS side and OpenCE build 125 as the upstream merge base.
