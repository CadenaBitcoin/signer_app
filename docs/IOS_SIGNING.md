# iOS signing and TestFlight delivery (Issue #71)

> **Status: readiness documentation. iOS signing and TestFlight delivery are NOT
> implemented.** No certificate, provisioning profile, App Store Connect API key,
> App Store Connect record, GitHub environment or signing workflow has been created, and
> none may be created from this document alone. The only iOS builds that exist are the
> unsigned compile-validation builds of [IOS_CI.md](IOS_CI.md). This page records what is
> verified, what is approved, and what is still undecided, so that nobody mistakes one
> for another. Parent issue: #54. It follows [RELEASE_POLICY.md](RELEASE_POLICY.md) and
> [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) and adds no rule to
> either.

Every statement below carries one of three labels:

| Label | Meaning |
|---|---|
| **Verified** | Checked in the repository, on GitHub or in Apple's documentation, on the stated date. |
| **Approved** | Decided by the project owners. It is the architecture to build, not a statement of fact about the world. |
| **Unresolved** | Not decided, or not yet confirmable. Nothing may assume an answer. |

## 1. Verified facts (checked 2026-10-21 on `development` `b7e523a`)

### Repository

| Fact | Where |
|---|---|
| Two flavors exist, `staging` and `production`, with their own Xcode schemes and `Debug/Profile/Release-<flavor>` configurations. | `ios/Runner.xcodeproj`, `ios/Flutter/*-staging.xcconfig`, `*-production.xcconfig` |
| Bundle IDs: staging `com.app.cadenabitcoin.staging` ("Cadena Signer STAGING"), production `com.app.cadenabitcoin` ("Cadena Bitcoin"). | `ios/Flutter/Flavor-*.xcconfig` |
| `DEVELOPMENT_TEAM = D65458CPDP` is committed (an identifier, not a secret). The Runner target sets no `CODE_SIGN_STYLE`, profile specifier or signing identity, so Xcode's default (automatic) applies. | `ios/Runner.xcodeproj/project.pbxproj` |
| No entitlements file, no `ExportOptions.plist`, no certificate, profile, `.p8`, keystore or `key.properties` is tracked. | `git ls-files` |
| The app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). `CFBundleShortVersionString` and `CFBundleVersion` come from `pubspec.yaml` (`1.0.3+1000034`). | project, `Info.plist` |
| `Info.plist` has no `ITSAppUsesNonExemptEncryption`. It lists `UIBackgroundModes` `fetch` and `remote-notification` and one `BGTaskSchedulerPermittedIdentifiers` entry; there is no `processing` mode and no push entitlement. The app has no `PrivacyInfo.xcprivacy`. The App Store icon `1024.png` is a JPEG with a `.png` name. | `ios/Runner` |
| `RELEASE_IDENTIFIER` and an in-app staging identifier do not exist yet. | `lib`, `config`, `tool` |
| Both iOS workflows use `contents: read`, no secrets, SHA-pinned actions, `--no-codesign`. They run on `macos-15` with Xcode 26.3. | `.github/workflows`, [IOS_CI.md](IOS_CI.md) |
| The minimum-iOS requirement of [IOS_CI.md](IOS_CI.md) is open: app 14.0, five frameworks 15.5, eight Rust objects 18.5. | [IOS_CI.md](IOS_CI.md) |
| No iOS build number is recorded as published, so no iOS floor is enforced. The published **Android** package is `com.cadenabitcoin.mobile.signer`, which differs from the bundle ID used here. Git history shows the iOS bundle ID has never been anything but `com.app.cadenabitcoin`, so nothing in the repository shows what Apple has registered. | `config/release/published_versions.json`, `git log` |

### GitHub

| Fact | Source |
|---|---|
| The repository is **public**. Run logs and artifacts are readable by any GitHub account. | GitHub API |
| No GitHub environment exists (`total_count` 0). | GitHub API |
| `CadenaBitcoin/Maintainers` has two accounts. **They are controlled by one individual** (statement of the project owner, 2026-10-21), so they are **one** approver, not two. | owner statement; [GOVERNANCE.md](../GOVERNANCE.md) |
| No release maintainers or signing custodians are named. | [GOVERNANCE.md](../GOVERNANCE.md) |

### Apple (documentation read 2026-10-21)

| Fact | Source |
|---|---|
| There are two kinds of App Store Connect API key: team keys ("access to all apps, with varying levels of access based on selected roles") and individual keys ("access and roles of the associated user"). | [Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) |
| "Team keys give access that's not isolated to a single app, but individual key access is tied to the apps and permissions of the user." "Team API keys are applied across all apps, so app access can't be limited for an API key." | same; [App Store Connect Help](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api) |
| Individual keys "aren't able to use Provisioning endpoints, access Sales and Finance, or notaryTool". | [Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) |
| "Each user can only have one active API key at a time." A key's name and access cannot be edited after it is generated. Generating a team key needs the Account Holder or Admin role. Generating an individual key needs the "Generate Individual API Keys" permission, which an Admin can remove. | [App Store Connect Help](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api) |
| The private key can be downloaded **once**; Apple keeps no copy. A revoked key cannot be reinstated. | both pages |
| The role-permission matrix has rows "Upload builds", "Submit apps", "Manage internal TestFlight groups and add builds" and "Manage app access". Certificate and profile tasks are marked as needing access to Certificates, Identifiers & Profiles, "granted as a separate permission in Users and Access". | [Roles](https://developer.apple.com/support/roles/) |
| "Users with the Developer role can create and revoke development certificates, submit certificate signing requests, download provisioning profiles, upload binaries to App Store Connect, manage internal TestFlight users, and more. Their access can be limited to certain apps." | [Developer role](https://developer.apple.com/help/glossary/developer) |
| "If you're enrolled as an individual and add users in App Store Connect, users receive access only to App Store Connect and are not considered part of your team in the Apple Developer Program." | [Developer role](https://developer.apple.com/help/glossary/developer) |

The role matrix's per-role marks could not be extracted from the page text, so **which role may
upload, which may submit for review, and which needs Certificates, Identifiers & Profiles
access is not verified** here (section 4, item 3).

## 2. Approved architecture

Decided by the project owners (Issue #71 audit and approval, 2026-10-21). Staging and
production contexts and the five-artifact target are in [RELEASE_POLICY.md](RELEASE_POLICY.md).

1. **First delivery target: internal-only TestFlight** of a separate staging record. No
   external tester group, no public link, no Beta App Review, no App Store submission.
2. **Separate GitHub environments** for staging and production, each deployable from one
   protected branch only.
3. **No public App Store submission or publication** by any pipeline, ever; production
   signing and production upload each need **separate authorization**.
4. **Controlled signed testing is permitted** to establish runtime compatibility. The
   effective minimum supported iOS version remains an **open release-readiness
   requirement** ([IOS_CI.md](IOS_CI.md)); a production release needs verified runtime
   compatibility, and this issue does not change a deployment target.
5. **Independent approval of production** (section 6).
6. **Assigning a processed build to internal testers needs explicit approval** at first.
   Automatic distribution may be considered only after the pipeline has been verified.
7. **Least-privilege Apple authentication**, with app-restricted individual API
   credentials as the preferred direction. The model is **not final** (section 5).
8. Signed IPAs are never stored as GitHub artifacts, Releases or log content.

## 3. Planned pipeline (proposed; not built; shape subject to a spike)

Everything in this section, and every "will" or imperative in sections 5 to 8, describes the
intended design. None of it exists yet.

```text
push to staging (reviewed PR merge)
  -> build job, NO secrets: dependencies, compile, unsigned archive, digest
  -> signing job, environment staging-ios: sign, export, verify, record evidence
  -> upload to the staging App Store Connect record, read processing state
  -> STOP: a build is assigned to internal testers only after explicit approval
```

- **Two-job split (Proposed).** Everything that downloads or runs third-party code (`pod install`,
  Flutter, Gradle-style fetches) runs in a job with no secrets. The job that holds signing
  material runs only scripts owned and tested in this repository and Apple's own tools, and
  checks the archive digest produced by the first job. The unsigned archive would be a
  one-day artifact (it is the open-source app, like today's unsigned validation artifact).
  **Open technical question:** whether an unsigned archive can be exported and re-signed
  cleanly, or the signing job must codesign and package the IPA itself. A spike on a
  hosted runner with a throwaway self-signed identity (no Apple credentials) answers it. If
  it fails, a single job is the fallback and its extra exposure is documented. What is already
  established without Apple, and what the spike still has to show, is in section 3.2.
- **New workflow files** (stage T3 of [RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md));
  the unsigned validation workflows keep their meaning.
- **Verification before upload** (`tool/verify_ipa.py`, written and tested on synthetic fixtures,
  not yet used by any workflow; section 3.1): bundle ID, version and build number against
  `pubspec.yaml` and the manifest, Team ID, signing authority and certificate fingerprint,
  provisioning-profile type, team, App ID and expiry, entitlements (`get-task-allow` absent),
  signature integrity. Evidence is text only.
- **Build numbers** stay single-sourced from `pubspec.yaml`. Apple rejects a repeated build
  number, and the pipeline treats that as a hard stop, never as something to work around.
- A static test must fail if any workflow uses `pull_request_target`, or contains a
  review-submission or release call to App Store Connect.

### 3.1 IPA verification tooling (implemented 2026-10-22; not wired into any workflow)

| File | Purpose |
|---|---|
| `tool/verify_ipa.py` | `verify ENV IPA --team-id T`: the checks below. `structure APP_OR_IPA`: the same signature, entitlement and seal checks without judging the identity (used to read what Apple's `codesign` wrote). `compare UNSIGNED SIGNED`: is the signed bundle the unsigned one plus signatures only. `analyze-unsigned APP`: what re-signing a given unsigned bundle involves. |
| `tool/ipa_inspect.py` | The reader (Mach-O, code signature, CodeDirectory, entitlements, CodeResources, CMS, provisioning profile). Standard library plus the `openssl` command for CMS signature validity. Read-only; it needs no credential and no Xcode. |
| `tool/ipa_fixture.py` | **Test tooling only.** Synthetic apps, a throwaway certificate chain whose names say "Synthetic", a fake profile and a signer that writes the structures Apple's `codesign` writes. Nothing it makes is accepted by Apple or a device. |
| `tool/test_verify_ipa.sh` | 96 checks (97 with a real build): acceptance cases and about 70 rejections. `REAL_UNSIGNED_APP=...` also re-signs a real unsigned build. |
| `tool/test_ios_signing_experiment.sh` | 17 static checks of the hosted experiment (section 3.3). |

`verify` checks, from the IPA alone: bundle identifier, display name, version and build number for the
environment and `pubspec.yaml` (staging and production cannot mix); that every executable is signed
(not ad hoc) by **one** certificate for the expected Team ID; the CodeDirectory page hashes, special
slots (Info.plist, requirements, CodeResources, entitlements) and the bundle's CodeResources against
the files (nothing changed or added after signing); the CMS signature and that it binds every
CodeDirectory; the certificate (distribution certificate, Team ID, issuer, validity, SHA-256
fingerprint, **pinned** with `--expect-cert-sha256`, required for production); the embedded profile
(CMS signature valid, app-store type, no device list, exact App ID, team, not expired, contains the
signing certificate); the entitlements (application identifier, team, `get-task-allow` absent,
`aps-environment` production, every entitlement granted by the profile); the IPA digest handed over by
the signing job; and, with the build manifest and the unsigned bundle, that the manifest describes
that bundle and the IPA contains the same code with signatures only. Archives with unsafe member
names, links leaving the bundle or more than one app are refused.

| Evidence level | What it covers |
|---|---|
| **Verified on real data** (accepted run `39608182641`, its unsigned artifact) | The parser reads the real signatures: the Apple-signed Swift runtime library has two CodeDirectories (SHA-1 and SHA-256), `openssl` verifies its CMS signature, and the Apple "cdhashes" attribute lists both; page hashes, the Info.plist, requirements and CodeResources special slots and the `CodeResources` of Flutter's and `App`'s frameworks all match. |
| **Verified on synthetic fixtures** | Every check above, including the rejections: tampered executable, resource, Info.plist or CMS; added file; replaced alternate CodeDirectory; ad-hoc or unsigned code; foreign signer; wrong team, certificate, issuer, expiry or pin; missing, expired, ad-hoc, development, wildcard or foreign profile; entitlements not granted, `get-task-allow`, `aps-environment`; wrong bundle, version or environment; unsafe archives; manifest of another environment; recompiled or injected content. Breaking three of the checks on purpose made the matching test fail. |
| **Needs a real Apple-signed IPA** | The certificate chain to an Apple root and revocation (no Apple trust anchors are used); how Apple's `codesign` lists nested bundles in the app's `CodeResources` (each nested bundle is verified on its own; the outer linkage is not); the keys of a real App Store profile and of the entitlements Xcode adds (a missing grant is a failure here, so the first real IPA may need a documented, reviewed allowance); whether export rewrites any file (`compare` requires byte-identical non-executables and names any file that differs); the `SwiftSupport` folder. |
| **Needs Apple or a device** | App Store Connect validation and processing; installation and runtime behaviour. |

Every run prints what it cannot verify. A pass is evidence about the files, not an Apple approval.

**Genuine versus synthetic identities.** The issuer is compared **by name only** unless the operator
supplies `--trust-anchors` (the Apple root and intermediate certificates, kept and reviewed by the
operator; nothing here ships or assumes them), in which case the signing chain and the profile's signer
chain are verified with `openssl verify` at the time given by `--now`. A certificate whose name says
"Synthetic" or "Throwaway" is refused unless `--allow-synthetic` is given, and is **never** accepted for
production. Production also requires `--expect-cert-sha256`, the fingerprint from the custody register: a
pinned leaf certificate is the strongest statement this tool can make without Apple's trust anchors.

**Security review of the verifier (2026-10-22).** Thirteen ways to a false pass were found, each
reproduced against the first version (all thirteen passed it) and now rejected, with a regression test:
a CMS signature naming its signer by key identifier so that the pinned certificate could be listed first
and reported as the signer; a CodeDirectory hashing only the first pages of the file; data appended
after the signature; DER entitlements (the form the kernel enforces) differing from the XML ones, or
changed after signing; an executable not built for arm64; a 32-bit Mach-O skipped as "not code"; a
nested app extension that would need its own profile; a `..` path in `CodeResources`; a nested cdhash in
`CodeResources` that is not the nested code's; a nested binary signed again after the app was sealed
(the stale seal was filtered out as "covered separately"); files hidden in `_CodeSignature/`; a profile
for another platform. Also closed: a CMS signature read differently by this parser and by `openssl`
(the signer and the verified content are now the ones `openssl` used), a weak CMS digest, duplicate or
encrypted archive members, a non-plain `CFBundleExecutable`, and any internal error (it is a failed
verification, never a pass or a stack trace).

One rule was **removed** because real data contradicted it: non-zero bytes between the end of the
SuperBlob and the end of its reserved area. Real Apple and Flutter signatures leave stale data there
(seen in the accepted CI artifact), so refusing it would reject genuine IPAs; bytes after the reserved
area are still refused.

**Still unverified against a real Apple-signed IPA** (the first one may need a reviewed adjustment):
the DER-entitlements layout (decoded from public descriptions, tested on the fixtures only), how Apple's
`codesign` lists nested bundles in `CodeResources` (the hosted experiment, section 3.3, reads this from
a real `codesign` run), the keys of a real App Store profile, and whether a certificate chain from
Apple's real roots verifies as expected.

### 3.2 Signing-job separation: findings (2026-10-22, credential-free)

Question: can the existing unsigned build be signed and packaged in a separate job without recompiling?

**Established**
- The unsigned artifact of the accepted staging run contains 16 Mach-O files: 13 with no signature
  (including `Runner`), 2 ad-hoc signed (`Flutter`, `App`) and 1 signed by Apple (the embedded
  `libswift_Concurrency.dylib`, team `59GAB85EFG`, signing certificate valid until 2026-10-24). All 16
  must be re-signed with `--force` so that the app carries one identity; the old `_CodeSignature`
  folders of the sealed frameworks are replaced.
- Every one of the 16 has room for a signature without relinking. Re-signing the real artifact with the
  synthetic fixture signer left all 16 executables identical apart from the signature and all 76 other
  files byte-identical (`verify_ipa.py compare`), and the result passes all 56 checks of `verify` with a
  synthetic identity and profile. This shows the transformation is structurally possible and that the
  check for "no recompile, nothing injected" works on real build output.
- Flutter 3.35.3 can produce an unsigned **archive** without credentials: `flutter build ipa --no-codesign`
  runs the archive with `CODE_SIGNING_ALLOWED=NO`, skips the export, and still runs Flutter's app-icon and
  launch-image validation (from the Flutter source of the pinned version, not yet run here).

**Not established (needs macOS and, for the last two, Apple assets)**
- That Apple's `codesign --force` and `--entitlements` accept every one of these files the way the fixture
  signer does. `tool/spike_resign_unsigned_ios.sh` tests it with a throwaway identity in a throwaway
  keychain; it is written but **has not been run** (no macOS here).
- Which route the signing job takes: **A** manual `codesign` of the existing `Runner.app` (credential-free
  testable, as above, but the job must build the IPA layout, embed the profile and create `SwiftSupport`
  itself), or **B** `flutter build ipa --no-codesign` in the build job and `xcodebuild -exportArchive`
  with a manual-signing `ExportOptions.plist` in the signing job (Xcode lays out the IPA, but whether
  export accepts an archive that was built unsigned can only be tested with a real distribution
  certificate and profile). B also changes the build artifact from the validated `flutter build ios` output
  to an archive, so it needs its own validation run.
- That App Store Connect accepts either result.

**Apple's procedure and the two routes (research of 2026-10-22; sources at the end of this section)**

What could and could not be established. Apple's own documentation pages (TN3125 and the `xcodebuild`
documentation) are rendered by script and could not be read from here, so the statements below rest on
the pinned Flutter source, on a DTS engineer's answer, on Apple's archived Q&A 1886 and on developer
forum reports. **No Apple statement was found** on whether `xcodebuild -exportArchive` signs an archive
that was built unsigned, or on the order in which embedded code must be signed.

| | Route A: sign the existing `Runner.app`, build the IPA ourselves | Route B: unsigned `.xcarchive`, then Xcode's `-exportArchive` |
|---|---|---|
| Credential-free part | Everything: the experiment (section 3.3) exercises Apple's `codesign` on the real artifact | Producing the archive: `flutter build ipa --no-codesign` (pinned Flutter source) |
| Needs Apple assets to test | Embedding a real profile, entitlements, upload validation | The export itself: `-exportArchive` with `app-store-connect` needs the distribution certificate and profile |
| Apple-supported path | Not documented by Apple for this use; practised by third-party tools (not verified here) | Yes: export with an `ExportOptions.plist`; a DTS engineer lists the methods (`app-store-connect`, `release-testing`, ...) |
| Reports found | none beyond the mechanics | Developers report that an "empty-signed" archive can be exported with the signing done at export time, and one then hit ITMS-90078 (missing push entitlement) after upload: entitlements the archive was built without are not invented by the export |
| What we must supply | The IPA layout, `embedded.mobileprovision`, entitlements, the `SwiftSupport` folder | `ExportOptions.plist` (manual signing, profile per bundle ID), entitlements in the project (there is no entitlements file today) |
| Effect on the validated build | None: the input is the build of the accepted runs | The build artifact changes from `flutter build ios` output to an archive: it needs its own validation run |
| Verdict | Technically viable by the credential-free evidence; not yet shown to be accepted by Apple | Viable as the supported route; not yet tested with an unsigned archive; needs Apple assets |

Both routes need the entitlements decided: `Info.plist` declares the `remote-notification` background
mode and the project has no entitlements file, so a push entitlement (`aps-environment`) is currently
nowhere (questionnaire B3). Neither route can be chosen on credential-free evidence alone; the choice
and the first real IPA need the Apple account.

**The Apple-signed Swift runtime library.** `Frameworks/libswift_Concurrency.dylib` is the back-deployment
copy of Swift Concurrency (the app's minimum iOS is 14.0, below the iOS 15 that ships it). The copy in the
artifact is signed by Apple (team `59GAB85EFG`, certificate "Software Signing"). Whether to re-sign it is
**not assumed**; the evidence is:
- Apple's archived Q&A 1886 documents that on a device an embedded Swift library whose signature does not
  carry the app's Team ID is refused ("mapped file has no team identifier and is not a platform binary");
  it concerns a missing team identifier, not a foreign one, so it does not settle the foreign-team case.
- Xcode's own embed step signs the Swift libraries it copies with the target's identity (reported in forums
  and visible in the `swift-stdlib-tool --sign` usage text); an export is generally understood to re-sign embedded code too (not verified here).
- `codesign --verify` does not judge team-identity consistency; the kernel does, at load time.
So re-signing it with the app's identity matches what Xcode does and is the working hypothesis, but only a
device run (the controlled internal TestFlight build, or a development build) can show whether leaving it
alone would also load. The experiment therefore runs **both** variants and reports the team identifiers it
finds; it does not decide.

Sources: Flutter 3.35.3 `build_ios.dart` (pinned SDK; `--no-codesign` skips the export);
[Apple Developer Forums, `method` values of `xcodebuild -exportArchive` (DTS engineer)](https://developer.apple.com/forums/thread/773749);
[Apple Developer Forums, signing an empty-signed archive at export (community; no Apple answer)](https://developer.apple.com/forums/thread/686345);
[Apple Q&A 1886 (2015), Swift libraries and the Team ID](https://developer.apple.com/library/archive/qa/qa1886/_index.html);
[Apple Developer Forums, re-signing an IPA and the `SwiftSupport` folder](https://developer.apple.com/forums/thread/94151).

**Obstacles and risks found**
- `Info.plist` declares `UIBackgroundModes` `remote-notification`: the App ID then needs the Push
  Notifications capability (`aps-environment`), otherwise App Store Connect warns (questionnaire B3).
- `ITSAppUsesNonExemptEncryption` is absent: the export-compliance question is asked at upload (questionnaire A6).
- The app has no `PrivacyInfo.xcprivacy` (Flutter and FingerprintPro frameworks have one).
- Third-party frameworks (Idensic, FingerprintPro) are unsigned vendor binaries that will be signed by us;
  a vendor's signature requirement, if any, is not known.
- The first real IPA will probably need one reviewed adjustment of the verifier (see "Needs a real
  Apple-signed IPA" above); that is the purpose of verifying before uploading.

### 3.3 Hosted feasibility experiment (prepared 2026-10-22; NOT RUN)

`.github/workflows/ios-signing-feasibility.yml`, started by hand only (`workflow_dispatch`):

1. selects Xcode 26.3 on `macos-15` (the pins of the iOS build workflows) and downloads the **existing**
   unsigned staging `Runner.app` from a chosen earlier "iOS CI validation build" run (default: `39608182641`),
   after checking that the run is of that workflow, succeeded and belongs to this repository, and that the
   inner `Runner.app.zip` has the SHA-256 given as input (default: the one in that run's `SHA256SUMS.txt`).
   Nothing is rebuilt;
2. verifies that input with `tool/verify_artifact.sh ios staging`;
3. `tool/spike_resign_unsigned_ios.sh`: a throwaway self-signed identity in a throwaway keychain; Apple's
   `codesign --force ... --timestamp=none` (no timestamp server is contacted) on nested code first, then the
   app with entitlements; two variants (all Mach-O files re-signed / the Apple-signed Swift runtime copy left
   alone); test IPAs packaged; Apple's `codesign --verify --deep --strict`; `tool/verify_ipa.py structure`
   (does our reading of what Apple wrote agree with Apple: CodeDirectory, special slots, CMS, **DER
   entitlements, `CodeResources` layout**); `tool/verify_ipa.py compare` (the executables are byte-identical
   to the build apart from the signatures, nothing added);
4. deletes the keychain and the identity, checks that they are gone, deletes the test IPAs.

It uses no Apple credential, certificate, profile or App Store Connect key, no secret, no environment, contacts
no Apple service, uploads **nothing** (no Actions artifact at all) and cannot be started by a push or pull
request; `tool/test_ios_signing_experiment.sh` checks all of this statically. **A pass does not prove Apple distribution
compatibility**: the identity is self-signed, there is no profile, and neither `xcodebuild -exportArchive`, the
App Store nor a device is involved. What it can establish: Apple's `codesign` accepts every Mach-O of this
application, the result verifies, the code is unchanged, and the verifier's reading of real Apple output
agrees (closing two of the "unverified" items above). Run it only after review of this page (it has not been
run, and the script it calls has only been exercised on Linux with stand-ins for the macOS commands).

### 3.4 Stage C: audit of the staging prerequisites (2026-10-22; read-only, nothing changed)

| Requirement | Finding | Needed |
|---|---|---|
| In-app staging identification | A "Test Environment: you are using Signet environment" banner appears on the Home screen only, and only because the build is Signet (`AppController.USE_TESTNET`). Nothing in the app says "STAGING", names the API host or shows a version, and the wallet creation and seed screens have no indicator. The launcher name "Cadena Signer STAGING" is outside the app. | An indicator on every screen that handles keys (design and approval; sensitive code, `CLAUDE.md` section 6). |
| Installed application version | Not available in the app. There is no `package_info_plus` dependency and no compile-time version define. "App: x \| API: y" on the Home screen shows the backend's *newest app version*, not the installed one. `RELEASE_IDENTIFIER` and its scheme do not exist (`RELEASE_POLICY.md` open decision 6). | A decision: `package_info_plus` (changes `pubspec.lock`), a define in the committed configuration (changes `BuildConfig`), or a platform channel. |
| Signet XPUB and address validation | Derivation is network-consistent by construction (Signet version bytes `0x045f1cf6`, path `m/84'/1'/0'`, `tb` addresses; the mainnet equivalents otherwise, all from `USE_TESTNET`). Nothing validates an externally supplied XPUB or address: `isValidBitcoinAddress` is unused and accepts only mainnet forms; the backend XPUB is compared with the local one as a string. Address checks inside the Rust library were not read (out of scope). | A pure Dart validator (prefix and address HRP must match the build) and the first `test/` directory; sensitive code. |
| Staging/production mixing | Satisfied at build time: `BuildConfig` fails on any inconsistency, the flavor must equal `APP_ENV`, the bundle IDs differ, and `verify_version`, `verify_artifact`, the build workflows and now `verify_ipa.py` check it. Open: the missing in-app indicator and the finding below. | |
| Background-task identifier | `ios/Runner/Info.plist` permits `com.app.cadenabitcoin.auto_signing_task`, but `AppDelegate.swift` registers `auto_signing_task`, and the same production-style name is permitted inside the staging bundle. iOS requires a registered identifier to be in the permitted list; the effect on a device (a failed registration or a crash) was **not tested**. | A decision and a device test; the controlled internal TestFlight build will exercise it. |
| Push entitlement | `UIBackgroundModes` includes `remote-notification`, but the project has no entitlements file (`aps-environment`). | The Push Notifications capability decision (questionnaire B3) before either signing route. |

No application code was changed for any of these.

## 4. Unresolved decisions and prerequisites

| # | Item | Needed from |
|---|---|---|
| 1 | Apple account identity, ownership, administrators, renewal | Apple account owner (questionnaire part A) |
| 2 | Whether an iOS app is live, its exact bundle ID, version and highest build number; whether `com.app.cadenabitcoin` is that ID | Apple account owner. **No production signing work starts until this is known.** |
| 3 | The role matrix: which role can upload a build, read processing status, and submit for review; whether a restricted service user can be created without Certificates, Identifiers & Profiles access, and who would hold its Apple ID sign-in | Apple account owner (the live Roles page and Users and Access) |
| 4 | App ID registration and App Store Connect record for `com.app.cadenabitcoin.staging` (not assumed registered) | Apple account owner |
| 5 | Existing distribution certificates, profiles and their custodians; shared or per-context certificates | Apple account owner, signing custodians |
| 6 | Capabilities and entitlements the app really needs (`remote-notification`, background tasks) | Apple account owner, maintainers |
| 7 | Export-compliance answer and App Privacy answers; then `ITSAppUsesNonExemptEncryption` in `Info.plist` (a native-config change, separate approval) | Apple account owner, legal |
| 8 | Internal tester list and who administers the tester group | Apple account owner |
| 9 | Release authority, signing custodians, and a second, independent approver (section 6) | project owners |
| 10 | Release identifier scheme, in-app staging identifier, Signet XPUB/address validation (prerequisites of [RELEASE_POLICY.md](RELEASE_POLICY.md) 8.1) | maintainers; separate issues |
| 11 | Whether the staging environment needs reviewers beyond the protected-branch merge (staging should require approval at first) | project owners |
| 12 | The effective minimum iOS version and its device testing | product decision; [IOS_CI.md](IOS_CI.md) |

## 5. Apple authentication model (investigated; not final)

Goal: the credential in the pipeline must be able to upload a build and read its processing
state, and must **not** be able to submit for review, release, create certificates or touch
another app. The model is **not finalized** before items 2 and 3 of section 4 are confirmed.

| Option | Isolation | Notes |
|---|---|---|
| **A. Team API key** | None: "access to all apps"; only the role limits it | Every team key reaches the production app too. Rejected as the staging credential, because a staging leak would reach production data. |
| **B. Individual API key of a dedicated, app-restricted service user (Preferred, to be confirmed)** | The key has "the access and roles of the associated user", so it is limited to the apps that user may see | One active key per user, so staging and production need **two** service users. No Provisioning endpoints, so it cannot create certificates (an advantage). Needs the "Generate Individual API Keys" permission, and the user's role must allow the upload. |
| C. Admin-level key or Xcode cloud-managed signing | None | Rejected: far above what an upload needs. |
| D. Apple ID app-specific password | A personal account | Rejected. |

Open points the account owner must confirm: that a service user can be restricted to the
staging app only; the lowest role that still shows **Upload builds**; that this role does not
show **Submit apps**; and that the organization accepts a dedicated service user. If B is not
possible, the fallback is the lowest-role team key, with the loss of app isolation recorded
and compensated by reviewer approval on the staging environment.

### Certificates, Identifiers & Profiles (CIP) access

- **The preferred credential cannot reach provisioning.** Individual keys "aren't able to use
  Provisioning endpoints" (section 1). The pipeline therefore can never create or download a
  certificate, a profile or an App ID with it, and it must not be designed to. This is a
  least-privilege advantage, and it has a cost: the distribution certificate, the provisioning
  profiles and the App IDs are created by the Apple account administrator **in the developer
  portal** (a role with CIP access) and handed to the custodians as environment secrets.
  Profiles and certificates expire, so renewal is a **manual administrator task**, scheduled
  in the custody register; `tool/verify_ipa.py` checks expiry so that a lapse fails
  visibly before an upload.
- **The service user must not receive CIP access.** The Developer role can, with that access,
  create and revoke development certificates and download profiles (section 1). The service
  user exists only to hold an upload-capable individual key limited to the staging app, so it
  gets no CIP access, no user-management permission and no access to other apps.
- **The service user is an Apple ID.** Someone must sign in once, with its second factor, to
  generate the key. Who holds that Apple ID's credentials and second factor, and how they are
  recovered, is a custody question for the account owner (questionnaire B4); the credentials are
  never shared with the pipeline or the repository.
- **Individual enrollment caveat.** If the team is an Individual enrollment, users added in
  App Store Connect are not part of the Developer Program team (section 1). Whether such a user
  can hold the upload role and generate an individual key is unconfirmed, and portal access is
  then limited to the Account Holder. If so, this model may be unavailable and the fallback of
  this section applies. Questionnaire A1 question 1 decides it.

The `.p8` is shown once; it is handed to the custodians through a secure channel, never through
chat, email, issues or the repository.

## 6. Independent approval of production signing and delivery

The two `Maintainers` accounts are controlled by one individual. **Accounts controlled by the same
individual are one approver, however many accounts exist.** Therefore:

- A GitHub environment's "required reviewers" and "prevent self-review" settings **cannot** by
  themselves provide independent approval while every eligible reviewer is the same person.
- **Production signing and production delivery must be approved by a person who is not the
  person who prepared, merged or triggered the run.** At least one such second human must be
  named (release authority or signing custodian) and added as a reviewer of `production-ios`
  **before** any production signing is authorized. Until then production signing stays
  disabled, and the production environment is not created.
- The same custodian separation applies to secrets: nobody is the only holder of a credential
  that can ship the production app (see [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) section 7).
- Staging can start with one human, but should still use a required reviewer so that a run is
  an explicit act. Independence is not claimed for it.

## 7. Public-repository security model

The repository is public. Anyone can read workflow logs, download artifacts, fork, and open
pull requests. The rules below are **requirements for the future signing workflows**. Today's
unsigned validation workflows already use `contents: read`, SHA-pinned actions and no secrets;
no signing workflow, environment or secret exists.

| Threat | Rule |
|---|---|
| Secrets or binaries leaving through logs and artifacts | No IPA, profile, certificate or key in an artifact, Release, comment or log. Only digests, fingerprints and verification text. No `set -x` near secrets. Derived values (a decoded profile, a base64 string) are never printed; masking only covers exact matches. |
| Pull requests from forks and from branches | No secret reaches them. Environments are restricted to one protected branch. No `pull_request_target`, and no `workflow_run` against untrusted code. |
| A contributor with Write access edits a workflow on a branch | The environment's deployment-branch rule refuses it. `staging` and `production` change only by reviewed pull request. |
| Third-party code seeing secrets | Two-job split (section 3). Actions pinned by SHA. No third-party action receives signing material. |
| Unsafe runners | GitHub-hosted, ephemeral runners only. **No self-hosted runner on this public repository.** |
| Credential scope | `GITHUB_TOKEN` is `contents: read`. Secrets only at environment level, never repository or organization level. Environment secrets are administered by Organization Owners only. The keychain is temporary and deleted in an `always()` step. |
| Tokens | A short-lived (20 minutes or less) JWT is derived per run from the `.p8`. |
| Accidental commits | Ask the Organization Owners to enable secret scanning and push protection. |
| Concurrency and duplicates | One upload at a time per environment; a build number already present is refused before upload. |
| Public publication | The credential cannot submit for review (section 5), the workflows contain no such call (tested), and production upload needs independent approval (section 6). |

## 8. Operating procedure (skeleton; every step is planned, none exists yet)

| Who | What |
|---|---|
| **Automated (after the pipeline exists and is approved)** | Build, sign, verify, record evidence, upload to the staging record, report processing state. |
| **Needs explicit authorization** | Starting a staging run (reviewer), assigning a processed build to internal testers (initially), any production signing, any production upload (independent approver). |
| **Apple account administrator (Noah)** | App IDs, App Store Connect records, certificates, profiles, service users and their keys, tester group, agreements and renewal, export-compliance and privacy answers. Not required to build or sign locally. |
| **Cadena maintainers** | Review and merge, workflow changes, environment settings (Owners), custody register (no secrets in the repository). |

- **Failed upload:** read the job's text evidence and the processing state; the commonest
  causes are a repeated build number, an expired or mismatched profile, a missing compliance
  answer, or a validation message from Apple. Fix the cause in a reviewed change; never rerun
  by editing a number outside `pubspec.yaml`.
- **Superseded build:** a newer reviewed version replaces it; the old build is expired in
  TestFlight by the account administrator. Build numbers are never reused.
- **Rotation and revocation:** revoke a leaked `.p8` immediately in App Store Connect (a
  revoked key cannot be reinstated); revoke a leaked certificate and re-sign; rotate secrets
  in the environment; record the event in the private custody register. A recovery drill is
  scheduled as in [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) section 7.

## 9. What can proceed without Apple credentials

| Work | Notes |
|---|---|
| This documentation and the questionnaire | Stages A and B. |
| Static workflow guards (no `pull_request_target`, no review-submission calls, explicit permissions, pinned actions) | Linux-testable. |
| `tool/verify_ipa.py` and its fixtures | **Done** (section 3.1), not yet wired into a workflow. |
| Signing spike with a throwaway self-signed identity; unsigned archive job; privacy-manifest check of the pods | Linux part **done** (section 3.2). The macOS part is prepared (`tool/spike_resign_unsigned_ios.sh`, not run); it proves plumbing, not Apple acceptance; a hosted run needs separate approval. |
| Release identifier scheme, in-app staging display, Signet validation | Separate issues, partly sensitive code. |
| Everything that needs a real certificate, profile, API key or App Store Connect record | Blocked on section 4 items 1 to 5. |

Questionnaire: [APPLE_ACCOUNT_QUESTIONNAIRE.md](APPLE_ACCOUNT_QUESTIONNAIRE.md).
