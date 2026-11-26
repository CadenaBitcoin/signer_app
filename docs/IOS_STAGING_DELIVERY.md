# iOS staging delivery: automatic signing and TestFlight upload on a merge into `staging`

Issues #54 (parent), #57, #69, #71. Workflow: `.github/workflows/ios-staging-delivery.yml`. Gate: `tool/check_staging_authorization.sh`.
Record: `docs/release-records/ios-staging-authorization.md`. Tests: `tool/test_check_staging_authorization.sh`, `tool/test_ios_staging_delivery.sh`.

**Status: implemented and statically tested; never run.** Nothing here has been executed on a macOS runner or against Apple. It is **not operational** until the
prerequisites of section 5 exist and the CTO's authorization is merged (section 4). The committed record is `WITHDRAWN`, so a merge into `staging` today
makes this workflow fail visibly at its first job and sign nothing.

## 1. What happens on a merge into `staging`

```text
merge PR development -> staging
   |-- android-ci-validation.yml   debug APK, staging flavor           -> GitHub artifact, 14 days            (unchanged)
   |-- ios-ci-validation.yml       unsigned compile validation          -> GitHub artifact, 14 days            (unchanged)
   |-- build-variants.yml          compile validation, evidence         ->                                     (unchanged)
   '-- ios-staging-delivery.yml    (this document)
         authorize   staging gate: record, version, live tip of staging, merge commit, development's content   (no secret)
         build       one unsigned `flutter build ipa --flavor staging`, verified, handed over as a one-day tar  (no secret)
         sign        environment ios-staging-signing: export + sign (cloud-managed certificate), V1..V9, upload (the only secrets)
```

No person starts anything after the merge. There is no `workflow_dispatch`. If the gate refuses, `authorize` fails, so the run is red, `build` and `sign`
are skipped, and no secret is read.

**Android** needs nothing new: `android-ci-validation.yml` already builds the staging APK on every push to `staging` (application ID
`com.cadenabitcoin.mobile.signer.staging`, staging configuration, staging icon, `tool/verify_artifact.sh` checks, debug signing classified, 14-day artifact named with the
version, environment and source commit). `tool/test_ios_staging_delivery.sh` pins this, and this change does not modify that workflow.

## 2. What is reused and what is new

| Reused unchanged | New |
|---|---|
| The production signing steps, **as text**: export and sign (the first step with the key), upload (the second), the upload-tool probe, the key-file checks, the hand-over validation, V1 to V9, the evidence seal | `ios-staging-delivery.yml` (trigger, authorization and source steps, the V6 call, the delivery record) |
| `tool/verify_ipa.py` (already supports `staging`), `ipa_inspect.py`, `validate_handover_archive.py`, `verify_artifact.sh`, `build_manifest.py`, `verify_build_config.sh check-binary` | `tool/check_staging_authorization.sh` and its test |
| The production gate's strict record parser (`check_signing_authorization.sh --print-field`) | `docs/release-records/ios-staging-authorization.md` (WITHDRAWN) |
| The Apple team, the cloud-managed Distribution certificate, `altool` | the GitHub environment `ios-staging-signing` (a GitHub setting) |

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
4. **Default closed**: the committed record is `WITHDRAWN`; a missing, repeated, indented, fenced, commented or malformed line refuses.
5. **Fail closed**: if the remote cannot be read, or `development` has no record, nothing is authorized.

**What is NOT bound, and why that is the residual risk.** The record cannot name the merge commit, so the human review of the pull request (a Maintainers approval; no bypass actors) is what
approves the content. A malicious change to the workflow or the tools is caught only by the blob lines, which the same pull request can also edit: the protection is the review, as for any
file under `.github/`. The environment's branch restriction (section 5) keeps the secret out of reach of every branch but `staging`.

**Unattended execution is a policy decision, recorded as S1 to S4** in the record, for the CTO: the staging application (S1), a **permanent Admin-role Apple team key** in a GitHub environment (S2), the
merge-is-the-authorization model for staging (S3), and the Signet-only rule (S4). S2 is the largest change of risk: production used temporary secrets removed after each run, and the production runs showed
that cloud-managed signing needs the Admin role (Developer and App Manager keys failed) and that a team key cannot be limited to one application. **If S2 is not accepted**, the smallest safe alternative is the
manual path: keep the secrets absent, start the staging workflow by hand after each merge (adding a `workflow_dispatch` is a reviewed change, not provided here), and delete the key after each run, as production does.

## 5. Prerequisites that are not repository changes (what the human must do)

Apple-side evidence read in the repository (all coordinator- or CTO-reported, **not verified through Apple**): the Organization team `D65458CPDP`; a cloud-managed Apple Distribution certificate
(SHA-256 `7ee3f6ce…ef418e`, valid until 2027-07-09, used by the production run 45221165334); the production application "Cadena Bitcoin" (Apple ID `6753348211`) with the internal group "Cadena Internal Testing".
**Nothing in the repository shows that the staging App ID, the staging App Store Connect application, a staging profile or a staging tester group exist; the documents say they do not.**

| # | Where | Action | Needed because |
|---|---|---|---|
| A1 | developer.apple.com, Identifiers | Register the App ID `com.app.cadenabitcoin.staging` (explicit; no push capability needed: the app signs no `aps-environment`). | Cloud signing may register it itself, but that is **unproven**; registering removes the question. |
| A2 | App Store Connect, Apps | Create the application "Cadena Signer STAGING", bundle ID `com.app.cadenabitcoin.staging`, a SKU, primary language. Note its **numeric Apple ID**. | The upload targets an existing record; the App Store Connect API cannot create one. |
| A3 | App Store Connect, TestFlight | Create an internal group for the staging application and add the testers; answer export compliance for the first build. | Nobody can install a build otherwise (assignment is not automated, on purpose). |
| A4 | App Store Connect, Users and Access, Keys | Create the Team API key for staging (**Admin** role, see S2). Keep the `.p8` only as the secret below. | Cloud-managed signing and `altool`. |
| G1 | GitHub, Settings, Environments | Create `ios-staging-signing`. **Deployment branches: selected branches, only `staging`.** No required reviewers (RELEASE_POLICY.md 2.3). | Without the branch restriction any branch could use the secret. |
| G2 | the environment's secrets | `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`. **Add them only when the record is ready to be AUTHORIZED**, and delete them to stop deliveries at once. | The three secrets of the two key-holding steps. |
| G3 | GitHub, Issue #54 | Write the CTO's decision S1 to S4 and the authorization (the comment URL goes into the record). | `G2S-STAGING-AUTHORIZATION`. |

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

`pubspec.yaml` is the only source; no workflow writes or overrides it. The authorization binds `X.Y.Z+N`. See the proposal in the pull request description / report: next staging **1.0.5+1000036**.

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

## 9. Not proven until the first real run

The new workflow's secret-bearing steps are the production steps' text, but: the staging archive and `flutter build ipa --flavor staging` have only been compiled as an unsigned `.app` by CI before;
whether Apple's cloud signing creates the staging App ID and profile on its own (A1 removes the doubt); the framework hash of a staging archive (the record's proposal is the production value; a mismatch stops the run
before any secret and prints the real value); and the Podfile.lock regeneration of section 6. Expect one or two corrective pull requests on the first real run; each stops safely.
