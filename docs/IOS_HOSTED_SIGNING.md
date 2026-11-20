# iOS hosted signing: sign and verify only (Issue #71)

> **Status: implemented, NOT authorized, NOT run.** `.github/workflows/ios-hosted-signing.yml` can sign and verify the approved
> iOS 1.0.4 (1000035) build on a GitHub-hosted runner with Apple's cloud-managed Distribution certificate. It **cannot sign today**:
> the environment and secrets do not exist, and the release record carries no authorization for it (section 5). It **never
> uploads**. It decides no D or X row of the release record, changes no gate and is not G2. Parent issue: #54; release
> procedure: [IOS_RELEASE.md](IOS_RELEASE.md); record: [release-records/ios-1.0.4-1000035.md](release-records/ios-1.0.4-1000035.md).
> Every statement about Apple's behaviour below is labelled **Unconfirmed** until a run has shown it.

## 1. What the workflow implements

Started by hand only (`workflow_dispatch`), from `refs/heads/development` only. Inputs: `approved_sha`, `content_ref`,
`expected_version` (the defaults are the release record's values) and `expected_cert_sha256` (empty on the first run).

| Job | Secrets / environment | What it does |
|---|---|---|
| `authorize` | none | Reads the release record **of its own commit** and runs `tool/check_signing_authorization.sh`. No G2S authorization in the record means `authorized=false`, and the signing job is skipped. |
| `build` | none | The part that runs third-party code. Checks out exactly the approved commit and verifies it (SHA, ancestor of `production`, content equal to the reviewed content, clean tree, version), then the repository's own checks (`verify_build_config`, `verify_version`, the pinned Rust library SHA-256, `verify_artifact.sh`, `check_build_drift.sh`). **One** compile: `flutter build ipa --release --no-codesign` (the command of the diagnostics run `44625655320`). Hands the unsigned archive over as a one-day tar with its SHA-256. It runs whether or not signing is authorized, so the hand-over is exercised first. |
| `sign` | environment `ios-hosted-signing`; three secrets in **one** step | Only when `authorize` said yes. Compiles nothing and installs nothing. Re-checks the authorization and the archive digest and re-verifies the unsigned app (no secret yet); exports and signs (section 2); verifies the IPA with no secret present (V1 to V9); keeps text evidence. |

Verification after signing (every step fails the job; [IOS_RELEASE.md](IOS_RELEASE.md) section 9 is the reference):

| Check | How |
|---|---|
| V1 identity and version | Bundle ID `com.app.cadenabitcoin`, name "Cadena Bitcoin", `1.0.4` / `1000035`, read from the IPA's `Info.plist` |
| V2 seals | `codesign --verify --deep --strict` |
| V3 certificate | Authority `Apple Distribution:`, Team `D65458CPDP`; `verify_ipa.py certificate` reads the fingerprint; `codesign` + `openssl` must give the same value; the public leaf is kept as `signer.pem` |
| V4, V5 profile, entitlements | Selected profile fields (name, team, expiry, application identifier, no devices, no `get-task-allow`) and the signed entitlements; `aps-environment` fails (D6) |
| V6 environment | Production URL at least once, `staging.purabitcoin.com` zero times |
| V7 verifier | `verify_ipa.py verify production ... --repo <approved checkout> --unsigned-app <archive app> --forbid-entitlement aps-environment --expect-cert-sha256 <pin>` |
| V8 signatures only | `verify_ipa.py compare <archive app> <signed app>`; the baseline is the app of the archive that was exported, not a second build |
| V9 native library | The pinned library SHA-256 (carried from the build job), the nine expected exports, no forbidden names; the known D1 symbol is reported, not hidden |
| IPA integrity | SHA-256 after export and again after verification; they must match |

**The certificate fingerprint** is printed in the job summary and kept in `certificate-sha256.txt` and `pin.txt`. With an empty
`expected_cert_sha256` the pin used in V7 is the value just discovered, which is **circular** and is labelled so
(`pin_source=DISCOVERED`). The coordinator records the value in the release record (D8) **before any upload**; a later run passes it
in `expected_cert_sha256`, and a different certificate then stops the run.

**The IPA never leaves the runner.** It is not an artifact, not a Release and not in a log ([IOS_SIGNING.md](IOS_SIGNING.md) section 2,
item 8). Only text is kept: hashes, the fingerprint, the checks, redacted tool output, 30 days.

## 2. How the Developer API key is used

- `-exportArchive` with `ExportOptions.plist`: `method` `app-store-connect`, `signingStyle` `automatic`, `teamID` `D65458CPDP`,
  `destination` `export` (never `upload`), `manageAppVersionAndBuildNumber` `false`, `testFlightInternalTestingOnly` `false` (D9).
  No certificate, profile or `.p12` is named.
- `-allowProvisioningUpdates -authenticationKeyPath <file> -authenticationKeyID <id> -authenticationKeyIssuerID <issuer>`. Apple's
  `xcodebuild -help` for this Xcode (26.3, run `44625655320`) says this lets `xcodebuild` "create and update profiles, app IDs, and
  certificates" for automatically signed targets, and that with `signingStyle` automatic Xcode "will create provisioning profiles and
  managed cloud signing certificates as necessary, but will not register devices, register app IDs, or modify app ID settings" (that
  sentence is about archives that were signed manually; ours was built unsigned, see section 6).
- The `.p8` is written from the environment secret to `$RUNNER_TEMP` (mode 600, umask 077, outside the workspace and every artifact
  path), passed by path to `xcodebuild`, and removed by a trap on every exit (`rm -P`). A later step that always runs checks that no
  key file remains. Nothing traces (`set +x`), and everything kept from the step passes through a filter that replaces the exact key
  ID, issuer ID, key lines and key path with `[REDACTED]` (the key ID and issuer ID are secrets here, so GitHub masks them in logs too).
- Only Apple's `xcodebuild` and that filter run while the key exists. No Flutter, CocoaPods, repository script or dependency does; the
  repository scripts of the approved commit that the verifier needs run in steps that have no secret.
- **Developer role.** The key is a team key with role `Developer`. Apple's description of that role (cited in
  [IOS_SIGNING.md](IOS_SIGNING.md) section 1) lists development certificates, profiles and uploads; it does not state that the role may
  create or use a **cloud-managed Distribution** certificate. **Unconfirmed.** Whether it suffices is the question of the first run.
  On failure the evidence is `export.log` (redacted) and `export-diagnosis.txt` (pattern counts such as permission, 401/403, "No
  signing certificate", "No profiles for"). That text is an inference, never proof of the cause. No `.p12` route is built; one is a
  separate decision after a demonstrated failure.

## 3. What each secret is

| Environment secret | Content |
|---|---|
| `APPLE_API_KEY_P8` | The complete text of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
| `APPLE_API_KEY_ID` | The key ID shown in App Store Connect (`8QC5B7DRM5` per the coordinator) |
| `APPLE_API_ISSUER_ID` | The issuer ID shown above the team keys list in App Store Connect |

## 4. What the owner must configure by hand (nothing here is done by the pull request)

Organization Owners only ([IOS_SIGNING.md](IOS_SIGNING.md) section 7). Do this only after the pull request is merged and section 5 is
satisfied; creating the environment earlier changes nothing but also earns nothing.

1. Repository **Settings, Environments, New environment**: name exactly `ios-hosted-signing`.
2. **Deployment branches and tags: Selected branches**, one rule: `development`. (The workflow also refuses any other ref.)
3. **Required reviewers: none.** The authorization is the release record ([RELEASE_POLICY.md](RELEASE_POLICY.md) 2.3; the two
   Maintainers accounts are one person, so a reviewer would add no independence). **Wait timer: none.**
4. Add the three **environment** secrets of section 3. **Never** repository or organization secrets.
5. Do not add a variable, a `.p12`, a certificate password or a provisioning profile.
6. Ask for secret scanning and push protection if they are not on yet.

After the run: the key stays valid until revoked. Revoke it in App Store Connect when hosted signing is no longer needed, or at once if
anything about the run is in doubt.

## 5. Authorization, and the minimum amendments

**What blocks signing today (by design).** Two independent locks:

1. The environment and its secrets do not exist (section 4).
2. The release record must contain a complete **G2S** authorization. `tool/check_signing_authorization.sh` (run by the `authorize`
   job and again at the start of the `sign` job, before any secret is touched) accepts only these lines, each exactly once at the
   start of a line with LF endings, matching the inputs of the run:

```text
G2S-STATUS: AUTHORIZED
G2S-OPERATION: sign-and-verify-only
G2S-APPROVED-SHA: <APPROVED_SHA>
G2S-VERSION: <1.0.4+1000035>
G2S-BUNDLE-ID: com.app.cadenabitcoin
G2S-TEAM-ID: D65458CPDP
G2S-VERIFIER-BLOBS: <git blob of tool/verify_ipa.py>,<git blob of tool/ipa_inspect.py>
G2S-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-<id>
```

   and the record's status must be `G1 AUTHORIZED` or `G2 AUTHORIZED`. A different SHA, version, bundle ID, team or verifier blob, a
   duplicate or a typo, or the status `WITHDRAWN`, is a refusal. The verifier blobs at the time of writing (`development` `665e2f0`) are
   `6ee2b9d74c31321904e2c042aa2bc82fc402ab35` (`verify_ipa.py`) and `af7ced4341873dcff0113c4c417c0cce697938f6` (`ipa_inspect.py`); if
   either file changes, the authorization is stale and must be re-issued. The check is a tripwire, not the authorization.

**Why the current documents do not support a signing-only authorization.** In the record, G2 is "production signing **and** the one
upload" ([record](release-records/ios-1.0.4-1000035.md) section 4.1 and section 6; [IOS_RELEASE.md](IOS_RELEASE.md) gate table). D3, D9,
D11 and D12 describe signing on a Mac under the operator's control; section 4.1 item 4 makes the operator's Mac-side diagnostic a
prerequisite; [IOS_SIGNING.md](IOS_SIGNING.md) section 5 rejects a team key for a staging credential (option A), prefers an individual
key (B) and rejects "Admin-level key or Xcode cloud-managed signing" (C), and section 3.3 closes the signing experiments. A Developer-role
team key used for cloud-managed signing is a **deviation from section 5**, which says its model "is not final". Nothing was changed in any
of these files by this pull request.

**Minimum amendments (proposed text; each is a reviewed pull request and the CTO's decision):**

| # | Where | Amendment |
|---|---|---|
| A1 | Record section 6 (gate table) and section 4.1 | Add a gate **G2S, hosted signing and verification only**: the CTO's written authorization, on Issue #71, of the single operation "run `ios-hosted-signing.yml` for `APPROVED_SHA`, version `1.0.4+1000035`, bundle ID `com.app.cadenabitcoin`, Team `D65458CPDP`, from `development`, which signs the unsigned archive of that run, verifies the IPA and keeps text evidence; **no upload**". State that G2S is distinct from G2, that G2 then means "the one upload of the IPA verified under G2S", and that G2S gives neither G3, G4 nor G5. G2S evidence: the CTO's comment and the merged pull request that adds the eight `G2S-` lines above. |
| A2 | Record section 4 | Re-word **D3** (hosted signing on a GitHub-hosted runner instead of a Mac, `workflow_dispatch` from `development`, protected environment, the manual operation still an exception to the automation and not to the authorization policy), **D7** (cloud-managed certificate **through the team API key**; Xcode may create an Xcode-managed Distribution certificate and App Store profile in the team account, and the account state is not previewable), **D9** (export once, verify, then upload **the same IPA**: see section 6 on what carries the IPA from signing to upload), **D11** and **D12** (G2S/G2 split). Add the credential decision: a Developer-role team key whose app isolation is none (IOS_SIGNING.md section 5 option A), accepted for hosted signing of this release, to be revoked afterwards. Record the decision date and the decider; leave every other row as it is. |
| A3 | Record section 4.1, item 4 | The operator prerequisite "the operator has completed IOS_RELEASE.md steps 1 to 3 with the outputs returned" is satisfied by the hosted diagnostics run `44625655320` (same commit, same toolchain, the corrected scan). State that, and that Noah's role is then not needed for signing. |
| A4 | Record section 4, row X2, and section 7 | Add the **completed technical evidence** from run `44625655320` (verified 2026-11-20): `dlc_wallet.framework` imports `_stat`, `_fstat`, `_lstat` (plus `_clock_gettime` and `_sysctlbyname`) and ships no `PrivacyInfo.xcprivacy`; every other binary that imports a covered API ships a manifest; the manifest list and details are identical to the first run. The row stays **Open**: the decision (accept the risk and let Apple's processing be the test, or add a manifest to the pod, which changes frozen source and needs a new G1) is the CTO's. |
| A5 | [IOS_SIGNING.md](IOS_SIGNING.md) sections 3 and 5 and [IOS_RELEASE.md](IOS_RELEASE.md) section 1 | A pointer to this document: hosted signing exists as a manually started workflow for 1.0.4; section 5's key model is superseded **for this release** by A2; the Apple-side operator role is not needed for signing. [IOS_SIGNING.md](IOS_SIGNING.md) section 3.3 ("closed") is unaffected: it concerns the throwaway self-signed identity. |
| A6 | [RELEASE_POLICY.md](RELEASE_POLICY.md) 2.3, "Manual operations before automation exist" | One sentence: a manual operation may be a manually started workflow in a protected environment; it still needs the CTO's written authorization of that operation and is not an exception to the authorization policy. Only if the CTO wants the policy text to say so; the record's A1 is enough for this release. |

Not part of G2S, and not decided here: X1, X2, D1 and D2 (the record still reads "Proposed" for both; if the CTO has already accepted them on
Issue #71, that is record bookkeeping, not verified here), G2 (upload), G3 to G5, the push entitlement (D6 is enforced by V5/V7, not decided).

## 6. What is not known (the first run answers it)

1. **Can an unsigned archive be exported and signed?** The archive comes from `flutter build ipa --no-codesign` (`CODE_SIGNING_ALLOWED=NO`;
   `SigningIdentity` and `Team` in its `Info.plist` are empty). No Apple statement found says `-exportArchive` signs such an archive
   ([IOS_SIGNING.md](IOS_SIGNING.md) section 3.2, route B; developer reports say it can be exported with signing done at export
   time). **Unconfirmed.** If the export refuses it, the evidence names why; the alternatives (route A, signing the `.app` and building
   the IPA by hand, or a development-signed archive) are separate decisions.
2. **Developer role versus cloud-managed Distribution signing.** Section 2. **Unconfirmed.** Failure here is a result, not a bug.
3. **Apple-account side effects.** Even without upload, the export may create an Xcode-managed Distribution certificate and an App Store
   profile in the team's account. This is D7's consequence and part of what G2S would authorize.
4. **V7 and V8 have never seen a real Apple-signed IPA** ([IOS_RELEASE.md](IOS_RELEASE.md) section 9): they may reject a legitimate
   detail (an entitlement Xcode adds, the layout of nested `CodeResources`, a `SwiftSupport` folder). A rejection is reported in full and is
   evidence; a reviewed pull request may add a narrow allowance. Nothing is edited ad hoc and no check is skipped.
5. **The pin is circular on the first run** (section 1). Only the coordinator's recording, before the upload, makes it a pin.
6. **The IPA is not kept.** The record's D9 uploads "that same IPA". A signed IPA cannot be an artifact in a public repository, and
   the encrypted retention of [RETAINED_ARTIFACTS.md](RETAINED_ARTIFACTS.md) has no recipient configured. The upload therefore has to be a
   job **in the same run**, behind its own gate (G2), reusing this job's verified IPA. That job is not built here.
7. **Not checked by this workflow:** a certificate chain to an Apple root (no trust anchors are supplied) and revocation; App Store
   Connect acceptance; runtime behaviour on a device; X1 and X2.

## 7. The smallest steps from here

1. The CTO reviews and merges this pull request (nothing signs: no environment, no authorization).
2. Optionally run the workflow once from `development` **before** anything else exists: `authorize` reports "not authorized", `build`
   proves the unsigned hand-over, `sign` is skipped, and no secret is read.
3. A record pull request with amendments A1 to A4 (A5 and A6 optionally) and the eight `G2S-` lines, preceded by the CTO's written G2S
   comment on Issue #71.
4. The owner creates the environment and the three secrets (section 4).
5. Run the workflow with the defaults. Read the summary; record the certificate fingerprint (D8); decide X2 and X1 before any upload.
6. The upload job, as its own pull request, reusing the verified IPA of the same run, behind G2.
