# Release record: iOS 1.0.4 (1000035), G1 AUTHORIZED (source only); G2S Authorization A consumed and withdrawn; G2S Authorization B (App Manager key) authorized, conditional

> **Record Status: `G1 AUTHORIZED`: the source commit only.** **G2S** (one GitHub-hosted signing-and-verification operation; no
> upload, no distribution) exists as two **separate** authorizations. **Authorization A** (section 4.2) was **consumed** by run `44800943301`, which reached Apple credential use
> and failed at the export, and was withdrawn (PR #118); it stays consumed and is never reactivated. **Authorization B** (section 4.3, D15; the CTO's decision
> https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7050074107) authorizes **one new** such operation with a dedicated App Manager-role key, is not an extension of A,
> and is effective only when this record is merged on `development` and the workflow's gate passes (`G2S-STATUS: AUTHORIZED`, section 6.1). Apple distribution signing for an upload, upload to App Store Connect
> (G2), assignment to testers (G3), App Review (G4) and public release (G5) are **NOT authorized**. G1 accepts no security
> risk; the dispositions of section 4 are decided or deferred exactly as marked there; Issue #22 stays open. Section 3 holds the verified evidence for the
> approved source. A blank or "TBD" is a stop, never a default. Procedure: [../IOS_RELEASE.md](../IOS_RELEASE.md); this file holds only what is specific to
> this release. It contains no secret, no key material and no credential, and must never receive
> one. Counterpart of [../ANDROID_RELEASE.md](../ANDROID_RELEASE.md) section 9.

## 0. Record status

Allowed values: `DRAFT`, `G1 AUTHORIZED`, `G2 AUTHORIZED`, `WITHDRAWN` (IOS_RELEASE.md section 3). Changed only by a reviewed
pull request; `M` (section 3 below) never changes after G1 without a new G1.

**Record Status: `G1 AUTHORIZED`**

Set by this record's pull request on the strength of the coordinator's G1 comment on Issue #71 (section 3.1), after the record
had been on `development` as `DRAFT` (PR #103). Under IOS_RELEASE.md (Quick start, section 3) this status lets the operator
retrieve and verify the source and make the unsigned build only. It does **not** allow signing by an operator or any upload:
those need G2 (section 6), which is pending. The exceptions are the G2S operations: one hosted signing and
verification run each, recorded by the G2S lines of section 6.1, never an upload; neither changes this status. **Authorization A is consumed and withdrawn** (section 4.2, "Second attempt");
**Authorization B** is the one current G2S authorization (section 4.3).

## 1. Fixed by the repository (not an authorization)

| | |
|---|---|
| Platform, channel | iOS, App Store Connect / TestFlight (production record, first delivery internal only) |
| Bundle ID | `com.app.cadenabitcoin` (display name "Cadena Bitcoin") |
| Version / build | `1.0.4` / `1000035` (`pubspec.yaml`; Android already published 1.0.4 (1000035); the ledger has no iOS entry) |
| Configuration | `config/build/production.json`: `APP_ENV` `production`, `NETWORK_ENVIRONMENT` `bitcoin`, `USE_TESTNET` `false`, `API_BASE_URL` `https://cadenabitcoin.com/app`; SHA-256 `4b640c4fac2ba9cdde8526d2ed36aab80ec3835679eedba4052f5c094d610409` |
| Reviewed content (`CONTENT_REF`) | `862831e0b3a0f30c4155d2e086c69fc28bdab286` (`development`, merge of PR #97; includes PRs #97, #98 and #99) |
| Verification tooling | **G2S (D10, decided):** the workflow, gate and tools named by the three blob lines of section 6.1 (`G2S-WORKFLOW-BLOB`, `G2S-GATE-BLOB`, `G2S-TOOL-BLOBS`), computed from the repository with `bash tool/check_signing_authorization.sh --print-expected --tools-root .`. The Mac route's `TOOLS_SHA` (`f1bc92ed518bdac19cecab68d4877f03051093bd`, merge of PR #107; `tool/verify_ipa.py` blob `6ee2b9d74c31321904e2c042aa2bc82fc402ab35`) is **not used for G2S** and would be decided again for a G2 operation on an operator Mac |
| Unsigned compile validation of `CONTENT_REF` | run `43210431581`, `ios-production`, success (compile and link only; no signing, no runtime evidence) |

## 2. Roles for this release (names or accounts; no role is implied by another)

| Role | Held by | Date confirmed |
|---|---|---|
| Release coordinator and release authority | CTO. The accounts `sziller` (preparation) and `CadenaWizard` (review, merge, and the G1 comment) are **the same person** | 2026-11-12: the G1 comment on Issue #71 (section 3.1) states "As CTO and release coordinator"; it was posted from `CadenaWizard`. Restated by the CTO on 2026-11-17 |
| Apple-side operator | Noah, intended (needed only for an operator-Mac route; **not needed for G2S**, where the hosted workflow performs the Apple-side work, D3) | TBD (Noah's acceptance is not yet recorded) |
| Deployment confirmation of the G2S run | The required reviewers of the GitHub environment `ios-hosted-signing`: `sziller` and `CadenaWizard`, **the same person** (the CTO); `prevent_self_review` is off, so no second person is required or claimed. The confirmation does not replace the CTO's authorization (D12) | 2026-11-20 (configuration read from the GitHub API, section 4.2) |

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

G1 decides none of these and accepts no security risk. On **2026-11-20** the CTO decided **D3, D6, D7, D8, D9, D10, D11, D12 and D14** for the G2S operation
(section 4.2; the accepted risks are written into each row). **The G2S operation of Authorization A has since been consumed and that authorization withdrawn** (PR #118; section 4.2, "Second attempt"): these decisions are retained as the history of what was decided and authorize no run by themselves. On **2026-11-20** the CTO also decided **D15**, the App Manager credential of **Authorization B** (section 4.3): D14 stays the historical decision for the Developer-role key of Authorization A, and D15 is separate from it. **D1, D2, D4, D5, X1 and X2 are not decided**: they are deferred to G2 and the later gates
(section 4.2), and D13 stays as it is. Each row states the **exact decision text as it
will stand once approved**; "Proposed" means the coordinator suggests it. A row takes effect only when the CTO fills in the decision,
the name and the date in a reviewed pull request; no row changes status by itself. There is one approver, the CTO, who is the release
authority under [../RELEASE_POLICY.md](../RELEASE_POLICY.md) principle 9; no row needs, and none may claim, a second person. D-numbers
are stable references. X1 and X2 are external decisions (owner and legal, or evidence still outstanding); they are not proposed here.
Evidence for each row is in the document it cites; nothing in this table is new technical research.

| ID | Item and exact proposed decision text | Status | By | Date |
|---|---|---|---|---|
| D1 | **Issue #22.** Issue #22 stays open. For iOS 1.0.4 (1000035) only, the existing pinned native Rust library (`libdlcplazacryptlib.a`, SHA-256 `203dcd7abe4187de0b756638a55f691b2d5c680b17d4fbfa7dda550ed703949b`) is retained without a rebuild, although it still contains and exports `_create_deterministic_nonce_c` (PR #97 removed the helper from the source interfaces only). No call path to it has been identified in the application (source review and symbol checks; not a proof). The residual risk is accepted by the CTO, **before G2 is requested**, for internal TestFlight with zero-value wallets (D2) only. This is not a remediation of #22, and it is no disposition for App Review or public release, which need a new one. Evidence: IOS_RELEASE.md section 11 ("Issue #22"), section 9 (symbol inspection), Issue #89 (no `Cargo.lock`) | Proposed, not decided | TBD | TBD |
| D2 | **Zero-value wallets.** Testing of this candidate uses disposable, zero-value wallet material only: a newly generated wallet, never a mnemonic that ever held value, never a wallet that will hold value, and an account created for the test, because the production build talks to the production backend and mainnet. The approver of the production-backend test account is recorded in section 5, item 12. Evidence: IOS_RELEASE.md section 11 | Proposed, not decided | TBD | TBD |
| D3 | **Hosted signing instead of an Apple-side operator Mac (G2S only).** For the G2S operation on 1.0.4 (1000035), signing and verification are performed by the GitHub-hosted workflow `.github/workflows/ios-hosted-signing.yml` on a GitHub-hosted macOS runner, started by hand from `development` and confirmed by the required reviewers of the protected environment `ios-hosted-signing`, instead of by an Apple-side operator on a Mac. It is an operational exception to the future automation (RELEASE_POLICY.md section 2.3, "Manual operations before automation exist"); it is **not** an exception to the authorization policy. **Risks accepted by the CTO:** the trust placed in a GitHub-hosted runner, which holds the Apple API key during one step; no operator-controlled machine; the controls of IOS_HOSTED_SIGNING.md in place of an operator's judgment. Mitigated by V1 to V9, by the gate and the bound blobs, by no credential entering the repository, a chat or a log, and by the evidence of IOS_HOSTED_SIGNING.md. The Mac route of IOS_RELEASE.md sections 6 to 12 remains the procedure for any operation G2S does not cover. Evidence: the CTO's comment https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7038341975; IOS_HOSTED_SIGNING.md sections 1, 2 and 5 | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D4 | **Production App Store Connect record.** For 1.0.4 (1000035) only, the first internal TestFlight delivery uses the existing production record (bundle ID `com.app.cadenabitcoin`) instead of the staging record of IOS_SIGNING.md section 2, item 1, because no staging record is registered. One-release exception to the architecture, not to the authorization policy; RELEASE_POLICY.md section 8.1 and IOS_SIGNING.md section 2 are unchanged. Consequences accepted: the build number 1000035 is consumed in the production record, and the build is processed beside the live application. Evidence: IOS_RELEASE.md section 1; the record's section 5, item 2 is still TBD and must show the exact bundle ID | Proposed, not decided | TBD | TBD |
| D5 | **Production gate for iOS.** `python3 -I tool/build_manifest.py gate --channel production` is read as applicable to iOS only for this release: `PASS ios` is the applicable result and `FAIL android` (1000035 is already published there) is not. After the upload the iOS number enters the ledger and the rule then applies to iOS too. Evidence: IOS_RELEASE.md section 4 | Proposed, not decided | TBD | TBD |
| D6 | **No `aps-environment` in 1.0.4.** Version 1.0.4 ships without the push-notification entitlement: the repository has no entitlements file and no push-related pod (checked in `ios/Podfile.lock` and `ios/` on 2026-11-17); Push Notifications is enabled on the App ID but unused; the `remote-notification` background mode stays. Apple warning ITMS-90078 is expected at a later upload and recorded, not dismissed. Enforced after signing by `verify_ipa.py verify --forbid-entitlement aps-environment` (V5 and V7 of the hosted signing job). **Risk accepted by the CTO:** no server-sent push notifications in this build (the app's use of them is unconfirmed, APPLE_ACCOUNT_QUESTIONNAIRE.md B3). Evidence: IOS_SIGNING.md section 3.2, IOS_RELEASE.md section 9 (V5, V7) | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D7 | **Apple cloud-managed Distribution signing with automatic provisioning, through a team API key.** The archive is built unsigned and exported with `signingStyle` automatic, `-allowProvisioningUpdates` and the dedicated team API key of D14, so that Apple's **cloud-managed** Distribution certificate signs it (no private key on any Mac or runner). **Risks accepted by the CTO:** Xcode may **create** an Xcode-managed App Store provisioning profile and other certificate or profile objects in the team's account; these are changes in the Apple account that nobody can preview. Whether the Developer role suffices for cloud-managed Distribution signing, and whether an unsigned archive can be exported and signed, are **Unconfirmed**: a failure is a result of the experiment, not a defect, and a temporary Admin-level credential would need its own authorization (D14). Evidence: IOS_HOSTED_SIGNING.md sections 2 and 6; IOS_SIGNING.md section 5 **Applicability (added for Authorization B; the decision and its accepted risks are unchanged):** the text above describes Authorization A, with the Developer-role key. For Authorization B the same question is open for the App Manager role (D15): whether it suffices for cloud-managed Distribution signing is **Unconfirmed**, a failure is again a result of the experiment and not a defect, and no Admin-level credential is authorized. | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D8 | **Certificate verification: discovery in the first run.** The signing certificate's SHA-256 fingerprint is read from the signed IPA (`verify_ipa.py certificate`), cross-checked with `codesign` and `openssl`, and **recorded by the coordinator in section 7**. In the first run it is only **discovered** (`pin_source=DISCOVERED`, a circular pin); it becomes a pin when the recorded value is passed as `expected_cert_sha256` to a later run or checked before any upload. **Limits accepted by the CTO:** the value is read from the artifact it later judges; no chain to Apple without `--trust-anchors`; no revocation check. Evidence: IOS_RELEASE.md section 9 (V3, "V3 is discovery, then approval"); PR #107; IOS_HOSTED_SIGNING.md section 1 | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D9 | **One archive, one export, verification; no upload.** G2S authorizes ONE operation: one archive is built from the approved commit, exported once, and the exported IPA is verified (V1 to V9; the comparison baseline of V8 is the application inside that archive; no second compile). The signed IPA **must not be uploaded or retained for distribution**: it stays on the runner and is gone with it, and nothing is sent to App Store Connect. The single-archive rule applies **per authorized operation**: a later G2 operation (upload) builds and signs its own archive under its own authorization, and its native-library hash is authorized again. A failed security or identity verification stops the operation. Evidence: IOS_HOSTED_SIGNING.md sections 1, 2.1 and 5 **Applicability (added for Authorization B; the decision is unchanged):** the limit is per authorization. The operation of Authorization A is consumed (section 4.2). Authorization B (section 4.3) authorizes one **new** operation, separately, under the same rules (one archive, one export, verification, no upload); it is not a second operation of Authorization A. | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D10 | **Verification tooling and implementation identity.** The workflow, the authorization gate and the tools that verify the IPA are exactly those named by the G2S blob lines of section 6.1: `G2S-WORKFLOW-BLOB`, `G2S-GATE-BLOB` and `G2S-TOOL-BLOBS` (the five tools `tool/build_manifest.py`, `tool/ipa_inspect.py`, `tool/validate_handover_archive.py`, `tool/verify_artifact.sh`, `tool/verify_ipa.py`), computed from the repository contents with `bash tool/check_signing_authorization.sh --print-expected --tools-root .`. The gate refuses to authorize if any of them differs, so a later change needs a new, reviewed authorization. This replaces the Mac route's `TOOLS_SHA` for G2S (section 1). Evidence: IOS_HOSTED_SIGNING.md section 5 | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D11 | **Reading of the gates for this release.** The merge of PR #102 (producing `M`) predates the authorization policy of 2026-11-17 and is G1, source selection only; it is not authorization to sign or upload. **G2S** is the CTO's separate, written authorization of one GitHub-hosted signing-and-verification operation, recorded by the G2S lines of section 6.1; it is signing only, never an upload or a distribution, and it is **not G2**. G2 (production signing for the one upload as "TestFlight & App Store"), G3 (assignment to named internal testers), G4 (submission to App Review, only after the acceptance evidence of IOS_RELEASE.md section 11, which has no minimum duration) and G5 (public release) remain the CTO's separate, written authorizations of specific **manual** operations and are **not authorized**. G2 and G3 are the initial internal TestFlight stage; submission is G4. No gate needs a second person | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D12 | **Policy basis.** The G2S operation is a manual operation started by hand (a manually started workflow in a protected environment) and is an operational exception to the future automation. It is **not** an exception to the authorization policy of RELEASE_POLICY.md principle 9 and section 2.3 (the authorized merge is the single human authorization boundary; `sziller` and `CadenaWizard` are one person): it needs the CTO's written authorization of that operation (section 4.2) and the merged record. The approval of the required reviewers of the environment `ios-hosted-signing` **confirms the deployment only; it does not replace the CTO's authorization** and does not create one. Upload and distribution remain **pending** until the prerequisites of section 4.1 are met and the CTO gives G2 | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D13 | Xcode other than 26.3 (17C529), if any | none | TBD | TBD |
| D14 | **Dedicated Developer-role Apple Team API key.** A **dedicated** App Store Connect **Team API key with the Developer role** is accepted as the credential of the G2S operation. It is stored only as environment secrets of `ios-hosted-signing` and never in the repository, a chat or a log. **Risk accepted by the CTO:** a team key's scope **cannot be restricted to this application** (access to all apps of the team, limited only by role; IOS_SIGNING.md section 5, option A, with the fallback recorded there). **Rotation and revocation remain available security controls; automatic revocation after the G2S operation is not mandatory.** Any temporary Admin-level credential requires its own, separate authorization. Evidence: IOS_SIGNING.md section 5; IOS_HOSTED_SIGNING.md section 2 **Applicability (added for Authorization B; the decision and its accepted risk are unchanged):** D14 is the historical decision for the Developer-role credential of Authorization A, which is consumed; it does not govern Authorization B, whose credential is decided by D15. | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D15 | **Dedicated App Manager-role Apple Team API key for G2S Authorization B.** A **dedicated** App Store Connect **Team API key** is approved for Authorization B only (section 4.3): name `Cadena iOS CI Signing -AppMngr`, **Key ID `47PP4C673P`** (an identifier, not a secret), role **App Manager**, purpose: the hosted iOS signing-and-verification experiment. The CTO states that the private key is stored locally outside the repository, with restricted filesystem permissions, and that its cryptographic format has been validated (a statement of the CTO; this record holds no key material and cannot verify it). Whether the key's capability is sufficient is **Unconfirmed**. It may be configured as an environment secret of `ios-hosted-signing` **only after** the record that makes Authorization B effective is merged and the gate has passed against the final `development` revision, and the three secrets are removed after the attempt (section 4.3). **Risks accepted by the CTO:** (1) the App Manager role provides broader permissions than Developer; (2) the team key is not restricted to a single application; (3) App Manager cloud-signing capability remains unverified; (4) another signing failure is possible even if the workflow operates correctly; (5) the independent backup of the private key is deferred; (6) the private key is temporarily available to the protected GitHub Actions signing job. **No Admin-level or Account Holder credential is authorized.** The previous Developer-role key (D14) remains unchanged; **neither key is revoked automatically**: revocation remains a separate operational decision, unless a compromise is suspected. D15 governs Authorization B only and does not extend to G2 or any later gate. Evidence: the CTO's decision https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7050074107 (section 3, "New credential: D15") | Decided | CTO (CadenaWizard) | 2026-11-20 |
| X1 | **Export compliance and App Privacy (external; no decision proposed).** Export-compliance and App Privacy answers (owner and legal). Technical facts only, no declaration: HTTPS (Flutter and `dio`); secp256k1 ECDSA, Schnorr and ECDH in the native library; `rand_chacha` as a random-number generator; `pointycastle` as a Dart dependency; Keychain through `flutter_secure_storage`; third-party Sumsub and FingerprintPro SDKs; `ITSAppUsesNonExemptEncryption` is not set The questions and answers are the owner's and legal's, never the operator's and never an assistant's | Open | TBD | TBD |
| X2 | **Privacy manifest (external; no decision proposed).** Privacy-manifest finding (no `PrivacyInfo.xcprivacy`). Read-only investigation, 2026-11-16: the pinned Rust library's arm64 slice imports `_stat _fstat _lstat _opendir _fdopendir _readdir_r _fsetattrlist _clock_gettime` from `std` and `_sysctlbyname` from `std_detect`/`compiler_builtins`; **only `_stat`, `_fstat` and `_lstat` are in a category of Apple's required-reason list (file timestamp)**, and no boot-time, disk-space or user-defaults symbol is imported; the library's only first-party file read (`init_from_file_c` → `fs::read_to_string`) has **no active caller** in the app (the call in `lib/main.dart` is commented out) but is an exported symbol of a force-loaded library in a **dynamic framework** (`use_frameworks!`), so `_fstat` is expected in `Frameworks/dlc_wallet.framework/dlc_wallet`; the Runner and plugin native code use no covered API; `dlc_wallet` and `flutter_idensic_mobile_sdk_plugin` ship no manifest; the other seven plugins of `Podfile.lock` ship one that their podspec packages; Sumsub's `IdensicMobileSDK` 1.42.0 ships none but imports none of the covered symbols and FingerprintPro 2.14.0 ships its own (both **carried from the earlier read of the vendor packages, not re-verified**). Apple's documentation says an app that does not describe required-reason use "aren't accepted by App Store Connect" (and that each executable or dynamic library using a covered API needs a manifest in its own bundle); Apple's own e-mail text and forum reports describe a warning e-mail only, and no Apple source found says a TestFlight upload is refused (**Unconfirmed** for November 2026). **Credible concern, not a finding of non-compliance: source-level inspection identifies `dlc_wallet.framework` as a likely carrier of a required-reason API symbol without a manifest, and Apple's documented enforcement is that such an app is not accepted by App Store Connect. Nothing here shows that the app is compliant or that Apple will accept the upload, and nothing shows that it will be refused; the decisive evidence is inspection of the final linked `dlc_wallet.framework` (the scan of IOS_RELEASE.md section 9) and Apple's own response to a processed build.** The smallest legitimate correction, if the coordinator chooses one, is a `PrivacyInfo.xcprivacy` in the `dlc_wallet` pod (podspec `resource_bundles`) declaring the file-timestamp category with the reason code that truthfully matches use; which code that is (for example C617.1 for files in the app container) is a determination by the code owner, not made here What the linked app really imports is read by the scan of IOS_RELEASE.md section 9 (preflight build, no credential). A manifest in `dlc_wallet` would change the frozen source and need a new G1. Accepting the possible Apple message or changing the source is the coordinator's decision **Technical evidence completed 2026-11-19 and 2026-11-20 by the credential-free hosted diagnostics runs `44619876867`, `44625655320` and `44726071796` (same commit, Xcode 26.3, corrected scanner of PR #113):** the linked `Frameworks/dlc_wallet.framework/dlc_wallet` imports `_stat`, `_fstat` and `_lstat` (file timestamp; also `_clock_gettime` and `_sysctlbyname`) and ships **no** `PrivacyInfo.xcprivacy`; every other binary that imports a covered API ships one. This is the inspection the row waited for. **The row stays Open:** the decision (accept the possible Apple message, or add a manifest to the pod, which changes frozen source and needs a new G1) is the CTO's, before G2; no statement of compliance is made, no privacy reason code is accepted and the frozen source is not changed. | Open | TBD | TBD |

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

1. D1 to D12 and D14 are each decided (no row still "Proposed"), by the CTO, in a merged pull request. D3, D6 to D12 and D14 were decided on 2026-11-20 **for the G2S operation**; the CTO's G2 decision states whether and how they extend to the G2 operation (D3, D7, D9 and D12 describe the hosted G2S route and the per-operation single archive); D1, D2, D4 and D5 are still to be decided.
2. X1 (export compliance and App Privacy) is decided by the owner and legal, and X2 (privacy manifest) is decided by the CTO after the
   compiled-framework inspection is recorded here.
3. Section 5 is filled with no stop answer: team, enrollment type and Team ID; the App Store Connect record (name, SKU, status, exact
   bundle ID); the live iOS version and the highest uploaded build; the operator's role and access (upload; certificate and profile
   management for route A); the zero-value test account's approver (item 12).
4. The operator has accepted the role (section 2) and has completed IOS_RELEASE.md steps 1 to 3 with the outputs returned, including the
   required-reason scan, so the CTO decides with that evidence. The credential-free hosted diagnostics runs `44619876867`, `44625655320` and
   `44726071796` (same commit and toolchain) supply that evidence for steps 1 to 3 and the required-reason scan; whether a G2 operation still
   needs an operator Mac is decided with G2.
5. The `development` record names the verification tooling (D10: the blob lines of section 6.1 for a hosted route, `TOOLS_SHA` for an operator Mac)
   and the status is `G1 AUTHORIZED` at the moment of G2.

**G2 evidence.** The CTO's written G2 decision on Issue #71 (naming the commit SHA, the version, the bundle ID and the operation) and the
merged reviewed pull request that sets `Status` to `G2 AUTHORIZED`. No second person is involved, required or claimed.

### 4.2 G2S Authorization A: one GitHub-hosted signing-and-verification operation (WITHDRAWN: CONSUMED by run 44800943301)

> **Current state.** This section is **Authorization A**, and its text is the **historical record** of what the CTO authorized, on which conditions, and what happened. **Authorization A
> is permanently consumed and withdrawn**: run `44800943301` reached Apple credential use, so its one operation is consumed (see "Second attempt" below), and its withdrawal became effective through
> **PR #118**, which set `G2S-STATUS` to `WITHDRAWN`. Statements below such as "G2S is no longer executable", "`G2S-STATUS` is `WITHDRAWN`" and "G2S authorization withdrawn" describe
> **Authorization A as of PR #118**; they are kept as the historical facts and are not rewritten. They do **not** describe the current status of the record. **Authorization B** (section 4.3) is a
> **separate, conditionally authorized** operation with its own CTO decision, credential (D15) and single operation; it is not an extension, a retry or a reactivation of A, and A stays consumed.
> **Section 6.1 now holds the active authorization fields of Authorization B.** The authorization text and the CTO decisions of A are preserved unchanged as history; they authorize no further run.

**The authorization.** The CTO's written decision "CTO Decision: G2S Hosted iOS Signing Authorization" on Issue #71:
https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7038341975
(comment id `7038341975`, account `CadenaWizard`, created 2026-11-20T11:26:04Z, never edited). It names the application (Cadena Bitcoin
Signer App), release `1.0.4 (1000035)`, `APPROVED_SHA` `42d358a4e7bcbf85b92aa992ec6439214dbd4405`, bundle ID `com.app.cadenabitcoin` and Apple Team ID
`D65458CPDP`, and accepts D3, D6, D7, D8, D9, D10, D11, D12 and D14 as worded in section 4. It states: "G2S execution becomes authorized only when
these conditions are reflected in the approved and merged release record and the workflow's authorization gate passes." **Supplemented on 2026-11-20 by the
CTO's decision https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7046097307** (workflow correction; see "Failed attempt and corrected workflow" below), which does not replace this authorization.

**The operation G2S authorizes (exhaustive).** One run of `.github/workflows/ios-hosted-signing.yml`, started by hand from `development` for the
approved source, version, bundle ID and team above, through the protected environment `ios-hosted-signing`: one unsigned archive is built, exported
and signed with Apple's cloud-managed Distribution certificate through the dedicated team API key (D7, D14), the IPA is verified (V1 to V9), and text
evidence is kept (the signing certificate's SHA-256, the IPA's SHA-256, the checks).

**What G2S does not authorize.** Upload to App Store Connect, TestFlight distribution, tester assignment or any distribution of the IPA (the IPA is not
uploaded or retained), App Review, public release, any other version, build, commit, bundle ID or team, a second run (condition 8), a temporary Admin-level
credential, and any decision of D1, D2, D4, D5, X1 or X2. G2, G3, G4 and G5 are **not authorized**; this record's status stays `G1 AUTHORIZED`.

**The CTO's conditions, and how they are met.**

| # | Condition (comment of 2026-11-20) | Where it is met |
|---|---|---|
| 1 | The release-policy and release-record amendments are reviewed and merged into `development` | The pull request that merges this section |
| 2 | All required G2S decisions are formally recorded | Section 4: D3, D6, D7, D8, D9, D10, D11, D12 and D14 are `Decided`, 2026-11-20; the gate refuses unless each is |
| 3 | The authorization binds the approved source, version, workflow, gate, verification tools and native framework hash | The eleven G2S lines of section 6.1 (the blobs of the workflow, the gate and five tools; `G2S-DLC-WALLET-SHA256`); a later change to any of them invalidates the authorization |
| 4 | Signing executes through the protected `ios-hosted-signing` environment | The `sign` job is the only job with an environment (IOS_HOSTED_SIGNING.md section 4); configuration verified below |
| 5 | Any failed security or identity verification stops the operation | The workflow fails closed at every check; the native-library hash is compared **before** Xcode is selected and before any secret exists |
| 6 | No upload or tester distribution | The workflow contains no upload operation (statically tested); the IPA is not an artifact; D9 |
| 7 | Results, certificate identity, IPA hash and verification evidence are recorded | Section 7, filled by a reviewed pull request after the run |
| 8 | Additional signing runs require separate authorization | **Not technically enforced**: there is no run counter. Kept by the operational controls below (consumption at credential use, a new CTO authorization for any further attempt, a deliberate and specific environment approval, removal of the three credentials from the environment and withdrawal of the G2S lines by a reviewed pull request); see "One operation" below and IOS_HOSTED_SIGNING.md sections 5.1 and 7 |

**One operation: the limitation and its operational controls.** The CTO authorized **exactly one** hosted signing-and-verification operation. **The workflow does not
technically enforce a one-time execution limit.** It has no run counter; neither the gate, the release record nor the GitHub environment marks the authorization as used; the gate
keeps accepting the G2S lines of section 6.1, and the workflow can be started again, until the record is changed and the secrets are gone. The limit is therefore kept by the
following controls, which are procedures, not mechanisms:

1. **An attempt that reaches Apple credential use consumes the authorization**, whether or not signing succeeds. "Reaches credential use" means that the step "Export and
   sign with the cloud-managed Distribution certificate (the only step with secrets)" of the `sign` job started, that is, the three secrets were read.
2. **Any additional signing attempt requires explicit CTO authorization**: a new written decision on Issue #71 and a new reviewed record pull request that re-issues the G2S
   lines (with blobs and the `dlc_wallet` hash recomputed). Nothing else, including a retry button, a repeated run or a reviewer's approval, is such an authorization.
3. **A failure before Apple credentials are accessed is not a completed signing attempt**: a gate refusal, the tip check, a failed build, the archive validator, the
   `dlc_wallet` hash comparison or any other check that stops the run before the secret step. It does not consume the authorization by itself, but **any subsequent
   attempt still requires an explicit operator decision**: the person who starts runs (for this release, the CTO) decides, notes the decision on Issue #71 with the failed
   run's ID and the cause that was understood, and only then dispatches again. A hash mismatch or a changed bound file is not retried until a reviewed record pull request
   has authorized the new value or implementation (section 6.1).
4. **The environment deployment approval must be deliberate and specific to the authorized operation.** The required reviewers confirm the deployment of one particular run.
   Before approving, the approver checks that this run was started by the CTO for this authorization; that it is the first attempt (not a re-run of an earlier run, and no other
   attempt is waiting); that its workflow commit is the tip of `development` and contains this record; that the inputs are the approved source, content reference and version
   `1.0.4+1000035`; and that the `authorize` and `build` jobs succeeded with `authorized=true`. An unexpected or doubtful deployment is **rejected**, never approved "to see
   what happens". The approval confirms a deployment only (D12); it does not authorize anything and does not replace the checks above.
5. **After the signing attempt, whatever its result:** (a) remove the three Apple credentials (`APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`) from the GitHub
   environment `ios-hosted-signing` at once, because that is what actually stops a further run while the next step is reviewed; (b) withdraw the G2S authorization through a
   reviewed pull request that sets the first line of section 6.1 to `G2S-STATUS: WITHDRAWN` (the gate then refuses). The results are recorded separately (section 7).
6. **Removing the GitHub secrets does not revoke the Apple Developer API key.** The key stays valid in App Store Connect, and the CTO's own copies of the `.p8` file are
   untouched, until the key is rotated or revoked there. Rotation and revocation remain available security controls and are **not** made mandatory by D14; they are a separate
   decision, to be taken at once if anything about the attempt is in doubt.

**Failed attempt and corrected workflow (authorization update of 2026-11-20).**

| Item | Fact |
|---|---|
| Run | `44738600156`, `workflow_dispatch` from `development` at `5270380c1b379ae63967d0dbc1c3e72bc3fee2b9` (2026-11-20): https://github.com/CadenaBitcoin/signer_app/actions/runs/44738600156 |
| Result | **FAILED** |
| Authorization gate | **PASSED** |
| Unsigned archive build | **PASSED** (archive SHA-256 `360746599adeccd28c6b72d79b4dd8a2b3c12e638733ca06af3375c493737163`) |
| Archive validation | **PASSED** before and after extraction; the `dlc_wallet` SHA-256 equals the authorized `9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13` (a fourth independent build) |
| Failure | The unsigned-state check of the `sign` job: `codesign -dv` exits non-zero for an unsigned bundle and the step ran under `pipefail`, so a genuinely unsigned archive was refused ("The archived app is not unsigned."). The archive was unsigned (no `_CodeSignature`, no embedded profile, the same Mach-O state as the preflight archive) |
| Apple credential-use step | **NOT REACHED**: skipped; no secret was read (the job log has no `APPLE_API` and no `exportArchive`) |
| Apple signing | **NOT EXECUTED** |
| App Store Connect upload | **NONE** |
| G2S operation consumed | **NO**: a failure before Apple credential use is not a completed signing attempt (section 4.2, control 3) |
| Credentials | The three environment secrets were removed afterwards: 0 environment, 0 repository and 0 organization secrets (read from GitHub on 2026-11-20) |
| Corrective implementation | **PR #116** (merge commit `e83201c9011925d118d356fa911e7c0a37502131`): the unsigned-state check judges `codesign`'s text instead of its exit status; the Report step no longer fails on an absent optional file; the V9 privacy-manifest line no longer decides the step's exit status. No security check is weakened |
| Workflow identity | `G2S-WORKFLOW-BLOB`: `2a0b4c3c07730c034bb4ac5fa7d859b3a5cf8f4a` (before) to `60945f9aeabc6c0a3dbeaee5de541879b641fd2c` (PR #116). The gate (`3807ee8a...`), the five bound tools, the application, the native library and `G2S-DLC-WALLET-SHA256` are unchanged. The previous workflow blob is **no longer authorized** |
| CTO decision | "CTO Decision: G2S Workflow Correction and Authorization Update", Issue #71 comment `7046097307` (`CadenaWizard`, 2026-11-20T17:26:33Z, never edited): https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7046097307 |

**This is a corrected attempt, not a second signing operation.** The CTO approved proceeding with a corrected attempt after a failure that stopped before Apple credential use.
The original G2S authorization (comment `7038341975`) stays the authorization of the operation and of its nine decisions; the update of comment `7046097307` supplements it with the
corrected workflow identity and replaces nothing else. The authorized scope is unchanged: **one** signing-and-verification operation, **no upload, no distribution**; it does not authorize an
additional signing operation after Apple credential use. The CTO's conditions of that update, and where they are met:

| # | Condition (comment of 2026-11-20, 17:26) | Where it is met |
|---|---|---|
| 1 | The updated workflow identity is recorded through a reviewed pull request merged into `development` | This record update |
| 2 | The authorization gate accepts the updated release record | The gate's verdict on this record with the corrected workflow, gate and tools |
| 3 | The protected `ios-hosted-signing` environment remains enforced | Reviewers `sziller` and `CadenaWizard`, administrator bypass disabled, deployment branch `development` only (read on 2026-11-20) |
| 4 | No further change to the bound workflow, gate or verification tools without reauthorization | The G2S blob lines of section 6.1: any change makes the gate refuse |
| 5 | No upload, TestFlight distribution or later gate is authorized | Unchanged: G2, G3, G4 and G5 are not authorized; the workflow has no upload operation |
| 6 | The Apple credentials are restored only after the updated authorization is merged and verified | The owner re-creates the three environment secrets only after this record is merged on `development` and the gate has been re-checked against it |
| 7 | The one-operation controls and the post-attempt credential-removal requirements remain in force | Section 4.2, "One operation" (controls 1 to 6), unchanged |

**Second attempt: run 44800943301 (consumed; Authorization A withdrawn by PR #118).** The corrected workflow of PR #116 was dispatched by `sziller` from `development`
at `78f77d0456cf85c4fefcdf60237d08cfec54d1d9` (the merge of PR #117, which made the CTO's update of comment `7046097307` effective) after the three credentials were restored
(2026-11-20, 19:18 to 19:29 UTC); the deployment was approved by `CadenaWizard` (the required reviewer, the same person as the dispatcher, D12). Evidence read from the run's GitHub
Actions record and from the evidence artifact (the downloaded copy equals the artifact file for file):

| Item | Fact |
|---|---|
| Run | `44800943301`, attempt 1, `workflow_dispatch`: https://github.com/CadenaBitcoin/signer_app/actions/runs/44800943301 |
| Authorized workflow revision | `78f77d0456cf85c4fefcdf60237d08cfec54d1d9` (the `development` tip; `workflow_blob` `60945f9aeabc6c0a3dbeaee5de541879b641fd2c`, the gate and the five tools as recorded in section 6.1) |
| Result | **FAILED** |
| Authorization gate | **PASSED** (job `authorize`); re-checked in the `sign` job before any secret was touched |
| Unsigned archive build | **PASSED** (job `build`; no secret, no environment); archive tar SHA-256 `b20362280ba12e4fac0b789a36dc5d3e74a31533ce49888419e66c46f7f3c02c` |
| Archive validation | **PASSED** before and after extraction (250 members, 0 symbolic links); bundle `com.app.cadenabitcoin`, `1.0.4`, `1000035`; archived app **not signed at all** |
| Authorized `dlc_wallet` SHA-256 | **PASSED**: the archive's binary equals the authorized `9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13` |
| Xcode | 26.3 (17C529) selected |
| Pre-signing environment | **VERIFIED** empty: `0 valid identities found`, `provisioning profiles installed: 0` |
| Apple credential-use step | **REACHED**: "Export and sign with the cloud-managed Distribution certificate (the only step with secrets)" started and failed |
| Xcode export | **FAILED**: `xcodebuild -exportArchive` exit **70** (`** EXPORT FAILED **`) |
| Errors (verbatim) | `error: exportArchive Cloud signing permission error` (16 lines); `error: exportArchive No signing certificate "iOS Distribution" found` (15 lines); `error: exportArchive No profiles for 'com.app.cadenabitcoin' were found` (1 line) |
| Distribution certificate | **Not available to the export** ("No signing certificate "iOS Distribution" found") |
| Provisioning profile | **Not found** ("No profiles for 'com.app.cadenabitcoin' were found") |
| Signed IPA | **NONE** (the run's artifacts are the build evidence, the unsigned archive and the signing evidence; no IPA; the workflow retains none) |
| App Store Connect upload | **NONE** (the workflow has no upload operation) |
| Signing certificate / IPA hashes (D8) | No signing certificate fingerprint or IPA hash was obtained or recorded; no signed IPA was produced. The D8 certificate fingerprint remains unrecorded. |
| **G2S operation** | **CONSUMED** (control 1: the credential-use step started, so the authorization is consumed whether or not signing succeeds) |
| Credentials | The key file was removed from the runner (`key_file_removed=yes`); afterwards the three environment secrets were deleted: GitHub reports 0 environment, 0 repository and 0 organization secrets visible to the repository (read on 2026-11-20) |
| Evidence artifact | `ios-hosted-signing-evidence_44800943301-1` (also `ios-hosted-build-evidence_44800943301-1` and `ios-hosted-unsigned-archive_44800943301-1`); its `SHA256SUMS.txt` has SHA-256 `65af5138443c72a04a62341ff3046e1d1c56181392bb1db62c453d55833ab415` |

**What the evidence shows, and what remains uncertain.** The failure is an Apple **cloud-signing permission error** raised by `xcodebuild -exportArchive`, followed by the absence of
a Distribution certificate and of a profile for the bundle ID. The evidence does **not** establish the underlying cause. The workflow's diagnosis step found 16 lines of
`Cloud signing permission error` and none of `forbidden`, `401`/`403`, `does not have permission`, `No Accounts` or `Failed to Use Accounts`; its own note says that the text
alone does not prove a cause. In particular, **it is not established that the Developer role of the API key is the root cause**, and it is not established that the key was
accepted or refused as such. Whether a cloud-managed Distribution certificate can be used by any role, whether an App Manager key would suffice, and what other requirement
Apple's cloud signing has on the team or the key, are **unconfirmed**. No Apple-side setting was read or changed for this record, and the key was not rotated or revoked
(control 6: removing the GitHub secrets does not revoke the Apple API key; that remains a separate decision of the CTO).

**Authorization A withdrawn (the state when PR #118 was merged).** Because the operation was consumed, PR #118 set `G2S-STATUS` to `WITHDRAWN` in section 6.1 (control 5(b)). The gate then refused, so the workflow could not be started
again on the strength of that record, and **at that time no signing operation was authorized.** The history is retained as it was: the original authorization (comment `7038341975`), the
failed pre-credential attempt `44738600156` and its outcome (not consumed), the CTO's update (comment `7046097307`), PR #116, PR #117 and the nine decisions of section 4 are
unchanged. The other G2S lines of section 6.1 kept their values as the record of what was authorized, and authorized nothing while the status was `WITHDRAWN`. Any further
signing attempt required, as control 2 says, a **new explicit CTO authorization**: a new written decision on Issue #71 and a new reviewed record pull request that re-issues
the G2S lines. That is **Authorization B** (section 4.3, CTO decision `7050074107`), a separate authorization and **not** a corrected attempt of the consumed operation of Authorization A.
G1 stays authorized; G2, G3, G4 and G5 stay **not authorized** (section 6).

**Next experiment: a proposal only, not an authorization.** The direction the CTO intends to consider is a **new App Store Connect team API key with the App Manager role**
(a new dedicated key; the Developer-role key of D14 is not widened). The reasoning: the Developer-role key met a cloud-signing permission error, and the preference is **incremental
privilege escalation** rather than issuing an Admin-level key at once. Whether the App Manager role can use cloud signing is **unverified**; **another failure is an explicitly
accepted possibility**. This paragraph is a proposal: it does **not** authorize creating, storing or using that key, does not amend D14 (which accepts a Developer-role key),
authorizes no signing operation and no use of any credential. Before any such attempt the CTO would decide, in a new written decision and a reviewed record pull request, the
credential, its role, its accepted risks (the decision about a role above Developer amends D14 and is the CTO's), whether the bound workflow needs changes, and the new operation.
**Update (2026-11-20):** the CTO has since decided this direction as **D15** and **Authorization B** (section 4.3); the paragraph above is kept as the history of the proposal.

**Historical statement.** This authorization update became effective when PR #117 was merged into `development` (2026-11-20, merge commit `78f77d0456cf85c4fefcdf60237d08cfec54d1d9`). It governed run `44800943301` (section 4.2, "Second attempt"). That operation was **consumed**, and **Authorization A was withdrawn** through PR #118 (`G2S-STATUS: WITHDRAWN` at that time); the update authorizes nothing further, and merging the record that withdrew it enabled no signing operation. Authorization B (section 4.3) is separate and does not revive it.
G1 remains authorized; G2, G3, G4 and G5 remain unauthorized.

**Credential-free preflight (2026-11-20).** Run `44726071796`, `workflow_dispatch` from `development` (`02375314a50d0da52872bbab01921f58c82d3196`) with the approved inputs:
https://github.com/CadenaBitcoin/signer_app/actions/runs/44726071796 . Result: success; the gate said `authorized=false`, the `sign` job was **skipped** (no
deployment to the environment, no secret, nothing signed or uploaded). The unsigned archive (`Runner.xcarchive.tar`, SHA-256
`6905272e54a679cec75fb3ed21fce0ba3cbcea46ba0670e3d8d6636aa0a48106`, 212,678,656 bytes) was downloaded and checked: source `42d358a4...`, version `1.0.4+1000035`, bundle
ID `com.app.cadenabitcoin`, Rust library `203dcd7abe4187de0b756638a55f691b2d5c680b17d4fbfa7dda550ed703949b` (the pinned value); `tool/validate_handover_archive.py list` passed before extraction (250 members,
0 symbolic links) and `tree` passed after extraction (249 entries); `Frameworks/dlc_wallet.framework/dlc_wallet` has SHA-256
`9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13`, equal to the value authorized in section 6.1 and identical in three independent builds on two runner images
(15 of the 16 Mach-O binaries were identical in all of them; the Dart snapshot `App.framework/App` was not). **A later build is not assumed to reproduce it:**
if it differs, the run stops before any secret is used and only a reviewed record pull request can authorize another binary.

**The GitHub environment `ios-hosted-signing` (read from the GitHub API on 2026-11-20).** Required reviewers: `sziller` and `CadenaWizard`;
administrator bypass **disabled**; `prevent_self_review` off; wait timer none; deployment branches: custom policy, exactly `development`; environment
secrets **0**, environment variables 0, repository secrets 0, organization secrets 0. The three environment secrets of IOS_HOSTED_SIGNING.md section 3
are created by the owner after this record is merged; no Apple credential is in GitHub today.

**Deferred: not prerequisites of G2S, required before the gate shown.** The signed IPA never leaves the runner under G2S: nothing is sent to App Store
Connect and nobody can install it.

| Row | Why G2S does not need it | Required before |
|---|---|---|
| D1 (Issue #22) | The CTO accepted the residual risk for internal TestFlight on Issue #71 (comment `6833982603`, 2026-11-12); the row is still to be recorded as decided | G2 |
| D2 (zero-value wallets) | No wallet material is involved in signing | G2 and every device test |
| D4 (production App Store Connect record) | The build number is consumed only by an upload | G2 |
| D5 (production gate) | It concerns the ledger and the upload; this run adds no ledger entry | G2 |
| X1 (export compliance, App Privacy) | Asked at upload and processing | G2 (App Privacy also before G3 and G4) |
| X2 (privacy manifest) | Apple evaluates it at upload processing; the technical evidence is complete (section 4, X2) | G2 (accept or fix); a fix changes frozen source and needs a new G1 before G4 or G5 |

### 4.3 G2S Authorization B: one new hosted signing-and-verification operation with the App Manager key (authorized, conditional)

**Authorizations A and B, kept apart.**

| | Authorization A (historical) | Authorization B (current) |
|---|---|---|
| CTO decisions | Original: Issue #71 comment `7038341975`; corrected workflow: comment `7046097307` | Issue #71 comment `7050074107` |
| Credential decision | D14: dedicated **Developer**-role team key | D15: dedicated **App Manager**-role team key, Key ID `47PP4C673P` |
| Workflow blob | `2a0b4c3c07730c034bb4ac5fa7d859b3a5cf8f4a`, then `60945f9aeabc6c0a3dbeaee5de541879b641fd2c` (PR #116) | `60945f9aeabc6c0a3dbeaee5de541879b641fd2c`, unchanged |
| Runs | `44738600156` (failed before credential use; not consumed); `44800943301` (reached credential use, failed at the export; **CONSUMED**) | none yet |
| State | **CONSUMED, permanently; WITHDRAWN** by PR #118 (merge `3dd49937e80961dbcd5459762d30aabf5c07709d`) | **AUTHORIZED, conditional**: executable only when the conditions below are met; ONE operation |
| `G2S-AUTHORIZATION` (section 6.1) | `https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7038341975` | `https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7050074107` |

Authorization A stays permanently consumed and is not reactivated. **Authorization B is independent of A**: it is not an extension, a continuation, a retry or a reactivation of A, and a run
under it is not "the second attempt" of A. The distinction is kept by this record (this ledger and sections 0, 4.2, 6, 6.1 and 7), by the CTO's written decisions, by human review of the record pull request and of the deployment, by the run IDs and evidence artifacts
(`ios-hosted-signing-evidence_<run>-<attempt>`) recorded in section 7 for each, and by the controlled registration of the credential (below). **It is not technically enforced** by the authorization gate (section 6.1), so this table is what a reader and the approver use.

**The authorization.** The CTO's written decision "CTO Decision: G2S Authorization B: App Manager Signing Experiment" on Issue #71:
https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7050074107
(comment id `7050074107`, account `CadenaWizard`, created 2026-11-20T20:38:48Z, never edited). It is **APPROVED, conditional on a reviewed and merged release-record update**. It names
the application (Cadena Bitcoin Signer App), `APPROVED_SHA` `42d358a4e7bcbf85b92aa992ec6439214dbd4405`, `CONTENT_REF` `862831e0b3a0f30c4155d2e086c69fc28bdab286`, version `1.0.4 (1000035)`,
bundle ID `com.app.cadenabitcoin`, Apple Team ID `D65458CPDP`, API key `47PP4C673P` (App Manager), workflow blob `60945f9a...`, gate blob `3807ee8a...` and the native-library SHA-256
`9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13`; it requires the five bound tool identities to match this record and to be re-verified before execution; it introduces **D15**
(section 4), explicitly accepts the risks listed there, and authorizes **one new** GitHub-hosted signing-and-verification operation: one archive export using Apple's cloud-managed Distribution signing,
followed by the prescribed IPA verification. It does **not** authorize upload, TestFlight distribution, App Review submission or public release, changing the application source, or changing the signing infrastructure.
G1 remains authorized; G2, G3, G4 and G5 remain unauthorized.

**The operation Authorization B authorizes (exhaustive).** One run of `.github/workflows/ios-hosted-signing.yml`, started by hand from `development` for the approved source, content reference,
version, bundle ID and team above, through the protected environment `ios-hosted-signing` (unchanged: required reviewers `sziller` and `CadenaWizard`, administrator bypass disabled, deployment branch
`development` only), with the three environment secrets holding the key of D15. The rules of section 4.2 apply unchanged: one archive, one export, verification V1 to V9, text evidence, no upload, no retained IPA.

**Single operation and controls (CTO decision, section 4).**

1. **Exactly one new operation.** It is **consumed when Apple credential use begins** (the step "Export and sign with the cloud-managed Distribution certificate (the only step with secrets)" starts), regardless of
   whether signing succeeds.
2. **A failure before credential use** (the gate, the tip check, the build, the archive validator, the `dlc_wallet` hash comparison) does not consume it, but **another dispatch then needs a documented operator decision** on Issue #71 under
   the existing policy (section 4.2, control 3). Nothing else is such an authorization, and a further attempt after consumption needs a new CTO decision and a new reviewed record pull request.
3. **The environment stays mandatory** with its reviewers, branch restriction and disabled administrator bypass. The reviewers confirm the deployment only (D12); before approving, the approver checks the points of section 4.2, control 4,
   and that this is the first run under Authorization B.
4. **The private key may be configured as a GitHub environment secret only after** this record is merged into `development` **and the authorization gate has passed against the final `development` revision.** The three Apple secrets
   must not be restored before that. This record's pull request must be the **final merge into `development` before execution** (the gate requires the workflow revision to be the `development` tip).
5. **After the attempt, whatever its result:** all three Apple environment secrets are removed at once; the outcome is recorded (section 7); **Authorization B is withdrawn through a reviewed release-record pull request**
   (`G2S-STATUS: WITHDRAWN`). Removing the secrets does not revoke the Apple key; neither key is revoked automatically (D15).

**The CTO's conditions for effectiveness, and where they are met.**

| # | Condition (comment `7050074107`) | Where it is met |
|---|---|---|
| 1 | The release record explicitly distinguishes Authorization A from Authorization B | This section, the ledger above, sections 0, 4.2, 6, 6.1 and 7 |
| 2 | D15 records the accepted App Manager credential risks | Section 4, row D15 |
| 3 | The new authorization reference identifies this CTO decision | `G2S-AUTHORIZATION` in section 6.1 names comment `7050074107` |
| 4 | The workflow, gate, verification tools and approved native-library identities are verified | See "Implementation identity" below; the gate verifies the blobs again at every run |
| 5 | The authorization gate accepts the revised record | The gate's verdict on this record, with the workflow, gate and tools of this checkout, is recorded in the pull request |
| 6 | The revised record has been reviewed and merged into `development` | The pull request that merges this section; effective only from that merge |

**Implementation identity (verified for Authorization B; nothing is changed).** Verified on 2026-11-20 against `development` at `3dd49937e80961dbcd5459762d30aabf5c07709d`, independently with `git hash-object` and with
`bash tool/check_signing_authorization.sh --print-expected --tools-root .`: workflow `60945f9aeabc6c0a3dbeaee5de541879b641fd2c`, gate `3807ee8a1b8caf4ce5f22a6f2540c0658aba90b6`, and the five tools
(`tool/build_manifest.py` `6e6c153e...`, `tool/ipa_inspect.py` `af7ced43...`, `tool/validate_handover_archive.py` `ef4ce2c6...`, `tool/verify_artifact.sh` `99074f4b...`, `tool/verify_ipa.py` `6ee2b9d7...`; full values in
section 6.1). They are the same files as under the corrected Authorization A (the workflow of PR #116): this record changes no workflow, gate, tool, application or native-library file. The native library's
`dlc_wallet` SHA-256 `9a2d1d98...` was equal in every archive built so far, including run `44800943301`'s; **a later build is not assumed to reproduce it**: if it differs, the run stops before any secret is used.

**Known limitations, recorded rather than fixed (the workflow is not modified).**

- **Stale diagnostic wording.** The workflow's diagnosis step prints "The Developer role of the key is a candidate cause if a permission or 401/403 pattern matches; the text alone does not prove it.", and a comment of the
  workflow says the run tests whether the Developer role suffices. Under Authorization B the key's role is App Manager: that wording is **informational and stale**. It decides nothing, and the text never proves a cause. In the
  evidence of a run under Authorization B it is to be read as "the role of the key".
- **The key is not machine-bound.** The gate and the workflow bind neither the API key ID nor its role: they read three secrets by name (`APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`), and the logs redact the values.
  Nothing in a run proves that the secrets hold key `47PP4C673P`. That is a procedural control: the CTO loads exactly that key (D15), and no other credential, after the conditions above are met.
- **Capability unverified.** Whether an App Manager key can use Apple's cloud-managed Distribution signing is unconfirmed (D15, D7). The record does not assume it suffices; a failure is a result of the experiment, not a defect, and
  would consume the operation.
- **The D8 certificate fingerprint is still unrecorded**; if signing succeeds, it is only discovered in this run (`pin_source=DISCOVERED`) and is recorded in section 7 by the coordinator.

**Not authorized.** Upload to App Store Connect, TestFlight distribution, tester assignment, App Review, public release; any second operation under B; any Admin-level or Account Holder credential; any change of the source,
the workflow, the gate or the bound tools; G2, G3, G4 and G5.

## 5. Facts confirmed by the operator before signing (IOS_RELEASE.md section 6)

**Provenance of the answers below.** *Coordinator-reported (2026-11-19)*: the release coordinator read Apple's Developer and App Store
Connect web pages directly; the values are not verified through the App Store Connect API, and no screenshot, account address or
other account detail is stored here. *Repository-verified*: read from the approved source or the repository. *Noah-reported*: given
earlier by the intended operator and not verified. None of these entries decides a D or X row, authorizes a gate, or records the
operator's acceptance of the role.

| # | Fact | Answer |
|---|---|---|
| 1 | Team, enrollment type, Team ID | Organization "Cadena Bitcoin S.A. de C.V.", enrollment type Organization, Team ID `D65458CPDP` (**coordinator-reported, 2026-11-19**). The Team ID equals `DEVELOPMENT_TEAM` in `ios/Runner.xcodeproj` (repository-verified). The team the operator signs in as on the operator's Mac is **not yet confirmed** (a G2 matter). For G2S the workflow's V3 reads `TeamIdentifier` from the signed app and stops on any team other than `D65458CPDP` |
| 2 | App Store Connect record: name, SKU, bundle ID, status | App "Cadena Bitcoin", SKU `com.app.cadenabitcoin`, Apple App ID `6753348211`, bundle ID `com.app.cadenabitcoin` (equals the repository's production bundle ID), iOS version record `1.0.4` in status `Prepare for Submission` (**coordinator-reported, 2026-11-19**). Nothing has been submitted for review |
| 3 | Live version and highest build ever uploaded | Highest build seen in the App Store Connect builds list: version `1.0.3`, build `1000034`, uploaded 2026-07-30; no build `1000035` or higher was in the inspected list (**coordinator-reported, 2026-11-19, not API-verified**; consistent with Noah's earlier report). The stop condition "highest build 1000035 or more" is not triggered on this evidence. Not stated: whether the inspected list covered expired and never-released builds. Live iOS version: TBD (not stated) |
| 4 | App ID registration and capabilities | Push Notifications is enabled on the registered App ID (Noah; **coordinator-reported, 2026-11-19**). No manually managed provisioning profile is visible in the portal (coordinator-reported; Xcode-managed profiles are not shown there). **A registered capability is not evidence that the application implements push**: the app declares the `remote-notification` background mode and has no entitlements file and no `aps-environment` (repository-verified; D6) |
| 5 | Operator's role and access | The Apple Developer organization has Admin accounts for the coordinator and for the intended operator; the coordinator reports that the operator's Apple-side privileges suffice for the planned workflow (**coordinator-reported, 2026-11-19**; account addresses are deliberately not recorded). **Still unverified:** the operator's acceptance of the role (section 2) and the operator's Xcode sign-in and signing capability on the Mac. Neither is needed for G2S (D3) |
| 6 | Distribution certificate: SHA-256 fingerprint, expiry, creator, key holder | An Apple **cloud-managed** Distribution certificate is listed, valid until 2027-07-09, created under the organization (no individual named); an Apple Development certificate is also listed, valid until 2027-07-09, its management type not stated (**coordinator-reported, 2026-11-19**). There is no local Apple Distribution certificate and no private key on any Mac (**Noah, not verified**). No certificate or profile was created for this inspection. **Cloud-managed signing has not been demonstrated by a signing operation for 1.0.4.** Fingerprint: **not known before signing**; collected from the signed IPA with `verify_ipa.py certificate` and recorded in section 7 by the coordinator before upload. The portal's expiry is a listing; the signing certificate's own expiry is read from the IPA (IOS_RELEASE.md section 9, V3, V4) |
| 7 | Signing route (A automatic / B manual) | A: automatic signing with Apple's cloud-managed Distribution certificate through a team API key; **decided for G2S by D7 on 2026-11-20** (section 4) |
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

Only G1 and the signing-only G2S have been decided: G2S Authorization A is withdrawn (consumed); G2S Authorization B is authorized, conditionally (section 4.3). Nothing in sections 1 to 4 substitutes for a row below, and G1 implies no other row; G2S implies no upload and none of G2 to G5. The policy basis is section 4, D11 and D12.

| Gate | Decision | By | Date | Reference |
|---|---|---|---|---|
| G1 source (commit only) | **AUTHORIZED** | CTO and release coordinator, GitHub account `CadenaWizard` | 2026-11-12 | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-6833584989 |
| **G2S Authorization A** hosted signing and verification only: the CTO's written authorization of ONE GitHub-hosted signing-and-verification operation; **no upload, no distribution; not G2** (section 4.2) | **WITHDRAWN: authorization CONSUMED by run `44800943301`** (historically: authorized, conditional, one operation; it reached Apple credential use and failed at the export; no signed IPA, no upload; section 4.2, "Second attempt"). **Authorization A authorizes no further signing operation, and never will again**: it is permanently consumed. A further operation needs a separate, new CTO authorization; that is **Authorization B**, in the next row, which is not an extension or reactivation of A | CTO, GitHub account `CadenaWizard` (authorization and update); withdrawn by the reviewed PR #118 | 2026-11-20 | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7038341975 (original authorization, historical); corrected workflow, historical: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7046097307 |
| **G2S Authorization B** hosted signing and verification only, with the dedicated App Manager-role key of D15: the CTO's written authorization of ONE **new** GitHub-hosted signing-and-verification operation; **no upload, no distribution; not G2; a separate authorization, independent of Authorization A (which stays consumed and withdrawn), not an extension or reactivation of it** (section 4.3) | **AUTHORIZED** (conditional: effective only when this record is merged on `development` and the workflow's gate passes; one operation; consumed when Apple credential use begins) | CTO, GitHub account `CadenaWizard` | 2026-11-20 | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7050074107 |
| G2 production signing and upload to App Store Connect: the CTO's written authorization of this manual operation, after the prerequisites of section 4.1 (not an exception to the authorization policy). **Not given by G2S**; a G2 operation builds and signs its own archive | **PENDING** | TBD | TBD | TBD |
| G3 assignment to named internal testers (the CTO) | **PENDING** | TBD | TBD | TBD |
| G4 submission to App Review (the CTO, a separate manual operation; needs the acceptance evidence of IOS_RELEASE.md section 11, which has no minimum duration) | **NOT AUTHORIZED** (not given) | | | |
| G5 public release (the CTO, separately from G4) | **NOT AUTHORIZED** (not given) | | | |

### 6.1 G2S authorization lines (read by the workflow's authorization gate)

These eleven lines are read by `tool/check_signing_authorization.sh` (IOS_HOSTED_SIGNING.md section 5). Each must stay exactly once, at the start of its
own line, with no other text on it, **outside** code blocks and comments; the gate also requires the decided rows of section 4, the status line of section 0,
the `APPROVED_SHA` row of section 3.1, and that the workflow revision is the current tip of `development`. They authorize **one** signing-and-verification operation and **never an upload**. **These lines are currently the lines of Authorization B** (section 4.3): `G2S-STATUS` is `AUTHORIZED` and
`G2S-AUTHORIZATION` names the CTO's decision of Authorization B. **Authorization A is consumed and stays so**: its lines carried `G2S-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7038341975` and, after run
`44800943301`, `G2S-STATUS: WITHDRAWN` (PR #118); that history is kept in section 4.2 and in this file's Git history. The other nine lines carry the same values as under Authorization A because the approved source,
the workflow, the gate, the five tools and the native library are the same (re-verified for Authorization B, section 4.3).

**What the gate does and does not do with these lines.** The gate checks that `G2S-AUTHORIZATION` has the required format, a link to a comment on Issue #71 (`…/issues/71#issuecomment-<digits>`), and appears exactly once. It does **not**
retrieve or validate that comment (its existence, author, date or content). It does **not** verify the API key ID or the key's role: the workflow reads three secrets by name and the gate never sees them. It does **not** enforce the operation
count: there is no run counter, and the gate accepts the lines for as long as they stay in the record. The gate therefore **cannot distinguish Authorization A from Authorization B**, and it cannot tell a first run from a later one. That distinction is
maintained **outside** the gate: by this release record (the ledger of section 4.3), by the CTO's written decisions (comments `7038341975` and `7046097307` for A, `7050074107` for B), by human review of the record pull request and of each
deployment approval, and by the controlled registration of the credential (the CTO loads exactly the key of D15, only after the merge and a passing gate). No technical enforcement is claimed.

The workflow does **not** enforce the one-operation limit (no counter): section 4.2, "One operation", lists the operational
controls, which apply to Authorization B unchanged. After the attempt of Authorization B the three credentials are removed from the environment and these lines are withdrawn by a reviewed pull request that sets the first line
to `G2S-STATUS: WITHDRAWN`; they must not be edited back to authorize another run without a new CTO decision and a new reviewed record pull request (section 4.2, control 2).

G2S-STATUS: AUTHORIZED

G2S-OPERATION: sign-and-verify-only

G2S-APPROVED-SHA: 42d358a4e7bcbf85b92aa992ec6439214dbd4405

G2S-VERSION: 1.0.4+1000035

G2S-BUNDLE-ID: com.app.cadenabitcoin

G2S-TEAM-ID: D65458CPDP

G2S-WORKFLOW-BLOB: 60945f9aeabc6c0a3dbeaee5de541879b641fd2c

G2S-GATE-BLOB: 3807ee8a1b8caf4ce5f22a6f2540c0658aba90b6

G2S-TOOL-BLOBS: tool/build_manifest.py=6e6c153e4accb9b03dcac13964a840272fa76d82,tool/ipa_inspect.py=af7ced4341873dcff0113c4c417c0cce697938f6,tool/validate_handover_archive.py=ef4ce2c686e2ae7c3eacb61d078764f8c5b71c3d,tool/verify_artifact.sh=99074f4b03e7db9a69cb1cfd03ee2b867e8dfd4a,tool/verify_ipa.py=6ee2b9d74c31321904e2c042aa2bc82fc402ab35

G2S-DLC-WALLET-SHA256: 9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13

G2S-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7050074107

Requirement before any G4 request: the acceptance criteria of IOS_RELEASE.md section 11 are met and evidenced on physical devices
installed through TestFlight. **There is no mandatory time window** (CTO decision of 2026-11-17). A TestFlight upload is not App
Review and not a release.

## 7. Results (filled from the operator's evidence; hashes and text only)

| | |
|---|---|
| G2S Authorization A attempt history: run `44738600156` FAILED before Apple credential use (corrected by PR #116); the operation was **not consumed**; no signing, no upload (section 4.2) | Recorded in section 4.2 |
| G2S Authorization A attempt history: run `44800943301` FAILED at the Xcode export (exit 70, cloud signing permission error; no certificate, no profile) after Apple credential use; the operation of Authorization A is **CONSUMED** and Authorization A is **WITHDRAWN** (PR #118); no signed IPA, no upload; credentials removed (section 4.2, "Second attempt") | Recorded in section 4.2 |
| G2S Authorization A run (hosted signing and verification): run ID and conclusion; evidence artifact `ios-hosted-signing-evidence_<run>-<attempt>` and its `SHA256SUMS` value; the first-run signing-certificate SHA-256 (D8, circular until recorded) | Run `44800943301`, **FAILED** (export exit 70), evidence artifact `ios-hosted-signing-evidence_44800943301-1`, `SHA256SUMS.txt` SHA-256 `65af5138443c72a04a62341ff3046e1d1c56181392bb1db62c453d55833ab415`; No signing certificate was obtained or recorded from this attempt, so the D8 hash is still unrecorded |
| G2S Authorization B attempt history: **no run yet**. Authorization B (section 4.3) is a separate operation from Authorization A; its runs, evidence artifacts and outcome are recorded here, separately, after the attempt | Not executed |
| G2S Authorization B run (hosted signing and verification, App Manager key of D15): run ID and conclusion; evidence artifact `ios-hosted-signing-evidence_<run>-<attempt>` and its `SHA256SUMS` value; the first-run signing-certificate SHA-256 (D8), if any | TBD |
| IPA SHA-256 and size | **NONE**: run `44800943301` produced no IPA; TBD for any later operation |
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
