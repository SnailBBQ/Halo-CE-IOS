# Build the IPA

You can build the app yourself without a Mac. GitHub's servers do the work and give you a `HaloCE.ipa` that you then
[sideload](INSTALL.md).

## How the build works

The workflow [`.github/workflows/ios.yml`](../../.github/workflows/ios.yml) runs diagnostics followed by two dependent builds:

1. **Build Halo engine guest** (Ubuntu). Builds the recovered game engine as a 32-bit-pointer `arm64_32` program (`halo_guest.elf`),
   with the iOS options and the iOS OpenGL ES stubs applied. It also runs the automated checks.
2. **Build and package iOS app** (macOS). Builds the native `HaloIOS` app with Xcode, puts the engine inside it, ad-hoc signs it and
   packages `HaloCE.ipa`.

The result is an IPA that must be re-signed on install. The iOS Simulator is not supported.

## Build with GitHub Actions

1. Sign in to GitHub and get your own copy of the repository (a fork, or push it to a repository of your own).
2. If GitHub asks, enable **Actions** for your copy.
3. Open **Actions → Halo CE iOS — Build IPA → Run workflow**.
4. Choose the branch (`main` for the regular app) and, if you wish, set the options below. Start the run.
5. Wait for diagnostics and both build jobs to succeed. Each job has a 40-minute timeout.
6. Open the finished run and download the **HaloCE-iOS** artifact. Extract the ZIP to get **`HaloCE.ipa`**.

Re-running an old run builds its original commit. To test newer changes, start a new run. Pushes that change the app, the engine
sources or the workflow on `main` also start a build automatically. Other branches do not build automatically. A newer run cancels unfinished older runs. Documentation-only updates do not trigger an IPA build. Native Linux, Windows and Android builds are manual only.

Standard GitHub-hosted runners are free for public repositories. Private repositories use the account's included allowance and any paid usage. Account payment or spending restrictions can prevent a run from starting. See [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

### Options

| Option | Default | Meaning |
| --- | --- | --- |
| `arena_fastpath` | on | Rewrites the engine's memory accesses so they avoid a slow fault. Turn it off only to make a baseline build for comparison. |
| `guest_pgo` | off | Optimises the engine with upstream's recorded profile. It needs a newer compiler and has not been proved on a device. |

### Artifacts

| Artifact | Contains | Kept for |
| --- | --- | --- |
| `HaloCE-iOS` | `HaloCE.ipa`, the installable app | 14 days |
| `HaloCE-iOS-Guest` | `halo_guest.elf`, an intermediate file that is not installable | 1 day |

### The Mod Test app

The separate app is maintained on [`ios/modtest`](https://github.com/SnailBBQ/Halo-CE-IOS/tree/ios/modtest), with its own bundle identity and loader. It receives shared updates alongside `main`, but GitHub's IPA pipeline is restricted to `main` and does not package ModTest, including manual dispatches on that branch. Build ModTest separately on a Mac with a matching ModTest guest image. Its output remains `HaloCE-ModTest.ipa`. See [Mod Test](MOD_TEST.md).

## Automated checks

The regular pipeline runs diagnostics and checks before packaging. Besides the engine build, they cover, for example:

- the settings code (saving, loading, bounds, left-handed layout, heat-aware frame cap);
- the map order, controller remapping, colour and key-name code;
- the campaign cheat rules and the cheat tick and actions, run against the real engine code with mocked state;
- the guest-conversion and build configuration;
- source checks for Apple framework links, guest host-import coverage and project function declarations; these checks supplement compilation and do not replace it;
- the real backup, mod and settings stores, compiled with Apple's tools on macOS.

Passing checks do not prove that the app looks or feels right on a device. Each [release note](RELEASE_NOTES.md) lists what to test.

## Build on a Mac

1. Install Xcode with the iOS SDK and clone the repository.
2. Download `halo_guest.elf` from the **HaloCE-iOS-Guest** artifact of the **same commit** as your checkout and place it at
   `build/guest/halo_guest.elf`. Building only the app without the matching engine is not enough.
3. From the repository root:

```sh
xcodebuild \
  -project port/ios/HaloIOS.xcodeproj \
  -scheme HaloIOS \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$PWD/build/ios/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build
```

4. Bundle the engine and package the IPA:

```sh
APP="$PWD/build/ios/DerivedData/Build/Products/Release-iphoneos/HaloIOS.app"
test -s build/guest/halo_guest.elf
cp build/guest/halo_guest.elf "$APP/halo_guest.elf"
codesign --force --sign - --entitlements port/ios/HaloIOS/HaloIOS.entitlements --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"
mkdir -p build/ios/package
PACKAGE=$(mktemp -d "$PWD/build/ios/package/ipa.XXXXXX")
mkdir "$PACKAGE/Payload"
cp -R "$APP" "$PACKAGE/Payload/"
(cd "$PACKAGE" && zip -qry HaloCE.ipa Payload)
cp "$PACKAGE/HaloCE.ipa" build/ios/HaloCE.ipa
```

Re-sign `build/ios/HaloCE.ipa` when you install it. The internal target and bundle are named `HaloIOS`; the name shown on the device is **Halo CE**.

## Publishing a release

The workflow does not publish releases by itself. No iOS release is currently published. Before publishing an IPA:

1. Run the workflow on the exact release commit and wait for both jobs to succeed. Complete the relevant device checklist, including campaign, multiplayer, save/reload and app relaunch.
2. Download the **HaloCE-iOS** artifact and extract `HaloCE.ipa`.
3. Verify the IPA version matches that commit. On GitHub, open **Releases → Draft a new release**, create a tag at the tested commit, such as `ios-M2.6.51`, attach `HaloCE.ipa`, and describe the changes
   (the [release notes](RELEASE_NOTES.md) are a good start).
4. If publishing `HaloCE-ModTest.ipa`, use its own tested commit and tag and mark it as a **prerelease**. Do not describe converted mods as playable without device evidence.
5. Update the download instructions only after the corresponding release and IPA attachment exist. Follow the [public release checklist](PUBLIC_RELEASE.md).

## Where things are

| Path | Contents |
| --- | --- |
| `port/ios/HaloIOS/` | The native iOS app: engine host, Settings, controls, audio, networking, backups, mods |
| `port/ios/HaloIOS.xcodeproj/` | The Xcode project |
| `source/` and `port/linux/` | The engine (shared with other platforms; iOS-only parts are guarded by `HALO_IOS_GUEST`) |
| `tools/ios_gl_stubs.py`, `tools/android_asm_convert.py` | Build tools used for the iOS engine build |
| `tools/tests/` | The automated checks |
| `docs/ios/` | This documentation |
| `port/ios/UPDATE_*.md` | Release notes and device checklists for each update |

## Non-Jailbreak Version (manual build)

The Non-Jailbreak Version is the official app built with extra address-space and JIT diagnostics and a fixed-window fallback; see
[UPDATE_M2669.md](../../port/ios/UPDATE_M2669.md). To build it, open **Actions → Halo CE iOS — Build IPA → Run workflow**, choose `main`, tick
`non_jailbreak` and leave `compatibility_test` unticked. The artifact is `HaloCE-iOS-NonJailbreak` and contains `HaloCE-NonJailbreak.ipa`.
Automatic builds never include it. It is experimental: it has not been tested on a device, and stock installs may still need a tool that enables
JIT.
