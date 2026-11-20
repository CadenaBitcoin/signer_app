# iOS hosted signing: sign and verify only (Issue #71)

> **Status: implemented, NOT authorized, NOT run.** `.github/workflows/ios-hosted-signing.yml` can sign and verify the approved
> iOS 1.0.4 (1000035) build on a GitHub-hosted runner with Apple's cloud-managed Distribution certificate. It **cannot sign today**:
> the environment and secrets do not exist, and the release record carries no authorization for it (section 5). It **never
> uploads**. It decides no D or X row of the release record, changes no gate and is not G2. Parent issue: #54; release
> procedure: [IOS_RELEASE.md](IOS_RELEASE.md); record: [release-records/ios-1.0.4-1000035.md](release-records/ios-1.0.4-1000035.md).
> Every statement about Apple's behaviour below is labelled **Unconfirmed** until a run has shown it.
>
> **Revised after the independent security audit of this pull request** (findings F1 to F10, section 8): the key text no longer
> reaches `xcodebuild`'s environment, the authorization is bound to the implementation and to the release decisions, the archive
> is validated before and after extraction, the authorization cannot outlive a withdrawal through a re-run, input validation is
> whole-string, and the tests now run the real steps and a mutation suite instead of searching for strings.

## 1. What the workflow implements

Started by hand only (`workflow_dispatch`), from `refs/heads/development` only. Inputs: `approved_sha`, `content_ref`,
`expected_version` (the defaults are the release record's values) and `expected_cert_sha256` (empty on the first run).

| Job | Secrets / environment | What it does |
|---|---|---|
| `authorize` | none | Reads the release record **of its own commit**, which must be the **current tip of `development`** (read with `git ls-remote`; a re-run of an old run is refused), checks the gate's own blob itself and runs `tool/check_signing_authorization.sh`. No G2S authorization in the record, an undecided release row, or a changed workflow, gate or tool, means `authorized=false`, and the signing job is skipped. |
| `build` | none | The part that runs third-party code. Checks out exactly the approved commit and verifies it (SHA, ancestor of `production`, content equal to the reviewed content, clean tree, version), then the repository's own checks (`verify_build_config`, `verify_version`, the pinned Rust library SHA-256, `verify_artifact.sh`, `check_build_drift.sh`). **One** compile: `flutter build ipa --release --no-codesign` (the command of the diagnostics run `44625655320`). Hands the unsigned archive over as a one-day tar with its SHA-256. It runs whether or not signing is authorized, so the hand-over is exercised first. |
| `sign` | environment `ios-hosted-signing`; three secrets in **one** step | Only when `authorize` said yes. Compiles nothing and installs nothing, and executes **no script of the approved commit, of the build job or of the archive** (only `tools/`, this workflow's commit, and Apple's tools). Re-checks the authorization against the tip of `development` again, checks the archive digest, validates the archive before and after extraction (section 2.1), reads the unsigned app (no secret yet); exports and signs (section 2); verifies the IPA with no secret present (V1 to V9); keeps text evidence. |

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
  path), passed by path to `xcodebuild`, and removed by a trap on every exit. **The key text is then `unset` from the step's
  environment, and `xcodebuild` runs under `env -u` for all three secrets, so neither it nor any process it starts inherits a secret
  through its environment** (audit F1). The key ID and issuer ID are command-line arguments, the only way `xcodebuild` takes them. A
  later step that always runs checks that no key file remains. Nothing traces (`set +x`), and the step does not run under `errexit`
  (the runner's default `bash -e` would otherwise stop at a failing `xcodebuild` before the redacted evidence exists).
- Everything kept from the step passes through a filter, run while the key file still exists, that replaces the exact key ID, issuer
  ID, key lines and key path, PEM markers, **JWT-shaped tokens and bearer tokens** with `[REDACTED]`, and **fails (keeps nothing) if
  an exact value survives** (the key ID and issuer ID are secrets here, so GitHub masks them in logs too). The final evidence scan
  refuses key markers and JWT-shaped strings, so they cannot reach an artifact.
- Only Apple's `xcodebuild` and that filter run while the key exists. No Flutter, CocoaPods, repository script or dependency does.
  **No script of the approved commit runs anywhere in the signing job** (audit F10): the verifier's two needs from a "repository" are
  assembled by the job, the identity-matrix script from this workflow's commit (bound by the authorization) and `pubspec.yaml` of the
  approved commit as plain data. No step before the secret step writes anything but four fixed variables to `GITHUB_ENV`, and none
  writes `PATH`.
- **Developer role.** The key is a team key with role `Developer`. Apple's description of that role (cited in
  [IOS_SIGNING.md](IOS_SIGNING.md) section 1) lists development certificates, profiles and uploads; it does not state that the role may
  create or use a **cloud-managed Distribution** certificate. **Unconfirmed.** Whether it suffices is the question of the first run.
  On failure the evidence is `export.log` (redacted) and `export-diagnosis.txt` (pattern counts such as permission, 401/403, "No
  signing certificate", "No profiles for"). That text is an inference, never proof of the cause. No `.p12` route is built; one is a
  separate decision after a demonstrated failure.

### 2.1 The hand-over from the build job is data to be checked (audit F4)

The unsigned archive comes from a job that ran third-party code. The signing job therefore (1) takes it only from **this run** (the
artifact name carries the run ID and attempt; no `run-id`, token or pattern), (2) compares its SHA-256 with the digest the build job
reported, (3) lets `tool/validate_handover_archive.py list` read the **member list before extraction**, refusing absolute or `..`
names, names outside the single top-level `Runner.xcarchive`, control characters, duplicates, members that are not regular files,
directories or links, set-id or sticky bits, symbolic links that are absolute or leave the archive, hard links to anything but an
earlier regular file inside it, paths that run through an earlier link, and archives beyond the member and size limits, (4) extracts
once, (5) lets `... tree` check the **extracted tree** (no special file, no set-id bit, every link resolving inside it), and (6) reads it
only with Apple's tools. **Residual:** the digest is the build job's own claim, so a build job compromised through a dependency could
deliver a malicious but well-formed archive; nothing in this pull request can prove provenance beyond the pinned lockfiles and the
checks of the build job. **One part is now enforced:** the pre-signature binary `Frameworks/dlc_wallet.framework/dlc_wallet` (the
framework that carries the pinned Rust library) must equal the SHA-256 in the record's `G2S-DLC-WALLET-SHA256` line, compared by a
step that runs before Xcode is selected and before any secret exists, with strict equality, no tolerance, no environment variable
or workflow input that can substitute the value, and a diagnosis (both hashes) kept as evidence. The initial value proposed to the
CTO is `9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13`, which both diagnostics runs of 2026-11-19 produced for the
archive build (the preflight `flutter build ios` binary differs, `f0ec22a4...`, and is not the one to authorize). **A new build is not
assumed to reproduce it:** the diagnostics built twice in one job and the signing build compiles once, on a runner image that may have
changed. A difference stops the run before any secret is used; the cause is to be understood, and only a reviewed record pull request
can authorize another binary (nothing is relaxed in the workflow). The hash covers `dlc_wallet`, not the whole app: the other native
binaries were identical across the two runs except the Dart snapshot `App.framework/App`, which was not.

## 3. What each secret is

| Environment secret | Content |
|---|---|
| `APPLE_API_KEY_P8` | The complete text of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
| `APPLE_API_KEY_ID` | The key ID shown in App Store Connect for the dedicated team key |
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
7. **Verify before the first run** that the restriction took effect (the environment is the real boundary for the secrets; the
   workflow's own ref checks are a second line): `gh api repos/CadenaBitcoin/signer_app/environments/ios-hosted-signing --jq
   '{branch_policy: .deployment_branch_policy, protection_rules: .protection_rules}'` must show a custom branch policy, and the
   branch policy list must contain exactly `development`.

After the run: the key stays valid until it is revoked or rotated. Rotation and revocation in App Store Connect remain available security
controls (use them at once if anything about a run is in doubt); this document does not make revocation after the first signing run
mandatory. A temporary Admin key, if it should later prove necessary, is a separate explicit decision and is not covered by D14.

## 5. Authorization, and the minimum amendments

**What blocks signing today (by design).** Two independent locks:

1. The environment and its secrets do not exist (section 4).
2. The release record must contain a complete **G2S** authorization, **and** the release decisions G2S needs must be decided.
   `tool/check_signing_authorization.sh` (run by the `authorize` job and again at the start of the `sign` job, before any secret is
   touched) accepts only these lines, each exactly once at the start of a line with LF endings, **outside** fenced code blocks and
   HTML comments, matching the inputs of the run:

```text
G2S-STATUS: AUTHORIZED
G2S-OPERATION: sign-and-verify-only
G2S-APPROVED-SHA: <APPROVED_SHA>
G2S-VERSION: <1.0.4+1000035>
G2S-BUNDLE-ID: com.app.cadenabitcoin
G2S-TEAM-ID: D65458CPDP
G2S-WORKFLOW-BLOB: <git blob of .github/workflows/ios-hosted-signing.yml>
G2S-GATE-BLOB: <git blob of tool/check_signing_authorization.sh>
G2S-TOOL-BLOBS: tool/build_manifest.py=<blob>,tool/ipa_inspect.py=<blob>,tool/validate_handover_archive.py=<blob>,tool/verify_artifact.sh=<blob>,tool/verify_ipa.py=<blob>
G2S-DLC-WALLET-SHA256: <SHA-256 of Frameworks/dlc_wallet.framework/dlc_wallet in the unsigned archive that may be signed; proposed initial value 9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13>
G2S-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-<id>
```

   `bash tool/check_signing_authorization.sh --print-expected --tools-root .` prints the three blob lines for a checkout (it authorizes
   nothing). **The authorization is bound to the implementation** (audit F2): a later change to the workflow, the gate or any tool the
   signing job runs (`verify_ipa.py` imports `ipa_inspect.py` and `build_manifest.py`, which runs `verify_artifact.sh`) changes a blob
   and invalidates it; the CTO's record pull request must then name the new blobs. The binding is checked from two sides: the gate
   checks the workflow's blob, and the workflow itself checks the gate's blob before running it, so replacing one of them needs a
   matching change in the other. The record's status must be `G1 AUTHORIZED` or `G2 AUTHORIZED`; its `APPROVED_SHA` table row must
   name the SHA; a different SHA, version, bundle ID, team or blob, a duplicate or a typo, or the status `WITHDRAWN`, is a refusal.
   **The workflow revision must be the current tip of `development`** (audit F8): GitHub keeps the commit of a re-run, so without this
   a re-run of an old run would read the old record and outlive a withdrawal; any later commit to `development`, including a
   withdrawal, now stops a run, and a run in progress stops at the re-check before the secret step. Do not merge to `development`
   while a signing run is in progress. The check is a tripwire, not the authorization: it does not verify that the comment exists.

**Release decisions G2S needs (audit F3), enforced by the gate.** Each row below must exist exactly once in the record's decision table
with Status exactly `Decided`, a name in By (not `TBD`) and a date `YYYY-MM-DD`, set by the CTO in a reviewed record pull request. The
gate decides nothing; today every row reads "Proposed, not decided", so it refuses.

| Row | Why signing and verification need it | Needed for G2 (upload)? |
|---|---|---|
| D3 | the signing route: hosted runner instead of a Mac, `workflow_dispatch` from `development` (to be re-worded, A2) | yes |
| D6 | no `aps-environment`: the signing job enforces it (V5, V7) | yes |
| D7 | cloud-managed certificate through the team key; the export may create an Xcode-managed Distribution certificate and an App Store profile in the account | yes |
| D8 | how the certificate fingerprint is read, cross-checked and recorded (the run only discovers it) | yes, and recorded before the upload |
| D9 | export once, verify, no second compile, V8 baseline (re-worded for hosted signing; its upload half is G2) | yes |
| D10 | the verification tooling that judges the IPA (the blobs above bind the exact files) | yes |
| D11, D12 | the reading of the gates and the policy basis, which must introduce G2S as distinct from G2 | yes |
| D14 (new) | the credential decision: a **dedicated Developer-role Apple Team API key** for hosted signing, accepted with the fact that a team key's scope **cannot be restricted to one application** (IOS_SIGNING.md section 5, option A: access to all apps of the team, limited only by role); rotation and revocation stay available (not mandatory after the first run); a temporary Admin key needs its own decision | yes |

**Not needed for G2S, required before G2 (upload, TestFlight) and untouched here:** D1 (Issue #22 residual risk, accepted "before G2 is
requested"), D2 (zero-value wallets), D4 (production App Store Connect record), D5 (production gate), X1 (export compliance, App
Privacy), X2 (privacy manifest) and the prerequisites of record section 4.1. The reason: under G2S the signed IPA never leaves the
runner, nothing is sent to App Store Connect and nobody can install it. The CTO may tighten the list by amending the gate in a reviewed
pull request, which changes the gate's blob. G2S gives neither G2, G3, G4 nor G5, and the existing G1 to G5 governance is unchanged.

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
| A1 | Record section 6 (gate table) and section 4.1 | Add a gate **G2S, hosted signing and verification only**: the CTO's written authorization, on Issue #71, of the single operation "run `ios-hosted-signing.yml` for `APPROVED_SHA`, version `1.0.4+1000035`, bundle ID `com.app.cadenabitcoin`, Team `D65458CPDP`, from `development`, which signs the unsigned archive of that run, verifies the IPA and keeps text evidence; **no upload**". State that G2S is distinct from G2, that G2 then means "the one upload of the IPA verified under G2S", and that G2S gives neither G3, G4 nor G5. G2S evidence: the CTO's comment and the merged pull request that adds the eleven `G2S-` lines above and decides the rows above. |
| A2 | Record section 4 | Re-word **D3** (hosted signing on a GitHub-hosted runner instead of a Mac, `workflow_dispatch` from `development`, protected environment, the manual operation still an exception to the automation and not to the authorization policy), **D7** (cloud-managed certificate **through the team API key**; Xcode may create an Xcode-managed Distribution certificate and App Store profile in the team account, and the account state is not previewable), **D9** (export once, verify, then upload **the same IPA**: see section 6 on what carries the IPA from signing to upload), **D11** and **D12** (G2S/G2 split). Add **row D14**, the credential decision: acceptance of a dedicated Developer-role Apple Team API key for hosted signing, including the fact that its scope cannot be restricted to one application (IOS_SIGNING.md section 5 option A is a deviation for this release); rotation and revocation remain available security controls and are not made mandatory after the first run; a temporary Admin key, if later required, is governed by a separate explicit decision. Set Status to `Decided` (exact), the decider and the date `YYYY-MM-DD` for D3, D6, D7, D8, D9, D10, D11, D12 and D14 only; leave every other row as it is (D1, D2, D4, D5, X1 and X2 stay open for G2). |
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
8. **Risks this pull request cannot eliminate** (audit residuals):
   - *Provenance of the archive* (section 2.1): the digest is the build job's own claim; a dependency compromised in the build job
     could deliver a well-formed, malicious archive that the signing job would sign. Mitigations are the lockfiles
     (`--enforce-lockfile`), the pinned Rust library, the build job's checks, and the enforced `dlc_wallet` hash (which covers that one framework, not the Dart snapshot or the vendor SDKs); none proves provenance.
   - *Process arguments:* `xcodebuild` takes the key ID and issuer ID as arguments, so same-user processes can read them while it runs.
     The key text itself is only in the mode-600 file. Both are removed with the runner at the end of the job.
   - *The binding is a tripwire, not a lock:* a pull request that changes the workflow **and** the gate **and** the record, approved by
     the one reviewer, can authorize itself. The review of such a pull request is the boundary (RELEASE_POLICY.md 2.3).
   - *The authorization comment* is matched by form only; the gate does not call GitHub to prove that it exists or who wrote it.
   - *Public evidence:* the repository is public, so the 30-day text artifacts are readable by anyone who can read it. They hold the
     profile summary, certificate subject and redacted export log, never a key, token or the IPA. Rotate or revoke the key if anything about a run is in doubt.
   - *What runs only on macOS* (the archive step's `codesign`/PlistBuddy reads, V1 to V9, the real `xcodebuild`) cannot run in the Linux
     tests, which stub `xcodebuild` and `plutil` and use synthetic credentials. The first real run is the first test of those steps.
   - *No merge to `development` during a run:* the tip check stops the run at the re-check (fail closed, but a wasted run).

## 7. The smallest steps from here

1. The CTO reviews and merges this pull request (nothing signs: no environment, no authorization).
2. Optionally run the workflow once from `development` **before** anything else exists: `authorize` reports "not authorized", `build`
   proves the unsigned hand-over, `sign` is skipped, and no secret is read.
3. A record pull request with amendments A1 to A4 (A5 and A6 optionally), the decided rows of section 5 and the eleven `G2S-` lines
   (blobs from `--print-expected`), preceded by the CTO's written G2S comment on Issue #71. It is merged last, with nothing else
   merged to `development` until the run has finished.
4. The owner creates the environment and the three secrets (section 4).
5. Run the workflow with the defaults. Read the summary; record the certificate fingerprint (D8); decide X2 and X1 before any upload.
6. The upload job, as its own pull request, reusing the verified IPA of the same run, behind G2.

## 8. Disposition of the independent audit findings

| Finding | Disposition | Where |
|---|---|---|
| F1 key text inherited by `xcodebuild` | **Fixed**: `unset` after the file is written, `env -u` for all three secrets, filter reads the key file, `set +e` so evidence survives a failing export | workflow, credential step; section 2 |
| F2 authorization not bound to the implementation | **Fixed**: `G2S-WORKFLOW-BLOB`, `G2S-GATE-BLOB`, `G2S-TOOL-BLOBS` (now including the modules `verify_ipa.py` imports and the script it runs), checked from both sides | gate; section 5 |
| F3 G2S had no prerequisites | **Fixed**: nine decision rows must be `Decided`; upload-time rows named and excluded; nothing is decided here | gate; section 5 |
| F4 archive checked by name only | **Fixed**: member-list check before and tree check after extraction, once-only extraction, digest first; provenance residual documented | `tool/validate_handover_archive.py`; section 2.1 |
| F5 tests missed six dangerous edits | **Fixed**: `tool/test_ios_hosted_signing_behavior.sh` runs the real steps with stubs and synthetic credentials, parses the YAML, and applies 33 mutations (the audit's six and more); all are caught. They run on every pull request in the job `ios-signing-security` of `android-release-tests.yml` (PyYAML pinned and hash-checked) | tests; CI |
| F6 JWT-shaped tokens not redacted | **Fixed**: redaction filter and evidence scan, tested with a synthetic token | workflow; tests |
| F7 line-based validation | **Fixed**: whole-string matching in the workflow and the gate; two-line values refused | workflow, gate; tests |
| F8 re-run outlives a withdrawal | **Fixed**: the revision must be the tip of `development`, in the gate, twice | gate, workflow |
| F9 gate looseness | **Fixed** for the `APPROVED_SHA` row (exactly one table row) and for lines hidden in code blocks or comments; **not fixed**: the comment URL is not verified against GitHub | gate |
| F10 approved-commit scripts in the signing job | **Fixed**: none runs; the verifier's repository view is assembled from this commit's script and the approved pubspec as data | workflow |
| F11 public evidence, environment restriction | **Documented** (section 4, section 6 item 8); the environment must be restricted to `development` by hand | document |

**Adjustments made after the CTO's review of the pre-commit report:** the `G2S-DLC-WALLET-SHA256` line and its enforcement before any
secret exists (section 2.1); the signing-security tests run in pull-request CI (job `ios-signing-security`, which installs PyYAML 6.0.3
from hash-checked wheels only, in a throwaway virtual environment, and runs the three test scripts against the pull request merged into
its base); the specific Apple key ID is no longer in this document; D14 describes a dedicated Developer-role team key with the
no-application-isolation fact and keeps rotation and revocation available instead of mandating revocation. The structure of the G2S
prerequisite list (D3 D6 D7 D8 D9 D10 D11 D12 D14) was accepted in that review; **no row is decided by that acceptance and G2S is not
authorized.**
