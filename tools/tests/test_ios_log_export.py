#!/usr/bin/env python3
"""Share logs, Copy logs and the start history are wired up the way M2.6.78 intends.

Objective-C cannot be compiled outside the Apple workflow, so this reads the sources for the mistakes an edit like this
can make: a button created but never put in the row, a callback declared but never assigned, a report builder defined
twice, or the history written after the launch has already overwritten the phase it is meant to keep.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "port/ios/HaloIOS"
failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


def read(path):
    return path.read_text(encoding="utf-8").replace("\r\n", "\n")


def method(text, signature):
    """The source of one Objective-C method, from its signature to its closing brace."""
    start = text.find(signature)
    if start < 0:
        return ""
    end = text.find("\n}\n", start)
    return text[start:end + 3] if end >= 0 else ""


app = read(HOST / "AppDelegate.m")
settings_m = read(HOST / "HaloSettingsViewController.m")
settings_h = read(HOST / "HaloSettingsViewController.h")
log_m = read(HOST / "HaloLogViewController.m")
log_h = read(HOST / "HaloLogViewController.h")
state_h = read(HOST / "halo_launch_state.h")

# ---- one report builder, used by every way of sending logs
check(settings_m.count("NSString *HaloProblemReportText(BOOL compact)\n{") == 1, "HaloProblemReportText must be defined exactly once")
check("NSString *HaloProblemReportText(BOOL compact);" in settings_h, "HaloProblemReportText must be declared in HaloSettingsViewController.h")
check('#import "HaloSettingsViewController.h"' in app, "AppDelegate.m must import HaloSettingsViewController.h to use the report builder")
check("HaloProblemReportText(NO)" in method(settings_m, "- (void)reportProblem:(UIView *)source\n{"), "Report a problem must use the shared report builder")
limits = re.findall(r'@\[@"start-history.txt", @4000\], @\[@"ios-boot.log", @(\d+)\]', settings_m)
check(len(limits) == 2, "the report must list start-history.txt first in both the compact and the full version (found %d)" % len(limits))
if len(limits) == 2:
    compact, full = map(int, limits)
    check(compact < full, "the compact report must keep less of the boot log than the full one (%d vs %d)" % (compact, full))
    check(compact <= 100000, "the compact report is meant to be pasted into a message; %d bytes of boot log is too much" % compact)

# ---- Share logs sends one text file
share = method(app, "- (void)shareLogs:(UIView *)sender {\n")
check(bool(share), "AppDelegate.m has no shareLogs:")
check("HaloProblemReportText(NO)" in share, "Share logs must send the shared report")
check("initWithActivityItems:@[url]" in share, "Share logs must share exactly one file")
check("initWithActivityItems:files" not in share and "NSMutableArray<NSURL *> *files" not in share, "Share logs must not go back to sending the raw files")
check("[self hasLogFiles]" in share, "Share logs must say so when there are no logs")

# ---- Copy logs puts the compact report on the clipboard
copy = method(app, "- (void)copyLogs:(UIView *)sender {\n")
check(bool(copy), "AppDelegate.m has no copyLogs:")
check("HaloProblemReportText(YES)" in copy, "Copy logs must use the compact report")
check("UIPasteboard.generalPasteboard.string = text;" in copy, "Copy logs must put the text on the clipboard")
check("[self hasLogFiles]" in copy, "Copy logs must say so when there are no logs")
files = method(app, "- (BOOL)hasLogFiles {\n")
check('@"start-history.txt"' in files and '@"ios-boot.log"' in files, "hasLogFiles must know the start history and the boot log")

# ---- the launch screen row
check('[copyButton setTitle:@"Copy logs" forState:UIControlStateNormal];' in app, "the launch screen needs a Copy logs button")
check("action:@selector(copyLogs:)" in app, "the Copy logs button must call copyLogs:")
check("@[import, disc, start, share, copyButton, help]" in app, "the Copy logs button must be in the row of buttons")
check("@[import,disc,start,share,copyButton,help]" in app, "the Copy logs button must be styled with the others")

# ---- the Diagnostics and Settings screens
check("log.onCopy = ^(UIView *source) { [weakSelf copyLogs:source]; };" in app, "Diagnostics must be wired to copyLogs:")
check("settings.onCopyLogs = ^(UIView *source) { [weakSelf copyLogs:source]; };" in app, "Settings must be wired to copyLogs:")
check("onCopy)(UIView *source);" in log_h and "self.onCopy(b)" in log_m, "the Diagnostics screen must declare and call onCopy")
check('HaloUIButton(@"Copy logs"' in log_m and "[self.view addSubview:copyButton];" in log_m and "copyButton.trailingAnchor" in log_m, "the Diagnostics Copy logs button must be added and laid out")
check("onCopyLogs)(UIView *source);" in settings_h and "self.onCopyLogs(b)" in settings_m, "Settings must declare and call onCopyLogs")
check('HaloUIButton(@"Copy logs as text"' in settings_m, "Settings needs a Copy logs as text row")

# ---- the history is written before the launch overwrites the phase it keeps
prepare = method(app, "- (void)prepareLaunchState {\n")
check(bool(prepare), "AppDelegate.m has no prepareLaunchState")
history = prepare.find("halo_launch_history_line(")
check(history >= 0 and "start-history.txt" in prepare and "halo_launch_history_append(" in prepare, "prepareLaunchState must record the start history")
check(0 <= history < prepare.find('halo_crash_phase("app launched")'), "the history must be written before the launch overwrites the phase file")
check(0 <= history < prepare.find("halo_crash_install("), "the history must be written before the crash reporter is installed")
check("halo_launch_history_line(" in state_h and "halo_launch_history_append(" in state_h, "halo_launch_state.h must define both history functions")

# ---- the docs say it
trouble = read(ROOT / "docs/ios/TROUBLESHOOTING.md")
check("Copy logs" in trouble and "start-history.txt" in trouble, "TROUBLESHOOTING.md must explain Copy logs and the start history")
check("Copy logs as text" in read(ROOT / "docs/ios/SETTINGS.md"), "SETTINGS.md must list Copy logs as text")

if failures:
    for message in failures:
        print("FAIL:", message)
    sys.exit(1)
print("PASS: Share logs sends one text file, Copy logs is on the start screen, Diagnostics and Settings, and the start history is written before the launch overwrites the phase")
