"""Every Apple framework the iOS host uses must be linked by the Xcode project, or the link step fails with "Undefined symbols"
(CoreImage's CIFilter and CIContext did, in M2.6.49). A framework counts as used when a source file imports one of its headers
or names one of its classes or functions below, even if UIKit happens to make the header visible. It counts as linked when it is
in the project's Frameworks build phase or in OTHER_LDFLAGS, and both build configurations must agree.
Run: python tools/tests/test_ios_frameworks_linked.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "port" / "ios"
PROJECT = ROOT / "HaloIOS.xcodeproj" / "project.pbxproj"
SOURCES = sorted(list((ROOT / "HaloIOS").glob("*.m")) + list((ROOT / "HaloIOS").glob("*.c")) + list((ROOT / "HaloIOS").glob("*.h")))

# header directories that are the C library, not a framework
NOT_FRAMEWORKS = {"sys", "os", "mach", "CommonCrypto", "objc", "dispatch", "arpa", "net", "netinet", "libkern", "malloc", "pthread", "unistd"}
# names that need a framework to be linked
SYMBOLS = {
    "CoreImage": r"\b(CIContext|CIFilter|CIImage|CIColor|CIVector|CIDetector)\b",
    "CoreMotion": r"\b(CMMotionManager|CMDeviceMotion|CMAttitude|CMPedometer|CMAltimeter|CMHeadphoneMotionManager)\b",
    "GameController": r"\b(GCController|GCExtendedGamepad|GCKeyboard|GCMouse|GCMicroGamepad)\b",
    "AVFoundation": r"\b(AVAudioEngine|AVAudioSession|AVAudioSourceNode|AVAudioFormat|AVAudioPlayer|AVPlayer|AVCaptureSession)\b",
    "CoreMedia": r"\b(kCMTime\w*|CMTime(?:Make|MakeWithSeconds|GetSeconds|Compare|Add|Subtract|ConvertScale)|CMClock\w*|CMSampleBuffer\w*|CMFormatDescription\w*)\b",
    "UniformTypeIdentifiers": r"\bUTType[A-Z]\w*",
    "OpenGLES": r"\b(EAGLContext|kEAGL\w+|EAGLSharegroup)\b",
    "QuartzCore": r"\b(CADisplayLink|CAShapeLayer|CATransaction|CALayer|CAEAGLLayer|CACurrentMediaTime|CABasicAnimation|CAMediaTiming|CAGradientLayer)\b",
    "CoreGraphics": r"\b(CGImageRelease|CGContext[A-Z]\w*|CGColorSpace[A-Z]\w*|CGPath[A-Z]\w*|CGDataProvider\w*|CGBitmapContext\w*)\b",
    "CoreHaptics": r"\b(CHHapticEngine|CHHapticPattern|CHHapticEvent)\b",
    "AudioToolbox": r"\b(AudioServices\w+|AudioQueue\w+|AudioUnit\w*|AudioFile\w+)\b",
    "Security": r"\b(SecItem\w+|SecRandom\w+|SecKey\w+)\b",
    "Network": r"\b(nw_[a-z_]+)\(",
    "SystemConfiguration": r"\b(SCNetworkReachability\w+)\b",
    "Photos": r"\b(PHPhotoLibrary|PHAsset|PHAssetChangeRequest)\b",
    "PhotosUI": r"\b(PHPickerViewController|PHPickerConfiguration)\b",
    "WebKit": r"\b(WKWebView|WKWebViewConfiguration)\b",
    "SafariServices": r"\b(SFSafariViewController)\b",
    "Metal": r"\b(MTLCreateSystemDefaultDevice|MTLDevice|MTLCommandQueue)\b",
    "CoreLocation": r"\b(CLLocationManager|CLLocation)\b",
    "UserNotifications": r"\b(UNUserNotificationCenter|UNMutableNotificationContent)\b",
    "MultipeerConnectivity": r"\b(MCSession|MCPeerID)\b",
    "CoreBluetooth": r"\b(CBCentralManager|CBPeripheral)\b",
    "MessageUI": r"\b(MFMailComposeViewController)\b",
    "StoreKit": r"\b(SKPaymentQueue|SKProduct)\b",
}
# frameworks UIKit or Foundation always bring along when they are linked (re-exported)
IMPLIED = {"UIKit": {"Foundation", "CoreGraphics", "QuartzCore"}, "Foundation": set()}


def strip(text):
    def blank(m):
        return re.sub(r"[^\n]", " ", m.group(0))

    text = re.sub(r"/\*.*?\*/", blank, text, flags=re.S)
    text = re.sub(r"//[^\n]*", blank, text)
    return re.sub(r'@?"(?:\\.|[^"\\\n])*"', lambda m: '""', text)


def project_frameworks():
    text = PROJECT.read_text(encoding="utf-8")
    refs = {m.group(1): m.group(2) for m in re.finditer(r"(\w+) = \{isa = PBXFileReference;[^}]*?name = (\w+)\.framework;", text)}
    builds = {m.group(1): m.group(2) for m in re.finditer(r"(\w+) = \{isa = PBXBuildFile; fileRef = (\w+);", text)}
    phase = re.search(r"isa = PBXFrameworksBuildPhase;[^}]*?files = \(([^)]*)\)", text)
    in_phase = {refs[builds[b]] for b in re.findall(r"\w+", phase.group(1)) if b in builds and builds[b] in refs} if phase else set()
    configs = [set(re.findall(r"-framework (\w+)", flags)) for flags in re.findall(r'OTHER_LDFLAGS = "([^"]*)"', text)]
    return in_phase, configs


def main():
    in_phase, configs = project_frameworks()
    problems = []
    if len(configs) < 2 or any(c != configs[0] for c in configs):
        problems.append(f"the build configurations disagree about OTHER_LDFLAGS frameworks: {configs}")
    linked = set(in_phase) | (configs[0] if configs else set())
    for framework in list(linked):
        linked |= IMPLIED.get(framework, set())
    used = {}
    for path in SOURCES:
        raw = path.read_text(encoding="utf-8", errors="replace")
        code = strip(raw)
        for match in re.finditer(r"#\s*(?:import|include)\s+<([A-Za-z0-9_]+)/[^>]+>", raw):
            name = match.group(1)
            if name not in NOT_FRAMEWORKS and name[0].isupper():
                used.setdefault(name, path.name)
        for match in re.finditer(r"@import\s+(\w+)", raw):
            used.setdefault(match.group(1), path.name)
        for framework, pattern in SYMBOLS.items():
            if re.search(pattern, code):
                used.setdefault(framework, path.name)
    for framework, where in sorted(used.items()):
        if framework not in linked:
            problems.append(f"{framework}: used by {where} but not linked (add -framework {framework} to OTHER_LDFLAGS in both configurations)")
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print(f"PASS: all {len(used)} frameworks the iOS host uses are linked ({', '.join(sorted(used))})")


if __name__ == "__main__":
    main()
