"""Inspect an app after signing. Report only capability booleans, not identities.

CI checks the requested entitlements in its ad-hoc signature. A re-signed app
must be checked again; neither check grants capabilities or proves execution.
"""
import argparse
import plistlib
from pathlib import Path
import subprocess

MEMORY_KEYS = (
    "com.apple.developer.kernel.extended-virtual-addressing",
    "com.apple.developer.kernel.increased-memory-limit",
)


def capability_report(signed, profile=None):
    return {key: {"signed": signed.get(key) is True,
                  "profile": None if profile is None else profile.get("Entitlements", {}).get(key) is True}
            for key in (*MEMORY_KEYS, "get-task-allow")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--report-only", action="store_true", help="Report missing capabilities without failing")
    parser.add_argument("--require-absent-memory", action="store_true",
                        help="Fail if a kernel memory entitlement is present. Used by the Non-Jailbreak IPA, which must not ask for any.")
    args = parser.parse_args()
    result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(args.app)],
                            capture_output=True, check=True)
    signed = plistlib.loads(result.stdout)
    profile_path = args.app / "embedded.mobileprovision"
    profile = None
    if profile_path.is_file():
        decoded = subprocess.run(["security", "cms", "-D", "-i", str(profile_path)],
                                 capture_output=True, check=True)
        profile = plistlib.loads(decoded.stdout)
    report = capability_report(signed, profile)
    for key, state in report.items():
        allowed = "not inspected (no provisioning profile)" if state["profile"] is None else str(state["profile"]).lower()
        print(f"{key}: signed={str(state['signed']).lower()}, profile-authorized={allowed}")
    print("This checks signature/profile contents only. Installation may change signing; execution still needs device validation.")
    if args.require_absent_memory:
        if any(report[k]["signed"] for k in MEMORY_KEYS):
            raise SystemExit("Non-Jailbreak build must not be signed with kernel memory entitlements.")
        return
    if not args.report_only and any(not report[k]["signed"] or report[k]["profile"] is False for k in MEMORY_KEYS):
        raise SystemExit("Required memory capabilities are missing or not authorized by the embedded profile.")


if __name__ == "__main__":
    main()
