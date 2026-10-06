# Public release preparation

This is an unofficial community iOS port, not a Microsoft, Bungie or OpenCE team release.

## Current publication state

- `main` contains M2.6.82 / OpenCE build 138 (network 20) after this update is applied. Every IPA carries build/engine identity metadata and automatic engine-change save protection; the release pipeline has strict upstream acceptance gates. M2.6.80 passed GitHub Actions. M2.6.81 failed the arm64_32 guest compile before an IPA was produced; M2.6.82 fixes the missing iOS-only compile dependencies, passes local strict source acceptance, and still needs its Actions/device validation. The maintainer reports playable campaign and PC multiplayer on earlier builds, but that is not yet a build-138 device result.
- M2.6.70 builds the regular app, Mod Test and the Non-Jailbreak diagnostic from `main`. Apple builds and device testing remain required.
- No GitHub release or release IPA attachment exists yet. Successful Actions artifacts are temporary downloads, not permanent release assets.
- The Mod Test app is experimental. Converted Cursed Halo attempts have failed; general PC/MCC mod compatibility is not established.

## Before changing repository visibility

1. Decide whether public copying is acceptable. Anyone can fork a public GitHub repository. Branch rulesets do not prevent forks or downloads. The existing CC0 dedication permits reuse of covered project code; third-party licenses still apply. See [GitHub visibility](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility) and [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
2. Review author identities in Git history. The migrated branch history was cleaned of the maintainer's personal email and verified from a fresh clone. Keep original backups and the original repository private; check future commits before publication. Contributor names were preserved.
3. Review Actions history, logs, artifacts, pull-request discussions and other repository attachments before exposure. Public visibility also exposes Actions logs; scanning Git blobs does not cover those resources.
4. Keep proprietary maps, extracted tags, disc images, original engine executables, signing identities and private keys out of Git and release attachments. Do not remove required font or third-party license notices.
5. Review artwork provenance and gameplay screenshots separately. This audit is not a legal clearance of every inherited asset. The app icon artwork is by ORION, used with permission, and is outside this repository's CC0 dedication.

## Audit performed on October 3, 2026

The README, project status, current iOS guides, developer guide and iOS milestone notes were reviewed against the relevant settings, campaign, invite, startup and packaging code. Historical notes are explicitly labelled so their old limitations are not presented as current instructions. Vendored documentation and the thousands of inherited research reports are retained as upstream records, not rewritten as iOS user guides.

A pattern scan covered 8,629 unique blobs (about 146 MiB) reachable from the fetched origin branch histories. No matching credential tokens or packaged map/disc/IPA/signing-key files were found. The single private-key marker was a PEM header constant in `mbedtls/library/pk_internal.h`, not private key material. Pattern scans can miss secrets, and this result does not cover unfetched refs, Actions logs or external attachments.

Corrections include unpublished download links, current versus pending build status, the removed touch-editor shortcut, mirrored-layout editing, invite token reuse, clipboard permissions, overshield behaviour, Safe Start timing, frame-rate claims and AirPlay aspect guidance.

## Recommended branch protections

Rulesets are optional. They are available for public repositories on GitHub Free; private repositories need an eligible plan. See [GitHub rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets).

For `main`:

- Block force pushes and branch deletion.
- Require changes through pull requests, with an administrator bypass for recovery.
- Resolve review conversations before merging.
- Add required guest and Apple build checks once those jobs can run successfully. Do not require unavailable checks or an external reviewer when there is no second maintainer.

Protect published release tags against deletion and replacement. These protections control this repository's branches and tags, not somebody else's fork. No ruleset or visibility change was applied by this audit.

## Before publishing an IPA

1. Choose the release commit, integrate the reviewed documentation, and run both build jobs successfully. Billing-blocked runs that never started are not source compilation results.
2. Complete the milestone's device checklist: stock campaign progression and save/reload; PC host and client play; menus; audio; settings persistence; background/resume and cold relaunch. Check the actual IPA version and bundle identity.
3. Include the required notices for embedded fonts and linked third-party components in the distributed app/package. The Overpass font notice must travel with the binary; the current iOS packaging workflow does not explicitly copy it. Verify the final IPA contents, not just the source-tree notices.
4. Attach `HaloCE.ipa` to a release tagged at that exact tested commit. Publish Mod Test separately as a prerelease, with its own tag and `HaloCE-ModTest.ipa`.
5. Describe tested devices and known limits. Do not promise universal 60 FPS, every campaign map, 128-player phone hosting, AirPlay latency or playable converted mods without evidence.
6. Update the README and Install download instructions after the release attachment exists. Retain the previous working release for recovery.

Public source access and a tested downloadable app release are separate decisions. Publishing source does not require presenting an untested IPA as stable.

## Repository privacy migration

The maintained repository is now `SnailBBQ/Halo-CE-IOS`. Personal author/committer emails were replaced without changing source trees. Only cleaned branches were uploaded to this fresh repository; old pull-request references were excluded. The original repository and local history backups remain private. Future commits use the new account’s GitHub privacy email. This does not by itself make the repository public or publish an IPA.
