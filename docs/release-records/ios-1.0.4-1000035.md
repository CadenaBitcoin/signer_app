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
| Verification tooling (`TOOLS_SHA`) | **Proposed (D10, section 4): `f1bc92ed518bdac19cecab68d4877f03051093bd`** (`development`, merge of PR #107; `tool/verify_ipa.py` last changed at `5310a78`); **not decided**. It is the `development` commit the operator uses for `tool/verify_ipa.py`, from a separate checkout that builds nothing (IOS_RELEASE.md section 9). It must contain PR #107 (`certificate` and `--forbid-entitlement`); the approved production commit does not. `tool/` tree `a3af380acdccdad0cd1a26fd3ce9f37579be464d` and `tool/verify_ipa.py` blob `6ee2b9d74c31321904e2c042aa2bc82fc402ab35` are identical at `f1bc92e` and at the later tip `5f4d0c8` (PR #108, documents only) |
| Unsigned compile validation of `CONTENT_REF` | run `43210431581`, `ios-production`, success (compile and link only; no signing, no runtime evidence) |

## 2. Roles for this release (names or accounts; no role is implied by another)

| Role | Held by | Date confirmed |
|---|---|---|
| Release coordinator and release authority | CTO. The accounts `sziller` (preparation) and `CadenaWizard` (review, merge, and the G1 comment) are **the same person** | 2026-11-12: the G1 comment on Issue #71 (section 3.1) states "As CTO and release coordinator"; it was posted from `CadenaWizard`. Restated by the CTO on 2026-11-17 |
| Apple-side operator | Noah, intended | TBD (Noah's acceptance is not yet recorded) |

Under the authorization policy of 2026-11-17 ([../RELEASE_POLICY.md](../RELEASE_POLICY.md) principle 9 and section 2.3) the authorized merge is the single human authorization boundary. **This release has no independent authorizer and none is required**; no row of this record may call anyone independent. The operator is a separate role for who performs the Apple-side work; the operator's acceptance of the role is recorded above when given.

## 3. Approved source (G1, by the release coordinator) and its verified evidence

### 3.1 Approved source (G1)

| | |
|---|---|
| `APPROVED_SHA` = `M` (a `production` merge commit; never the commit of a record pull request) | **`42d358a4e7bcbf85b92aa992ec6439214dbd4405`** (version `1.0.4+1000035`) |
| Content reference | `CONTENT_REF` `862831e0b3a0f30c4155d2e086c69fc28bdab286` (section 1); proof of equality in 3.2 |
| G1 decision | "G1 APPROVED — Source selection only" |
| Authorizing account and date | GitHub account `CadenaWizard`, which states "As CTO and release coordinator"; comment created 2026-11-12T19:21:05Z, never edited (created and updated times are equal) |
| Written on Issue #71 by the coordinator | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-6833584989 (comment id 6833584989); it names `42d358a4e7bcbf85b92aa992ec6439214dbd4405`, version `1.0.4+1000035`, staging run `43214314837`, production run `43279190732`, and states that signing, TestFlight upload, App Review and public release are not permitted by it and that #22 and the later gates remain pending |

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

## 4. Dispositions and the policy basis of the manual operation

G1 decides none of these and accepts no security risk. **None of D1 to D12 is decided.** Each row states the **exact decision text as it
will stand once approved**; "Proposed" means the coordinator suggests it. A row takes effect only when the CTO fills in the decision,
the name and the date in a reviewed pull request; no row changes status by itself. There is one approver, the CTO, who is the release
authority under [../RELEASE_POLICY.md](../RELEASE_POLICY.md) principle 9; no row needs, and none may claim, a second person. D-numbers
are stable references. X1 and X2 are external decisions (owner and legal, or evidence still outstanding); they are not proposed here.
Evidence for each row is in the document it cites; nothing in this table is new technical research.

| ID | Item and exact proposed decision text | Status | By | Date |
|---|---|---|---|---|
| D1 | **Issue #22.** Issue #22 stays open. For iOS 1.0.4 (1000035) only, the existing pinned native Rust library (`libdlcplazacryptlib.a`, SHA-256 `203dcd7abe4187de0b756638a55f691b2d5c680b17d4fbfa7dda550ed703949b`) is retained without a rebuild, although it still contains and exports `_create_deterministic_nonce_c` (PR #97 removed the helper from the source interfaces only). No call path to it has been identified in the application (source review and symbol checks; not a proof). The residual risk is accepted by the CTO, **before G2 is requested**, for internal TestFlight with zero-value wallets (D2) only. This is not a remediation of #22, and it is no disposition for App Review or public release, which need a new one. Evidence: IOS_RELEASE.md section 11 ("Issue #22"), section 9 (symbol inspection), Issue #89 (no `Cargo.lock`) | Proposed, not decided | TBD | TBD |
| D2 | **Zero-value wallets.** Testing of this candidate uses disposable, zero-value wallet material only: a newly generated wallet, never a mnemonic that ever held value, never a wallet that will hold value, and an account created for the test, because the production build talks to the production backend and mainnet. The approver of the production-backend test account is recorded in section 5, item 12. Evidence: IOS_RELEASE.md section 11 | Proposed, not decided | TBD | TBD |
| D3 | **Mac-local signing, an operational exception to the future automation.** For 1.0.4 (1000035) only, signing is performed on a Mac under the Apple-side operator's control because automated Apple signing is not implemented (Issue #71; RELEASE_POLICY.md section 2.3, "Manual operations before automation exist"). It is **not** an exception to the authorization policy. Consequences accepted: no protected environment and no pipeline-enforced checks; the Apple ID session is on an operator-controlled machine; mitigated by V1 to V9, by no credential entering the repository, a chat or a log, and by the evidence of IOS_RELEASE.md section 12. Evidence: IOS_RELEASE.md section 1 ("Documented deviation", approved in principle by the project owner 2026-11-12) | Proposed, not decided | TBD | TBD |
| D4 | **Production App Store Connect record.** For 1.0.4 (1000035) only, the first internal TestFlight delivery uses the existing production record (bundle ID `com.app.cadenabitcoin`) instead of the staging record of IOS_SIGNING.md section 2, item 1, because no staging record is registered. One-release exception to the architecture, not to the authorization policy; RELEASE_POLICY.md section 8.1 and IOS_SIGNING.md section 2 are unchanged. Consequences accepted: the build number 1000035 is consumed in the production record, and the build is processed beside the live application. Evidence: IOS_RELEASE.md section 1; the record's section 5, item 2 is still TBD and must show the exact bundle ID | Proposed, not decided | TBD | TBD |
| D5 | **Production gate for iOS.** `python3 -I tool/build_manifest.py gate --channel production` is read as applicable to iOS only for this release: `PASS ios` is the applicable result and `FAIL android` (1000035 is already published there) is not. After the upload the iOS number enters the ledger and the rule then applies to iOS too. Evidence: IOS_RELEASE.md section 4 | Proposed, not decided | TBD | TBD |
| D6 | **No `aps-environment` in 1.0.4.** Version 1.0.4 ships without the push-notification entitlement: the repository has no entitlements file and no push-related pod (checked in `ios/Podfile.lock` and `ios/` on 2026-11-17); Push Notifications is enabled on the App ID but unused; the `remote-notification` background mode stays. Apple warning ITMS-90078 is expected and recorded, not dismissed. Enforced after signing by `verify_ipa.py verify --forbid-entitlement aps-environment`. Risk accepted: no server-sent push notifications in this build (the app's use of them is unconfirmed, APPLE_ACCOUNT_QUESTIONNAIRE.md B3). Evidence: IOS_SIGNING.md section 3.2, IOS_RELEASE.md section 9 (V5, V7) | Proposed, not decided | TBD | TBD |
| D7 | **Signing route A with a cloud-managed certificate.** The build is signed by route A: automatic signing and provisioning-profile management in Xcode with Apple's **cloud-managed** distribution certificate (no private key on any Mac). Consequences accepted: Xcode may **create** an Xcode-managed App Store profile (none is listed today) and, because the archive is signed for development, an Apple Development certificate and profile in the team's account; these are changes in the Apple account that nobody here can preview. Evidence: IOS_RELEASE.md sections 6 (items 6, 7) and 8; the account state is reported by Noah, unverified | Proposed, not decided | TBD | TBD |
| D8 | **Certificate verification after signing.** The signing certificate's SHA-256 fingerprint is read from the signed IPA (`verify_ipa.py certificate`), cross-checked with `codesign` and `openssl`, **recorded by the coordinator in section 7 before the upload**, and only then used as `--expect-cert-sha256` in V7 (a cloud-managed certificate has no fingerprint before signing). Limits accepted: the value is read from the artifact it later judges, so only the recording before upload makes it a pin; no chain to Apple without `--trust-anchors`; no revocation check. Evidence: IOS_RELEASE.md section 9 (V3, "V3 is discovery, then approval"); PR #107 | Proposed, not decided | TBD | TBD |
| D9 | **Export, verify, then Transporter.** One archive is made and exported; no second compile; the comparison baseline (V8) is the application inside the exported archive; the exported IPA passes section 9 in full; **that same IPA** is uploaded with Transporter as "TestFlight & App Store", never with Organizer's integrated Upload and never "TestFlight Internal Only"; its SHA-256 is recorded before and after the upload. Fallback: Organizer, same archive, Distribute, **Export** only. A failed verification stops the operation. Evidence: IOS_RELEASE.md sections 8 to 10; PR #107 and PR #108 | Proposed, not decided | TBD | TBD |
| D10 | **Verification tooling (`TOOLS_SHA`).** `TOOLS_SHA` is `f1bc92ed518bdac19cecab68d4877f03051093bd` (`development`, merge of PR #107; contains the `certificate` command and `--forbid-entitlement`; the approved commit does not). The `tool/` tree is `a3af380acdccdad0cd1a26fd3ce9f37579be464d` and `tool/verify_ipa.py` is blob `6ee2b9d74c31321904e2c042aa2bc82fc402ab35`; both are identical at the later `development` tip `5f4d0c8` (PR #108, documents only), so either commit gives the same verifier. The operator confirms both values in the separate tools checkout before using it. Evidence: `git rev-parse f1bc92e:tool 5f4d0c8:tool` (2026-11-17) | Proposed, not decided | TBD | TBD |
| D11 | **Reading of the gates for this release.** The merge of PR #102 (producing `M`) predates the authorization policy of 2026-11-17 and is G1, source selection only; it is not authorization to sign or upload. G2, G3, G4 and G5 are the CTO's separate, written authorizations of specific **manual** operations, because no production pipeline exists that could carry the merge's authorization: G2 production signing and the one upload as "TestFlight & App Store"; G3 assignment to named internal testers; G4 submission to App Review (only after the acceptance evidence of IOS_RELEASE.md section 11, which has no minimum duration); G5 public release. G2 and G3 are the initial internal TestFlight stage; the build is uploaded under the production record and could later be submitted without a rebuild, but submission is G4. No gate needs a second person | Proposed, not decided | TBD | TBD |
| D12 | **Policy basis.** The manual iOS 1.0.4 operation is an operational exception to the future automation. It is **not** an exception to the authorization policy of RELEASE_POLICY.md principle 9 and section 2.3 (the authorized merge is the single human authorization boundary; `sziller` and `CadenaWizard` are one person). Signing and upload remain **pending** until the prerequisites of section 4.1 are met and the CTO gives G2 | Proposed, not decided | TBD | TBD |
| D13 | Xcode other than 26.3 (17C529), if any | none | TBD | TBD |
| X1 | **Export compliance and App Privacy (external; no decision proposed).** Export-compliance and App Privacy answers (owner and legal). Technical facts only, no declaration: HTTPS (Flutter and `dio`); secp256k1 ECDSA, Schnorr and ECDH in the native library; `rand_chacha` as a random-number generator; `pointycastle` as a Dart dependency; Keychain through `flutter_secure_storage`; third-party Sumsub and FingerprintPro SDKs; `ITSAppUsesNonExemptEncryption` is not set The questions and answers are the owner's and legal's, never the operator's and never an assistant's | Open | TBD | TBD |
| X2 | **Privacy manifest (external; no decision proposed).** Privacy-manifest finding (no `PrivacyInfo.xcprivacy`). Read-only investigation, 2026-11-16: the pinned Rust library's arm64 slice imports `_stat _fstat _lstat _opendir _fdopendir _readdir_r _fsetattrlist _clock_gettime` from `std` and `_sysctlbyname` from `std_detect`/`compiler_builtins`; **only `_stat`, `_fstat` and `_lstat` are in a category of Apple's required-reason list (file timestamp)**, and no boot-time, disk-space or user-defaults symbol is imported; the library's only first-party file read (`init_from_file_c` → `fs::read_to_string`) has **no active caller** in the app (the call in `lib/main.dart` is commented out) but is an exported symbol of a force-loaded library in a **dynamic framework** (`use_frameworks!`), so `_fstat` is expected in `Frameworks/dlc_wallet.framework/dlc_wallet`; the Runner and plugin native code use no covered API; `dlc_wallet` and `flutter_idensic_mobile_sdk_plugin` ship no manifest; the other seven plugins of `Podfile.lock` ship one that their podspec packages; Sumsub's `IdensicMobileSDK` 1.42.0 ships none but imports none of the covered symbols and FingerprintPro 2.14.0 ships its own (both **carried from the earlier read of the vendor packages, not re-verified**). Apple's documentation says an app that does not describe required-reason use "aren't accepted by App Store Connect" (and that each executable or dynamic library using a covered API needs a manifest in its own bundle); Apple's own e-mail text and forum reports describe a warning e-mail only, and no Apple source found says a TestFlight upload is refused (**Unconfirmed** for November 2026). **Credible concern, not a finding of non-compliance: source-level inspection identifies `dlc_wallet.framework` as a likely carrier of a required-reason API symbol without a manifest, and Apple's documented enforcement is that such an app is not accepted by App Store Connect. Nothing here shows that the app is compliant or that Apple will accept the upload, and nothing shows that it will be refused; the decisive evidence is inspection of the final linked `dlc_wallet.framework` (the scan of IOS_RELEASE.md section 9) and Apple's own response to a processed build.** The smallest legitimate correction, if the coordinator chooses one, is a `PrivacyInfo.xcprivacy` in the `dlc_wallet` pod (podspec `resource_bundles`) declaring the file-timestamp category with the reason code that truthfully matches use; which code that is (for example C617.1 for files in the app container) is a determination by the code owner, not made here What the linked app really imports is read by the scan of IOS_RELEASE.md section 9 (preflight build, no credential). A manifest in `dlc_wallet` would change the frozen source and need a new G1. Accepting the possible Apple message or changing the source is the coordinator's decision **Decision waits for the actual inspection of the compiled `dlc_wallet.framework` (Noah's Mac-side diagnostic, in progress as of 2026-11-17); until it is recorded here, no statement of compliance is made, no privacy reason code is accepted and the frozen source is not changed.** | Open | TBD | TBD |

### 4.1 Prerequisites for the CTO's G2 authorization of the manual operation (NOT GIVEN)

G2 is the CTO's written authorization of **this specific operation** under the policy of 2026-11-17. It is not an exception to that
policy and it is not given by this section, by the merge of this record, or by any earlier merge. It is **pending**.

**The operation G2 would authorize (exhaustive).** Production signing and one upload to App Store Connect of the IPA that passed
IOS_RELEASE.md section 9, for the initial internal TestFlight stage, of: iOS `1.0.4` build `1000035`; commit
`42d358a4e7bcbf85b92aa992ec6439214dbd4405`; bundle ID `com.app.cadenabitcoin`; Apple Team `D65458CPDP` (confirmed by the operator before
signing, section 5 item 1; a different team stops the operation); zero-value wallets only (D2).

**What G2 would not authorize.** Tester assignment (G3), App Review submission (G4), public release or distribution (G5), external
TestFlight testers or public links, any other version, build, commit, bundle ID or team, any later release, any rebuild or second
archive, any change to code, version or build number, any bypass of signing or artifact verification (V1 to V9, the certificate record
of D8, `--forbid-entitlement aps-environment`, the single-archive rule, the evidence of IOS_RELEASE.md section 12), and any use of
wallets that hold or will hold value.

**Prerequisites, all required before the CTO gives G2:**

1. D1 to D12 are each decided (no row still "Proposed"), by the CTO, in a merged pull request.
2. X1 (export compliance and App Privacy) is decided by the owner and legal, and X2 (privacy manifest) is decided by the CTO after the
   compiled-framework inspection is recorded here.
3. Section 5 is filled with no stop answer: team, enrollment type and Team ID; the App Store Connect record (name, SKU, status, exact
   bundle ID); the live iOS version and the highest uploaded build; the operator's role and access (upload; certificate and profile
   management for route A); the zero-value test account's approver (item 12).
4. The operator has accepted the role (section 2) and has completed IOS_RELEASE.md steps 1 to 3 with the outputs returned, including the
   required-reason scan, so the CTO decides with that evidence.
5. The `development` record names `TOOLS_SHA` (D10) and the status is `G1 AUTHORIZED` at the moment of G2.

**G2 evidence.** The CTO's written G2 decision on Issue #71 (naming the commit SHA, the version, the bundle ID and the operation) and the
merged reviewed pull request that sets `Status` to `G2 AUTHORIZED`. No second person is involved, required or claimed.

## 5. Facts confirmed by the operator before signing (IOS_RELEASE.md section 6)

**Provenance of the answers below.** *Coordinator-reported (2026-11-19)*: the release coordinator read Apple's Developer and App Store
Connect web pages directly; the values are not verified through the App Store Connect API, and no screenshot, account address or
other account detail is stored here. *Repository-verified*: read from the approved source or the repository. *Noah-reported*: given
earlier by the intended operator and not verified. None of these entries decides a D or X row, authorizes a gate, or records the
operator's acceptance of the role.

| # | Fact | Answer |
|---|---|---|
| 1 | Team, enrollment type, Team ID | Organization "Cadena Bitcoin S.A. de C.V.", enrollment type Organization, Team ID `D65458CPDP` (**coordinator-reported, 2026-11-19**). The Team ID equals `DEVELOPMENT_TEAM` in `ios/Runner.xcodeproj` (repository-verified). The team the operator signs in as on the operator's Mac is **not yet confirmed**; a different team stops the operation |
| 2 | App Store Connect record: name, SKU, bundle ID, status | App "Cadena Bitcoin", SKU `com.app.cadenabitcoin`, Apple App ID `6753348211`, bundle ID `com.app.cadenabitcoin` (equals the repository's production bundle ID), iOS version record `1.0.4` in status `Prepare for Submission` (**coordinator-reported, 2026-11-19**). Nothing has been submitted for review |
| 3 | Live version and highest build ever uploaded | Highest build seen in the App Store Connect builds list: version `1.0.3`, build `1000034`, uploaded 2026-07-30; no build `1000035` or higher was in the inspected list (**coordinator-reported, 2026-11-19, not API-verified**; consistent with Noah's earlier report). The stop condition "highest build 1000035 or more" is not triggered on this evidence. Not stated: whether the inspected list covered expired and never-released builds. Live iOS version: TBD (not stated) |
| 4 | App ID registration and capabilities | Push Notifications is enabled on the registered App ID (Noah; **coordinator-reported, 2026-11-19**). No manually managed provisioning profile is visible in the portal (coordinator-reported; Xcode-managed profiles are not shown there). **A registered capability is not evidence that the application implements push**: the app declares the `remote-notification` background mode and has no entitlements file and no `aps-environment` (repository-verified; D6) |
| 5 | Operator's role and access | The Apple Developer organization has Admin accounts for the coordinator and for the intended operator; the coordinator reports that the operator's Apple-side privileges suffice for the planned workflow (**coordinator-reported, 2026-11-19**; account addresses are deliberately not recorded). **Still unverified:** the operator's acceptance of the role (section 2) and the operator's Xcode sign-in and signing capability on the Mac |
| 6 | Distribution certificate: SHA-256 fingerprint, expiry, creator, key holder | An Apple **cloud-managed** Distribution certificate is listed, valid until 2027-07-09, created under the organization (no individual named); an Apple Development certificate is also listed, valid until 2027-07-09, its management type not stated (**coordinator-reported, 2026-11-19**). There is no local Apple Distribution certificate and no private key on any Mac (**Noah, not verified**). No certificate or profile was created for this inspection. **Cloud-managed signing has not been demonstrated by a signing operation for 1.0.4.** Fingerprint: **not known before signing**; collected from the signed IPA with `verify_ipa.py certificate` and recorded in section 7 by the coordinator before upload. The portal's expiry is a listing; the signing certificate's own expiry is read from the IPA (IOS_RELEASE.md section 9, V3, V4) |
| 7 | Signing route (A automatic / B manual) | Proposed: A (section 4); **not decided** |
| 8 | Agreements accepted | Free Apps Agreement **Active**, through 2027-09-09; Digital Services Act compliance **Active**; Paid Apps Agreement **New** (not accepted), which the coordinator reads as not required for the intended internal TestFlight distribution; no outstanding agreement blocker was identified (**coordinator-reported, 2026-11-19**). Program License Agreement accepted (**Noah, not verified**; not part of the 2026-11-19 inspection). **Open:** IOS_RELEASE.md section 6 item 8 stops on "any" pending agreement; whether a Paid Apps Agreement in status New counts is for the coordinator to decide before G2 |
| 9 | Export compliance and privacy answers given | TBD |
| 10 | Push and privacy-manifest decisions known | TBD |
| 11 | Mac, Xcode, SDK, Flutter, CocoaPods versions; test devices and iOS versions | TBD |
| 12 | Zero-value production test account approved by | TBD |

**Internal TestFlight configuration (coordinator-reported, 2026-11-19; not a numbered item).** An internal group "Cadena Internal
Testing" exists (renamed from a generic name) with two internal testers, who have installed the application on physical iPhones before;
tester feedback is enabled and automatic distribution is configured **for Xcode builds**. Automatic distribution for Xcode builds does not
establish how a build uploaded with Transporter is assigned, so the group's behavior for such an upload is unverified and should be
checked before G2. **Nothing has been uploaded, assigned or distributed**; assignment to testers is G3 (section 6), pending. Tester
identities are not recorded here and the section 7 row for the tester group stays TBD until after an upload.

## 6. Authorization gates (IOS_RELEASE.md section 1)

Only G1 has been decided. Nothing in sections 1 to 4 substitutes for a row below, and G1 implies no other row. The policy basis is section 4, D11 and D12.

| Gate | Decision | By | Date | Reference |
|---|---|---|---|---|
| G1 source (commit only) | **AUTHORIZED** | CTO and release coordinator, GitHub account `CadenaWizard` | 2026-11-12 | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-6833584989 |
| G2 production signing and upload to App Store Connect: the CTO's written authorization of this manual operation, after the prerequisites of section 4.1 (not an exception to the authorization policy) | **PENDING** | TBD | TBD | TBD |
| G3 assignment to named internal testers (the CTO) | **PENDING** | TBD | TBD | TBD |
| G4 submission to App Review (the CTO, a separate manual operation; needs the acceptance evidence of IOS_RELEASE.md section 11, which has no minimum duration) | **NOT AUTHORIZED** (not given) | | | |
| G5 public release (the CTO, separately from G4) | **NOT AUTHORIZED** (not given) | | | |

Requirement before any G4 request: the acceptance criteria of IOS_RELEASE.md section 11 are met and evidenced on physical devices
installed through TestFlight. **There is no mandatory time window** (CTO decision of 2026-11-17). A TestFlight upload is not App
Review and not a release.

## 7. Results (filled from the operator's evidence; hashes and text only)

| | |
|---|---|
| IPA SHA-256 and size | TBD |
| Signing certificate collected from the IPA (`certificate` output, `codesign`/`openssl` cross-check); SHA-256 **recorded by the coordinator before upload**; embedded profile name, type and expiry | TBD |
| Archive baseline (`archive-app.sha256`) and `DistributionSummary.plist` | TBD |
| Verification V1 to V9 | TBD |
| Required-reason import scan (preflight build and `$APP`) and manifests found | TBD |
| Symbol inspection (a) to (c); the nine exported names (expected to include `_create_deterministic_nonce_c`: the library is not rebuilt) | TBD |
| Upload time, tool, App Store Connect messages (verbatim) | TBD |
| Processed build as shown in App Store Connect | TBD |
| Tester group and testers (roles or names) | TBD |
| Session log summary (a record, not a minimum): devices, iOS versions, activity | TBD |
| Tests T1 to T10 | TBD |
| Crashes; device-log secret check hit counts | TBD |
| Retention (IOS_RELEASE.md section 12): `SHA256SUMS` value, storage kind, custodian role, access list, transfers | TBD |
| Ledger entry in `config/release/published_versions.json` (PR) | TBD |
