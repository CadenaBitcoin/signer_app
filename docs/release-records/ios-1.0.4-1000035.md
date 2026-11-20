# Release record: iOS 1.0.4 (1000035), G1 AUTHORIZED (source only); G2S Authorizations A, B and C all consumed and withdrawn: no current G2S authorization

> **Record Status: `G1 AUTHORIZED`: the source commit only.** **G2S** (one GitHub-hosted signing-and-verification operation; no
> upload, no distribution) existed as three **separate** authorizations, and **all three are consumed and withdrawn; no G2S authorization is current**. **Authorization A** (section 4.2; Developer-role key) was consumed by run `44800943301` and
> withdrawn by PR #118; **Authorization B** (section 4.3; App Manager-role key) by run `44821325087` and PR #120; **Authorization C** (section 4.4, D16; the CTO's decision
> https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7052148143; Admin-role key) was consumed by run `44834801248`, in which **Apple signing succeeded** and the workflow then **failed at the repository's own IPA verification (V7/V8)**, and is withdrawn by this
> record (`G2S-STATUS: WITHDRAWN`, section 6.1; the gate refuses). None is reactivated; any further signing operation needs a **new explicit CTO authorization** and a new reviewed record pull request. Apple distribution signing for an upload, upload to App Store Connect
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
verification run each, recorded by the G2S lines of section 6.1, never an upload; none of the three G2S operations (Authorizations A, B and C) changes this status. **Authorization A is consumed and withdrawn** (section 4.2, "Second attempt");
**Authorization B is consumed and withdrawn** (section 4.3, "Execution of Authorization B");
**Authorization C is consumed and withdrawn** (section 4.4, "Execution of Authorization C"). No G2S authorization is current.

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
(section 4.2; the accepted risks are written into each row). **The G2S operation of Authorization A has since been consumed and that authorization withdrawn** (PR #118; section 4.2, "Second attempt"): these decisions are retained as the history of what was decided and authorize no run by themselves. On **2026-11-20** the CTO also decided **D15**, the App Manager credential of **Authorization B** (section 4.3): D14 stays the historical decision for the Developer-role key of Authorization A, and D15 is separate from it. **Authorization B has since been consumed and withdrawn** (section 4.3): D15 is retained as the history of what was decided and authorizes no run by itself. On **2026-11-20** the CTO also decided **D16**, the Admin credential of **Authorization C** (section 4.4): D14 and D15 stay the historical decisions for the keys of Authorizations A and B, and D16 is separate from them. **Authorization C has since been consumed and withdrawn** (section 4.4): D16 is retained as the history of what was decided and authorizes no run by itself. **D1, D2, D4, D5, X1 and X2 are not decided**: they are deferred to G2 and the later gates
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
| D7 | **Apple cloud-managed Distribution signing with automatic provisioning, through a team API key.** The archive is built unsigned and exported with `signingStyle` automatic, `-allowProvisioningUpdates` and the dedicated team API key of D14, so that Apple's **cloud-managed** Distribution certificate signs it (no private key on any Mac or runner). **Risks accepted by the CTO:** Xcode may **create** an Xcode-managed App Store provisioning profile and other certificate or profile objects in the team's account; these are changes in the Apple account that nobody can preview. Whether the Developer role suffices for cloud-managed Distribution signing, and whether an unsigned archive can be exported and signed, are **Unconfirmed**: a failure is a result of the experiment, not a defect, and a temporary Admin-level credential would need its own authorization (D14). Evidence: IOS_HOSTED_SIGNING.md sections 2 and 6; IOS_SIGNING.md section 5 **Applicability (added for Authorization B; the decision and its accepted risks are unchanged):** the text above describes Authorization A, with the Developer-role key. For Authorization B the same question is open for the App Manager role (D15): whether it suffices for cloud-managed Distribution signing is **Unconfirmed**, a failure is again a result of the experiment and not a defect, and no Admin-level credential is authorized. **Applicability (added for Authorization C; the decision and its accepted risks are unchanged):** for Authorization C the same question is open for the Admin role (D16): whether it suffices for cloud-managed Distribution signing is **Unconfirmed**, an Admin credential does not guarantee success, and a failure is again a result of the experiment and not a defect. **Outcome (added after run `44834801248`; the decision and its accepted risks are unchanged):** the Apple signing step succeeded with the Admin-role key of Authorization C, whereas those of the Developer-role (A) and App Manager-role (B) keys failed. The evidence supports the role as a plausible explanation and does not prove it; Authorization C is consumed and withdrawn (section 4.4). | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D8 | **Certificate verification: discovery in the first run.** The signing certificate's SHA-256 fingerprint is read from the signed IPA (`verify_ipa.py certificate`), cross-checked with `codesign` and `openssl`, and **recorded by the coordinator in section 7**. In the first run it is only **discovered** (`pin_source=DISCOVERED`, a circular pin); it becomes a pin when the recorded value is passed as `expected_cert_sha256` to a later run or checked before any upload. **Limits accepted by the CTO:** the value is read from the artifact it later judges; no chain to Apple without `--trust-anchors`; no revocation check. Evidence: IOS_RELEASE.md section 9 (V3, "V3 is discovery, then approval"); PR #107; IOS_HOSTED_SIGNING.md section 1 **Applicability (added after run `44834801248`; the decision and its limits are unchanged):** the first run that produced a signed IPA (Authorization C) **discovered** the signing certificate's SHA-256 `7ee3f6ce78eea83748e198102f6ab66527c626296baaea437c3a90db81ef418e` (section 4.4 and section 7). It is a discovered value, circular by D8's own terms, recorded as evidence; it is **not** an approved pin. | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D9 | **One archive, one export, verification; no upload.** G2S authorizes ONE operation: one archive is built from the approved commit, exported once, and the exported IPA is verified (V1 to V9; the comparison baseline of V8 is the application inside that archive; no second compile). The signed IPA **must not be uploaded or retained for distribution**: it stays on the runner and is gone with it, and nothing is sent to App Store Connect. The single-archive rule applies **per authorized operation**: a later G2 operation (upload) builds and signs its own archive under its own authorization, and its native-library hash is authorized again. A failed security or identity verification stops the operation. Evidence: IOS_HOSTED_SIGNING.md sections 1, 2.1 and 5 **Applicability (added for Authorization B; the decision is unchanged):** the limit is per authorization. The operation of Authorization A is consumed (section 4.2). Authorization B (section 4.3) authorizes one **new** operation, separately, under the same rules (one archive, one export, verification, no upload); it is not a second operation of Authorization A. **Applicability (added for Authorization C; the decision is unchanged):** the limit stays per authorization. Authorization C (section 4.4) authorizes one **new** operation, separately, under the same rules (one archive, one export, verification, no upload); it is not a further operation of Authorization A or B, both of which are consumed. | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D10 | **Verification tooling and implementation identity.** The workflow, the authorization gate and the tools that verify the IPA are exactly those named by the G2S blob lines of section 6.1: `G2S-WORKFLOW-BLOB`, `G2S-GATE-BLOB` and `G2S-TOOL-BLOBS` (the five tools `tool/build_manifest.py`, `tool/ipa_inspect.py`, `tool/validate_handover_archive.py`, `tool/verify_artifact.sh`, `tool/verify_ipa.py`), computed from the repository contents with `bash tool/check_signing_authorization.sh --print-expected --tools-root .`. The gate refuses to authorize if any of them differs, so a later change needs a new, reviewed authorization. This replaces the Mac route's `TOOLS_SHA` for G2S (section 1). Evidence: IOS_HOSTED_SIGNING.md section 5 | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D11 | **Reading of the gates for this release.** The merge of PR #102 (producing `M`) predates the authorization policy of 2026-11-17 and is G1, source selection only; it is not authorization to sign or upload. **G2S** is the CTO's separate, written authorization of one GitHub-hosted signing-and-verification operation, recorded by the G2S lines of section 6.1; it is signing only, never an upload or a distribution, and it is **not G2**. G2 (production signing for the one upload as "TestFlight & App Store"), G3 (assignment to named internal testers), G4 (submission to App Review, only after the acceptance evidence of IOS_RELEASE.md section 11, which has no minimum duration) and G5 (public release) remain the CTO's separate, written authorizations of specific **manual** operations and are **not authorized**. G2 and G3 are the initial internal TestFlight stage; submission is G4. No gate needs a second person | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D12 | **Policy basis.** The G2S operation is a manual operation started by hand (a manually started workflow in a protected environment) and is an operational exception to the future automation. It is **not** an exception to the authorization policy of RELEASE_POLICY.md principle 9 and section 2.3 (the authorized merge is the single human authorization boundary; `sziller` and `CadenaWizard` are one person): it needs the CTO's written authorization of that operation (section 4.2) and the merged record. The approval of the required reviewers of the environment `ios-hosted-signing` **confirms the deployment only; it does not replace the CTO's authorization** and does not create one. Upload and distribution remain **pending** until the prerequisites of section 4.1 are met and the CTO gives G2 | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D13 | Xcode other than 26.3 (17C529), if any | none | TBD | TBD |
| D14 | **Dedicated Developer-role Apple Team API key.** A **dedicated** App Store Connect **Team API key with the Developer role** is accepted as the credential of the G2S operation. It is stored only as environment secrets of `ios-hosted-signing` and never in the repository, a chat or a log. **Risk accepted by the CTO:** a team key's scope **cannot be restricted to this application** (access to all apps of the team, limited only by role; IOS_SIGNING.md section 5, option A, with the fallback recorded there). **Rotation and revocation remain available security controls; automatic revocation after the G2S operation is not mandatory.** Any temporary Admin-level credential requires its own, separate authorization. Evidence: IOS_SIGNING.md section 5; IOS_HOSTED_SIGNING.md section 2 **Applicability (added for Authorization B; the decision and its accepted risk are unchanged):** D14 is the historical decision for the Developer-role credential of Authorization A, which is consumed; it does not govern Authorization B, whose credential is decided by D15. **Applicability (added for Authorization C; the decision and its accepted risk are unchanged):** D14 likewise does not govern Authorization C, whose Admin credential is decided by D16; its sentence that any Admin-level credential requires its own separate authorization is met for Authorization C by D16 and the CTO's decision `7052148143`. | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D15 | **Dedicated App Manager-role Apple Team API key for G2S Authorization B.** A **dedicated** App Store Connect **Team API key** is approved for Authorization B only (section 4.3): name `Cadena iOS CI Signing -AppMngr`, **Key ID `47PP4C673P`** (an identifier, not a secret), role **App Manager**, purpose: the hosted iOS signing-and-verification experiment. The CTO states that the private key is stored locally outside the repository, with restricted filesystem permissions, and that its cryptographic format has been validated (a statement of the CTO; this record holds no key material and cannot verify it). Whether the key's capability is sufficient is **Unconfirmed**. It may be configured as an environment secret of `ios-hosted-signing` **only after** the record that makes Authorization B effective is merged and the gate has passed against the final `development` revision, and the three secrets are removed after the attempt (section 4.3). **Risks accepted by the CTO:** (1) the App Manager role provides broader permissions than Developer; (2) the team key is not restricted to a single application; (3) App Manager cloud-signing capability remains unverified; (4) another signing failure is possible even if the workflow operates correctly; (5) the independent backup of the private key is deferred; (6) the private key is temporarily available to the protected GitHub Actions signing job. **No Admin-level or Account Holder credential is authorized.** The previous Developer-role key (D14) remains unchanged; **neither key is revoked automatically**: revocation remains a separate operational decision, unless a compromise is suspected. D15 governs Authorization B only and does not extend to G2 or any later gate. Evidence: the CTO's decision https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7050074107 (section 3, "New credential: D15") **Applicability (added after the attempt; the decision and its accepted risks are unchanged):** Authorization B was consumed by run `44821325087` and withdrawn (section 4.3). D15 is retained as the history of what the CTO decided; the risks were accepted for that one operation only, and it authorizes no further use of the key. **Applicability (added for Authorization C; the decision and its accepted risks are unchanged):** D15's sentence "No Admin-level or Account Holder credential is authorized" described Authorization B. The Admin credential of Authorization C is decided separately by D16; D15 itself is not amended and authorizes no Admin credential. | Decided | CTO (CadenaWizard) | 2026-11-20 |
| D16 | **Dedicated Admin-role Apple Team API key for G2S Authorization C.** A **dedicated** App Store Connect **Team API key** is approved for Authorization C only (section 4.4): name `Cadena iOS CI Signing -Admin`, **Key ID `9Y3NM5CN5B`** (an identifier, not a secret), role **Admin**, purpose: the hosted iOS signing-and-verification experiment. The CTO states that the private key has been downloaded, stored locally outside the repository with restricted filesystem permissions, and validated with OpenSSL, and that an independent backup is **deferred** (statements of the CTO; this record holds no key material and cannot verify them). **The CTO explicitly accepts the elevated security risk of an Admin-role Team API key**, including: (1) account-wide access, not restricted to the Signer App; (2) broad administrative capabilities beyond application signing; (3) temporary exposure of the credential to the protected GitHub Actions signing environment; (4) the possibility that the Admin role will still fail to satisfy Apple's cloud-managed signing requirements (an Admin credential does not guarantee success); (5) the deferred independent backup of the private key. The credential must never enter the repository, application source, logs or release artifacts. It may be registered as environment secrets of `ios-hosted-signing` **only after** the record that makes Authorization C effective is merged and the gate has passed against the final `development` revision; **all three secrets are removed immediately after the experiment**; **no indefinite GitHub credential storage is authorized**. **Revocation of the Admin key remains a separate explicit CTO decision.** D16 governs Authorization C only and does not extend to G2 or any later gate; D14 and D15 remain the historical credential decisions of Authorizations A and B. If the Admin experiment produces the same Apple signing failure, **further privilege escalation is not authorized** by this decision. Evidence: the CTO's decision https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7052148143 (section 2, "New credential: D16") **Applicability (added after the attempt; the decision and its accepted risks are unchanged):** Authorization C was consumed by run `44834801248` and withdrawn (section 4.4). D16 is retained as the history of what the CTO decided; the risks were accepted for that one operation only, it authorizes no further use of the key, and **revocation of the Admin key remains a separate CTO decision** (the locally stored key has not been revoked). | Decided | CTO (CadenaWizard) | 2026-11-20 |
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
> **separate** operation with its own CTO decision, credential (D15) and single operation; it was authorized after A was withdrawn, is not an extension, a retry or a reactivation of A, and A stays consumed. **Authorization B has itself since been
> consumed by run `44821325087` and withdrawn (section 4.3).** **Authorization C** (section 4.4) was a separate, later authorization and has itself since been consumed by run `44834801248` and withdrawn; **no G2S authorization is current**. The authorization text and the CTO decisions of A are preserved unchanged as history; they authorize no further run.

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

### 4.3 G2S Authorization B: one new hosted signing-and-verification operation with the App Manager key (WITHDRAWN: CONSUMED by run 44821325087)

> **Current state.** This section is **Authorization B**, and everything in it except "Execution of Authorization B" is the **historical record** of what the CTO authorized and on which conditions. **Authorization B is consumed and withdrawn**:
> run `44821325087` reached Apple credential use, so its one operation is consumed, and PR #120 set `G2S-STATUS` to `WITHDRAWN`. Present-tense statements in this section (for example "authorizes", "may be configured", "is authorized,
> conditional") describe Authorization B **as authorized**, before the attempt; they do not describe the current status. **Authorization A also stays consumed and withdrawn.** **Authorization C** (section 4.4) was a separate, later authorization and has itself since been consumed and withdrawn;
> **no G2S authorization is current**.

**Authorizations A and B, kept apart.**

| | Authorization A (historical) | Authorization B (historical) |
|---|---|---|
| CTO decisions | Original: Issue #71 comment `7038341975`; corrected workflow: comment `7046097307` | Issue #71 comment `7050074107` |
| Credential decision | D14: dedicated **Developer**-role team key | D15: dedicated **App Manager**-role team key, Key ID `47PP4C673P` |
| Workflow blob | `2a0b4c3c07730c034bb4ac5fa7d859b3a5cf8f4a`, then `60945f9aeabc6c0a3dbeaee5de541879b641fd2c` (PR #116) | `60945f9aeabc6c0a3dbeaee5de541879b641fd2c`, unchanged |
| Runs | `44738600156` (failed before credential use; not consumed); `44800943301` (reached credential use, failed at the export; **CONSUMED**) | `44821325087` (reached credential use, failed at the export; **CONSUMED**) |
| State | **CONSUMED, permanently; WITHDRAWN** by PR #118 (merge `3dd49937e80961dbcd5459762d30aabf5c07709d`) | **CONSUMED by run `44821325087`; WITHDRAWN** by the reviewed record pull request (PR #120) that set `G2S-STATUS` to `WITHDRAWN` (authorized, conditional, ONE operation, before the attempt) |
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

**Execution of Authorization B: run 44821325087 (consumed; Authorization B withdrawn).** Facts read from GitHub (the run, its jobs and steps, its artifacts and approvals) and from the evidence artifact, downloaded
and checked against its own `SHA256SUMS.txt` (every file verified):

| Item | Fact |
|---|---|
| Run | `44821325087`, attempt 1, `workflow_dispatch` by `sziller` from `development` at `f8ab48bdd464044d4df4688033604f0d8b9e267c` (the merge of PR #119), 2026-11-20T21:33:10Z to 21:45:30Z: https://github.com/CadenaBitcoin/signer_app/actions/runs/44821325087 |
| Deployment | Approved by `CadenaWizard` (the required reviewer; the same person as the dispatcher, D12) |
| Credential | The CTO states that the App Manager-role key `47PP4C673P` (D15) was used. **Not verifiable from the run**: the workflow and the gate bind neither the key ID nor its role, and the logs redact their values (section 4.3, "Known limitations") |
| Result | **FAILED** |
| Jobs | `authorize` **success**; `build` **success**; `sign` **failure** |
| Authorization gate | **PASSED**, and re-checked in the `sign` job (step 4) before any secret was touched |
| Unsigned archive build | **PASSED**; archive tar SHA-256 `4663954e595711f2dedd6d5f21754efa71286027fdddbd74be4a0893857b2e0f` (the tar differs from run `44800943301`'s, `b2036228...`; the `dlc_wallet` binary does not) |
| Archive validation | **PASSED** before and after extraction (250 members, 0 symbolic links); bundle `com.app.cadenabitcoin`, `1.0.4`, `1000035`; archived app "not signed at all" |
| Authorized `dlc_wallet` SHA-256 | **PASSED**: equals `9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13`; Rust library `203dcd7a...` equals the pinned value |
| Pre-signing environment | Xcode 26.3 (17C529); `0 valid identities found`, `provisioning profiles installed: 0` |
| Apple credential-use step | **REACHED**: step 13, "Export and sign with the cloud-managed Distribution certificate (the only step with secrets)", ran and **failed** |
| Xcode export | `xcodebuild -exportArchive` exit **70** (`** EXPORT FAILED **`, 1 line) |
| Diagnostic counts (`export-diagnosis.txt`) | `Cloud signing permission error` **16**; `No signing certificate "iOS Distribution" found` **15**; `No profiles for 'com.app.cadenabitcoin' were found` **1**; `forbidden`, `401`/`403`, `does not have permission`, `No Accounts`, `Failed to Use Accounts`, `ITMS-`: **0** each |
| Signed IPA | **NONE**: the verification steps V1 to V9 and the IPA digest (steps 15 to 21) were **skipped**; the run's artifacts are text evidence, build evidence and the unsigned archive; no `.ipa` exists in any of them |
| App Store Connect upload / distribution | **NONE**: the workflow has no upload operation (`destination` is `export`; its only upload steps publish GitHub artifacts) |
| Signing certificate / IPA hashes (D8) | No signing certificate fingerprint or IPA hash was obtained or recorded; no signed IPA was produced. The D8 certificate fingerprint remains unrecorded |
| Key file | Removed from the runner (`key_file_removed=yes`, step 14) |
| Credentials | The CTO removed all three environment secrets afterwards; GitHub reports 0 environment, 0 repository and 0 organization secrets visible to the repository (read on 2026-11-20). The CTO reports the locally stored Apple API keys unchanged; this record revokes nothing (revocation of either key remains a separate decision, D14, D15) |
| Evidence artifacts | `ios-hosted-signing-evidence_44821325087-1` (text; `SHA256SUMS.txt` SHA-256 `156893e442945a8a71383b162f0241b1f3d0cd3b40f728cb108eb83c45e93058`; `export.log` `5a97aa6455020c287afb6cc7c6ae65a05096ade858309e4413918f77bda10be4`), `ios-hosted-build-evidence_44821325087-1`, `ios-hosted-unsigned-archive_44821325087-1` (one day). GitHub keeps the evidence artifact until 2026-12-20 |
| **G2S Authorization B** | **CONSUMED** (control 1: the credential-use step started), **WITHDRAWN** by PR #120 |

**Authorization A and Authorization B compared (evidence, not proof).** The two experiments used different credentials (Developer role, D14; App Manager role, D15) with the same source, workflow, gate, tools and native library, and ended alike:

| Compared | Run `44800943301` (A, Developer) | Run `44821325087` (B, App Manager) |
|---|---|---|
| Stage reached | credential use, export step | credential use, export step |
| Export exit | 70 | 70 |
| `Cloud signing permission error` / `No signing certificate "iOS Distribution" found` / `No profiles for 'com.app.cadenabitcoin' were found` | 16 / 15 / 1 | 16 / 15 / 1 |
| `export-diagnosis.txt` (SHA-256 `12ee043a...`), `export-result.txt`, `signing-material-before.txt`, `archive-codesign-state.txt`, `dlc-wallet-hash.txt`, `key-removed.txt` | identical | identical |
| `export.log` | `99c6ab10...` | `5a97aa64...`: differs from A's only in the timestamp and bundle path of line 1 and in the order of the last two error lines (the certificate line and the profile line) |
| Signed IPA / upload | none / none | none / none |

**What this shows, and what it does not.** The two failures **match**: the same error messages in the same counts, from two different roles of key. That is **evidence** and **not proof**. It does **not** establish the root cause, and in particular it does **not**
establish that the key's role (Developer or App Manager) caused either failure, or that it did not: the wording of "permission" in an Apple error does not name a role. The evidence does not show whether the key was accepted or refused by Apple, which requirement of Apple's cloud
signing was unmet (a team, account or key setting, the key type, the export method, or something else), or whether any App Store Connect API key can satisfy it. No Apple-side setting was read or changed for this record. The workflow's diagnostic line "The Developer role of the key is a
candidate cause…" is the stale wording documented above and decides nothing. **No further experiment was proposed or authorized by the record of PR #120** (Authorization C, section 4.4, was authorized later by a separate CTO decision); a credential of any other role, or any other route, is a separate decision of the CTO (D15 stated that no Admin-level or Account Holder
credential was authorized **for Authorization B**; that restriction applied to B only, and the Admin credential of Authorization C is separately authorized by D16, section 4.4), and any further signing attempt needs a **new explicit CTO authorization** and a new reviewed record pull request (section 4.2, control 2).

**Authorization B withdrawn (the state when PR #120 was merged).** Because the operation was consumed, PR #120 set `G2S-STATUS` to `WITHDRAWN` in section 6.1 (control 5 of this section). The gate then refused. **At that time no G2S authorization was current**: Authorization A stayed consumed and withdrawn, and Authorization B was consumed and
withdrawn. The history is retained: both CTO authorizations (comments `7038341975`, `7046097307` for A; `7050074107` for B), the failed pre-credential attempt `44738600156`, run `44800943301`, run `44821325087`, PRs #116 to #119, D14 and D15 are unchanged. G1 stays authorized; G2, G3, G4 and G5 stay **not authorized**.

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

**Not authorized.** Upload to App Store Connect, TestFlight distribution, tester assignment, App Review, public release; any second operation under B; any Admin-level or Account Holder credential **for Authorization B** (the original restriction of B, preserved here as historical; Authorization C is separately authorized by D16, section 4.4); any change of the source,
the workflow, the gate or the bound tools; G2, G3, G4 and G5.

### 4.4 G2S Authorization C: one new hosted signing-and-verification operation with the Admin key (WITHDRAWN: CONSUMED by run 44834801248)

> **Current state.** This section is **Authorization C**, and everything in it except "Execution of Authorization C" is the **historical record** of what the CTO authorized and on which conditions. **Authorization C is consumed and withdrawn**:
> run `44834801248` reached Apple credential use, so its one operation is consumed, and this record sets `G2S-STATUS` to `WITHDRAWN`. Present-tense statements in this section (for example "authorizes", "may be registered", "is authorized,
> conditional") describe Authorization C **as authorized**, before the attempt; they do not describe the current status. **Authorizations A and B also stay consumed and withdrawn. No G2S authorization is current.** Section 6.1 holds the
> withdrawn lines of Authorization C, which authorize nothing.

**Authorizations A, B and C, kept apart.**

| | Authorization A (historical) | Authorization B (historical) | Authorization C (historical) |
|---|---|---|---|
| CTO decisions | Original: Issue #71 comment `7038341975`; corrected workflow: comment `7046097307` | Comment `7050074107` | Comment `7052148143` |
| Credential decision | D14: dedicated **Developer**-role team key | D15: dedicated **App Manager**-role team key, Key ID `47PP4C673P` | D16: dedicated **Admin**-role team key, Key ID `9Y3NM5CN5B` |
| Workflow blob | `2a0b4c3c...`, then `60945f9aeabc6c0a3dbeaee5de541879b641fd2c` (PR #116) | `60945f9aeabc6c0a3dbeaee5de541879b641fd2c` | `60945f9aeabc6c0a3dbeaee5de541879b641fd2c`, unchanged |
| Runs | `44738600156` (failed before credential use; not consumed); `44800943301` (reached credential use, failed at the export) | `44821325087` (reached credential use, failed at the export) | `44834801248` (reached credential use; **Apple signing succeeded**; the workflow failed at V7/V8 verification; **CONSUMED**) |
| Result | export exit 70; `Cloud signing permission error` 16, `No signing certificate "iOS Distribution" found` 15, `No profiles for 'com.app.cadenabitcoin' were found` 1; no signed IPA, no upload | the same counts; no signed IPA, no upload | `xcodebuild -exportArchive` exit 0 (`EXPORT SUCCEEDED`); a signed IPA was produced and **not retained**; V1 to V6 passed; V7/V8 failed (29 passed, 21 failed, 1 warning; unresolved); V9 not run; no upload |
| Evidence artifact / `SHA256SUMS.txt` SHA-256 | `ios-hosted-signing-evidence_44800943301-1` / `65af5138443c72a04a62341ff3046e1d1c56181392bb1db62c453d55833ab415` | `ios-hosted-signing-evidence_44821325087-1` / `156893e442945a8a71383b162f0241b1f3d0cd3b40f728cb108eb83c45e93058` | `ios-hosted-signing-evidence_44834801248-1` / `393c412e0f7f6c5cda8a508505520e9a658af6ed1e4a389e2681ec948fb9bb69` |
| State | **CONSUMED, permanently; WITHDRAWN** (PR #118) | **CONSUMED, permanently; WITHDRAWN** (PR #120) | **CONSUMED by run `44834801248`; WITHDRAWN** by the reviewed record pull request that sets `G2S-STATUS` to `WITHDRAWN` (authorized, conditional, ONE operation, before the attempt) |
| `G2S-AUTHORIZATION` (section 6.1) | `https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7038341975` | `https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7050074107` | `https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7052148143` |

Authorizations A and B stay permanently consumed and are not reactivated. **Authorization C is independent of both**: it is not an extension, a continuation, a retry or a reactivation of either, and a run under it is not "the next attempt" of
either. The distinction is kept by this record (this ledger and sections 0, 4.2, 4.3, 6, 6.1 and 7), by the CTO's written decisions, by human review of the record pull request and of the deployment, by the run IDs and evidence artifacts
(`ios-hosted-signing-evidence_<run>-<attempt>`) recorded in section 7 for each, and by the controlled registration of the credential (below). **It is not technically enforced** by the authorization gate (section 6.1).

**The authorization.** The CTO's written decision "CTO Decision: G2S Authorization C: Admin Signing Experiment" on Issue #71:
https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7052148143
(comment id `7052148143`, account `CadenaWizard`, created 2026-11-20T22:28:09Z, never edited). It is **APPROVED, conditional on a reviewed and merged release-record update**. It records the two completed experiments (A, Developer role; B, App Manager role), both of
which built the unsigned application and failed during `xcodebuild -exportArchive` with identical diagnostic counts and produced no signed IPA, and states that **the matching errors do not establish that the API key's role caused either failure**. It introduces **D16**
(section 4), explicitly accepts the elevated risks of an Admin-role Team API key listed there, and names the application (Cadena Bitcoin Signer App), `APPROVED_SHA` `42d358a4e7bcbf85b92aa992ec6439214dbd4405`, `CONTENT_REF` `862831e0b3a0f30c4155d2e086c69fc28bdab286`,
version `1.0.4 (1000035)`, bundle ID `com.app.cadenabitcoin`, Apple Team ID `D65458CPDP`, API key `9Y3NM5CN5B` (Admin), workflow blob `60945f9a...`, authorization gate blob `3807ee8a...` and the native-library SHA-256
`9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13`. It requires the five bound tool identities to be independently reverified before execution, and authorizes **one new GitHub-hosted signing-and-verification operation**: one unsigned archive build,
one export attempt using Apple's cloud-managed Distribution signing, verification of the resulting IPA if signing succeeds, and preservation of the prescribed evidence. It does **not** authorize upload, TestFlight distribution, App Review submission or public release,
a second operation, or any change of the application source, the workflow or the verification tools. G1 remains authorized; G2, G3, G4 and G5 remain unauthorized.

**The operation Authorization C authorizes (exhaustive).** One run of `.github/workflows/ios-hosted-signing.yml`, started by hand from `development` for the approved source, content reference, version, bundle ID and team above, through the protected
environment `ios-hosted-signing` (unchanged: required reviewers `sziller` and `CadenaWizard`, administrator bypass disabled, deployment branch `development` only), with the three environment secrets holding the key of D16. The rules of section 4.2 apply
unchanged: one archive, one export, verification V1 to V9 if signing succeeds, text evidence, no upload, no retained IPA.

**Single operation and controls (CTO decision, section 4).**

1. **Exactly one new operation.** It is **consumed when Apple credential use begins** (the step "Export and sign with the cloud-managed Distribution certificate (the only step with secrets)" starts), regardless of whether signing succeeds. No additional
   signing operation is authorized by this decision.
2. **A failure before credential use** (the gate, the tip check, the build, the archive validator, the `dlc_wallet` hash comparison) does not consume it, but **another dispatch then needs a documented operator decision** on Issue #71 under the existing policy
   (section 4.2, control 3). A further attempt after consumption needs a new CTO decision and a new reviewed record pull request.
3. **The environment stays mandatory** with its reviewers, branch restriction and disabled administrator bypass. The reviewers confirm the deployment only (D12); before approving, the approver checks the points of section 4.2, control 4, and that this is the
   first run under Authorization C.
4. **The Admin credential may be registered as GitHub environment secrets only after** this record is merged into `development` **and the authorization gate has passed against the final `development` revision.** The three Apple secrets must not be registered
   before that. This record's pull request must be the **final merge into `development` before execution** (the gate requires the workflow revision to be the `development` tip).
5. **After the attempt, whatever its result:** (a) remove all three GitHub environment secrets **immediately**; (b) preserve and verify the available evidence; (c) document the outcome (section 7); (d) **withdraw Authorization C through a reviewed
   release-record pull request** (`G2S-STATUS: WITHDRAWN`). Removing the secrets does not revoke the Apple key; **revocation of the Admin key is a separate explicit CTO decision**, and no indefinite GitHub credential storage is authorized (D16).
6. **If the Admin experiment produces the same Apple signing failure**, further privilege escalation is **not authorized** by this decision. The next action is **investigation of Apple's account-level signing configuration or engagement with Apple Developer Support**,
   under a new CTO decision for anything that needs authorization. This authorization permits no further experiment if Authorization C also fails.

**The CTO's conditions for effectiveness, and where they are met.**

| # | Condition (comment `7052148143`) | Where it is met |
|---|---|---|
| 1 | The release record permanently preserves Authorizations A and B as consumed and withdrawn | The ledger above; sections 4.2, 4.3, 6 and 7 keep their history and evidence unchanged |
| 2 | D16 documents the Admin credential and accepted security risks | Section 4, row D16 |
| 3 | The new `G2S-AUTHORIZATION` references this CTO decision | `G2S-AUTHORIZATION` in section 6.1 names comment `7052148143` |
| 4 | The workflow, gate, verification tools and native-library identities are reverified | See "Implementation identity" below; the gate verifies the blobs again at every run |
| 5 | The authorization gate accepts the proposed record | The gate's verdict on this record, with the workflow, gate and tools of this checkout, is recorded in the pull request |
| 6 | The release-record pull request is reviewed and merged into `development` | The pull request that merges this section; effective only from that merge, and it is the final merge before execution |

**Execution of Authorization C: run 44834801248 (consumed; Authorization C withdrawn).** Facts read from GitHub (the run, its jobs and steps, its artifacts and approvals) and from the evidence artifact, downloaded and checked against its own `SHA256SUMS.txt`
(every file verified; a fresh download equals the preserved local copy file for file). **The GitHub Actions workflow failed, but Apple signing succeeded; this is not an Apple signing failure.**

| Item | Fact |
|---|---|
| Run | `44834801248`, attempt 1, `workflow_dispatch` by `sziller` from `development` at `ee440fbc16f5c097510be1fd2cb0932e55b0ec6a` (the merge of PR #121), 2026-11-20T23:10:27Z to 23:18:16Z: https://github.com/CadenaBitcoin/signer_app/actions/runs/44834801248 |
| Deployment | Approved by `CadenaWizard` (the required reviewer; the same person as the dispatcher, D12) |
| Credential | The CTO states that the Admin-role key `9Y3NM5CN5B` (D16) was used. **Not verifiable from the run**: the workflow and the gate bind neither the key ID nor its role, and the logs redact their values (section 4.4, "Known limitations") |
| Result | **FAILED** (the workflow's conclusion), at step 19, the repository IPA verifier (V7/V8) |
| Jobs | `authorize` **success**; `build` **success**; `sign` **failure** |
| Authorization gate | **PASSED**, and re-checked in the `sign` job (step 4) before any secret was touched |
| Unsigned archive build | **PASSED**; archive tar SHA-256 `13446eaacec1f0ad7a824072129d5d1192e6d832d53edc1db23c09c8d5d5ecc9` (the tar differs per run; the `dlc_wallet` binary does not) |
| Archive validation | **PASSED** before and after extraction (250 members, 0 symbolic links); bundle `com.app.cadenabitcoin`, `1.0.4`, `1000035`; archived app "not signed at all" |
| Authorized `dlc_wallet` SHA-256 | **PASSED**: equals `9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13` |
| Pre-signing environment | Xcode 26.3 (17C529); `0 valid identities found`, `provisioning profiles installed: 0` |
| Apple credential-use step | **REACHED**: step 13, "Export and sign with the cloud-managed Distribution certificate (the only step with secrets)", ran and **succeeded** |
| Xcode export | `xcodebuild -exportArchive` exit **0** (`** EXPORT SUCCEEDED **`); export options `method app-store-connect`, `destination export`, `signingStyle automatic`, `teamID D65458CPDP`, `manageAppVersionAndBuildNumber 0` |
| Signed IPA | **PRODUCED**: 22,693,541 bytes, SHA-256 `4999d0fb8da454ed1d7063a9ad2d9dd8feda4dcc942ea028e32c4fa7b856b1cc`. **NOT RETAINED** (D9): it stayed on the runner, which is gone; the run's artifacts are text evidence, build evidence and the unsigned archive, and none contains an `.ipa` |
| Verification steps | V1 (identity) **PASSED**; V2 (`codesign` verification: "valid on disk", "satisfies its Designated Requirement") **PASSED**; V3 (certificate extraction and cross-check) **PASSED**; V4 (embedded profile) **PASSED**; V5 (entitlements) **PASSED**; V6 (environment) **PASSED**; **V7/V8 (repository IPA verifier) FAILED**; V9 and the IPA digest re-check were **NOT EXECUTED** (steps 20 and 21 skipped) |
| Evidence and report | Steps 22 to 24 ran: the text evidence was sealed, reported and uploaded |
| App Store Connect upload / distribution | **NONE**: the workflow has no upload operation (`destination` is `export`; its only upload steps publish GitHub artifacts) |
| Key file | Removed from the runner (`key_file_removed=yes`, step 14) |
| Credentials | The CTO removed all three environment secrets afterwards; GitHub reports 0 environment, 0 repository and 0 organization secrets visible to the repository (read on 2026-11-20). The CTO states that the locally stored Admin key has **not** been revoked; revocation of any key remains a separate CTO decision (D16) |
| Evidence artifacts | `ios-hosted-signing-evidence_44834801248-1` (text, 72,557 bytes; `SHA256SUMS.txt` SHA-256 `393c412e0f7f6c5cda8a508505520e9a658af6ed1e4a389e2681ec948fb9bb69`), `ios-hosted-build-evidence_44834801248-1`, `ios-hosted-unsigned-archive_44834801248-1` (one day: GitHub expires it on 2026-11-21T23:13Z). GitHub keeps the evidence artifact until 2026-12-20; a copy is kept outside the repository by the CTO's procedure |
| Key evidence files (SHA-256) | `v7-ipa-verify-output.txt` `b5b621b275f52c28a6e5e2943bdefa4d02bf291e2c71086fb82c355f872c2826`; `Packaging.log` `9748b5051cab9405d4cc966e04eb6a3a3a75317573028c4ab7491ea61a78ec63`; `DistributionSummary.txt` `e024d58b86fb4779cdfc6e535d94b8e31cbeddf80bba576bb24e271e30d8ed96`; `signer.pem` (the PUBLIC certificate) `347b91be045f335157a6c3357e9a2b455abb354cad9a90d94e0f7d13b405a4c8`; `export.log` `3af4644b043783f66941ea7f1d9bf429eaa204ea1c2ff5c313c0fe444f4f0b0f`; `export-result.txt` `c41c90d198d40d83a2986827d49543d0ccf385dfcc54b6c496ca329364bd2bc4` |
| **G2S Authorization C** | **CONSUMED** (control 1: the credential-use step started), **WITHDRAWN** by this record |

**Signing certificate discovered from the signed IPA (D8).** The evidence artifact's `v3-certificate-output.txt`, `v3-openssl-cert.txt`, `v3-codesign-identity.txt` and `DistributionSummary.txt` give:

| Property | Value |
|---|---|
| Certificate type | Cloud Managed Apple Distribution (`DistributionSummary.txt`) |
| Subject | `Apple Distribution: Cadena Bitcoin S.A. de C.V. (D65458CPDP)` |
| Team ID | `D65458CPDP` |
| Serial | `6E0B1FC31A51B362A9FC9378161167D6` |
| Valid | from 2026-07-09T14:51:09Z until 2027-07-09T14:51:08Z |
| Issuer | Apple Worldwide Developer Relations Certification Authority (G3) |
| SHA-256 | `7ee3f6ce78eea83748e198102f6ab66527c626296baaea437c3a90db81ef418e` |
| SHA-1 | `cd121c430bfeb3c650d3de75a6bb2bdd04a5d6f3` |
| Embedded profile | "iOS Team Store Provisioning Profile: com.app.cadenabitcoin", type app-store, no device list, `get-task-allow` false, expires 2027-07-09T14:51:08Z |
| Carried by | all 16 signed executables of the IPA; the embedded profile lists this certificate |

This fingerprint is **DISCOVERED, not approved**: it was read from the artifact it would later judge (`pin_source=DISCOVERED`), so by D8's own terms it is circular and is evidence only. **It is not an approved signing identity and not a pin.** The chain to an Apple root and the revocation status were
**not** verified (the workflow ran without trust anchors and with no OCSP/CRL lookup). Converting it into a pin needs the release coordinator's recording and an independent source (trust anchors, the profile, the Apple account), as IOS_RELEASE.md V3 says. The certificate's `notBefore` date (2026-07-09) is earlier than
every run of this release, so it was not created by run `44834801248` (read from the X.509 dates); the log shows only certificate lookups and signing requests, but whether this run created or changed any other Apple-side object (for example the profile, D7's accepted risk) is **not established** and no Apple-side setting was read or changed for this record.

**V7/V8 verification findings (UNRESOLVED).** The repository verifier (`tool/verify_ipa.py`, `v7-ipa-verify-output.txt`) reported **29 checks passed, 21 failed and 1 warning**. The 21 failures are: (1) **16** "CMS signature is unreadable: Invalid file" (the main executable and 15 nested executables, including
`Frameworks/libswift_Concurrency.dylib`); (2) the main executable's DER entitlements "unreadable: unsupported DER entitlements version or layout"; (3) "the main executable has no embedded entitlements" (the verifier's report); (4) `Frameworks/libswift_Concurrency.dylib`: "the CodeDirectory seals Info.plist, which is absent" (reported twice); (5) V8: "files that differ from the unsigned build: Info.plist".
The one warning is that `Info.plist` has no `ITSAppUsesNonExemptEncryption`. The checks that passed include the container, bundle ID, version and build number, the embedded profile (CMS signature, platform, type, Team ID, App ID, validity), `CodeResources` of every nested bundle and of the outer bundle, and "no file of the unsigned build is missing from the IPA". These failures are **why the workflow failed**.
Apple's own `codesign` verification (V2) passed, the certificate was extracted and cross-checked (V3), and the provisioning-profile checks (V4) passed. **V9 and the final IPA digest re-check were not executed.** The IPA was not uploaded or distributed and was not retained.

**Interpretation, and what is not established.** The failures are **consistent with** possible incompatibilities between the repository verifier and the output of Apple's cloud-managed signing, and the repository's own IOS_HOSTED_SIGNING.md recorded before any run that V7 and V8 had never seen a real Apple-signed IPA and might reject a legitimate one. **The root causes are not established.**
An investigation lead only, not a conclusion: "Invalid file" is the default message of Python's `plistlib.InvalidFileException`, and by reading the code the only plist parse on the CMS path is the one of Apple's `cdhashes` signed attribute in `tool/ipa_inspect.py` (no traceback was captured, and the exact cause is unconfirmed). Accordingly this record does **not** declare the IPA invalid because V7/V8 failed,
does **not** declare it release-ready because `codesign` passed, does **not** classify the verification failures as harmless, and does **not** recommend disabling any verification check. **The V7/V8 failures are recorded as unresolved findings that require investigation.** The verifier is not repaired in this record.
Nothing here authorizes an upload, a distribution or a further signing operation, and a signed IPA that is not retained cannot be re-examined.

**The three experiments.**

| Authorization | API key role | Apple signing | Workflow outcome |
|---|---|---|---|
| A (`44800943301`) | Developer | **Failed** (export exit 70) | Failed at the export step |
| B (`44821325087`) | App Manager | **Failed** (export exit 70, the same messages and counts as A) | Failed at the export step |
| C (`44834801248`) | Admin | **Succeeded** (export exit 0; signed IPA produced, not retained) | Failed at the V7/V8 verification step |

The workflow, gate, bound tools, source and native library were the same in all three, and seven evidence files are byte-identical across them (`archive-codesign-state`, `archive-validate-list`, `archive-validate-tree`, `dlc-wallet-hash`, `key-removed`, `signing-material-before`, `xcode`). The evidence supports the **Admin role as a plausible explanation** of the difference between A and B on one side and C on the other.
It does **not** prove causation: the key is not machine-bound, so a run cannot show which key it used; Apple-side state could have changed between runs; and there are three observations only.

**Authorization C withdrawn.** Because the operation was consumed, this record sets `G2S-STATUS` to `WITHDRAWN` in section 6.1 (control 5 of this section). The gate then refuses. **Authorizations A, B and C are all consumed and withdrawn, and no further signing operation is authorized.** The history is retained: all three CTO authorizations (comments `7038341975`, `7046097307` for A; `7050074107` for B; `7052148143` for C),
the failed pre-credential attempt `44738600156`, runs `44800943301`, `44821325087` and `44834801248`, PRs #116 to #121, D14, D15 and D16 are unchanged. G1 stays authorized; G2 and G3 stay pending, and G4 and G5 stay **not authorized**.

**Implementation identity (verified for Authorization C; nothing is changed).** Verified on 2026-11-20 against `development` at `dbdfe7aa7fe1e249fb8ab9e99c9866ab14ff2bd4`, independently with `git hash-object` and with
`bash tool/check_signing_authorization.sh --print-expected --tools-root .`: workflow `60945f9aeabc6c0a3dbeaee5de541879b641fd2c`, gate `3807ee8a1b8caf4ce5f22a6f2540c0658aba90b6`, and the five tools
(`tool/build_manifest.py` `6e6c153e...`, `tool/ipa_inspect.py` `af7ced43...`, `tool/validate_handover_archive.py` `ef4ce2c6...`, `tool/verify_artifact.sh` `99074f4b...`, `tool/verify_ipa.py` `6ee2b9d7...`; full values in
section 6.1). No workflow, gate, tool, application or native-library file has changed since run `44821325087` (the only changes on `development` since its revision `f8ab48bd...` are to this record), and this record changes none. The native library's
`dlc_wallet` SHA-256 `9a2d1d98...` was equal in every archive built so far, including those of runs `44800943301` and `44821325087`; **a later build is not assumed to reproduce it**: if it differs, the run stops before any secret is used.

**Known limitations, recorded rather than fixed (the workflow and the gate are not modified).**

- **The gate does not validate the CTO comment** (existence, author, date or content); it checks the format of the `G2S-AUTHORIZATION` URL and its link to Issue #71 only (section 6.1).
- **The gate does not independently validate D16.** The gate's list of required decisions is fixed (`D3 D6 D7 D8 D9 D10 D11 D12 D14`) and it never reads the rows D15 or D16: a missing, altered or undecided D16 row would not change its verdict
  (the same holds for D15). D16 is established by the CTO's decision (comment `7052148143`) and by this release record as reviewed and merged, **not** by any automated validation of that decision row. The gate is not modified.
- **The key is not machine-bound.** The gate and the workflow bind neither the API key ID nor its role: they read three secrets by name (`APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`), and the logs redact the values. Nothing in a run proves that the
  secrets hold key `9Y3NM5CN5B`; that is a procedural control: the CTO loads exactly that key (D16), and no other credential, after the conditions above are met.
- **The workflow does not enforce the single-operation limit** (no run counter); the controls above and in section 4.2 are procedures.
- **Stale diagnostic wording.** The diagnosis step still prints "The Developer role of the key is a candidate cause if a permission or 401/403 pattern matches; the text alone does not prove it." and a comment of the workflow mentions the Developer role. Under Authorization C
  the key's role is Admin: that wording is **informational and stale**, decides nothing, and is to be read as "the role of the key".
- **The signing certificate fingerprint remains unrecorded** (D8): no signing certificate was obtained or recorded from any attempt; if signing succeeds, it is only discovered in this run (`pin_source=DISCOVERED`) and is recorded in section 7 by the coordinator.
- **The Admin credential does not guarantee successful cloud signing** (D16, D7). The comparison of Authorizations A and B (section 4.3) remains **evidence, not proof** of the root cause; it does not establish that the role of the key caused either failure. A failure would
  consume the operation and is a result of the experiment, not a defect.

**Not authorized.** Upload to App Store Connect, TestFlight distribution, tester assignment, App Review, public release; any second operation under C; any further privilege escalation or other experiment after a failure of C; any change of the source, the workflow, the gate or
the bound tools; indefinite storage of the credential in GitHub; G2, G3, G4 and G5.

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

Only G1 and the signing-only G2S have been decided: G2S Authorizations A and B are both withdrawn (consumed); G2S Authorization C is also withdrawn (consumed); no G2S authorization is current (sections 4.2 to 4.4). Nothing in sections 1 to 4 substitutes for a row below, and G1 implies no other row; G2S implies no upload and none of G2 to G5. The policy basis is section 4, D11 and D12.

| Gate | Decision | By | Date | Reference |
|---|---|---|---|---|
| G1 source (commit only) | **AUTHORIZED** | CTO and release coordinator, GitHub account `CadenaWizard` | 2026-11-12 | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-6833584989 |
| **G2S Authorization A** hosted signing and verification only: the CTO's written authorization of ONE GitHub-hosted signing-and-verification operation; **no upload, no distribution; not G2** (section 4.2) | **WITHDRAWN: authorization CONSUMED by run `44800943301`** (historically: authorized, conditional, one operation; it reached Apple credential use and failed at the export; no signed IPA, no upload; section 4.2, "Second attempt"). **Authorization A authorizes no further signing operation, and never will again**: it is permanently consumed. **Authorization B**, in the next row, was authorized independently after A (it is not an extension or reactivation of A) and **has itself since been consumed and withdrawn**. **Neither authorization permits further signing**; a further operation needs a new, separate CTO authorization and a new reviewed record pull request (**Authorization C**, below, was such a later authorization and has itself since been consumed and withdrawn) | CTO, GitHub account `CadenaWizard` (authorization and update); withdrawn by the reviewed PR #118 | 2026-11-20 | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7038341975 (original authorization, historical); corrected workflow, historical: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7046097307 |
| **G2S Authorization B** hosted signing and verification only, with the dedicated App Manager-role key of D15: the CTO's written authorization of ONE **new** GitHub-hosted signing-and-verification operation; **no upload, no distribution; not G2; a separate authorization, independent of Authorization A (which stays consumed and withdrawn), not an extension or reactivation of it** (section 4.3) | **WITHDRAWN: authorization CONSUMED by run `44821325087`** (historically: authorized, conditional, one operation; it reached Apple credential use and failed at the export; no signed IPA, no upload; section 4.3, "Execution of Authorization B"). **Authorization B authorizes no further signing operation**; a further one needs a separate, new CTO authorization (**Authorization C**, in the next row, was such a later authorization and has itself since been consumed and withdrawn) | CTO, GitHub account `CadenaWizard` (authorization); withdrawn by the reviewed PR #120 | 2026-11-20 | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7050074107 |
| **G2S Authorization C** hosted signing and verification only, with the dedicated Admin-role key of D16: the CTO's written authorization of ONE **new** GitHub-hosted signing-and-verification operation; **no upload, no distribution; not G2; a separate authorization, independent of Authorizations A and B (which stay consumed and withdrawn), not an extension or reactivation of either** (section 4.4) | **WITHDRAWN: authorization CONSUMED by run `44834801248`** (historically: authorized, conditional, one operation; it reached Apple credential use, **Apple signing succeeded**, and the workflow failed at the V7/V8 verification; the signed IPA was not retained; no upload; section 4.4, "Execution of Authorization C"). **Authorization C authorizes no further signing operation, and neither do A or B**: all three are consumed and withdrawn, and a further operation needs a new, separate CTO authorization and a new reviewed record pull request | CTO, GitHub account `CadenaWizard` (authorization); withdrawn by this record's reviewed pull request | 2026-11-20 | https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7052148143 |
| G2 production signing and upload to App Store Connect: the CTO's written authorization of this manual operation, after the prerequisites of section 4.1 (not an exception to the authorization policy). **Not given by G2S**; a G2 operation builds and signs its own archive | **PENDING** | TBD | TBD | TBD |
| G3 assignment to named internal testers (the CTO) | **PENDING** | TBD | TBD | TBD |
| G4 submission to App Review (the CTO, a separate manual operation; needs the acceptance evidence of IOS_RELEASE.md section 11, which has no minimum duration) | **NOT AUTHORIZED** (not given) | | | |
| G5 public release (the CTO, separately from G4) | **NOT AUTHORIZED** (not given) | | | |

### 6.1 G2S authorization lines (read by the workflow's authorization gate)

These eleven lines are read by `tool/check_signing_authorization.sh` (IOS_HOSTED_SIGNING.md section 5). Each must stay exactly once, at the start of its
own line, with no other text on it, **outside** code blocks and comments; the gate also requires the decided rows of section 4, the status line of section 0,
the `APPROVED_SHA` row of section 3.1, and that the workflow revision is the current tip of `development`. They authorize **one** signing-and-verification operation and **never an upload**. **These lines are the lines of Authorization C, now `WITHDRAWN`** (section 4.4): `G2S-STATUS` is `WITHDRAWN` (run `44834801248` consumed the operation) and
`G2S-AUTHORIZATION` still names the CTO's decision of Authorization C, **kept as the record of what was authorized; while the status is `WITHDRAWN` the gate refuses and these lines authorize nothing. No G2S authorization is current.** **Authorizations A and B are consumed and stay so**: A's lines carried `G2S-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7038341975` and, after run
`44800943301`, `G2S-STATUS: WITHDRAWN` (PR #118); B's carried `G2S-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7050074107` and, after run `44821325087`, `G2S-STATUS: WITHDRAWN` (PR #120); that history is kept in sections 4.2 and 4.3
and in this file's Git history. The other ten lines keep the values of the consumed Authorization C as **historical evidence** (the approved source, the workflow, the gate, the five tools and the native library were the same under all three authorizations).

**What the gate does and does not do with these lines.** The gate checks that `G2S-AUTHORIZATION` has the required format, a link to a comment on Issue #71 (`…/issues/71#issuecomment-<digits>`), and appears exactly once. It does **not**
retrieve or validate that comment (its existence, author, date or content). It does **not** verify the API key ID or the key's role: the workflow reads three secrets by name and the gate never sees them. It does **not** enforce the operation
count: there is no run counter, and the gate accepts the lines for as long as they stay in the record. The gate therefore **cannot distinguish Authorization C from Authorizations A and B**, and it cannot tell a first run from a later one. That distinction is
maintained **outside** the gate: by this release record (the ledger of section 4.4), by the CTO's written decisions (comments `7038341975` and `7046097307` for A, `7050074107` for B, `7052148143` for C), by human review of the record pull request and of each
deployment approval, and by the controlled registration of the credential (the CTO loads exactly the key of D16, only after the merge and a passing gate). No technical enforcement is claimed.

The workflow does **not** enforce the one-operation limit (no counter): section 4.2, "One operation", lists the operational
controls, which apply to Authorization C unchanged. After the attempt of Authorization C the three credentials were removed from the environment and these lines are withdrawn by the reviewed pull request that sets the first line
to `G2S-STATUS: WITHDRAWN` (this record update); they must not be edited back to authorize another run without a new CTO decision and a new reviewed record pull request (section 4.2, control 2).

G2S-STATUS: WITHDRAWN

G2S-OPERATION: sign-and-verify-only

G2S-APPROVED-SHA: 42d358a4e7bcbf85b92aa992ec6439214dbd4405

G2S-VERSION: 1.0.4+1000035

G2S-BUNDLE-ID: com.app.cadenabitcoin

G2S-TEAM-ID: D65458CPDP

G2S-WORKFLOW-BLOB: 60945f9aeabc6c0a3dbeaee5de541879b641fd2c

G2S-GATE-BLOB: 3807ee8a1b8caf4ce5f22a6f2540c0658aba90b6

G2S-TOOL-BLOBS: tool/build_manifest.py=6e6c153e4accb9b03dcac13964a840272fa76d82,tool/ipa_inspect.py=af7ced4341873dcff0113c4c417c0cce697938f6,tool/validate_handover_archive.py=ef4ce2c686e2ae7c3eacb61d078764f8c5b71c3d,tool/verify_artifact.sh=99074f4b03e7db9a69cb1cfd03ee2b867e8dfd4a,tool/verify_ipa.py=6ee2b9d74c31321904e2c042aa2bc82fc402ab35

G2S-DLC-WALLET-SHA256: 9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13

G2S-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7052148143

Requirement before any G4 request: the acceptance criteria of IOS_RELEASE.md section 11 are met and evidenced on physical devices
installed through TestFlight. **There is no mandatory time window** (CTO decision of 2026-11-17). A TestFlight upload is not App
Review and not a release.

## 7. Results (filled from the operator's evidence; hashes and text only)

| | |
|---|---|
| G2S Authorization A attempt history: run `44738600156` FAILED before Apple credential use (corrected by PR #116); the operation was **not consumed**; no signing, no upload (section 4.2) | Recorded in section 4.2 |
| G2S Authorization A attempt history: run `44800943301` FAILED at the Xcode export (exit 70, cloud signing permission error; no certificate, no profile) after Apple credential use; the operation of Authorization A is **CONSUMED** and Authorization A is **WITHDRAWN** (PR #118); no signed IPA, no upload; credentials removed (section 4.2, "Second attempt") | Recorded in section 4.2 |
| G2S Authorization A run (hosted signing and verification): run ID and conclusion; evidence artifact `ios-hosted-signing-evidence_<run>-<attempt>` and its `SHA256SUMS` value; the first-run signing-certificate SHA-256 (D8, circular until recorded) | Run `44800943301`, **FAILED** (export exit 70), evidence artifact `ios-hosted-signing-evidence_44800943301-1`, `SHA256SUMS.txt` SHA-256 `65af5138443c72a04a62341ff3046e1d1c56181392bb1db62c453d55833ab415`; No signing certificate was obtained or recorded from this attempt, so the D8 hash is still unrecorded |
| G2S Authorization B attempt history: run `44821325087` FAILED at the Xcode export (exit 70, `Cloud signing permission error` 16, `No signing certificate "iOS Distribution" found` 15, `No profiles for 'com.app.cadenabitcoin' were found` 1) after Apple credential use, with the App Manager-role key of D15; the operation of Authorization B is **CONSUMED** and Authorization B is **WITHDRAWN**; no signed IPA, no upload; credentials removed. It is a separate operation from Authorization A's; the two matched (evidence, not proof of a cause) | Recorded in section 4.3 |
| G2S Authorization B run (hosted signing and verification, App Manager key of D15): run ID and conclusion; evidence artifact `ios-hosted-signing-evidence_<run>-<attempt>` and its `SHA256SUMS` value; the first-run signing-certificate SHA-256 (D8), if any | Run `44821325087`, **FAILED** (export exit 70), evidence artifact `ios-hosted-signing-evidence_44821325087-1`, `SHA256SUMS.txt` SHA-256 `156893e442945a8a71383b162f0241b1f3d0cd3b40f728cb108eb83c45e93058`; No signing certificate was obtained or recorded from this attempt, so the D8 hash is still unrecorded |
| G2S Authorization C attempt history: run `44834801248` reached Apple credential use with the Admin-role key of D16; **Apple signing SUCCEEDED** (`xcodebuild -exportArchive` exit 0; signed IPA SHA-256 `4999d0fb8da454ed1d7063a9ad2d9dd8feda4dcc942ea028e32c4fa7b856b1cc`, 22,693,541 bytes) and the workflow then **FAILED at V7/V8** (29 checks passed, 21 failed, 1 warning; unresolved); V1 to V6 passed, V9 not executed; the IPA was **not retained**, not uploaded, not distributed; credentials removed. The operation of Authorization C is **CONSUMED** and Authorization C is **WITHDRAWN**. It is a separate operation from Authorizations A and B; A and B stopped at the export (section 4.4) | Recorded in section 4.4 |
| G2S Authorization C run (hosted signing and verification, Admin key of D16): run ID and conclusion; evidence artifact `ios-hosted-signing-evidence_<run>-<attempt>` and its `SHA256SUMS` value; the first-run signing-certificate SHA-256 (D8), if any | Run `44834801248`, **FAILED** (at V7/V8; Apple signing succeeded), evidence artifact `ios-hosted-signing-evidence_44834801248-1`, `SHA256SUMS.txt` SHA-256 `393c412e0f7f6c5cda8a508505520e9a658af6ed1e4a389e2681ec948fb9bb69`; signing certificate SHA-256 `7ee3f6ce78eea83748e198102f6ab66527c626296baaea437c3a90db81ef418e` (**DISCOVERED, not approved**; see below) |
| IPA SHA-256 and size | Neither run `44800943301` (Authorization A) nor run `44821325087` (Authorization B) produced a signed IPA. Run `44834801248` (Authorization C) **produced** one: SHA-256 `4999d0fb8da454ed1d7063a9ad2d9dd8feda4dcc942ea028e32c4fa7b856b1cc`, 22,693,541 bytes (from `export-result.txt`); it was **not retained** (D9), not uploaded and not distributed, and cannot be re-examined. TBD for any later operation |
| Signing certificate collected from the IPA (`certificate` output, `codesign`/`openssl` cross-check); SHA-256 **recorded by the coordinator before upload**; embedded profile name, type and expiry | From the signed IPA of run `44834801248` (D8 discovery): SHA-256 `7ee3f6ce78eea83748e198102f6ab66527c626296baaea437c3a90db81ef418e`, SHA-1 `cd121c430bfeb3c650d3de75a6bb2bdd04a5d6f3`, serial `6E0B1FC31A51B362A9FC9378161167D6`, valid 2026-07-09 to 2027-07-09, `Apple Distribution: Cadena Bitcoin S.A. de C.V. (D65458CPDP)`, type Cloud Managed Apple Distribution; profile "iOS Team Store Provisioning Profile: com.app.cadenabitcoin", app-store, expires 2027-07-09. **DISCOVERED (circular), not an approved pin;** chain and revocation not verified (section 4.4); the coordinator's recording and approval are still open. The fingerprint has been recorded as evidence. Independent verification and approval as a signing-identity pin remain outstanding. |
| Archive baseline (`archive-app.sha256`) and `DistributionSummary.plist` | Run `44834801248`: `archive-app.sha256` (95 files) SHA-256 `9d70b8979081caf86a02ab6848b6f29c9dce9d7eefa9a7f82203daec2b7cac6a`; `DistributionSummary.txt` (the export's summary, as text) SHA-256 `e024d58b86fb4779cdfc6e535d94b8e31cbeddf80bba576bb24e271e30d8ed96`. V8's comparison against this baseline **failed on `Info.plist`** (unresolved, section 4.4) |
| Verification V1 to V9 | Run `44834801248`: V1 to V6 **PASSED**; **V7 and V8 FAILED** (the verifier: 29 passed, 21 failed, 1 warning; **unresolved findings**, section 4.4); V9 **not executed**. No verification result in this record is an acceptance of the IPA; for any later operation: TBD |
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
