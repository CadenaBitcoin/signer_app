# iOS hosted signing: sign and verify only (Issue #71)

> **Status: implemented; G2S authorization recorded (conditional); credential-free preflight done; NOT yet run with credentials.**
> `.github/workflows/ios-hosted-signing.yml` can sign and verify the approved iOS 1.0.4 (1000035) build on a GitHub-hosted runner with Apple's
> cloud-managed Distribution certificate. The CTO authorized **one** such run (**G2S**, release record sections 4.2 and 6.1, comment
> https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-7038341975); it becomes effective only when that record is merged on `development` and the gate passes. It **cannot sign** until the
> owner also creates the three environment secrets (section 4). It **never uploads**, and G2S is not G2: it gives no upload, no distribution and no later gate.
> The protected environment `ios-hosted-signing` exists (section 4); the credential-free preflight run `44726071796` (2026-11-20) built the unsigned archive,
> skipped `sign`, and showed that the real archive passes the validator and carries the authorized `dlc_wallet` hash (record section 4.2). Parent issue: #54; release
> procedure: [IOS_RELEASE.md](IOS_RELEASE.md); record: [release-records/ios-1.0.4-1000035.md](release-records/ios-1.0.4-1000035.md).
> Every statement about Apple's behaviour below is labelled **Unconfirmed** until a run has shown it.
>
> **Upload (section 9).** Everything above describes the signing-only operation. The same workflow can also upload the SAME verified IPA, but **only** when the release record's
> `G2S-OPERATION` is `sign-verify-and-upload` (record status `G2 AUTHORIZED`, D1, D2, D4 and D5 decided); otherwise it uploads nothing, as stated here.
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

Verification after signing (every step fails the job; [IOS_RELEASE.md](IOS_RELEASE.md) section 9 is the reference). After V7 to V9 and the digest
check, and even when one of them failed, a separate **read-only evidence step** keeps the archive's and the exported `Info.plist`, the DER
entitlements blob and the facts about them as text under `evidence/v8-capture/` ([IOS_SIGNING.md](IOS_SIGNING.md) section 3.1d). It decides nothing,
uses no secret, keeps no IPA, and fails only if evidence that should exist cannot be captured.

| Check | How |
|---|---|
| V1 identity and version | Bundle ID `com.app.cadenabitcoin`, name "Cadena Bitcoin", `1.0.4` / `1000035`, read from the IPA's `Info.plist` |
| V2 seals | `codesign --verify --deep --strict` |
| V3 certificate | Authority `Apple Distribution:`, Team `D65458CPDP`; `verify_ipa.py certificate` reads the fingerprint; `codesign` + `openssl` must give the same value; the public leaf is kept as `signer.pem` |
| V4, V5 profile, entitlements | Selected profile fields (name, team, expiry, application identifier, no devices, no `get-task-allow`) and the signed entitlements; `aps-environment` fails (D6) |
| V6 environment | Production URL at least once, `staging.purabitcoin.com` zero times |
| V7 verifier | `verify_ipa.py verify production ... --repo <approved checkout> --unsigned-app <archive app> --forbid-entitlement aps-environment --expect-cert-sha256 <pin>` |
| V8 signatures only | `verify_ipa.py compare <archive app> <signed app>`; the baseline is the app of the archive that was exported, not a second build. Byte-strict for every file except the top-level `Info.plist`, which may differ in serialization only (IOS_SIGNING.md section 3.1e); `compare` authenticates no signature (and says so on every invocation), `verify` does; the accepted file is equal in content, not byte for byte |
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
  Since Phase 7C a failed export also keeps this run's `Packaging.log` (redacted) in the evidence, with `packaging-log-source.txt` saying where it
  came from or why it was not collected ([IOS_SIGNING.md](IOS_SIGNING.md) section 3.1d).

### 2.1 The hand-over from the build job is data to be checked (audit F4)

The unsigned archive comes from a job that ran third-party code. The signing job therefore (1) takes it only from **this run** (the
artifact name carries the run ID and attempt; no `run-id`, token or pattern), (2) compares its SHA-256 with the digest the build job
reported, (3) lets `tool/validate_handover_archive.py list` check the **member list before extraction**, (4) extracts once, (5) lets
`... tree` check the **extracted tree**, and (6) reads it only with Apple's tools.

What the validator guarantees (and what it does not):
- **Before extraction (`list`)** it *simulates* the tree that extraction would create, the way macOS creates it: names are compared
  **ignoring case and Unicode normalization** (APFS treats `a` and `A`, or a precomposed and a decomposed accent, as one file). It
  refuses an absolute or `..` name, a name outside the single top-level `Runner.xcarchive`, control characters, NUL or backslashes;
  a name that equals an earlier one under that comparison; a member whose path runs **through** a symbolic link (so extraction never
  writes through a link, including by a case or normalization alias); a symbolic link that is absolute, or that, **resolved
  physically in the final simulated tree** (following every other link, `..` included), leaves the archive or loops (a purely lexical
  check misses `d -> .` plus `E -> d/..`, where each link looks contained and `E` is the parent of the archive); a hard link to
  anything but an earlier regular file inside it; every member type except regular file, directory, symbolic link and hard link (no
  device, FIFO, sparse or contiguous member); set-id and sticky bits; and archives beyond the member and size limits.
- **Symbolic links that stay inside the archive are accepted.** The diagnostics of run `44625655320` recorded the archive's tree but
  not which entries are links, so nothing proves that a genuine archive has none, and rejecting them could stop a genuine run. The
  tests include a genuine-structure archive (names from that run: 14 frameworks, the privacy bundle, `dSYMs`, `SwiftSupport`), with
  and without contained links of the `Versions/Current` kind, and it is accepted before and after extraction.
- **After extraction (`tree`)** the real filesystem is the judge: no special file, no set-id bit, and every link must resolve inside
  the extracted directory. This is the backstop for what the simulation cannot foresee, and the tests show that it also refuses the
  reviewer's chain.
- **Not guaranteed:** that the system `tar` and Python's `tarfile` read a crafted archive identically (a parser difference would make
  the simulation judge a different tree than the one extracted; the post-extraction check and the system tar's own refusal to write
  through links are the backstops, and the second is unverified on a macOS runner until the first run); and provenance (below).

**Residual:** the digest is the build job's own claim, so a build job compromised through a dependency could
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

Organization Owners only ([IOS_SIGNING.md](IOS_SIGNING.md) section 7). **Actual state (read from the GitHub API on 2026-11-20):** items 1 to 3 are
done and item 4 is not; the environment holds no secret, no variable, and the repository and organization hold no secret.

1. Repository **Settings, Environments, New environment**: name exactly `ios-hosted-signing`.
2. **Deployment branches and tags: Selected branches**, one rule: `development`. (The workflow also refuses any other ref.)
3. **Required reviewers: `sziller` and `CadenaWizard`** (the two accounts are one person, the CTO; `prevent_self_review` is off, so the CTO can confirm the
   deployment; **administrator bypass is disabled**). This approval **confirms the deployment only** (it is asked when the `sign` job starts, after the
   gate and the build, before any secret exists); it does **not** replace the CTO's authorization, which is the release record ([RELEASE_POLICY.md](RELEASE_POLICY.md)
   2.3, decision D12). It adds no independence and none is claimed. **Wait timer: none.** Do not merge anything to `development` while the run waits for this
   approval: the tip check would stop it.
4. Add the three **environment** secrets of section 3. **Never** repository or organization secrets.
5. Do not add a variable, a `.p12`, a certificate password or a provisioning profile.
6. Ask for secret scanning and push protection if they are not on yet.
7. **Verify before the first run** that the restriction took effect (the environment is the real boundary for the secrets; the
   workflow's own ref checks are a second line): `gh api repos/CadenaBitcoin/signer_app/environments/ios-hosted-signing --jq
   '{branch_policy: .deployment_branch_policy, protection_rules: .protection_rules}'` must show a custom branch policy, and the
   branch policy list must contain exactly `development`.

After the run: **remove the three secrets from the environment at once** (section 5.1); that is what stops a further run, because the workflow does not count runs.
Removing the GitHub secrets does **not** revoke the Apple key: it stays valid until it is revoked or rotated in App Store Connect. Rotation and revocation remain
available security controls (use them at once if anything about a run is in doubt); this document does not make revocation after the first signing run mandatory.
A temporary Admin key, if it should later prove necessary, is a separate explicit decision and is not covered by D14.

## 5. Authorization, and the minimum amendments

**What blocks signing today (by design).** Two independent locks:

1. The three environment secrets do not exist (the environment itself exists, section 4).
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

**Why the documents did not support a signing-only authorization (the state before the G2S authorization pull request, which amends them as listed below the table).** In the record, G2 is "production signing **and** the one
upload" ([record](release-records/ios-1.0.4-1000035.md) section 4.1 and section 6; [IOS_RELEASE.md](IOS_RELEASE.md) gate table). D3, D9,
D11 and D12 describe signing on a Mac under the operator's control; section 4.1 item 4 makes the operator's Mac-side diagnostic a
prerequisite; [IOS_SIGNING.md](IOS_SIGNING.md) section 5 rejects a team key for a staging credential (option A), prefers an individual
key (B) and rejects "Admin-level key or Xcode cloud-managed signing" (C), and section 3.3 closes the signing experiments. A Developer-role
team key used for cloud-managed signing is a **deviation from section 5**, which says its model "is not final". Nothing was changed in any
of these files by the pull request that added this document.

**Minimum amendments (the original proposal; each is a reviewed pull request and the CTO's decision; applied by the G2S authorization pull request as listed below the table):**

| # | Where | Amendment |
|---|---|---|
| A1 | Record section 6 (gate table) and section 4.1 | Add a gate **G2S, hosted signing and verification only**: the CTO's written authorization, on Issue #71, of the single operation "run `ios-hosted-signing.yml` for `APPROVED_SHA`, version `1.0.4+1000035`, bundle ID `com.app.cadenabitcoin`, Team `D65458CPDP`, from `development`, which signs the unsigned archive of that run, verifies the IPA and keeps text evidence; **no upload**". State that G2S is distinct from G2, that G2 then means "the one upload of the IPA verified under G2S", and that G2S gives neither G3, G4 nor G5. G2S evidence: the CTO's comment and the merged pull request that adds the eleven `G2S-` lines above and decides the rows above. |
| A2 | Record section 4 | Re-word **D3** (hosted signing on a GitHub-hosted runner instead of a Mac, `workflow_dispatch` from `development`, protected environment, the manual operation still an exception to the automation and not to the authorization policy), **D7** (cloud-managed certificate **through the team API key**; Xcode may create an Xcode-managed Distribution certificate and App Store profile in the team account, and the account state is not previewable), **D9** (export once, verify, then upload **the same IPA**: see section 6 on what carries the IPA from signing to upload), **D11** and **D12** (G2S/G2 split). Add **row D14**, the credential decision: acceptance of a dedicated Developer-role Apple Team API key for hosted signing, including the fact that its scope cannot be restricted to one application (IOS_SIGNING.md section 5 option A is a deviation for this release); rotation and revocation remain available security controls and are not made mandatory after the first run; a temporary Admin key, if later required, is governed by a separate explicit decision. Set Status to `Decided` (exact), the decider and the date `YYYY-MM-DD` for D3, D6, D7, D8, D9, D10, D11, D12 and D14 only; leave every other row as it is (D1, D2, D4, D5, X1 and X2 stay open for G2). |
| A3 | Record section 4.1, item 4 | The operator prerequisite "the operator has completed IOS_RELEASE.md steps 1 to 3 with the outputs returned" is satisfied by the hosted diagnostics run `44625655320` (same commit, same toolchain, the corrected scan). State that, and that Noah's role is then not needed for signing. |
| A4 | Record section 4, row X2, and section 7 | Add the **completed technical evidence** from run `44625655320` (verified 2026-11-20): `dlc_wallet.framework` imports `_stat`, `_fstat`, `_lstat` (plus `_clock_gettime` and `_sysctlbyname`) and ships no `PrivacyInfo.xcprivacy`; every other binary that imports a covered API ships a manifest; the manifest list and details are identical to the first run. The row stays **Open**: the decision (accept the risk and let Apple's processing be the test, or add a manifest to the pod, which changes frozen source and needs a new G1) is the CTO's. |
| A5 | [IOS_SIGNING.md](IOS_SIGNING.md) sections 3 and 5 and [IOS_RELEASE.md](IOS_RELEASE.md) section 1 | A pointer to this document: hosted signing exists as a manually started workflow for 1.0.4; section 5's key model is superseded **for this release** by A2; the Apple-side operator role is not needed for signing. [IOS_SIGNING.md](IOS_SIGNING.md) section 3.3 ("closed") is unaffected: it concerns the throwaway self-signed identity. |
| A6 | [RELEASE_POLICY.md](RELEASE_POLICY.md) 2.3, "Manual operations before automation exist" | One sentence: a manual operation may be a manually started workflow in a protected environment; it still needs the CTO's written authorization of that operation and is not an exception to the authorization policy. Only if the CTO wants the policy text to say so; the record's A1 is enough for this release. |

**Decided for G2S on 2026-11-20** (release record section 4): D3, D6, D7, D8, D9, D10, D11, D12 and D14. D6, the absence of the push-notification entitlement
(`aps-environment`), **is decided**: the CTO accepted it for this release, and the signing job enforces it (V5, V7). That acceptance does not extend to the Apple warning
ITMS-90078 at a later upload.

**Not part of G2S, still undecided, deferred to the gates named in record section 4.2:** X1, X2, D1, D2, D4 and D5 (the record still reads "Proposed" or "Open" for them;
the substance of D1 was accepted by the CTO on Issue #71 on 2026-11-12, which is record bookkeeping still to be done before G2), G2 (upload) and G3 to G5.

**Applied by the G2S authorization pull request** (reviewed by the CTO, which is the authorization boundary): (1) the release record: the gate
G2S in the gate table (section 6), the G2S lines (section 6.1), the scope, conditions, preflight and environment facts (new section 4.2), D3, D6, D7, D8,
D9, D10, D11, D12 and the new D14 `Decided` on 2026-11-20 with the accepted risks written into each row, the deferred rows D1, D2, D4, D5, X1 and X2
unchanged (X2 only gains the completed technical evidence and stays Open), the roles (section 2), signing route and facts (section 5), the results rows
(section 7), and the status unchanged at `G1 AUTHORIZED`; (2) [IOS_RELEASE.md](IOS_RELEASE.md): the G2S gate, the hosted-route notes and the Mac-route note of
section 8; (3) [IOS_SIGNING.md](IOS_SIGNING.md) section 5: the exception for this operation; (4) [RELEASE_POLICY.md](RELEASE_POLICY.md) 2.3: one sentence;
(5) this document: the status, the environment's actual configuration and the steps below.

### 5.1 One operation is authorized, and the workflow does not enforce it

The CTO authorized **exactly one** hosted signing-and-verification operation. **The workflow does not technically enforce a one-time execution limit**: it has no run
counter, the gate cannot tell that an authorization was used, and the same G2S lines keep passing the gate (and a new run can be dispatched) until the record is changed
and the secrets are gone. A re-run of an old run is refused only because the tip of `development` moves; a new dispatch from an unchanged tip is not. The controls are
procedures, written into the release record (section 4.2, "One operation"):

- An attempt that **reaches Apple credential use** (the secret step of the `sign` job starts) **consumes** the authorization, whether or not signing succeeds.
- Any **additional signing attempt requires explicit CTO authorization** (a new Issue #71 decision and a new reviewed record pull request).
- A failure **before** credentials are accessed (the gate, the build, the archive validator, the `dlc_wallet` hash comparison, any pre-secret check) is **not** a completed
  signing attempt; **any subsequent attempt still needs an explicit operator decision**, noted on Issue #71 with the failed run's ID and cause. Do not use GitHub's
  "Re-run" button for this.
- The **environment deployment approval is deliberate and specific** to the one authorized run (checklist in the record); a doubtful deployment is rejected.
- **After the attempt**, whatever its result, **remove the three Apple credentials from the environment** `ios-hosted-signing` at once and **withdraw the G2S
  authorization** through a reviewed pull request (`G2S-STATUS: WITHDRAWN`).
- **Removing the GitHub secrets does not revoke the Apple Developer API key.** The key remains valid in App Store Connect until it is rotated or revoked there, which stays
  an available security control and is not mandatory (D14).

## 6. What is not known (the first run answers it)

1. **Can an unsigned archive be exported and signed?** The archive comes from `flutter build ipa --no-codesign` (`CODE_SIGNING_ALLOWED=NO`;
   `SigningIdentity` and `Team` in its `Info.plist` are empty). No Apple statement found says `-exportArchive` signs such an archive
   ([IOS_SIGNING.md](IOS_SIGNING.md) section 3.2, route B; developer reports say it can be exported with signing done at export
   time). **Unconfirmed.** If the export refuses it, the evidence names why; the alternatives (route A, signing the `.app` and building
   the IPA by hand, or a development-signed archive) are separate decisions.
2. **Developer role versus cloud-managed Distribution signing.** Section 2. **Unconfirmed.** Failure here is a result, not a bug.
3. **Apple-account side effects.** Even without upload, the export may create an Xcode-managed Distribution certificate and an App Store
   profile in the team's account. This is D7's consequence and part of what G2S would authorize.
4. **V7 and V8 have seen real Apple-signed IPAs only in failed runs (the first two; see IOS_SIGNING.md sections 3.1d and 3.1e for what the second showed)** ([IOS_RELEASE.md](IOS_RELEASE.md) section 9): they may reject a legitimate
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
   - *No one-time execution limit:* the workflow does not count runs, and nothing technical marks the authorization as used (section 5.1). The single use rests on the
     procedures named there: the deliberate environment approval, removing the credentials, and the reviewed withdrawal.

## 7. The smallest steps from here

1. Done: the workflow and the gate are merged; the environment exists; the credential-free preflight (run `44726071796`) built the real archive and the
   validator and the `dlc_wallet` hash were checked against it.
2. The CTO reviews and merges the G2S authorization pull request (the record with the decided rows and the G2S lines). It is the last merge to `development`
   before the run.
3. The owner creates the three environment secrets of section 3 in `ios-hosted-signing` (never repository or organization secrets) and re-reads the environment
   (section 4, item 7).
4. Start the workflow by hand from `development` with the defaults. The required reviewers confirm the deployment **deliberately, for this one run** (the checklist of
   record section 4.2). The gate re-checks the record, the tip and the hash before any secret is used. Read the summary: the certificate SHA-256 is **discovered** (circular, D8) and is recorded in the release record, section 7.
5. After the signing attempt, whatever its result: **remove the three credentials from the environment at once**, then a reviewed pull request sets `G2S-STATUS: WITHDRAWN`
   (condition 8: a further attempt needs the CTO's new authorization; a failure before credential use is not a completed attempt, but a later attempt still needs an
   explicit operator decision, section 5.1) and, separately, fills section 7. Removing the secrets is not revoking the Apple key; rotate or revoke it if anything about
   the run is in doubt (D14).
6. The upload (G2) is a later, separate authorization and, if wanted, a separate pull request for an upload job; X1, X2, D1, D2, D4 and D5 are decided before it.

## 8. Disposition of the independent audit findings

| Finding | Disposition | Where |
|---|---|---|
| F1 key text inherited by `xcodebuild` | **Fixed**: `unset` after the file is written, `env -u` for all three secrets, filter reads the key file, `set +e` so evidence survives a failing export | workflow, credential step; section 2 |
| F2 authorization not bound to the implementation | **Fixed**: `G2S-WORKFLOW-BLOB`, `G2S-GATE-BLOB`, `G2S-TOOL-BLOBS` (now including the modules `verify_ipa.py` imports and the script it runs), checked from both sides | gate; section 5 |
| F3 G2S had no prerequisites | **Fixed**: nine decision rows must be `Decided`; upload-time rows named and excluded; nothing is decided here | gate; section 5 |
| F4 archive checked by name only | **Fixed**: member-list check before and tree check after extraction, once-only extraction, digest first; provenance residual documented | `tool/validate_handover_archive.py`; section 2.1 |
| F5 tests missed six dangerous edits | **Fixed**: `tool/test_ios_hosted_signing_behavior.sh` runs the real steps with stubs and synthetic credentials, parses the YAML, and applies 34 mutations (the audit's six and more); all are caught. They run on every pull request in the job `ios-signing-security` of `android-release-tests.yml` (PyYAML pinned and hash-checked) | tests; CI |
| F6 JWT-shaped tokens not redacted | **Fixed**: redaction filter and evidence scan, tested with a synthetic token | workflow; tests |
| F7 line-based validation | **Fixed**: whole-string matching in the workflow and the gate; two-line values refused | workflow, gate; tests |
| F8 re-run outlives a withdrawal | **Fixed**: the revision must be the tip of `development`, in the gate, twice | gate, workflow |
| F9 gate looseness | **Fixed** for the `APPROVED_SHA` row (exactly one table row) and for lines hidden in code blocks (CommonMark fences: closed only by the same character, at least as long, nothing after it) or comments; **not fixed**: the comment URL is not verified against GitHub | gate |
| F10 approved-commit scripts in the signing job | **Fixed**: none runs; the verifier's repository view is assembled from this commit's script and the approved pubspec as data | workflow |
| F11 public evidence, environment restriction | **Documented** (section 4, section 6 item 8); the environment must be restricted to `development` by hand | document |

**Adjustments made after the CTO's review of the pre-commit report:** the `G2S-DLC-WALLET-SHA256` line and its enforcement before any
secret exists (section 2.1); the signing-security tests run in pull-request CI (job `ios-signing-security`, which installs PyYAML 6.0.3
from hash-checked wheels only, in a throwaway virtual environment, and runs the three test scripts against the pull request merged into
its base); the specific Apple key ID is no longer in this document; D14 describes a dedicated Developer-role team key with the
no-application-isolation fact and keeps rotation and revocation available instead of mandating revocation. The structure of the G2S
prerequisite list (D3 D6 D7 D8 D9 D10 D11 D12 D14) was accepted in that review; **no row is decided by that acceptance and G2S is not
authorized.**

**Final-review corrections (three findings of the last security review of commit `638c87d`):** (1) the archive validator now simulates
the extracted tree, ignoring case and Unicode normalization, and resolves symbolic links physically in the final state (section 2.1);
(2) the gate's Markdown fence parsing follows CommonMark, so a marker hidden behind a `~~~` line inside a backtick block, or behind a
shorter fence inside a longer one, is no longer live; (3) the key text is unset right after it is written, before `chmod` or any other
process starts, and a test wraps the programs the step runs and fails if any of them has the key text in its environment.

## 9. The upload operation: sign, verify and upload the SAME IPA (`sign-verify-and-upload`)

**What it is.** The workflow can, when the release record says so, upload to App Store Connect the very IPA it has just exported and verified, from the same runner, and
nothing else. Without that record it behaves exactly as sections 1 to 8 describe: it signs and verifies and uploads nothing. Delivery to internal TestFlight needs this operation
because the signed IPA never leaves the runner (it is not an artifact, and a public repository cannot hold it), so it can be uploaded only from inside the run that verified it.

**How it is authorized (two separate answers).** The gate (`tool/check_signing_authorization.sh`) accepts exactly two values of `G2S-OPERATION`: `sign-and-verify-only` and `sign-verify-and-upload`.
The second additionally requires the record status **`G2 AUTHORIZED`** and the decisions **D1, D2, D4 and D5** to be decided, on top of everything G2S needs (the same blob binding of the workflow, the gate and the tools,
the approved SHA, version, bundle ID and team, the current tip of `development`). The `authorize` job exposes the answer as `upload_authorized`: true only when the gate passed **and** the record names the upload operation.
The lines of an earlier signing-only authorization can therefore never authorize an upload, and a withdrawn authorization authorizes nothing. The authorization itself is the CTO's written decision and the merged record pull request
(sections 5 and 5.1 apply unchanged: one operation, consumed when the credential step starts, secrets removed afterwards, withdrawal by reviewed pull request). G3 (tester assignment), G4 (App Review) and G5 (release) are **not** given by it.

**What the signing job does, in order** (all three upload steps run only when `upload_authorized` is true; none has `always()`, `failure()` or `continue-on-error`, so GitHub runs them **only if every earlier step succeeded**, V1 to V9 and the digest check included):

1. **Probe Apple's upload tool** (no secret; before the export). `xcrun altool --help` must offer a complete interface: the current one (`--upload-package` with `--api-key` and `--api-issuer`, `--platform`, `--apple-id`, `--bundle-version`,
   `--bundle-short-version-string`) or the legacy one (`--upload-app` with `--apiKey` and `--apiIssuer`). Neither means the run stops here, **before any credential is used** and before the export. The syntax is chosen from what the runner's Xcode actually offers, not assumed.
2. The export and the verification as before.
3. **Re-check** (no secret). The authorization is read again with the live tip of `development` (a withdrawal merged while the run is going stops the upload), the record's operation is `sign-verify-and-upload`, the IPA's digest equals the one recorded at the export and after the verification,
   and its bundle ID, version and build equal the verified ones (V1) and the release record's.
4. **Validate and upload** (the second and last step with the three secrets). The key text is written to `AuthKey_<id>.p8` in an empty mode-700 directory of `RUNNER_TEMP` (the key ID and issuer ID must have the shape Apple issues before any file name or argument is built from them), removed from the environment before any other process starts,
   and altool runs with no secret in its environment. `altool --validate-app` runs first (Apple's own check; it uploads nothing); only if it succeeds is the **one** upload run, of the same file. There is no loop and no retry. Everything kept passes the redaction filter of the export step; the key file is removed on every exit.
5. **Check again** that no key file remains (always), then the evidence steps as before. Evidence added: `upload-tool-probe.txt`, `upload-tool-help.txt`, `upload-precheck.txt`, `upload-validate.log`, `upload.log` (redacted) and `upload-result.txt` (`uploaded=yes|no`, the exit codes, the digest of the uploaded file).

**What a failure means.** A failed validation uploads nothing. A failed **upload** leaves no IPA anywhere (it was never an artifact): the operation is consumed, the evidence says what Apple answered, and a new run needs the CTO's explicit decision (look in App Store Connect for a build 1.0.4 (1000035) first; do not use GitHub's Re-run).
A successful upload is **not** availability to testers: Apple processes the build, the export-compliance question is answered in App Store Connect, and assignment to the internal group is G3.

**Constants and limits.** `APP_APPLE_ID` (`6753348211`) is the App Store Connect record of the production app, taken from the release record (section 5 item 2, coordinator-reported); altool's current interface needs it, and a wrong value is refused by Apple. The credential is the same environment's three secrets;
which key (role) is loaded is the CTO's decision and is not verifiable from the run. Unconfirmed until a run has shown it: that the runner's altool offers one of the two interfaces (the probe decides, before any credential), and Apple's acceptance of the build.
