# iOS staging delivery: automatic signing and TestFlight upload on a merge into `staging`

Issues #54 (parent), #57, #69, #71. Workflow: `.github/workflows/ios-staging-delivery.yml`. Gate: `tool/check_staging_authorization.sh`.
Record: `docs/release-records/ios-staging-authorization.md`. Tests: `tool/test_check_staging_authorization.sh`, `tool/test_ios_staging_delivery.sh`.

**Status: run once, failed before signing; no signing or upload has ever happened.** The first attempt, version `1.0.5+10005001` (run `45995314041`), failed at the secret check because no secret existed for the job (section 8.1); its number is consumed. The CTO authorized the delivery on 2026-11-27 (Issue #71; decisions S1 to S4 and C1 to C4) and authorized the next attempt, `1.0.5+10005002`, by the recovery decision named in the record; the committed record is `AUTHORIZED` for that version only and is withdrawn again by a reviewed pull request after the delivery (section 4). The delivery is not complete until a promotion merge, the credential, the environment approval and the upload have actually happened. The record states
its own default: a record that is not `AUTHORIZED` for the exact version of the commit makes this workflow fail visibly at its first job and sign nothing.

**Credential model (CTO decision on Issue #71, 2026-11-26, revising the first design of this pull request).** The original temporary provisioning of the Admin-level App Store
Connect API key is **preserved**: the key is **never stored permanently in GitHub**. The merge starts the workflow; the credential-free jobs run by themselves; the signing job
**waits for the approval of the protected environment `ios-hosted-signing-stg`**; the CTO provisions the three secrets for that window, approves, and removes them afterwards
(section 1.1). Permanent storage of the Admin key is **not authorized**.

## 1. What happens on a merge into `staging`

```text
merge PR development -> staging
   |-- android-ci-validation.yml   debug APK, staging flavor           -> GitHub artifact, 14 days            (unchanged)
   |-- ios-ci-validation.yml       unsigned compile validation          -> GitHub artifact, 14 days            (unchanged)
   |-- build-variants.yml          compile validation, evidence         ->                                     (unchanged)
   '-- ios-staging-delivery.yml    (this document)
         authorize   staging gate: record, version, live tip of staging, merge commit, development's content   (no secret)
         build       one unsigned `flutter build ipa --flavor staging`, verified, handed over as a one-day tar  (no secret)
         sign        environment ios-hosted-signing-stg, required reviewers: WAITS for the CTO's approval
                     then export + sign (cloud-managed certificate), V1..V9, upload (the only secrets; provisioned for this window only)
```

Nobody dispatches anything: the merge starts the run. There is no `workflow_dispatch`. If the gate refuses, `authorize` fails, so the run is red, `build` and `sign`
are skipped, and no secret is read. If the gate passes, the `sign` job stops at the environment approval and nothing happens until the CTO acts (section 1.1).

### 1.1 The operational order of one delivery

The record is already `AUTHORIZED` (merged before the promotion, section 4); the environment `ios-hosted-signing-stg` exists with **no secret** in it.

| # | Who | What | Why here |
|---|---|---|---|
| 1 | Maintainers | A reviewed `development -> staging` merge carries the version advance and the `AUTHORIZED` record. The merge starts `ios-staging-delivery.yml`. | The authorization is the record, given before the promotion; nobody dispatches. |
| 2 | GitHub | `authorize` (the gate, no secret) and `build` (one unsigned archive of the merge commit, no secret) run and finish. The archive is handed over as a **one-day** artifact. | Everything that runs third-party code finishes before any credential exists anywhere. |
| 3 | GitHub | `sign` shows *Waiting*: the environment's required reviewers must approve. No secret is released to it and nothing runs. | The approval is the human moment before the credential is used. |
| 4 | CTO | **Before approving**, checks the run (list below) and **provisions the three environment secrets** `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` of `ios-hosted-signing-stg` from the key held offline. | The key is in GitHub only from here until step 7. |
| 5 | CTO | **Approves** the `sign` job. | The deployment is confirmed (see below: it does not replace the record). |
| 6 | GitHub | `sign` runs: the gate runs again, the hand-over is validated, the framework hash is enforced (all before any secret is read), then export and signing, V1 to V9, the pre-upload re-check, and the upload of **the same IPA** to the staging application. | Unchanged from the tested production steps. |
| 7 | CTO | **Removes the three secrets at once**, whatever the result, and checks that the environment holds none (`gh api repos/CadenaBitcoin/signer_app/environments/ios-hosted-signing-stg/secrets --jq .total_count` must print `0`; it lists names only). | Removing the secrets is what stops a further run. It does not revoke the Apple key (a separate CTO decision). |

**Before approving (step 4)**, the approver checks that: the run belongs to the promotion just merged and is the **current tip of `staging`**; `authorize` and `build` succeeded with the authorized version
(`1.0.5+...` as recorded); no other run of this workflow is waiting (section 1.3); **the build finished less than a day ago (section 1.2)**; and nothing about the run is in doubt. A doubtful run is
**rejected**, never approved "to see what happens". The approval **confirms the deployment only**: it is not the authorization (the record is), it adds no independence (the two reviewer accounts are one
person, as for production) and it never replaces the gate, which runs again after the approval and before the key is read.

### 1.2 The one-day retention constraint of the unsigned archive

The `build` job hands the unsigned archive to `sign` as a GitHub artifact with `retention-days: 1` (the minimum; the app is open source and the archive is unsigned, but nothing keeps it longer than needed).
**The approval must therefore come within one day of the end of the `build` job** (aim for hours: the artifact is deleted at 24 hours from its creation, and `sign` downloads it
right after the approval). Consequences:

- if the approval comes later, the artifact is gone, `sign` fails at **"Download the unsigned archive"**, which is **before any secret is read**; nothing is signed or uploaded;
- the secrets must nevertheless be removed (step 7), because they were released to the job when it started;
- the run cannot be repaired by **Re-run** (the archive is gone and the gate refuses a stale tip); the repair is a reviewed pull request with a new build number (section 8), exactly as for any failed delivery;
- raising the retention would keep an unsigned archive longer, and would let an approval wait longer; that is a deliberate, reviewed change of the workflow and of the record's blob, **not made here**.

### 1.3 Waiting runs, a second promotion, rejection

The workflow has `concurrency: group ios-staging-delivery, cancel-in-progress: false`. A run waiting for approval counts as running, so a **second promotion queues behind it** (GitHub keeps
the newest queued run). The waiting run is then stale: its gate would refuse it after the approval (the tip of `staging` moved), so **reject it** and approve the newer one. A rejected run fails the `sign` job; no
secret was read. Whether and when GitHub times out a job that waits for approval indefinitely is **not established here**: do not rely on it, and treat the one-day constraint above as the limit.

**Android** needs nothing new: `android-ci-validation.yml` already builds the staging APK on every push to `staging` (application ID
`com.cadenabitcoin.mobile.signer.staging`, staging configuration, staging icon, `tool/verify_artifact.sh` checks, debug signing classified, 14-day artifact named with the
version, environment and source commit). `tool/test_ios_staging_delivery.sh` pins this, and this change does not modify that workflow.

## 2. What is reused and what is new

| Reused unchanged | New |
|---|---|
| The production signing steps, **as text**: export and sign (the first step with the key), upload (the second), the upload-tool probe, the key-file checks, the hand-over validation, V1 to V9, the evidence seal | `ios-staging-delivery.yml` (trigger, authorization and source steps, the V6 call, the delivery record) |
| `tool/verify_ipa.py` (already supports `staging`), `ipa_inspect.py`, `validate_handover_archive.py`, `verify_artifact.sh`, `build_manifest.py`, `verify_build_config.sh check-binary` | `tool/check_staging_authorization.sh` and its test |
| The production gate's strict record parser (`check_signing_authorization.sh --print-field`) | `docs/release-records/ios-staging-authorization.md` (AUTHORIZED for 1.0.5+10005002) |
| The Apple team, the cloud-managed Distribution certificate, `altool` | the GitHub environment `ios-hosted-signing-stg` (a GitHub setting) |

`ios-hosted-signing.yml`, `check_signing_authorization.sh`, the production record and every bound tool are **byte-identical**: `tool/test_ios_staging_delivery.sh` checks the
workflow against the blob its production record names, and compares the secret-bearing and verification steps of the two workflows text for text (after undoing a short list of
re-pointings). The production workflow stays manual, development-only and gated; it still cannot run for staging.

## 3. The staging identity

Constants of the workflow **and** of the gate (never values of the record or of an input): bundle ID `com.app.cadenabitcoin.staging`, display name "Cadena Signer STAGING",
environment `staging` (`config/build/staging.json`, Signet), flavor `staging`, team `D65458CPDP`. The gate refuses the production bundle ID and the production Apple application
(`6753348211`) whatever a record says. V6 requires the staging backend URL inside the signed app and the production URL nowhere.

## 4. Authorization design

**The conflict.** The production gate authorizes ONE manual, consumed operation, for a commit that already exists on `production`, read from `development`. A merge into `staging` has no
such moment: the merge commit does not exist when the decision is taken, and RELEASE_POLICY.md 2.3 (CTO, 2026-11-17) says the authorized merge is the authorization with no step after it.
CLAUDE.md and `GOVERNANCE.md` forbid weakening a signing gate. The two are reconciled, not traded off:

1. **The authorization is given before the promotion**, by the reviewed pull request that advances the version and updates the staging record. It is bound to everything that can be known then:
   the version `X.Y.Z+N`, the staging bundle ID, the Apple team, the staging Apple application, the **recorded** certificate fingerprint, the native library's framework hash, and the git blobs of the
   workflow, the gate and the tools. A change to any of them invalidates it.
2. **What cannot be known (the merge commit) is checked structurally**, by the gate, at run time: the commit is the **current tip of `staging`** (a re-run or a later promotion refuses), a **two-parent
   merge**, its merged side is an **ancestor of the current `development`**, and the application content under the same paths as the production workflow's `CONTENT_PATHS` equals that side.
3. **A live kill switch**: the same record on the **current tip of `development`** must still say `AUTHORIZED`. A withdrawal merged on `development` stops the next delivery, even for a promotion that
   already carries `AUTHORIZED`, and even for a run already in progress (the gate runs again before the key is touched and again before the upload).
4. **Default closed**: a record that is not `AUTHORIZED` for this version refuses (the designed default is `WITHDRAWN`); a missing, repeated, indented, fenced, commented or malformed line refuses.
5. **Fail closed**: if the remote cannot be read, or `development` has no record, nothing is authorized.

**What is NOT bound, and why that is the residual risk.** The record cannot name the merge commit, so the human review of the pull request (a Maintainers approval; no bypass actors) is what
approves the content. A malicious change to the workflow or the tools is caught only by the blob lines, which the same pull request can also edit: the protection is the review, as for any
file under `.github/`. The environment's branch restriction (section 5) keeps the secret out of reach of every branch but `staging`.

**Staging delivery follows the production credential model, recorded as the CTO's decisions S1 to S4** in the record: the staging application (S1), a **temporarily provisioned Admin-role Apple team key**
with an environment approval (S2), the record-before-promotion authorization with the approval as a deployment confirmation (S3), and the Signet-only rule (S4). The production runs showed that cloud-managed
signing needs the Admin role (Developer and App Manager keys failed with identical errors; whether the Admin role is strictly necessary is not proven) and that a team key cannot be limited to one application.
So the key is powerful and account-wide, and **it is not kept in GitHub**: the master copy stays offline with the CTO; GitHub holds the three secrets only from step 4 to step 7 of section 1.1, exactly as for each production
authorization (A to E; the CTO's D16 decision: "No indefinite GitHub credential storage is authorized"). **Permanent storage of the key in a GitHub environment, which the first design of this change proposed, is NOT authorized.**

**Where this differs from the written policy (to be reconciled by a reviewed amendment, not by this change).** RELEASE_POLICY.md 2.3 says the authorized merge is the authorization and that no step follows it, and
IOS_SIGNING.md section 6 says required reviewers are "not used". The CTO's decision on Issue #71 adds one human step **after** the merge for staging: the environment approval, together with the temporary credential.
It is a deployment confirmation, the same role as for the production operations (D12), not a second authorization. Neither document is edited here.

## 5. Prerequisites that are not repository changes (what the human must do)

Apple-side evidence read in the repository (all coordinator- or CTO-reported, **not verified through Apple**): the Organization team `D65458CPDP`; a cloud-managed Apple Distribution certificate
(SHA-256 `7ee3f6ce…ef418e`, valid until 2027-07-09, used by the production run 45221165334); the production application "Cadena Bitcoin" (Apple ID `6753348211`) with the internal group "Cadena Internal Testing".
**Reported by the maintainer on 2026-11-26 (after PR #144; not independently verified through Apple by Claude):** the staging application now exists in App Store Connect: "Cadena Signer STAGING",
bundle ID `com.app.cadenabitcoin.staging`, **Apple ID `6839776198`**, with the internal TestFlight group "Cadena Internal Testing - staging only" (testers: Kevin and Noah). The GitHub environment exists
under the name **`ios-hosted-signing-stg`** (deliberately distinct from the production environment `ios-hosted-signing`, which is unchanged): required reviewers `sziller` and `CadenaWizard`, deployment branch `staging`, **no
environment secret**. Its configuration is managed by the maintainer, not by this repository. The staging provisioning profile is still not shown anywhere; cloud signing creates it (unproven until the first run).

| # | Where | Action | Needed because |
|---|---|---|---|
| A1 | developer.apple.com, Identifiers | Register the App ID `com.app.cadenabitcoin.staging` (explicit; no push capability needed: the app signs no `aps-environment`). | Cloud signing may register it itself, but that is **unproven**; registering removes the question. |
| A2 | App Store Connect, Apps | **Done** (Apple ID `6839776198`, section above). Create the application "Cadena Signer STAGING", bundle ID `com.app.cadenabitcoin.staging`, a SKU, primary language. Note its **numeric Apple ID**. | The upload targets an existing record; the App Store Connect API cannot create one. |
| A3 | App Store Connect, TestFlight | **Done** (group "Cadena Internal Testing - staging only"; export compliance for the first build is still to be answered). Create an internal group for the staging application and add the testers; answer export compliance for the first build. | Nobody can install a build otherwise (assignment is not automated, on purpose). |
| A4 | App Store Connect, Users and Access, Keys | Provide the Team API key for staging (**Admin** role, see S2): the existing key of the production authorizations (D16 to D18, a CTO decision to reuse it) or a new one. Keep the `.p8` **offline** (restricted permissions, encrypted backups); GitHub gets it only temporarily (G2). | Cloud-managed signing and `altool`. |
| G1 | GitHub, Settings, Environments | **Done by the maintainer** (name `ios-hosted-signing-stg`). Create `ios-hosted-signing-stg`. **Deployment branches: selected branches, only `staging`. Required reviewers: `sziller` and `CadenaWizard`** (the same two accounts as `ios-hosted-signing`; `prevent_self_review` off because they are one person; administrator bypass disabled; wait timer none). **Create it with no secret.** | The branch restriction keeps the secret from every other branch; the reviewers make `sign` wait for the approval, and secrets are only released to a job after it. |
| G2 | the environment's secrets | **Nothing in advance.** For each delivery, the CTO adds `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` **while `sign` waits** (section 1.1, step 4) and removes them after the run (step 7). Never repository or organization secrets. | The three secrets of the two key-holding steps, present only for the run. An empty environment is the standing "off" state. |
| G3 | GitHub, Issue #71 | The CTO's decisions S1 to S4 on Issue #71 and the authorization comment (its URL goes into the record). | `G2S-STAGING-AUTHORIZATION`. |

Repository secrets and the production environment `ios-hosted-signing` hold **0** secrets today (read via the GitHub API on 2026-11-26), so nothing is reusable there: the production Admin key was removed after
its last run, as its record required. Reusing the **same key** is possible (the decision is the CTO's, as D17/D18 did for production); it is then stored in two environments.

## 6. `package_info_plus` and `ios/Podfile.lock` (resolved by this change)

The Dashboard reads the installed version with `package_info_plus` 8.3.1 (Issue #142, merged by PR #143), which is a new iOS pod. The committed `ios/Podfile.lock` did not list it, so
`tool/check_build_drift.sh` failed every iOS build: this would have failed the `build` job of the staging delivery on its first run. Resolution (reviewed in the pull request of this change):
the manual `iOS CI validation build` was run on `development` (run `45873167994`, `e670192`, no secrets, unsigned); it failed on exactly that drift and printed the lock's diff, which is
four additive hunks (the pod, its `Flutter` dependency, its external source, its checksum `package_info_plus: c0502532a26c7662a62a356cebe2692ec5fe4ec4`). That diff was applied unchanged, and
the resulting file has the git blob `13c9efdd...` that the runner printed. The lock therefore comes from the pinned runner, not from a developer machine (docs/IOS_CI.md). A green
`iOS CI validation build` on this pull request's branch is the proof that no drift remains.

## 7. Versions

`pubspec.yaml` is the only source; no workflow writes or overrides it. The authorization binds `X.Y.Z+N`: the first staging delivery attempt was **1.0.5+10005001** (approved on Issue #54, PR #146; authorized on Issue #71 on 2026-11-27; failed, consumed, section 8.1); the next attempt is **1.0.5+10005002**, then `10005003`, and so on.

## 8. Failure handling

| Failure | Result |
|---|---|
| Record WITHDRAWN, incomplete, stale blobs, or version differs from `pubspec.yaml` | `authorize` red; nothing built or signed; the Android APK and the unsigned iOS validation are unaffected |
| Not a merge commit, not development's content, not the tip of `staging` | the same |
| Native library framework differs from the record | `sign` stops before Xcode and before any secret |
| Export / signing fails | redacted evidence kept, key file removed, nothing uploaded |
| Any of V1 to V9 fails (identity, certificate pin, profile, V6 environment, V8 "signatures only", native exports) | nothing uploaded |
| A newer promotion or a withdrawal appears during the run | the gate runs again before the key and before the upload and stops it |
| Apple's validation or upload fails | no retry; a person looks in App Store Connect first; **do not use Re-run**; the repair is a reviewed pull request with a new build number |
| Build number already used in the staging application | Apple refuses the upload; consumed numbers are never reused (RELEASE_POLICY.md 7.3) |
| The approver rejects the waiting `sign` job | `sign` fails; no secret was read; nothing signed or uploaded; the record is unchanged; nothing to remove if no secret was provisioned |
| Approval comes after more than a day (section 1.2) | the archive download fails before any secret is read; **remove the secrets**; no Re-run; a new promotion with a new build number |
| Approved with a missing secret | the first secret step stops at "A secret ... is missing" before it writes a key file; nothing signed; provision the missing secret **only for a new run** (no Re-run) |
| Another promotion is merged while a run waits (section 1.3) | the waiting run is stale: reject it; its gate would refuse it after the approval (the tip of `staging` moved) |
| The secrets are still in the environment after a run | the standing "off" state is lost: remove them at once and check `total_count` is `0` (section 1.1, step 7); a leftover key can be used by the next run that is approved |

### 8.1 The first attempt (`1.0.5+10005001`) and the second (`1.0.5+10005002`)

**What happened (run `45995314041`, `staging` at `a6ed42f`, 2026-11-27).** `authorize` and `build` passed, and the framework hash check passed on the real merge commit. `sign` waited for the approval, was approved by `CadenaWizard` about 31 seconds after it began waiting,
and stopped at "Export and sign ... (the only step with secrets)" with `A secret of the environment ios-hosted-signing-stg is missing`: the three secrets were empty in the step (the environment, the production environment and the repository held none). No key file was written
and nothing was exported, signed or uploaded. The number `10005001` is consumed. Whether a secret added **during** the wait reaches the job was not tested by that run, because none was added.

**Second attempt (`10005002`): the order changes, the mechanisms do not.** The three secrets are provisioned in `ios-hosted-signing-stg` and **verified before the merge into `staging`**: `gh api repos/CadenaBitcoin/signer_app/environments/ios-hosted-signing-stg/secrets --jq '.total_count, [.secrets[].name]'`
must print `3` and exactly `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_P8` (names only; the values are never read). The secrets are still released to the job only after the environment approval and only on the branch `staging`; the approval, the gate runs, the one-day archive retention and the removal after the run
(step 7 of section 1.1, `total_count` back to `0`) are unchanged. Do not add or approve anything else in the meantime; a failed attempt again needs a reviewed pull request with the next number.

## 9. Not proven until the first real run

The new workflow's secret-bearing steps are the production steps' text, but: the staging archive and `flutter build ipa --flavor staging` have only been compiled as an unsigned `.app` by CI before;
whether Apple's cloud signing creates the staging App ID and profile on its own (A1 removes the doubt); the framework hash of a staging archive (the record's proposal is the staging archive's own value, measured by two preflight runs, section 10.1; a different hash stops the run
before any secret and prints the real value); and the Podfile.lock regeneration of section 6. Expect one or two corrective pull requests on the first real run; each stops safely.

**Also not proven: that a secret added while the job waits is available when it starts.** GitHub documents that a job cannot access environment secrets until the required reviewers approve it, which points
the right way, but nothing in this repository shows a secret being added during the wait (the production authorizations added theirs before dispatch). The operational order of section 1.1 depends on it.
**CTO decision of 2026-11-27: no separate experiment is required**; the documented GitHub lifecycle is accepted, with this exact sequence not yet exercised. Appendix A remains available as an optional harmless test and was **not run**. If the order does not hold,
`sign` stops at its first secret step ("A secret ... is missing") before it writes a key file; nothing is signed; the secrets are removed, the build number is consumed, and the next reviewed attempt provisions the secrets
before the merge (they would then exist in the environment while the run waits, which is the production sequence) and the approval still gates their use.

## 10. Credential-free preflight of the staging archive (the `dlc_wallet` hash before any authorization)

**Why.** The record pins the SHA-256 of `Frameworks/dlc_wallet.framework/dlc_wallet` inside the unsigned **archive** that the `build` job makes with `flutter build ipa --release --no-codesign --flavor staging`
and the `sign` job extracts. The first proposed pin (`9a2d1d98…fc13`) was measured on **production** archives of 1.0.4, because no staging archive existed; it was replaced by the staging value of section 10.1 once the preflight showed that it cannot match. A mismatch stops a real delivery before any secret and, under
RELEASE_POLICY.md 7.3, consumes the build number of the promotion. The preflight finds out first, from the tip of `development`, with no credential.

**Why not `ios-ci-validation.yml`.** It runs `flutter build ios`, whose product is a bare `Runner.app`, not an archive. The `dlc_wallet` binary of its run 45958826732 hashes to `65a0b90d…814b1`: not the pin, but also **not
comparable** (a different build action, flavor and version than the production archives), so the difference proves nothing either way. Nothing here treats that hash as equivalent.

**What it is.** `.github/workflows/ios-staging-archive-preflight.yml` (manual only, `development` only, `contents: read`, no secret, no environment, no Apple name, no signing, export or upload command, no binary uploaded):
the environment pins and the nine archive steps are the **text** of the delivery's `build` job, and the extraction, the pin read and the hashed path are those of its `sign` job; `tool/test_ios_staging_preflight.sh`
proves that, comment-free, and exercises the comparison on a synthetic archive. It changes neither the delivery workflow nor the gate, so the blobs bound by the record stay valid. It reads the pin from the record
the way the signing job does and **does not read the status**: it authorizes and consumes nothing.

**Run it (maintainer).** *Actions, "iOS staging archive preflight", Run workflow, branch `development`.* A run on another ref, or on a commit that is not the current tip of `development`, fails at once. Read the job summary
and the artifact `ios-staging-preflight-evidence_<run>-<attempt>` (text: the hash, the proposed pin, the identity and version of the archived app, the toolchain, `SHA256SUMS.txt`).

| Result | Meaning | Next step |
|---|---|---|
| green, `preflight_result=MATCH` | the staging archive's framework equals the proposed pin, on today's runner image | C2 can be approved with this run as its evidence; the delivery's own check stays the final one |
| red, `preflight_result=DIFFERENT` | the real value is in the log, summary and evidence | a reviewed pull request corrects `G2S-STAGING-DLC-WALLET-SHA256` after the CTO decides whether the new value is acceptable (no promotion happened, so no number is consumed) |
| red before the hash | source, toolchain, dependency, configuration, Rust-library or identity failure | fix on `development`, run again |

**Limit.** The same commands on the same pins are strong evidence, not a proof of byte equality: the runner image version of the day, and what Apple's tools do with it, are not under this repository's control (the
production hash was equal in every build on two runner images, an observation). If a preflight and a later delivery ever disagree, the delivery's check decides and the cause is investigated before the next promotion.

### 10.1 The first two preflight runs: the staging value is the proposed pin

| | Run 1 | Run 2 |
|---|---|---|
| Run | [45967581978](https://github.com/CadenaBitcoin/signer_app/actions/runs/45967581978) | [45969558826](https://github.com/CadenaBitcoin/signer_app/actions/runs/45969558826) |
| Source | `development` `2aac65d2b3ee33918f4a636c7442d52e139abdec`, tree `a94a58588209aaa57233a916b0217bdf08aa3bcb`, `1.0.5+10005001` | the same |
| Build | `flutter build ipa --release --no-codesign --flavor staging --dart-define-from-file=config/build/staging.json` | the same |
| Toolchain | runner image `macos15 20261118.0550.1`, macOS 15.8.2, Xcode 26.3 (17C529), SDK 26.2, Flutter 3.35.3, Dart 3.9.2, CocoaPods 1.17.0, Rust library `203dcd7a…949b` | identical |
| `dlc_wallet` SHA-256 | `92231f38c71864833cd6bcdf03c4849c72e6e0a7d66bd59b826dd2798680646d` | identical |
| Archive tar SHA-256 | `d288829b…500b` | `d13a735b…20e5` (the tar differs, the framework does not) |

Both runs reported `DIFFERENT` because the record then still carried the production value; that was the expected, visible failure, not a defect.

**The staging value is therefore the proposed authorization pin** (`G2S-STAGING-DLC-WALLET-SHA256` in the record, with its provenance in the record's section 2.1). It is evidence supporting decision C2, **not the CTO's approval of C2**.

**Why the production value cannot be reused.** The framework embeds Xcode's object-file paths, which carry the flavor and the build action: `ArchiveIntermediates/production/…/Pods.build/Release-production-iphoneos/dlc_wallet.build/…` in the production archive, `…/Release-staging-iphoneos/dlc_wallet.build/…` in a staging build. After normalizing those four path strings the two binaries' string tables are identical (17,169 strings), the bytes are not. Any staging archive therefore differs from any production archive. (A staging `flutter build ios` binary, `65a0b90d…`, was identical across two sources, 1.0.4 and 1.0.5, which also shows that a version change alone does not move the hash.)

**Limitation.** The two runs used one runner image, so equality across images is not shown. A change of Xcode, of the runner image's tools or paths, of the runner work directory, of the Pods build layout or of any compiler-generated path can change the hash. The delivery then stops before Xcode and before any secret, and the promotion's build number is consumed (RELEASE_POLICY.md 7.3). Run the preflight again on the final `development` tip, after the authorization pull request is merged and before the promotion; it must report `MATCH`.

## Appendix A. Harmless test: do secrets added during the wait reach the job?

Run in a **throwaway public repository** that the CTO owns, not in this repository (required reviewers on environments need a public repository on the GitHub Free, Pro and Team plans). No Apple credential,
no real secret, no change to this repository's settings.

1. Create the repository; add `.github/workflows/probe-secret-timing.yml` with the workflow below on its default branch.
2. Create the environment `secret-timing-probe` with **required reviewers** (yourself) and **no secret**.
3. Run the workflow (*Actions, Run workflow*). The job `probe` shows *Waiting*.
4. **While it waits**, add the environment secret `PROBE_DUMMY` with the value `dummy-not-a-credential`.
5. Approve the job. **Expected: `RESULT: present, length 22`.** If it says `absent`, secrets added during the wait do **not** reach the job: use the fallback of section 9.
6. Control, to prove that the test can fail: delete the secret, run again, approve with no secret added. **Expected: `RESULT: absent`** (the job fails).
7. Delete the secret, the environment and the repository.

```yaml
name: Secret timing probe (dummy value only)
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  probe:
    runs-on: ubuntu-latest
    environment: secret-timing-probe
    steps:
      - name: Report whether the dummy secret exists when the job starts (never prints it)
        env:
          PROBE_VALUE: ${{ secrets.PROBE_DUMMY }}
        run: |
          if [ -z "$PROBE_VALUE" ]; then echo "RESULT: absent"; exit 1; fi
          echo "RESULT: present, length ${#PROBE_VALUE}"
```
