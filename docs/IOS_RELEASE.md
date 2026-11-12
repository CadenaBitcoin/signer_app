# iOS release: build, signing, verification, upload and testing (Issue #71)

> **Status: procedure documented; NOT yet executed; authorizes nothing.** This is the
> technical handoff for the Apple-side operator. It describes *how* to build, sign, verify and
> upload an iOS release and *what must be true first*. It does not say that any build is
> approved. Approval lives in a separate release record (section 3), created only after the
> authorizations of section 2. The repository holds no Apple credential and no workflow signs or
> uploads anything. Counterpart of [ANDROID_RELEASE.md](ANDROID_RELEASE.md); it reuses that
> document's conventions and the shared documents below instead of repeating them:
> [RELEASE_POLICY.md](RELEASE_POLICY.md), [RELEASE_VERSIONING.md](RELEASE_VERSIONING.md),
> [IOS_SIGNING.md](IOS_SIGNING.md), [IOS_CI.md](IOS_CI.md),
> [SECURITY_BOUNDARY.md](SECURITY_BOUNDARY.md),
> [APPLE_ACCOUNT_QUESTIONNAIRE.md](APPLE_ACCOUNT_QUESTIONNAIRE.md), [../GOVERNANCE.md](../GOVERNANCE.md).

Statements carry the labels of [IOS_SIGNING.md](IOS_SIGNING.md): **Verified** (checked, with the
source), **Approved** (decided by the project owners), **Proposed** (a design not yet approved),
**Unconfirmed** (nobody has established it). Nothing Unconfirmed may be assumed.

## Quick start for the operator

The short version. **Sections 1 to 13 are the authority**: if a command here ever differs from the detailed
section it points to, stop and ask the release coordinator.

**Where the approved release comes from.** Only from the official public repository
`https://github.com/CadenaBitcoin/signer_app`, through the **release record**
`docs/release-records/ios-1.0.4-1000035.md`, read at `origin/development`. The record names the approved commit
(`APPROVED_SHA`, a `production` merge commit) and the reviewed content it must equal (`CONTENT_REF`). The same SHA is
written on Issue #71 by the coordinator and by the independent authorizer (sections 3 and 5). Nothing arrives by chat,
e-mail, zip or someone else's checkout. The record's `Status` line says what you may do:

| Record `Status` | You may |
|---|---|
| `DRAFT` | Nothing. The record is not authorized |
| `G1 AUTHORIZED` | Steps 1 to 3 (retrieve, verify, unsigned build). **Not** sign, **not** upload |
| `G2 AUTHORIZED` | Also steps 4 to 6 (signed build, verification, upload to TestFlight) |
| `WITHDRAWN` | Nothing. Stop |

**What you execute** (details, expected output and the reasons are in the sections named):

```bash
# 1. Retrieve and verify the source (section 5). $WORK is an empty directory you control.
git clone https://github.com/CadenaBitcoin/signer_app.git "$WORK/cadena-ios" && cd "$WORK/cadena-ios"
git fetch origin development production
git show origin/development:docs/release-records/ios-1.0.4-1000035.md      # Status, APPROVED_SHA, CONTENT_REF
git merge-base --is-ancestor "$APPROVED_SHA" origin/production && git checkout --detach "$APPROVED_SHA"
test "$(git rev-parse HEAD)" = "$APPROVED_SHA" && test -z "$(git status --porcelain)" && echo SOURCE-OK
git diff --stat "$CONTENT_REF" "$APPROVED_SHA" -- lib ios flutter_plugin pubspec.yaml pubspec.lock config/build android   # must be empty

# 2. Confirm the Apple-side facts of section 6 and send the answers to the coordinator.

# 3. Credential-free build and checks (section 8, steps 1 to 4)
flutter pub get --enforce-lockfile && (cd flutter_plugin/flutter_plugin && flutter pub get)
tool/verify_version.sh && /bin/bash tool/verify_build_config.sh verify
flutter build ios --release --no-codesign --flavor production --dart-define-from-file=config/build/production.json
tool/verify_artifact.sh ios production build/ios/iphoneos/Runner.app --min-sdk 26

# 4. Only with Status G2 AUTHORIZED (re-read the record first): signed build (section 8, step 5)
flutter build ipa --release --flavor production --dart-define-from-file=config/build/production.json \
  --export-options-plist "$WORK/ExportOptions.plist"

# 5. Verify the IPA: checks V1 to V9 and the symbol inspection of section 9.
# 6. Retain the artifacts (section 12), then upload with Transporter or Xcode Organizer "TestFlight & App Store"
#    (section 10), after re-reading the record again. Do not assign testers, do not submit for review.
```

**What you return** (text and hashes only, through the channel the coordinator names; section 12 lists every item):
the commands' output for sections 5, 7, 8 and 9; the IPA SHA-256; the certificate fingerprint and signing route; the
symbol-inspection results; the App Store Connect messages, verbatim; the answers of section 6; later the test log and
results of section 11. **Never** return or publish the IPA, certificates, profiles, keys, passwords, recovery phrases or
unredacted logs. The signed IPA, its checksum and the evidence are kept only as section 12 ("Temporary retention") says,
never as a public GitHub artifact.

**Stop, and report to the coordinator, if any of these is true:**
- The record is not on `development` through a merged pull request, has no `APPROVED_SHA`, shows `DRAFT` or `WITHDRAWN`, or its
  SHA differs from the one on Issue #71 or changes after you started.
- The SHA is not an ancestor of `origin/production`, the content diff is not empty, or the working tree is not clean.
- A tool version differs from section 7; the native library SHA-256 differs; `ios/Podfile.lock` changes by anything but checksum
  lines, or any other tracked file changes.
- Any stop answer of section 6 (wrong team, no or different App Store Connect record, highest uploaded build 1000035 or more,
  unknown certificate fingerprint, missing export-compliance answer).
- Any check of section 9 fails, or `verify_ipa.py` rejects the IPA. Report it with its full output; never edit, skip or bypass it.
- Apple rejects the build number, or App Store Connect shows a message the coordinator has not seen.
- You are asked to edit the source, the version or the build number, to choose "TestFlight Internal Only", to assign testers,
  to submit for review, or to place the IPA or any secret on GitHub or in a chat.

## 1. Roles and responsibility boundaries

Three roles. **No role is held by anyone merely because of their title, account or repository
permission, and none implies another** (`GOVERNANCE.md` section 1). Who holds each role for a
given release is written into that release's record (section 3), not here. Several accounts
controlled by one individual are one person.

| Role | Responsibility | Not allowed to |
|---|---|---|
| **Release coordinator** (the CTO) | Prepares the release candidate (branch promotions through reviewed pull requests, the release record); authorizes the **source revision**; coordinates the other roles; decides when a build is handed to internal testers | Sign, upload or approve independently of the third role; treat source authorization as release authorization |
| **Apple-side operator** | On a Mac under their control: retrieves and verifies the approved source, builds, signs, verifies the IPA, uploads to App Store Connect when authorized, runs the physical-device tests, returns the evidence | Change application code, the version or the build number; build from anything but the approved revision; skip or weaken a verification; upload before the independent authorization is recorded; submit for review; distribute the IPA |
| **Independent release authorizer** | Gives the separate approval governance requires for production signing and production delivery, for submission to App Review, and for public release | Be the person who prepared, merged or triggered the release (that excludes the release coordinator and the operator). **Not yet designated** |

**Verified:** `GOVERNANCE.md` section 1 and [RELEASE_POLICY.md](RELEASE_POLICY.md) principle 9:
production signing and delivery need approval by a person who did not prepare, merge or trigger
the run, and until a second independent human is designated production signing is not
authorized. [IOS_SIGNING.md](IOS_SIGNING.md) section 6 says the same. `CadenaBitcoin/Maintainers`
has two accounts controlled by one individual, so it is **one** approver. **Claude and any other
AI assistant hold none of the three roles**; they may help with documentation and read-only
checks and never merge, promote, sign, upload or authorize.

### Authorization gates

Each gate is a separate, written, dated decision recorded in the release record. A later gate is
never implied by an earlier one.

| Gate | Decision | Decided by | Needed before |
|---|---|---|---|
| **G1** | Source revision authorized: the exact commit SHA and the content it must equal | Release coordinator | The operator retrieves anything |
| **G2** | Production signing **and** upload to App Store Connect (TestFlight) | Independent release authorizer | Signing certificates are used, and the upload |
| **G3** | The processed build may be assigned to named internal testers | Release coordinator (initially; [IOS_SIGNING.md](IOS_SIGNING.md) section 2, item 6) | Any tester receives the build |
| **G4** | **Submission to App Review**, with the evidence of section 11 (including the 12 hours) | Independent release authorizer | The "Submit for Review" button |
| **G5** | **Public release** of an approved version | Independent release authorizer, separately from G4 | Any step that makes the build available to the public |

### Internal TestFlight versus App Review

| | Initial **internal TestFlight** delivery (this procedure, G2 and G3) | **App Review** submission (G4) and public release (G5) |
|---|---|---|
| Audience | Named internal testers in the Apple team only | App Review, then the public |
| Build | The production-distribution IPA, uploaded as "TestFlight & App Store" (never "TestFlight Internal Only") | **The same processed build**, not rebuilt or re-uploaded |
| Record | The **existing production** App Store Connect record, bundle ID `com.app.cadenabitcoin` | The same record |
| Wallet material | Disposable, zero-value only | Not applicable until G4 is decided |
| Authorization | G1, G2, G3, each written and recorded | G4 and G5, each separate and written |
| Precondition | Section 6 confirmations; section 9 verification | Section 11: at least 12 hours of successful internal TestFlight evaluation and every other listed condition |

**Approved (2026-11-12, project owner):** the first delivery target is **internal TestFlight**, not App Review; the build is a
production-distribution build that can be submitted later **without rebuilding**. A rebuild would be a new build number
and would restart the evaluation. G4 and G5 are **not given by this document, by passing every test in it, or by a successful
upload**.

**Documented deviation from the earlier architecture (approved in principle by the project owner on 2026-11-12; effective for
1.0.4 only when the independent authorizer gives G2 in writing, recorded in the release record).**
[IOS_SIGNING.md](IOS_SIGNING.md) section 2 (items 1 and 3) and [RELEASE_POLICY.md](RELEASE_POLICY.md) section 8.1 approved a
**separate staging App Store Connect record** as the first TestFlight target. That record is not registered with Apple
(policy section 10), so for iOS 1.0.4 the internal TestFlight evaluation uses the **existing production record**. This is a
one-release exception. It **changes no policy**: those sections stay the architecture, a later release follows them unless a
reviewed pull request changes them, and the exception must be accepted and dated in the release record's section 4. A second
deviation is recorded the same way: signing on a Mac under the operator's control instead of in a protected CI environment
(policy section 2.1, requirements 3 and 4, are not met). Because the production record talks to the production backend and
mainnet, the zero-value rule of section 11 is part of the exception, not an optional extra.

## 2. Preconditions the release coordinator owns

All must hold, and be recorded, before the operator is told to start.

1. **Promotion done by reviewed pull requests**: `development` → `staging` → `production`
   ([RELEASE_POLICY.md](RELEASE_POLICY.md) section 2.2, `GOVERNANCE.md` section 3). This document
   performs none of it. The unsigned `build-variants` runs on both pushes are green
   ([RELEASE_TRIGGERS.md](RELEASE_TRIGGERS.md)).
2. **`development` was frozen** between the candidate commit and the promotions, so that no
   unreviewed commit travelled with it.
3. **The approved revision equals the reviewed content.** The authorized commit is a `production`
   merge commit whose application content is identical to the reviewed `development` commit
   (section 3 gives the check).
4. **Issue #22 has a recorded disposition** for this release (section 11). Open PRs that change
   native code or the application must not have been merged into the candidate.
5. **The independent release authorizer is designated** and has given G2 before the operator
   starts step 5 of section 8 (the signed build). Steps 1 to 4 of section 8 and the unsigned
   checks need only G1.
6. **Release-specific facts are in the record** (section 3). Permanent procedure and one release's
   authorization are kept apart on purpose.

## 3. Permanent procedure versus release-specific record

| | Lives in | Changes by |
|---|---|---|
| The procedure (this file) | `docs/IOS_RELEASE.md` | Reviewed pull request |
| **One release's authorization and results** | `docs/release-records/ios-<version>-<build>.md`, created from the skeleton `docs/release-records/ios-1.0.4-1000035.md` | Reviewed pull request (the coordinator prepares it; the operator's evidence is added after) |
| Facts about versions already delivered | `config/release/published_versions.json` | Reviewed pull request, after a maintainer confirms the number in App Store Connect |
| Evidence files, the signed IPA, certificate material | Private custody register / controlled storage **outside the repository** | Operator and custodians |

The release record is what the operator trusts for *which* commit. It is authoritative only when it is on `development`
through a merged, reviewed pull request (a record that exists only in a chat, an e-mail or a branch is not). Its `Status` line is
one of `DRAFT` (the skeleton), `G1 AUTHORIZED`, `G2 AUTHORIZED` or `WITHDRAWN`.

**No circular dependency.** A record cannot contain the SHA of the commit that contains it, so the order is fixed:

1. The promotions are merged. The `production` merge commit `M` exists, and its content is checked against the reviewed content.
2. A reviewed pull request adds `M` and `CONTENT_REF` to the record on `development` and sets `Status` to `G1 AUTHORIZED`
   (release coordinator). `M` is **not** the commit of this pull request and never changes because of it. The record is never
   promoted; it need not exist on `production`.
3. A second reviewed pull request sets `Status` to `G2 AUTHORIZED` and fills the accepted deviations (record section 4). The
   independent authorizer's **approving review** of that pull request is the G2 evidence, and the same SHA is repeated in a
   comment on Issue #71 by the coordinator and by the independent authorizer.
4. Results, G3 and later gates are further pull requests. A different `M` after G1 is a new G1: set `WITHDRAWN`, start again.

**How the operator retrieves it independently**, using only public GitHub and nothing sent by anyone: read the record at
`origin/development`; confirm that it arrived by merged pull requests with
`git log --first-parent --format='%h %s' -5 origin/development -- docs/release-records/ios-1.0.4-1000035.md` (lines
`Merge pull request #N`; the numbers are also on Issue #71); compare `M` with the Issue #71 comments of the coordinator and of the
independent authorizer; check that `M` is an ancestor of `origin/production` (section 5). **Re-read the record immediately before
signing and again before the upload:** `WITHDRAWN`, a changed `M` or a lower `Status` than the step needs means stop.

## 4. Identity and versioning

Conventions are those of [RELEASE_VERSIONING.md](RELEASE_VERSIONING.md) and
[RELEASE_POLICY.md](RELEASE_POLICY.md) section 7; only the iOS facts are listed.

| | Value | Source |
|---|---|---|
| Application | Cadena Bitcoin (production flavor) | `ios/Flutter/Flavor-production.xcconfig` |
| Bundle ID | `com.app.cadenabitcoin` (differs from the Android package) | same; `tool/verify_artifact.sh matrix` |
| Product version `CFBundleShortVersionString` | `1.0.4`, equal to Android | `pubspec.yaml` |
| Build `CFBundleVersion` | `1000035` | `pubspec.yaml` |
| Configuration | `config/build/production.json` (mainnet, `https://cadenabitcoin.com/app`) | `BuildConfig` |
| Team ID | `D65458CPDP` committed. **Unconfirmed** that it is the team that owns the live app | `project.pbxproj` |
| Deployment target | iOS 14.0 declared; five frameworks 15.5; eight Rust C objects 18.5. **Unresolved** | [IOS_CI.md](IOS_CI.md) |

- **The version is never edited by the operator.** Only `pubspec.yaml`, by a reviewed commit,
  changes it; no `--build-name` or `--build-number`, no Xcode edit, no "Manage Version and Build
  Number" ([RELEASE_VERSIONING.md](RELEASE_VERSIONING.md); `tool/verify_version.sh`).
- **The same version on both platforms is valid** (policy 7.1); Android's 1000035 does not occupy
  Apple's number space. Apple rejects a build number already used **for the same version** and
  the operator must treat that as a stop (section 13), never a reason to edit a number.
- **The iOS floor is Unconfirmed.** `published_versions.json` records no iOS build; the operator
  reads the highest uploaded build in App Store Connect before signing (section 6), and the number
  must be above it.
- **The production gate.** `python3 -I tool/build_manifest.py gate --channel production` reports
  each platform. Today it prints `PASS ios` (no floor recorded) and `FAIL android` (1000035 is the
  published Android build) and exits non-zero. That is an **Android** fact about an Android release
  already published. The gate has no per-platform mode, so for an iOS-only release the **iOS line is the
  applicable result**, and the coordinator records in the release record that this reading is
  accepted. It is a reading of the rule, not a bypass of it: after the upload the iOS number enters the ledger
  (section 10) and the rule then applies to iOS too. A platform-scoped gate is a small reviewed
  tool change and is listed in section 13.
- Build numbers may differ between platforms in future (policy 7.3); no mechanism exists and
  none is introduced here.

## 5. Retrieving and verifying the approved source

**The application is taken only from the approved revision in the official GitHub repository.**
Not from a zip, a fork, a chat attachment, a synchronized folder, an IDE copy, another person's
checkout or a branch name. A branch name moves; the SHA of the record does not.

```bash
# Work outside any existing checkout. $WORK is an empty directory you control.
git clone https://github.com/CadenaBitcoin/signer_app.git "$WORK/cadena-ios" && cd "$WORK/cadena-ios"
git remote get-url origin                       # must be exactly https://github.com/CadenaBitcoin/signer_app.git
git fetch origin development production

# 1. Read the record from development; it names the approved SHA and the content it must equal.
git show origin/development:docs/release-records/ios-1.0.4-1000035.md
git log --first-parent --format='%h %s' -5 origin/development -- docs/release-records/ios-1.0.4-1000035.md
#    The record arrived by merged pull requests. Its Status must allow the step you are about to do (Quick start).
#    Take APPROVED_SHA and CONTENT_REF from it. Compare with the SHA the coordinator and the
#    independent authorizer each wrote on Issue #71. All three must match, or STOP.

# 2. The commit exists, and is on the production branch.
git cat-file -t "$APPROVED_SHA"                 # commit
git merge-base --is-ancestor "$APPROVED_SHA" origin/production && echo ON-PRODUCTION

# 3. Build from exactly that commit, detached, nothing else.
git checkout --detach "$APPROVED_SHA"
test "$(git rev-parse HEAD)" = "$APPROVED_SHA" && test -z "$(git status --porcelain)" && echo SOURCE-OK

# 4. Its application content equals the reviewed content (empty output required).
git diff --stat "$CONTENT_REF" "$APPROVED_SHA" -- lib ios flutter_plugin pubspec.yaml pubspec.lock config/build android
```

A mismatch, an unreachable SHA, a SHA that differs between the record and the issue, or any
difference printed by step 4 means **stop and report**; do not look for another revision.
GitHub shows a "Verified" badge for merge commits made in the web interface; `git verify-commit`
needs the signing key and may print that it cannot check. Neither replaces the SHA agreement above
(the SHA and the record are the proof, `GOVERNANCE.md` section 3).

## 6. What the operator must confirm before signing

Answer each from the Apple account itself and record the answer in the release record, with
"unknown" if it is unknown ([APPLE_ACCOUNT_QUESTIONNAIRE.md](APPLE_ACCOUNT_QUESTIONNAIRE.md) holds
the longer list and says where answers go). **A stop answer ends the procedure until the
coordinator decides.** Do not send keys, certificates with private keys, `.p12`/`.p8`/profile
files, passwords or codes to anyone.

| # | Confirm | Stop if |
|---|---|---|
| 1 | The Apple Developer team you sign in as, its enrollment type (Organization or Individual), and that its Team ID is `D65458CPDP` | It is a different team |
| 2 | An App Store Connect app record exists whose bundle ID is **exactly** `com.app.cadenabitcoin`, its name, SKU and status | No record, or a different bundle ID |
| 3 | Whether an iOS version is live, its version, and the **highest build number ever uploaded** (including never-released builds) | The highest build is 1000035 or more, or 1.0.4 is closed to new builds |
| 4 | `com.app.cadenabitcoin` is registered as an App ID in that team, and the capabilities enabled on it. The app declares the `remote-notification` background mode and has **no** `aps-environment` entitlement ([IOS_SIGNING.md](IOS_SIGNING.md) section 3.4) | The capability state is not what the coordinator recorded as decided |
| 5 | Your role and access in the team (Users and Access), and whether you may upload builds and manage certificates and profiles | You lack upload access |
| 6 | Distribution certificate: which one signs, its **SHA-256 fingerprint** (a public value), expiry, creator, and who holds its private key | The fingerprint is unknown or differs from the record |
| 7 | Signing method (section 8): **automatic** (Xcode may create or refresh a certificate and profile in the team, with `-allowProvisioningUpdates`) or **manual** with an administrator-supplied certificate and App Store profile | You cannot say which |
| 8 | Agreements are accepted in the Developer portal and in App Store Connect | Any is pending |
| 9 | The export-compliance answer for this app (the app uses cryptography and HTTPS) and the App Privacy answers, **given by the owner and legal**, not by the operator. `ITSAppUsesNonExemptEncryption` is not set in `Info.plist`, so App Store Connect will ask for each build | No answer exists |
| 10 | Whether the privacy-manifest and push-entitlement findings of [IOS_SIGNING.md](IOS_SIGNING.md) section 3.2 were decided (accept as is, or change by a separate approved issue) | Undecided |
| 11 | Your Mac: macOS version, Xcode, SDK, Flutter, CocoaPods (section 7), and the iPhone(s) you will test on with their iOS versions | A required tool is missing |
| 12 | Whether a zero-value production test account may be created on the production backend, and who approves it (section 11) | No approval |

## 7. Required tools

| Tool | Required | Source |
|---|---|---|
| Xcode | **26.3 (17C529)**, the version that built the accepted CI runs. Another Xcode 26.x is allowed only as a deviation recorded in the release record. The iPhoneOS SDK must be **26 or later** (Apple's upload requirement) | [IOS_CI.md](IOS_CI.md) |
| Flutter | **3.35.3** stable, revision `a402d9a437`; Dart 3.9.2 | `CLAUDE.md` section 3 |
| CocoaPods | **1.17.0** | [IOS_CI.md](IOS_CI.md) |
| Python 3 (standard library only), `openssl`, `git`, `shasum`, `codesign`, `security`, `lipo`, `nm`, `strings`, `PlistBuddy` | present on the Mac | the tools below |
| Network | CocoaPods CDN, `SumSubstance/Specs` (git), Sumsub's `IdensicMobileSDK` zip, GitHub | [IOS_CI.md](IOS_CI.md) |

Do not upgrade, "modernize" or switch any of them (`CLAUDE.md` sections 3 and 7).

```bash
flutter --version            # Flutter 3.35.3, revision a402d9a437, Dart 3.9.2
xcodebuild -version          # Xcode 26.3, Build version 17C529
xcrun --sdk iphoneos --show-sdk-version     # 26.x
pod --version                # 1.17.0
```

## 8. Build, sign and export

Run from the clean checkout of section 5. Nothing here needs a secret typed into a command or a file.
Steps 1 to 4 are credential-free and need only G1; **step 5 uses the signing identity and needs G2.**

```bash
# 1. Dependencies, exactly as the lockfiles say.
flutter pub get --enforce-lockfile
(cd flutter_plugin/flutter_plugin && flutter pub get)

# 2. Static checks of the source (no Xcode needed). All must pass.
tool/verify_version.sh                       # RESULT: OK; iOS 1.0.4 / 1000035
/bin/bash tool/verify_build_config.sh verify
shasum -a 256 flutter_plugin/flutter_plugin/ios/Classes/libdlcplazacryptlib.a
#   203dcd7abe4187de0b756638a55f691b2d5c680b17d4fbfa7dda550ed703949b  (pinned; any other value: STOP)
python3 -I tool/build_manifest.py gate --channel production   # read section 4 before judging the result

# 3. Unsigned reference build, the same command CI runs. It is the comparison baseline for step 6.
flutter build ios --release --no-codesign --flavor production \
  --dart-define-from-file=config/build/production.json
tool/verify_artifact.sh ios production build/ios/iphoneos/Runner.app --min-sdk 26
mkdir -p "$WORK/unsigned" && ditto build/ios/iphoneos/Runner.app "$WORK/unsigned/Runner.app"

# 4. Drift rule. The build may rewrite ios/Podfile.lock on a Mac whose Ruby `json` gem differs from
#    the pinned runner (IOS_CI.md, "ios/Podfile.lock drift"). Only checksum lines may differ:
git status --porcelain                       # only ios/Podfile.lock may be listed
git diff ios/Podfile.lock | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
  | grep -vE '^[+-]  [A-Za-z_]+: [0-9a-f]{40}$|^[+-]COCOAPODS:'      # must print NOTHING
git diff ios/Podfile.lock > "$WORK/Podfile.lock.drift.diff"          # evidence; never commit it
git checkout -- ios/Podfile.lock             # restore, so the tree is clean again
#    Any other change to any tracked file, or any printed line: STOP and report.
```

**The export options.** Flutter's own generated export plist contains only `method` and
`uploadBitcode`. Xcode may then *manage the app version and build number* on export and
upload (reported default, see the note below), which could change `CFBundleVersion` behind your back. The following file, kept **outside**
the repository, switches that off and states the distribution method explicitly:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key>                          <string>app-store-connect</string>
  <key>teamID</key>                          <string>D65458CPDP</string>
  <key>manageAppVersionAndBuildNumber</key>  <false/>
  <key>uploadSymbols</key>                   <true/>
  <!-- Manual signing only (route B); omit these three for route A (automatic): -->
  <key>signingStyle</key>                    <string>manual</string>
  <key>signingCertificate</key>              <string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict><key>com.app.cadenabitcoin</key><string>NAME OF THE APP STORE PROFILE</string></dict>
</dict></plist>
```

- **`testFlightInternalTestingOnly` must not be present** (and must not be `true`). A build
  exported that way cannot later be submitted to App Review without a rebuild, which is exactly
  what the approved plan avoids. The same applies to the Xcode Organizer: choose the App Store
  Connect destination with **TestFlight & App Store**, never **TestFlight Internal Only**.
- **Unconfirmed against Apple's documentation:** the key names `manageAppVersionAndBuildNumber`
  and `testFlightInternalTestingOnly` and their defaults come from `xcodebuild -help` output
  quoted in developer forums, not from an Apple page the authors could read. Run
  `xcodebuild -help` on Xcode 26.3 and confirm both keys before use; the post-export check of
  section 9 (V1) catches a changed build number regardless.
- Flutter 3.35.3 does not accept `--export-method` together with `--export-options-plist`
  (verified in the pinned SDK, `build_ios.dart`).
- Route A (**automatic**) is the committed project style (`DEVELOPMENT_TEAM` set, no signing style
  override) and Flutter then passes `-allowProvisioningUpdates` to the export, so Xcode may create
  or refresh certificates and profiles in the Apple account. Route B (**manual**) uses an
  administrator-created distribution certificate and App Store profile already in your keychain.
  Which one is used, and who created the certificate, is recorded (section 6, items 6 and 7).

```bash
# 5. Signed archive and IPA, production flavor only, the committed configuration only.
flutter build ipa --release --flavor production \
  --dart-define-from-file=config/build/production.json \
  --export-options-plist "$WORK/ExportOptions.plist"
#    Output (verified in the pinned Flutter): build/ios/archive/Runner.xcarchive and build/ios/ipa/*.ipa
#    Run step 4's drift rule again if the working tree changed.

# 6. Fix the artifact: hash it now; retention is section 12 ("Temporary retention").
IPA=$(ls build/ios/ipa/*.ipa); shasum -a 256 "$IPA"
```

Never commit, attach, e-mail or upload the IPA, the archive, a profile, a certificate or a
keychain export to GitHub (Actions artifacts, issues, pull requests, Releases) or any chat.
GitHub is public ([RELEASE_POLICY.md](RELEASE_POLICY.md) section 8.2).

## 9. Verification before upload

All checks run on the **IPA that will be uploaded**, not on the build directory. Save every output
to `$WORK/evidence/` (section 12). Any failure stops the procedure; report it, do not work around it.

```bash
mkdir -p "$WORK/x" "$WORK/evidence" && unzip -q "$IPA" -d "$WORK/x" && APP="$WORK/x/Payload/Runner.app"
FINGERPRINT=<certificate SHA-256 recorded before the build, hex without colons>
```

| # | Check | Required result |
|---|---|---|
| V1 | Identity and version read from the IPA's `Info.plist` | Bundle ID `com.app.cadenabitcoin`, version `1.0.4`, build `1000035`, display name `Cadena Bitcoin`, exactly as the record |
| V2 | Signature seals | `codesign --verify` exits 0 |
| V3 | Signing identity | Authority `Apple Distribution: ...`, TeamIdentifier `D65458CPDP`, certificate fingerprint **equal to the one recorded before the build** (section 6, item 6) |
| V4 | Embedded profile | App Store profile: no `ProvisionedDevices`, no `get-task-allow`, team `D65458CPDP`, application-identifier `D65458CPDP.com.app.cadenabitcoin`, not expired |
| V5 | Entitlements | `get-task-allow` absent or false; application identifier and team as V4; every key granted by the profile. Record the full list; `aps-environment` appears only if the coordinator decided the push capability |
| V6 | Environment inside the app | The production URL occurs at least once; `staging.purabitcoin.com` occurs **0** times |
| V7 | This repository's IPA verifier | Every check passes |
| V8 | Only signatures were added | The signed bundle is the unsigned one plus signatures |
| V9 | Native library | Library SHA-256 as in section 8, and the symbol inspection below |

```bash
# V1
for k in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion CFBundleDisplayName; do
  /usr/libexec/PlistBuddy -c "Print :$k" "$APP/Info.plist"; done
# V2, V3
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -e Authority -e TeamIdentifier
security find-certificate -c "Apple Distribution" -Z        # SHA-256 of each matching certificate
# V4, V5 (the profile is read, never copied out of $WORK)
security cms -D -i "$APP/embedded.mobileprovision" > "$WORK/profile.plist"
codesign -d --entitlements :- "$APP"
# V6
strings -a "$APP/Frameworks/App.framework/App" | grep -c 'https://cadenabitcoin.com/app'     # >= 1
strings -a "$APP/Frameworks/App.framework/App" | grep -c 'staging.purabitcoin.com'           # 0
# V7, V8
python3 -I tool/verify_ipa.py verify production "$IPA" --team-id D65458CPDP \
  --expect-cert-sha256 "$FINGERPRINT" --unsigned-app "$WORK/unsigned/Runner.app" \
  --evidence "$WORK/evidence/ipa-verify.txt"
python3 -I tool/verify_ipa.py compare "$WORK/unsigned/Runner.app" "$APP"
```

**V7 and V8 have never seen a real Apple-signed IPA** ([IOS_SIGNING.md](IOS_SIGNING.md)
section 3.1): the first run may reject a legitimate detail of real Apple output (an entitlement
Xcode adds, the layout of nested `CodeResources`). A rejection is **reported with its full output**
and the build is not uploaded. A reviewed pull request may then add a documented, narrow allowance;
an ad hoc override, an edited verifier or a skipped check is never acceptable. `--trust-anchors`
(Apple's root and intermediate certificates, supplied and reviewed by the operator) is optional;
without it the issuer is compared by name and the leaf is pinned by fingerprint only.

### Native symbol-table inspection (Issue #22)

Purpose: confirm that the unsafe custom Schnorr signer is **not** in the iOS release. The checks were
dry-run on the committed library with `llvm-nm` (arm64 slice) and are expected to give these results.
Repeat them on the Mac with Apple's tools, on **both** the committed library and the built framework.

```bash
LIB=flutter_plugin/flutter_plugin/ios/Classes/libdlcplazacryptlib.a
lipo -info "$LIB"                                          # arm64 and x86_64
lipo "$LIB" -thin arm64 -output "$WORK/lib-arm64.a"
nm -a "$WORK/lib-arm64.a" > "$WORK/evidence/lib-arm64.nm.txt"

# (a) Names that must NOT exist (Rust-side signer, its nonce callback and wrapper): no output.
grep -E 'sign_schnorr_with_nonce|schnorrsig_sign_with_nonce|constant_nonce_fn' "$WORK/evidence/lib-arm64.nm.txt"

# (b) The C functions the library exports. Expected: exactly these nine.
nm -g --defined-only "$WORK/lib-arm64.a" | grep -E ' T _(create|free|get|init|sign)[a-z_]*$' | awk '{print $3}' | sort -u
#   _create_cet_adaptor_sigs_c  _create_deterministic_nonce_c  _free_cstring  _get_address_c
#   _get_public_key_c  _get_xpub_c  _init_from_file_c  _init_with_entropy_c  _sign_hash_ecdsa_c

# (c) The built app: the same names must not appear as exported symbols or strings.
FW="$APP/Frameworks/dlc_wallet.framework/dlc_wallet"
nm -gU "$FW" > "$WORK/evidence/dlc_wallet.exports.txt"
grep -E 'sign_schnorr_with_nonce|schnorrsig_sign_with_nonce|constant_nonce_fn' "$WORK/evidence/dlc_wallet.exports.txt"   # no output
strings -a "$FW" | grep -E 'sign_schnorr_with_nonce|schnorrsig_sign_with_nonce|constant_nonce_fn'                          # no output
```

How to read it, honestly:
- **Do not search for the word "schnorr" alone.** The library legitimately links the secp256k1
  C library, which defines `…schnorrsig_sign_custom`, `…schnorrsig_sign32`, `…schnorrsig_verify` and
  Rust `secp256k1::schnorr::Signature` code (seen in the dry run). Those are the primitive and the
  verification path, not the unsafe wrapper. The forbidden names in (a) are the Rust wrapper and its callback.
- **A stripped release binary cannot prove absence**, because Xcode removes local symbols. Check (a) on the
  unstripped committed library is the strong check; (c) is supporting evidence. The pinned SHA-256 of the
  library (section 8) ties the two together.
- Result in the dry run: **(a) no output; (b) exactly the nine functions**, including
  `_create_deterministic_nonce_c`.
- This is evidence about symbols, not a proof that no unsafe signing is reachable. The source review of Issue #22 for
  this release is in section 11.

### Secret logging check (during the device tests)

Capture the device log while the disposable wallet is created, imported and used (Console on the Mac
with the iPhone attached, or Xcode → Devices and Simulators → Open Console), save it, and search it
**on the Mac** for the secrets of the *disposable* wallet only: the full recovery phrase as one string, its
first four words in sequence, the account password, and the prefixes `xprv`, `yprv`, `zprv`, `tprv`, `vprv`.
**Required result: no hit.** Report counts, never the matches. Do not type the phrase into a command
line that is logged (read it from a file you create locally, then delete the file). Known and **not** secret:
the native iOS plugin logs signing hashes, signatures, public keys, nonce public values and the XPUB through
`NSLog` (`flutter_plugin/flutter_plugin/ios/Classes/DlcWalletPlugin.m`), which is looser than the "minimized"
rule of [SECURITY_BOUNDARY.md](SECURITY_BOUNDARY.md) section 2; record what you see, it does not by itself fail
this check.

## 10. Upload to App Store Connect

**Only after G2 is recorded** (section 1) **and every check of section 9 has passed.** Nothing in this
procedure submits for review.

1. Upload with **Apple's Transporter app** (the method Flutter's own output names), or Xcode Organizer
   → *Distribute App* → *App Store Connect* → **TestFlight & App Store** → *Upload*. **Never** *TestFlight
   Internal Only*. Sign in with your own Apple ID; no credential goes into a repository, script, chat or log.
2. `xcrun altool` is not used: it needs an App Store Connect API key (API access is reported disabled,
   [IOS_SIGNING.md](IOS_SIGNING.md) section 4) or an app-specific password
   ([IOS_SIGNING.md](IOS_SIGNING.md) section 5, option D, rejected).
3. Wait for processing. Read App Store Connect's messages and record each one (warnings such as a
   missing push entitlement are recorded and **not** dismissed; see section 13). Answer the export-compliance
   and privacy prompts only with the owner's decided answers (section 6, item 9).
4. In App Store Connect confirm the processed build shows **1.0.4 (1000035)** under the production record. Record
   the time and the build's status.
5. **Do not assign the build to any tester, and do not press "Submit for Review".** Tell the coordinator the build is
   processed. Assignment is G3, submission to App Review is G4, public release is G5.
6. After a maintainer confirms the number in App Store Connect, a reviewed pull request adds the iOS entry to
   `config/release/published_versions.json` (platform `ios`, bundle `com.app.cadenabitcoin`, version `1.0.4`,
   build `1000035`, status "uploaded to TestFlight"). Any entry raises the iOS floor
   (`tool/build_manifest.py`, `floor_for`), so the number cannot be reused; it records history and authorizes nothing.

## 11. Internal TestFlight evaluation and the conditions for App Review

**Approved, mandatory:** at least **12 hours of successful physical-device evaluation of the internal TestFlight build** must
be completed and evidenced **before submission to App Review (G4)**, and therefore before public release (G5). Simulators and
Xcode development installs do not count; the build is the one installed through TestFlight by a named internal tester. **Approved:** initial testing uses **disposable, zero-value wallet
material only**: a newly generated wallet, never a mnemonic that ever held value, never a wallet that will hold
value, and an account created for the test. The production build talks to the **production backend and mainnet**
(`config/build/production.json`), so a careless test is a real-world action.

**Proposed definition of the 12 hours** (to be confirmed by the coordinator): cumulative, timestamped time in which
the candidate build is installed from TestFlight on at least one physical iPhone and the plan below is being executed or
the app is idle in the background as part of it; the log of sessions (start, stop, device model, iOS version, activity)
is part of the evidence. At least one continuous overnight or idle interval is included, to exercise background
tasks. **A crash, an unexplained failure or a rebuilt candidate restarts the count for that build.**

| Test | What it shows |
|---|---|
| T1 Install from TestFlight on a clean device; first launch | Signing and entitlements accepted by the device; the background-task registration does not crash the app (the identifier `auto_signing_task` registered in `AppDelegate.swift` is not in `BGTaskSchedulerPermittedIdentifiers`; effect **untested**) |
| T2 Create a new wallet; verify the recovery phrase; restart the app | Wallet creation and persistence |
| T3 Import a disposable phrase on a second install or after deleting the app | Import path |
| T4 Sign in with the disposable account; camera permission and QR scan; notifications permission | Backend over HTTPS, camera, permissions |
| T5 Background and idle intervals, including overnight; reopen | Background fetch and task behaviour; no crash or lock-up |
| T6 Manual and automatic signing | **Not exercised unless a zero-value contract exists for the disposable account**; otherwise recorded as "not exercised", as in [SECURITY_BOUNDARY.md](SECURITY_BOUNDARY.md) section 4 |
| T7 Oldest iOS available; also a device below 15.5 if one exists | Whether the declared minimum is true (installation may be refused below 15.5, **not yet tried**) |
| T8 If a live App Store version exists: install the TestFlight build over it; check the keychain and wallet data survive | In-place update. The Android in-place update **failed with an unknown cause** ([ANDROID_RELEASE.md](ANDROID_RELEASE.md) section 9), so this is not assumed |
| T9 Device-log secret check (section 9) throughout | No secret in logs |
| T10 Crash reports (TestFlight feedback, device analytics) | Zero crashes |

**Necessary, not sufficient, for G4.** Submission to App Review additionally needs, each recorded:
the 12 hours and the table above with the evidence of section 12; the Issue #22 disposition (below); the
**effective minimum iOS version decided and tested** ([IOS_CI.md](IOS_CI.md), policy open decision 12); the
push-entitlement and privacy-manifest decisions; the export-compliance and privacy answers; the named independent
authorizer's explicit approval. **No test result in this document implies G4 or G5; public release (G5) is a further, separate authorization after App Review.**

### Issue #22: unresolved security consideration for this release

Facts (Verified in the repository at `5d90291`, which the library has not changed since the baseline `df269f6`):
- The custom Schnorr signer that derives its nonce from public data (`sign_schnorr_with_nonce`) is in the Rust
  source and is exposed only through the optional `with-pyo3` Python module. It is not a C export and not part of
  the iOS plugin, which handles only `signHashEcdsa`, `createCetAdaptorSigs` and `initWithEntropy`.
- **`create_deterministic_nonce_c` is a real C export** of the library, declared in `dlc_wallet_bridge.h` and wrapped
  by the Dart plugin (`createDeterministicNonce`, `createDlcSetup`). It returns a nonce **secret** that is a hash of a
  public string. **The application never calls it** (no caller in `lib/`; the iOS method channel does not expose it). It is
  **unused but present**, and it is the "nonce-generation helper" Issue #22 asks to remove.
- Sensitive logging named by #22 was removed by `9a37b8d` (Issue #37, 2026-10-06); runtime proof in this release is the check of section 9.

**Recorded as unresolved, not as resolved:** the helper stays in this release because removing it means changing the Rust
library and rebuilding native code, which this release does not do and which needs separate authorization (open PR #97
appears related and was not reviewed for this document). The #22 items beyond the iOS binary (Oracle and backend callers,
whether any real key used the unsafe API, the runtime sentinel tests, the exposure scope of earlier builds) remain open.
**The coordinator records, in the release record, an explicit disposition of #22 for this release; the independent
authorizer accepts or rejects it at G2.** Android's earlier publication is not such a disposition.

## 12. Evidence to return

Returned by the operator to the coordinator through the controlled channel named in the release record, and summarized in the release record
by a reviewed pull request. **Text and hashes only.** Never return: the IPA or archive, certificates, `.p12`/`.p8`, provisioning
profiles, keychain contents, passwords, recovery phrases, tokens, device logs with unredacted content.

| File or field | Content |
|---|---|
| Source | `APPROVED_SHA`, `git rev-parse HEAD`, output of the section 5 checks (including the empty diff) |
| Toolchain | Outputs of section 7 (Flutter, Dart, Xcode build, SDK, CocoaPods), macOS version |
| Static checks | `verify_version.sh`, `verify_build_config.sh verify`, library SHA-256, `gate` output, `verify_artifact.sh ios` output |
| Drift | `Podfile.lock.drift.diff` and the statement that the only differences were checksum lines |
| Artifact | IPA SHA-256 and size; the export options file (contains no secret) |
| Verification | Outputs of V1 to V9; `ipa-verify.txt`; the entitlement and profile summaries **without** profile contents |
| Symbols | `lib-arm64.nm.txt` result lines of (a) to (c), the nine exported names |
| Signing | Certificate SHA-256 fingerprint, expiry, signing route (A or B), who created the certificate |
| Upload | Time, tool used, App Store Connect messages (verbatim), processed build status, version and build as shown |
| Tests | Device models and iOS versions, the 12-hour session log, each test T1 to T10 result (pass, fail, not exercised), crash count, log-check hit counts |
| Decisions | The answers of section 6 and who gave them |

### Temporary retention of the signed artifacts

**Proposed; applies to 1.0.4 until the coordinator designates permanent storage in the release record.** The signed IPA, its
SHA-256 checksum and the verification evidence are kept, for audit and for investigating a failure, in access-controlled storage
**outside GitHub**. The IPA is not needed for App Review: the build submitted later is the one already processed in App Store
Connect.

1. **Never public.** Not a GitHub Actions artifact, release asset, pull-request or issue attachment, comment or log; no public link,
   link-shared drive or messaging attachment ([RELEASE_POLICY.md](RELEASE_POLICY.md) section 8.2,
   [IOS_SIGNING.md](IOS_SIGNING.md) section 2 item 8). No workflow is created to store it.
2. **What is kept**, in one directory `ios-1.0.4-1000035_<first 7 characters of APPROVED_SHA>`: the IPA; `SHA256SUMS`, written on the
   Mac right after the export (`shasum -a 256 *.ipa > SHA256SUMS`); and the `evidence/` text files of section 9. **Never kept
   there:** certificates, private keys, provisioning profiles, API keys, passwords, recovery phrases or device logs with content.
3. **Where.** The operator's Mac: FileVault on, the directory created under `umask 077`, not inside a synchronized cloud folder or a
   backup others can read. One **encrypted copy** (for example an encrypted disk image, `hdiutil create -encryption AES-256`) held by
   one custodian named by the coordinator; its passphrase is delivered by a different channel than the image and never written
   next to it or into a chat.
4. **Access.** Named people only (operator, coordinator, independent authorizer, the custodian); the list is in the release record
   (roles and storage kind, no secret). Every transfer is recorded (who, when, how). After every copy and before any use run
   `shasum -a 256 -c SHA256SUMS`; the IPA hash must equal the value in the record.
5. **What travels in the open.** Only text: the SHA-256 value and the evidence summaries enter the release record by pull request.
6. **Duration and deletion.** Nothing is deleted until the coordinator records the outcome of G4 and confirms the processed build in
   App Store Connect. The coordinator then records either a permanent arrangement (open, section 13) or secure deletion (date, by
   whom, method). A rejected or superseded build is kept until the coordinator records its disposition.

## 13. Failure modes, known limitations and open items

| You see | Meaning |
|---|---|
| Section 5 mismatch (SHA, ancestry, diff) | Wrong or tampered source. Stop |
| `Podfile.lock` drift beyond checksum lines, or any other tracked file changed | Dependencies differ from the approved set. Stop |
| Library SHA-256 differs | Not the approved native library. Stop |
| `verify_artifact.sh`/`verify_ipa.py` fail | See the note after the table in section 9; report, never bypass |
| Apple rejects the build number | Already used; do not edit it. Report; the coordinator decides through a reviewed `pubspec.yaml` change |
| `ITMS-90078` (missing push entitlement) | Documented ([IOS_SIGNING.md](IOS_SIGNING.md) section 3.2); record and report |
| A privacy-manifest message (for example `ITMS-91053`) | Possible (the app has no `PrivacyInfo.xcprivacy`; Apple's current enforcement is **Unconfirmed**); record and report |
| Missing export-compliance answer | Needs the owner's decision (section 6, item 9) |
| Expired profile or certificate | An administrator renews it in the portal; the verifier checks expiry |
| Certificate fingerprint differs from the record | Different identity from the one authorized. Stop |

**Known limitations (all Unconfirmed or open; none resolved by this document):**
- Signing is local to one Mac, outside a protected CI environment; no independent authorizer is designated; no certificate custodian is named.
- `verify_ipa.py` has never verified a real Apple-signed IPA; the first run may need a reviewed adjustment.
- The unsigned CI build proves compile and link only, not runtime ([IOS_CI.md](IOS_CI.md)).
- The effective minimum iOS version, the five 15.5 frameworks and the eight 18.5 Rust objects are unresolved.
- The Rust library's provenance is undocumented (Issue #89); the unused `create_deterministic_nonce_c` stays in it.
- The `NSLog` lines of the iOS plugin and the BGTask identifier mismatch are unresolved.
- The production gate has no per-platform mode (section 4); a reviewed tool change would add one.
- Retention of the signed IPA and the evidence is only the temporary procedure of section 12; a permanent custody arrangement is open.
- The `Xcode`-key names of section 8 and the Organizer wording of section 10 are Unconfirmed against Apple's documentation.

**What this document does not do:** it does not authorize signing, upload, tester assignment, submission to App Review or public
release; it does not select the release revision; it does not designate the independent authorizer; it does not change any
code, version or cryptographic material.
