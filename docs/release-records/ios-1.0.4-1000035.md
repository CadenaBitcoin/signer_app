# Release record: iOS 1.0.4 (1000035), G1 AUTHORIZED (source only)

> **Record Status: `G1 AUTHORIZED`: the source commit only.** Apple distribution signing, upload to App Store Connect
> (G2), assignment to testers (G3), App Review (G4) and public release (G5) are **NOT authorized**. G1 accepts no security
> risk and decides none of the dispositions of section 4; Issue #22 stays open. Section 3 holds the verified evidence for the
> approved source. A blank or "TBD" is a stop, never a default. Procedure: [../IOS_RELEASE.md](../IOS_RELEASE.md); this file holds only what is specific to
> this release. It contains no secret, no key material and no credential, and must never receive
> one. Counterpart of [../ANDROID_RELEASE.md](../ANDROID_RELEASE.md) section 9.

## 0. Record status

Allowed values: `DRAFT`, `G1 AUTHORIZED`, `G2 AUTHORIZED`, `WITHDRAWN` (IOS_RELEASE.md section 3). Changed only by a reviewed
pull request; `M` (section 3 below) never changes after G1 without a new G1.

**Record Status: `G1 AUTHORIZED`**

Set by this record's pull request on the strength of the coordinator's G1 comment on Issue #71 (section 3.1), after the record
had been on `development` as `DRAFT` (PR #103). Under IOS_RELEASE.md (Quick start, section 3) this status lets the operator
retrieve and verify the source and make the unsigned build only. It does **not** allow signing or upload: those need G2
(section 6), which is pending.

## 1. Fixed by the repository (not an authorization)

| | |
|---|---|
| Platform, channel | iOS, App Store Connect / TestFlight (production record, first delivery internal only) |
| Bundle ID | `com.app.cadenabitcoin` (display name "Cadena Bitcoin") |
| Version / build | `1.0.4` / `1000035` (`pubspec.yaml`; Android already published 1.0.4 (1000035); the ledger has no iOS entry) |
| Configuration | `config/build/production.json`: `APP_ENV` `production`, `NETWORK_ENVIRONMENT` `bitcoin`, `USE_TESTNET` `false`, `API_BASE_URL` `https://cadenabitcoin.com/app`; SHA-256 `4b640c4fac2ba9cdde8526d2ed36aab80ec3835679eedba4052f5c094d610409` |
| Reviewed content (`CONTENT_REF`) | `862831e0b3a0f30c4155d2e086c69fc28bdab286` (`development`, merge of PR #97; includes PRs #97, #98 and #99) |
| Unsigned compile validation of `CONTENT_REF` | run `43210431581`, `ios-production`, success (compile and link only; no signing, no runtime evidence) |

## 2. Roles for this release (names or accounts; no role is implied by another)

| Role | Held by | Date confirmed |
|---|---|---|
| Release coordinator | CTO (`sziller`) | 2026-11-12: the G1 comment on Issue #71 (section 3.1) states "As CTO and release coordinator"; it was posted from the GitHub account `CadenaWizard` |
| Apple-side operator | Noah, intended | TBD (Noah's acceptance is not yet recorded) |
| Independent release authorizer (not the coordinator, not the operator) | **Not designated.** A candidate is under consideration; nobody is appointed and nobody has accepted | TBD |

A person becomes the authorizer only when this record names them after their explicit acceptance.

## 3. Approved source (G1, by the release coordinator) and its verified evidence

### 3.1 Approved source (G1)

| | |
|---|---|
| `APPROVED_SHA` = `M` (a `production` merge commit; never the commit of a record pull request) | **`42d358a4e7bcbf85b92aa992ec6439214dbd4405`** (version `1.0.4+1000035`) |
| Content reference | `CONTENT_REF` `862831e0b3a0f30c4155d2e086c69fc28bdab286` (section 1); proof of equality in 3.2 |
| G1 decision | "G1 APPROVED — Source selection only" |
| Authorizing account and date | GitHub account `CadenaWizard`, which states "As CTO and release coordinator"; comment created 2026-11-12T19:21:05Z, never edited (created and updated times are equal) |
| Written on Issue #71 by the coordinator | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-6833584989 (comment id 6833584989); it names `42d358a4e7bcbf85b92aa992ec6439214dbd4405`, version `1.0.4+1000035`, staging run `43214314837`, production run `43279190732`, and states that signing, TestFlight upload, App Review and public release are not permitted by it and that #22 and the later gates remain pending |
| Written on Issue #71 by the independent authorizer | TBD (none exists; required before G2) |

The SHA in the comment equals the SHA of this record, `git rev-parse origin/production` and the merge commit of PR #102 when this
record was prepared. A different `M` after this point is a new G1: set `WITHDRAWN` and start again (IOS_RELEASE.md section 3).

### 3.2 `M` and what was verified (2026-11-12, read-only verification; the decision is in 3.1)

| | |
|---|---|
| Production commit | `42d358a4e7bcbf85b92aa992ec6439214dbd4405` = tip of `production` at verification time and when G1 was recorded |
| How it got there | PR #102 (`staging` into `production`), **merge commit**, signature verified by GitHub; parents `fceeb667e04fd7b4f582d0aa9027ae0e06477237` (previous `production`) and `f7e0bd5902e2046b64ef59c6c5ce7467eeec95ee` (`staging`) |
| Staging step | PR #101 (`development` into `staging`) produced `f7e0bd5902e2046b64ef59c6c5ce7467eeec95ee`; its parents are the previous `staging` tip (`a4df412…`) and `d6238bf19547c8b55b37e9a3ae5abb9030e153ad` |
| Source tree | `5f18173ea3382fc96eb2572e6b73b0d8c32e363f`, identical for `42d358a`, `f7e0bd5` and `d6238bf` (`git diff` between them is empty) |
| Content equals `CONTENT_REF` | `git diff --stat 862831e0b3a0f30c4155d2e086c69fc28bdab286 42d358a4e7bcbf85b92aa992ec6439214dbd4405 -- lib ios flutter_plugin pubspec.yaml pubspec.lock config/build android` printed nothing. The two commits differ only in `docs/IOS_RELEASE.md` and this record |
| Native library | `flutter_plugin/flutter_plugin/ios/Classes/libdlcplazacryptlib.a`, SHA-256 `203dcd7abe4187de0b756638a55f691b2d5c680b17d4fbfa7dda550ed703949b` (the file the podspec vendors and the CI hashes; unchanged; the pinned binary, not a rebuild). The repository holds further copies in `device/` and `simulator/` that the podspec does not reference; the operator confirms in the build which one is linked |
| Podfile.lock | `ios/Podfile.lock` is identical at `42d358a` and `d6238bf`; CI drift check: none (diff 0 bytes) |

### 3.3 Hosted CI evidence (compile and link only)

| Run | What | Result |
|---|---|---|
| `43214314837` | `build-variants`, push to `staging` at `f7e0bd5`; selected exactly `android-staging-apk` and `ios-staging` | success; `build_manifest.py verify-dir` OK for both and the cross-checks |
| `43279190732` | `build-variants`, push to `production` at `42d358a`, attempt 1; selected exactly `android-production-apk`, `android-production-aab`, `ios-production` | success; `build_manifest.py verify-dir --repo` OK for all three and the cross-checks (re-run on a fresh checkout of `42d358a`) |
| `43214314838` / `43214314751` | Android / iOS CI validation on `staging` at `f7e0bd5` | success |
| `43210431581` | `ios-production` on `CONTENT_REF` | success (section 1) |

Production run `43279190732`: jobs `android-production-apk` (131396218340), `android-production-aab` (131396218335) and
`ios-production` (131396218408) succeeded. GitHub keeps the evidence artifacts until 2026-11-26; they are text and manifests,
not release artifacts, and are not the retention of IOS_RELEASE.md section 12: `build-evidence_android-production-apk_a1`
(13973605131), `build-evidence_android-production-aab_a1` (13973015679), `build-evidence_ios-production_a1` (13970774833) and
`ios-diagnostics_ios-production_a1` (13971034423).

`ios-production` manifest (`cadena-build-manifest/1`, classification `compile-validation`):

| | |
|---|---|
| Source | commit `42d358a4e7bcbf85b92aa992ec6439214dbd4405`, ref `production`, event `push`, `release_id` null; build id `43279190732.1:ios-production` |
| Version | pubspec `1.0.4+1000035`; platform version `1.0.4`, build `1000035` |
| Identity | `com.app.cadenabitcoin`, "Cadena Bitcoin", environment `production`; production URL present and staging URL absent in the built app |
| Command | `flutter build ios --release --no-codesign --flavor production --dart-define-from-file=config/build/production.json` |
| Toolchain | Xcode 26.3 (17C529), iPhoneOS SDK 26.2, Flutter 3.35.3 (a402d9a437), Dart 3.9.2, CocoaPods 1.17.0, runner `macos15` arm64 |
| Native library | `203dcd7abe4187de0b756638a55f691b2d5c680b17d4fbfa7dda550ed703949b` |
| Deployment targets | app 14.0; frameworks between 12.0 and 15.5; 5 known conflicts reported; Rust objects up to 18.5 (known open item, IOS_RELEASE.md section 13) |
| Signing | `unsigned`, `distributable=no`; `Runner.app` directory-manifest SHA-256 `86fea16b5087ca78e5d893d179c6c773bfb46ac186e98ac81505d80948a192fa` (a hash of the unsigned directory; no installable artifact exists and none was kept) |

The Android variants of the same run are `com.cadenabitcoin.mobile.signer`, `1.0.4+1000035`, debug-signed, not distributable.
`tool/build_manifest.py gate --channel production` prints PASS for iOS and FAIL for Android (1000035 is already published there);
that is the documented expected result (IOS_RELEASE.md section 4).

**What this does not prove.** No code signing, no entitlements or provisioning, no archive or IPA, no App Store Connect
validation, and no runtime or device behavior. The unsigned build cannot show that the app starts on a device.

## 4. Dispositions and accepted deviations

G1 decides none of these and accepts no security risk. None of these is decided. "Proposed" means the coordinator suggests it; it takes effect only when the decision, the name and
the date are filled in by the stated role in a reviewed pull request.

| Item | Status / decision | By | Date |
|---|---|---|---|
| Issue #22 for this release (IOS_RELEASE.md section 11). **#22 stays open.** The deterministic-nonce helper was removed from the source interfaces (PR #97) but **remains in the precompiled library**; no call path to it has been identified. PR #97 is not a remediation of the binary | Open; no disposition decided | TBD | TBD |
| **Proposed:** retain the existing pinned native Rust binary for the 1.0.4 TestFlight candidate; no rebuild. **Requires the CTO's explicit risk acceptance before G2 is requested**; the independent authorizer accepts or rejects it at G2 | Proposed, not decided | TBD | TBD |
| **Proposed condition:** testing of this candidate uses disposable, zero-value wallets only (IOS_RELEASE.md section 11) | Proposed, not decided | TBD | TBD |
| Mac-local signing instead of a protected CI environment (policy section 2.1) | Proposed, not decided | TBD | TBD |
| Existing production App Store Connect record used for the first internal TestFlight delivery, instead of the staging record of IOS_SIGNING.md section 2 item 1 (one-release exception; no policy change) | Proposed, not decided | TBD | TBD |
| `gate --channel production` read as applicable to iOS only (IOS_RELEASE.md section 4) | Proposed, not decided | TBD | TBD |
| Push entitlement and `remote-notification` mode (no `aps-environment`; Apple warning ITMS-90078 expected) | Open | TBD | TBD |
| Export-compliance and App Privacy answers (owner and legal) | Open | TBD | TBD |
| Privacy-manifest finding (no `PrivacyInfo.xcprivacy`) | Open | TBD | TBD |
| Xcode other than 26.3 (17C529), if any | none | TBD | TBD |

## 5. Facts confirmed by the operator before signing (IOS_RELEASE.md section 6)

| # | Fact | Answer |
|---|---|---|
| 1 | Team, enrollment type, Team ID | TBD |
| 2 | App Store Connect record: name, SKU, bundle ID, status | TBD |
| 3 | Live version and highest build ever uploaded | TBD |
| 4 | App ID registration and capabilities | TBD |
| 5 | Operator's role and access | TBD |
| 6 | Distribution certificate: SHA-256 fingerprint, expiry, creator, key holder | TBD |
| 7 | Signing route (A automatic / B manual) | TBD |
| 8 | Agreements accepted | TBD |
| 9 | Export compliance and privacy answers given | TBD |
| 10 | Push and privacy-manifest decisions known | TBD |
| 11 | Mac, Xcode, SDK, Flutter, CocoaPods versions; test devices and iOS versions | TBD |
| 12 | Zero-value production test account approved by | TBD |

## 6. Authorization gates (IOS_RELEASE.md section 1)

Only G1 has been decided. Nothing in sections 1 to 4 substitutes for a row below, and G1 implies no other row.

| Gate | Decision | By | Date | Reference |
|---|---|---|---|---|
| G1 source (commit only) | **AUTHORIZED** | CTO and release coordinator, GitHub account `CadenaWizard` | 2026-11-12 | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-6833584989 |
| G2 production signing and upload to App Store Connect (independent authorizer; also needs the CTO's risk acceptance of section 4) | **PENDING** | TBD | TBD | TBD |
| G3 assignment to named internal testers | **PENDING** | TBD | TBD | TBD |
| G4 submission to App Review (needs the 12-hour evidence, IOS_RELEASE.md section 11) | **NOT AUTHORIZED** (not given) | | | |
| G5 public release | **NOT AUTHORIZED** (not given) | | | |

Unchanged requirement: before any G4 request, the candidate must have **at least 12 hours of internal TestFlight evaluation on
physical devices** with the tests and logs of IOS_RELEASE.md section 11. A TestFlight upload is not App Review and not a release.

## 7. Results (filled from the operator's evidence; hashes and text only)

| | |
|---|---|
| IPA SHA-256 and size | TBD |
| Verification V1 to V9 | TBD |
| Symbol inspection (a) to (c); the nine exported names (expected to include `_create_deterministic_nonce_c`: the library is not rebuilt) | TBD |
| Upload time, tool, App Store Connect messages (verbatim) | TBD |
| Processed build as shown in App Store Connect | TBD |
| Tester group and testers (roles or names) | TBD |
| 12-hour session log summary: total hours, devices, iOS versions, overnight interval | TBD |
| Tests T1 to T10 | TBD |
| Crashes; device-log secret check hit counts | TBD |
| Retention (IOS_RELEASE.md section 12): `SHA256SUMS` value, storage kind, custodian role, access list, transfers | TBD |
| Ledger entry in `config/release/published_versions.json` (PR) | TBD |
