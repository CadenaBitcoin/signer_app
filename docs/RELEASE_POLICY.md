# Release policy

> **Status: draft (parent issue #54).** The architecture below was approved by the
> project owners on 2026-10-12; the document itself still goes through the normal
> pull-request review.
>
> **This document states policy, not implementation status.** Implementation status is maintained in the
> [as-built overview (STA-01)](70-state/as-built.adoc); where a statement below says that something does
> not exist, it was written before the first staging delivery (2026-11-27) and the as-built overview governs.
> The decisions and requirements of the framework are consolidated in the adopted
> [release-framework specification](release-process/index.adoc). *Decided* marks requirements fixed by the project
> owners on 2026-10-12; *Proposed* marks mechanisms that are not decided; open points are in
> [section 11](#11-open-decisions).
>
> **Amended by documentation step P1 (2026-11-28, reconciliation items REC-01, REC-03, REC-06, REC-07).**
> The authorization wording of section 2.3 and open decision 9, the status tables of sections 2.3 and 10, and the
> version and identifier rules of sections 3.1 and 7.3 carry marked notes that separate the current mechanism
> from the approved target. The consolidation of this document into the new hierarchy is step P8.

> **Revised for CTO review (Issue #54, CTO decisions of 2026-11-17, V1 to V6).** Principles 3 and 9, section 2.3 (authorization
> architecture), section 2.4 (failure, retry and recovery) and 7.3 (version advancement) replace the earlier rules that production
> signing and delivery need a second, independent human and that publication is a separate authorization. **The authorized merge into
> a protected release branch is the single human authorization boundary.** The policy states the intended architecture; what is
> implemented and what is not is stated in section 2.3 ("Verified implementation state") and section 10.

Branch roles, merge authority and issue handling stay in
[GOVERNANCE.md](../GOVERNANCE.md) and are not repeated. Signing and credentials:
[RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md). Order of work:
[RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md).

## 1. Principles (Decided)

1. **One product, one version.** Cadena Signer has one logical product version,
   `MAJOR.MINOR.PATCH` (`X.Y.Z`), carried by Android and iOS alike for the same
   approved release. `pubspec.yaml` is the primary source. Product version,
   platform build number and release identifier are three different things
   ([section 7](#7-version-rules)).
2. **Staging and production are different applications.** Different application
   IDs, different backends, different Bitcoin networks, different signing and
   deployment contexts, independently installable side by side on one device
   ([section 5](#5-application-identity)).
3. **Two protected release branches, one pipeline each; the target branch is the
   authorization.** An authorized merge into `staging` is authorization to execute the
   complete staging pipeline (two artifacts); an authorized merge into `production`
   is authorization to execute the complete production pipeline (three artifacts).
   There is no further manual authorization after the merge
   ([section 2.3](#23-authorization-architecture-decided-by-the-cto-2026-11-17)).
4. **Explicit, fail-closed configuration.** Backend, network and identity are
   chosen explicitly and checked. A missing, inconsistent or unsuitable
   configuration fails the build; staging never falls back to production
   ([section 6](#6-build-configuration)).
5. **Cadena-controlled signing.** Every one of the five artifacts is signed under
   Cadena-controlled authority, through protected GitHub environments, never with
   credentials in the repository, and never dependent on one person's machine
   ([RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md)).
6. **Independent builds are not official.** Anyone may compile, modify and sign
   the open-source application with their own keys. Cadena guarantees no update
   compatibility or migration between independent builds and official releases,
   and independent builds never receive Cadena credentials or protected
   environments.
7. **Staging is experimental.** No public support, stability, compatibility or
   upgrade guarantee; internal testers only; never presented as production.
8. **Traceability.** A signed artifact is attributable to an approved Git
   revision and carries the release record of [section 9](#9-release-record).
9. **The authorized merge is the single human authorization boundary.** The release
   authority is exercised by one act: merging a reviewed pull request into a protected
   release branch. The established GitHub workflow is `sziller` (development and pull-request
   preparation) and `CadenaWizard` (CTO-controlled review and merge authorization). **Both
   accounts belong to the same person.** GitHub does not let an author approve their own pull
   request, which is why there are two accounts. This policy neither requires nor pretends that
   they are independent human reviewers, and no document, release record, workflow or status
   check may describe them as such. What replaces a second human is **automated and
   mandatory** in the intended architecture: protected branches, signed commits, required checks,
   verification that stops delivery on failure, strict provenance and auditable records. Which of
   these is active today is stated in
   [section 2.3](#23-authorization-architecture-decided-by-the-cto-2026-11-17) ("Verified implementation state").
   *(Amended by P1: see the amendment in section 2.3. The authorization is the written, version-bound decision carried by the reviewed promotion; the environment approval only confirms the deployment.)*

## 2. Release branches and triggers

```text
issue branch → development → staging → production
                              │            │
                    merge triggers   merge triggers
                    staging pipeline production pipeline
```

| | `staging` | `production` |
|---|---|---|
| Exists | Yes, protected | **No** (verified 2026-10-12) |
| Receives | Pull request from `development` | Pull request from `staging` |
| Merge triggers | The complete staging pipeline (2.3): version advance, build, verify, sign, deliver, record; 2 artifacts | The complete production pipeline (2.3): build, verify, sign, deliver, record; 3 artifacts |
| Build configuration | Staging (backend, Signet) | Production (backend, mainnet) |
| Distribution | iOS: restricted TestFlight (mandatory). Android: internal only, never public (section 8) | The production pipeline's configured non-public upload, authorized by the merge; no automatic App Review submission or public publication (2.3); Apple's and Google's review and acceptance still apply |
| Protected environments | Staging signing/deployment context | Production signing/deployment context |

### 2.1 Creating `production` (Decided: required; branch created, Issue #68)

*Status, not a decision:* the branch exists. It was created at the adopted initial
baseline `7b63c97` and is protected by rulesets. Requirements 3 and 4 below are not yet
met; the only merge into it so far was a compile-only infrastructure acceptance under a
one-time exception approved by the owner (Issue #68).

`production` is not created by this document or without approval. It requires:

1. The authoritative currently released source commit and artifact lineage are
   established (`GOVERNANCE.md`). The branch starts from a commit with that
   provenance and the production configuration, not from a guess.
2. Protection at least as strong as `staging`, set up by the Organization
   Owners/Maintainers before the first merge:
   - only the `CadenaBitcoin/Maintainers` team can update it; no administrator
     bypass; no force-push; no deletion;
   - pull request required; at least one Maintainers approval; stale approvals
     dismissed; conversations resolved;
   - source restricted to pull requests from `staging` (adjacent-branch
     promotion only);
   - required status checks once available (version validation, configuration
     validation, CI validation);
   - Proposed: creation of release tags `v*` restricted to the release workflow
     identity. One approval from `CadenaBitcoin/Maintainers` is the authorization;
     a second approval is not required and would not be independent (principle 9).
3. Protected environments for the production signing context exist and accept
   deployments from `production` only
   ([RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md)).
4. The production pipeline is merged and reviewed **before** the first merge into
   `production`, so that the branch's first update already builds under control.

### 2.2 Promotion procedure

1. Work reaches `development` by pull request (`Implements #N`).
2. `development → staging` by pull request. The merge executes the complete staging
   pipeline (2.3), including delivery to the configured internal testing
   destinations. Testers verify the artifacts.
3. `staging → production` by pull request containing only commits already on
   `staging`. The merge executes the complete production pipeline (2.3) from the
   same source with the production configuration. The environment differences are the
   configuration and identity inputs, not diverging source
   (`GOVERNANCE.md` section 3).
4. The merge authorizes the production pipeline's configured delivery operations (upload to
   non-public destinations); no separate approval follows it (2.3). Automatic App Review
   submission and public publication are outside that scope; the configuration changes only by a
   reviewed pull request.

### 2.3 Authorization architecture (Decided by the CTO, 2026-11-17)

**The target branch is the authorization.** An authorized merge into `staging` or `production`
is authorization to execute that branch's complete pipeline. After the merge there is **no
further release authorization**: no manual release-intent flag, no change classification and **no
file-path filter**. Every merge, including a documentation-only one, runs its branch's pipeline.
(`development` is not a release branch: a merge into it builds nothing.)

> **Amendment (P1, REC-01 and REC-08), recording what the project established after this decision.**
> The release authorization is the CTO's written, version-bound decision, carried by the reviewed
> promotion and, for iOS staging today, by the reviewed authorization record that the delivery gate
> reads. The approval of the protected signing environment (required reviewers) **confirms the
> deployment** of an already authorized release; it creates no authorization and is not an independent
> review (`EXC-08`). Temporary Apple credentials are provisioned and verified **before** the promotion
> merge and removed after the delivery (`DEC-28`); their possession authorizes nothing. The sentences of
> this section that say no approval prompt or reviewer follows the merge are superseded by this
> amendment. The lists below of what every merge must do are the earlier design; the approved build-trigger matrix is `DEC-36`, and the Android staging APK is no longer produced by the staging promotion under the approved target (see 3.1). See `DEC-05`, `DEC-08`, `DEC-20` and `DEC-28` in the specification.

**Every successful merge into `staging`** must:

1. carry the build-version advancement, validated **before** the merge and never written after it (7.3);
2. trigger the staging CI/CD pipeline;
3. build the Android staging APK and the iOS staging (TestFlight) artifact;
4. retain the built artifacts and verify them;
5. sign them and verify the signed artifacts again;
6. deliver them to their configured internal testing destinations;
7. record the deployment evidence (section 9).

**Every successful merge into `production`** must:

1. trigger the production CI/CD pipeline;
2. build the production Android APK, the production Android AAB and the iOS App Store distribution IPA;
3. retain the built artifacts and verify them;
4. sign them and verify the signed artifacts again;
5. deliver the applicable artifacts to the configured production delivery destinations (below);
6. record the deployment evidence (section 9).

**Scope of the automated production delivery (CTO decision, 2026-11-17).** The configured delivery
is the upload of the verified, signed artifacts to their configured **non-public** destinations
(for example App Store Connect for the IPA and the Play Console for the AAB). **Automatic
submission to App Review and any public publication or release are outside the configured
automated scope** and may be incorporated later only by an explicit architectural extension of
this policy, through a reviewed pull request. Leaving them out is not an approval step and adds
none: nothing human follows the merge. Apple's and Google's own review and acceptance remain the
stores' requirements, and a store's refusal is a failed delivery, not a question of
authorization. The exact destinations are decided with the implementation (open decision 16).

Versioning follows section 7 and [RELEASE_VERSIONING.md](RELEASE_VERSIONING.md) and keeps both
platforms compatible.

**The single human boundary.** The merge, by the CTO-controlled account after the required
review, is the one human authorization (principle 9). Automated security and integrity checks
are mandatory, and **a verification failure stops delivery**: nothing further is delivered and
the stop point is recorded. What happens next depends on the kind of failure (2.4).

**Technical invariants** (preserved; each is the replacement for what a second human would
have done):

| Invariant | Where it is specified |
|---|---|
| Protected release branches: pull request, approval from `CadenaBitcoin/Maintainers`, no force push, no deletion, no bypass actor | `GOVERNANCE.md` section 6, [RELEASE_TRIGGERS.md](RELEASE_TRIGGERS.md) |
| Signed commits and required CI checks on the release branches, including the version check | Implementation requirement, not active (below) |
| Verified, retained build artifacts, encrypted to public keys, never public | [RETAINED_ARTIFACTS.md](RETAINED_ARTIFACTS.md), section 3.2 |
| **No recompilation during signing**: signing acts on the verified retained artifact (Android) or the exported archive (iOS) | [RETAINED_ARTIFACTS.md](RETAINED_ARTIFACTS.md), [IOS_RELEASE.md](IOS_RELEASE.md) sections 8, 9 (V8) |
| Isolated signing credentials: protected environments deployable from their one branch, secrets at environment level only, no access from forks or pull requests, build and sign in separate jobs | [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) |
| Strict artifact provenance: source commit, build manifest, artifact SHA-256, configuration hash, toolchain | [RELEASE_VERSIONING.md](RELEASE_VERSIONING.md), section 9 |
| Automated post-signing verification that stops delivery on failure | `tool/verify_ipa.py`, `tool/verify_android_release.py`, `tool/verify_artifact.sh`, `tool/build_manifest.py` |
| Auditable delivery records, including every retry attempt | Sections 2.4 and 9 |
| Failure-safe deployment: fail closed, no partial delivery presented as success | This section and 2.4 |

**Signing credential custody (CTO decision, 2026-11-17).** Secure custody, backup and recovery of
the signing credentials Cadena controls are preserved, for **business continuity and recovery
from credential loss**. Custodians are **not release authorizers**, and no second-person approval
is required for routine signing or deployment. Three kinds of credential are kept apart
([RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) section 7): (1) credentials
Cadena itself controls (Android upload and app-signing keys, an App Store Connect API key);
(2) Apple **cloud-managed** signing certificates, whose private key Apple holds and which Cadena
cannot back up; (3) working copies of credentials stored in protected CI/CD environments. This
policy creates and transfers none of them.

> **Superseded snapshot (P1, REC-03).** The table below records the state of 2026-11-17 and is not maintained. Since then the first staging delivery took place (2026-11-27) and a protected signing environment with temporary credentials exists for iOS staging. The current state is in the [as-built overview (STA-01)](70-state/as-built.adoc).

**Verified implementation state (checked 2026-11-17, GitHub API and repository).** The policy above
is the intended architecture. These are **not** active, and nothing in this amendment activates
them:

| Control | State today |
|---|---|
| Protected release branches | **Active** on `development`, `staging` and `production`: pull request with a `Maintainers` review required, deletion and force push blocked, bypass lists empty in the API response |
| Mandatory signed-commit enforcement | **Not active**: no `required_signatures` rule on any branch; signed commits are a development practice |
| Required CI status checks | **Not active**: no `required_status_checks` rule on any branch |
| Version-advancement check (7.3) | **Not implemented** |
| Artifact-retention recipients | **Not configured**: `config/release/artifact_recipients.txt` names no key |
| Protected signing environments | **None**: the repository has no GitHub environment |
| Automated signing credentials | **None**: no workflow uses a secret or an environment; the Android upload key is held by the CFO and used locally |
| Automated signing and automated store delivery | **Not implemented** |
| Retry handling (2.4) | **Not implemented** |
| What a release-branch merge does today | Compile-only `build-variants` plus the validation workflows: no signing, no upload |

These are the implementation requirements of issue #54 ([RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md)).
A pipeline step is switched on only when what it relies on exists, and this amendment activates
no incomplete signing or upload workflow. Until then a merge authorizes only what the workflows
actually do.

**Manual operations before automation exist.** Where a delivery step is not yet automated, a
person performs it by hand. That is an **operational exception to the future automation**, not
an exception to this authorization policy. Because no pipeline run exists to carry the merge's
authorization, such an operation needs the CTO's explicit, written authorization of that specific
operation, made through the same boundary. It does not need, and no document may require, a
second human. The first is iOS 1.0.4 ([IOS_RELEASE.md](IOS_RELEASE.md)). A manual operation may be carried out by a manually started workflow in a
protected environment (iOS 1.0.4, G2S: [IOS_HOSTED_SIGNING.md](IOS_HOSTED_SIGNING.md)); it still needs the CTO's written authorization of that specific operation, it is
not a merge-authorized pipeline (a merge authorizes only what the workflows actually do), and the environment's reviewer approval confirms a deployment, never
replaces that authorization.

### 2.4 Failure, retry and recovery (architectural requirement; not implemented)

Two kinds of failure are kept apart.

**Application or artifact failure.** A defective application, a failed verification (including a
failed post-signing verification) or an invalid artifact is corrected through the approved
source-control workflow: a fix on `development`, then the normal pull requests. The corrected
release receives a new version and build number (7.3); the failed number stays consumed.

**Infrastructure or delivery failure.** A transient failure (a lost runner, a network or store
outage, an interrupted upload, a rate limit) after a verified artifact exists must **not**
require a recompilation or a new version. The eventual pipeline retries, in a controlled way,
**the same previously retained and verified artifact**. It must:

1. act on the retained artifact identified by its SHA-256 and manifest, and verify it again
   before every attempt;
2. be idempotent: check the destination before each upload and never upload a second copy, or a
   different artifact under the same version and build number;
3. repeat only the configured non-public delivery operations, so a retry can never publish;
4. preserve provenance: the manifest and digest are those of the first attempt;
5. record **every** attempt (attempt number, time, operation, destination, artifact digest, result,
   reason);
6. be bounded: after the configured limit it stops, records the failure and leaves the next step
   to a person.

A failure **before** a verified artifact is retained (the build infrastructure itself) is repaired
by running the same commit again: a new CI execution of the same commit and the same version,
as [RELEASE_VERSIONING.md](RELEASE_VERSIONING.md) already says. An artifact that then fails its
verification is an artifact failure, above. Run attempts are already identified as
`<run id>.<attempt>`.

## 3. The five signed artifacts

Target state (**Decided**). What exists today is stated in the [as-built overview](70-state/as-built.adoc).

### 3.1 `staging` merge: two artifacts

| | Android staging | iOS staging |
|---|---|---|
| Product name | Cadena Signer STAGING | Cadena Signer STAGING |
| Product version | `X.Y.Z` | `X.Y.Z` |
| Release identifier | `vX.Y.Z-rc.N` | `vX.Y.Z-rc.N` |
| Embedded version | `versionName` = `X.Y.Z-rc.N` | `CFBundleShortVersionString` = `X.Y.Z` (numeric); identifier shown inside the app and recorded in metadata |
| Build number | `versionCode` | `CFBundleVersion` |
| Backend | DLC Plaza **staging** | DLC Plaza **staging** |
| Network | Bitcoin **Signet**, Signet XPUB/address validation | Bitcoin **Signet**, Signet XPUB/address validation |
| Application identity | Separate staging application ID | Separate staging bundle ID **and** separate App Store Connect record |
| Signing | Cadena-authorized, staging context | Cadena-authorized, staging context |
| Artifact | Signed APK | Signed iOS distribution build |
| Distribution | Internal testing only; **never publicly distributed** (section 8.2) | **Restricted TestFlight only; mandatory** (section 8.1) |

> **Current mechanism versus approved target (REC-06).** The identifier `vX.Y.Z-rc.N` and the signed Android staging APK above are the earlier design. The independent release-candidate counter is ended (`DEC-29`); a build is identified by application version, numerical build number, source commit and durable build evidence. The approved target is that Magic, a manually started Android build, is the sole routine mechanism that allocates build numbers and produces the staging APK, and that a staging promotion delivers iOS only (`DEC-32`, `DEC-33`, `DEC-36`, `DEC-39`). *None of this is implemented.* Today a staging push builds both a debug-signed Android validation APK and, when authorized, delivers iOS, and the validation tools still check `-rc.N`. The signing identity of the Android staging APK is open (`UNR-01`).

### 3.2 `production` merge: three artifacts

| | Android APK | Android AAB | iOS |
|---|---|---|---|
| Product name | Cadena Signer | Cadena Signer | Cadena Signer |
| Product version | `X.Y.Z` | `X.Y.Z` (same) | `X.Y.Z` |
| Release identifier | `vX.Y.Z` | `vX.Y.Z` | `vX.Y.Z` |
| Staging identifier | None | None | None |
| Embedded version | `versionName` = `X.Y.Z` | identical `versionName` | `CFBundleShortVersionString` = `X.Y.Z` |
| Build number | `versionCode` | **identical** `versionCode` | `CFBundleVersion` (may differ from Android) |
| Backend | Production | Production | Production |
| Network | Bitcoin **mainnet**, mainnet XPUB/address validation | same | same |
| Application identity | Production application ID | same | Production bundle ID |
| Signing | Cadena-authorized | Cadena-authorized **upload** signing; compatible official app-signing identity | Cadena-authorized |
| Artifact | Signed APK | AAB for Google Play | Signed iOS distribution build suitable for App Store submission |
| Distribution | Cadena's website | Google Play | App Store (via App Store Connect) |
| Update family | One family with the AAB | One family with the APK | Apple's |

Rules common to all five:

- **A pipeline output is a signed build artifact.** It goes only to the delivery
  operations the branch's pipeline is configured for, authorized by the merge
  (section 2.3). The *Distribution* row above names where each artifact eventually
  goes; the automated delivery ends at non-public upload, and public publication
  (the website, a Play production release, an App Store release) and submission to
  App Review are outside it until an explicit architectural extension (2.3). A
  manual upload, before the pipeline can do it, needs the CTO's written
  authorization of that operation (2.3).
- The APK and the AAB of one production release share `versionName`,
  `versionCode`, application ID and update family. The official APK is the
  universal APK (`--split-per-abi` changes the `versionCode`).
- The artifact name carries identifier, platform, build number and short commit
  SHA, and its release record is attached (section 9).
- **No signed artifact is stored where the public can retrieve it.** The
  repository is public, and the artifacts and logs of its workflow runs are
  readable by any GitHub account (the CI documents already note this). A signed
  artifact is therefore never left as an ordinary Actions artifact, a GitHub
  Release or a pull request attachment, whatever its delivery configuration
  (section 8.2). Digests and the release record, which contain no binary, may be
  public. An artifact kept **encrypted to the custodians' public keys**
  ([RETAINED_ARTIFACTS.md](RETAINED_ARTIFACTS.md), Stage 2) is ciphertext and is not retrievable
  in this sense; a readable artifact is still never uploaded.
- Successful compilation is not signing and signing is not distribution. The CI
  validation builds (section 4) are none of the five.

## 4. Kinds of build

| | CI validation build | Staging pipeline build | Production pipeline build | Independent build |
|---|---|---|---|---|
| Exists today | **Yes** ([ANDROID_CI.md](ANDROID_CI.md), [IOS_CI.md](IOS_CI.md)) | No | No | n/a |
| Trigger | Push to `staging`, or manual | Merge into `staging` | Merge into `production` | The builder |
| Output | Android: **debug-signed** APK. iOS: **unsigned** `Runner.app` | 2 signed artifacts | 3 signed artifacts | Builder's choice |
| Signing | Ephemeral debug key / none | Cadena, staging context | Cadena, production context | Builder's own keys |
| Distributable | **Never** | Restricted only: iOS via TestFlight (mandatory), Android internal and non-public | Through the pipeline's configured delivery, authorized by the merge (2.3) | Builder's responsibility |
| Official | No | Candidate | Yes, once published | No |

- Validation builds stay as they are until a deliberate, approved transition
  ([RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md) section 3).
  They are not promoted, renamed or signed into release artifacts.
- The Android `release` build type is **debug-signed unless `CADENA_SIGNING=release`** selects a
  keystore supplied from outside the repository ([ANDROID_RELEASE.md](ANDROID_RELEASE.md), Issue #72).
  A build made without it (all CI builds) is not official and must not be distributed. An official
  Android build is one made by the local release procedure with the Cadena upload key and
  verified by `tool/verify_android_release.py`; no CI pipeline signs yet.
- A build is official only if the pipeline of its branch produced it, from an
  approved commit, signed in the matching context, with a complete release
  record. Anything else is not official, whatever it is called.

## 5. Application identity

**Decided:** staging and production are different applications and must install
side by side on one device. **Proposed:** the identifiers below. Nothing here is
registered with Apple or configured with Google, and no such registration may be
assumed.

| | Production (exists) | Staging (proposed, not registered) |
|---|---|---|
| Android `applicationId` | `com.cadenabitcoin.mobile.signer` (the package published on Google Play, Issue #72) | `com.cadenabitcoin.mobile.signer.staging` |
| iOS bundle ID | `com.app.cadenabitcoin` | `com.app.cadenabitcoin.staging` |
| App Store Connect | Production app record | **Own, separate** app record |
| Provisioning (iOS) | Production App Store profile | **Own** profile for the staging bundle ID |
| Android signing | Production context | Staging context |
| Display name | "Cadena Bitcoin" today; production name to be confirmed | "Cadena Signer STAGING" |

Apple distribution certificates may be shared at the team level where
appropriate; application identities, App Store Connect records and provisioning
profiles stay distinct. Whether the certificate is actually shared is a
separation trade-off ([RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md)).

### Where the identity is wired today (investigated, not changed)

| Place | Today | Consequence |
|---|---|---|
| Android `applicationId` and `namespace` | `applicationId` `com.cadenabitcoin.mobile.signer` (flavor suffix `.staging`); `namespace` `com.app.cadenabitcoin` (`build.gradle.kts`, Issue #72) | Only `applicationId` varies; `namespace`/`MainActivity` package stay, so no source rename is needed |
| Android label | Fixed `"Cadena Bitcoin"` in the manifest | Needs a per-variant label |
| iOS bundle ID | `PRODUCT_BUNDLE_IDENTIFIER` in the 3 app-target configurations (Debug, Release, Profile) | Needs per-environment values |
| iOS name | Fixed `CFBundleDisplayName` `"Cadena Bitcoin"` | Needs a per-environment value |
| iOS schemes/configurations | One scheme (`Runner`), configurations Debug/Release/Profile | Flutter flavors need additional schemes and configurations |
| iOS signing | `DEVELOPMENT_TEAM` committed, automatic signing | CI needs manual signing with imported profiles; automatic signing is not usable on a runner |
| iOS entitlements | None in the project | No capability needs re-registering today |
| `BGTaskSchedulerPermittedIdentifiers` | Lists `com.app.cadenabitcoin.auto_signing_task`; `AppDelegate` registers `auto_signing_task` | A literal production bundle ID is embedded; the two names look inconsistent. **Unverified at runtime; not changed here.** Must be understood before the staging identity is created |
| Firebase / Google services / URL schemes | None found | Nothing to re-register |
| Third-party SDKs (Sumsub, and the Fingerprint Pro pod it pulls in on iOS) and the DLC Plaza backend | Unknown whether any key, allowlist or rule is bound to an application ID | Must be checked with the backend/providers before a new ID is used |

**Proposed mechanism:** Flutter flavors named `staging` and `production` on both
platforms (Android `productFlavors`; iOS schemes and configurations driven by
`xcconfig`). The flavor selects identity and name; it must agree with the build
configuration ([section 6](#6-build-configuration)), otherwise the build fails.
This edits Gradle and Xcode project files, which is build configuration and not
application logic, but it is the largest change to the native projects and
changes the build commands of both CI workflows (implementation plan
section 3).

## 6. Build configuration

**Decided:** environment selection is explicit and deterministic.

| | Staging | Production |
|---|---|---|
| Backend | `https://staging.purabitcoin.com/app` | `https://cadenabitcoin.com/app` |
| Network | Signet (`NETWORK_ENVIRONMENT = "signet"`, `USE_TESTNET = true`) | Mainnet (`"bitcoin"`, `false`) |
| XPUB/address handling | Signet (`vpub`, `tb1…`) | Mainnet (`bc1…`) |
| Flavor / application identity | `staging` | `production` |
| Release identifier | Present (`vX.Y.Z-rc.N`) | **Absent** |

Rules:

- The configuration is a complete set of inputs supplied at build time
  (**Proposed**: files under `config/build/`, passed with
  `--dart-define-from-file`, as the unfinished Issue #57 B1 does).
- **There is no default.** If the configuration is absent, incomplete,
  self-contradictory, or does not match the flavor or the target branch, the build
  fails (`staging` branch requires the staging configuration; `production`
  requires the production configuration). Staging never falls back to production,
  and production never falls back to staging.
- The Git branch name never selects the environment inside the app; the pipeline
  of a branch selects the configuration, and verifies that it is the one that
  branch requires.
- The checks must fail in release/AOT builds as well as debug builds (B1's
  constant-assertion technique does).

### Network-specific XPUB and address validation (finding)

The requirement that each environment validate XPUBs and addresses for its own
network is **not met by existing code**, and is in sensitive territory
(`CLAUDE.md` section 6):

- Network-dependent behavior exists only in wallet derivation: the key version
  bytes (`vpub` for Signet), the derivation path and the address prefix
  (`tb`/`bc`) follow `USE_TESTNET`, and the native library receives
  `NETWORK_ENVIRONMENT`.
- `isValidBitcoinAddress` accepts only mainnet forms (`bc1…`, legacy `1…`/`3…`)
  and **has no callers**, so Signet addresses are not validated anywhere in app
  code.
- XPUB comparison with the server (`compareXpubWithServer`) is a plain string
  equality of the stored and server XPUB; no prefix/network check was found in the
  app. The backend's service-version response lists an XPUB-validation endpoint
  (`GET_XPUB_VALIDATION`); what the backend enforces was not investigated.
- `generateP2WPKHAddress` defaults to `isTestnet = true`, an implicit default.

Adding explicit, environment-driven validation is a separate issue that needs an
investigation report and approval before any code changes.

## 7. Version rules

### 7.1 Three different identifiers (Decided)

| | Product version | Build number | Release identifier |
|---|---|---|---|
| What it is | User-facing version of the product | Counter that makes each uploaded build unique | Name of a staging candidate or a production release |
| Format | `X.Y.Z` | Positive integer | Staging `vX.Y.Z-rc.N`; production `vX.Y.Z` |
| Example | `1.0.4` | `1000035` | `v1.0.4-rc.1`, `v1.0.4` |
| Source | `pubspec.yaml` | `pubspec.yaml` today | Staging: the staging configuration (Proposed); production: the product version |
| In the apps | Always, numeric | Always | Staging: yes, see 7.2. Production: **never** |
| Same on Android and iOS | **Yes, always** | **May differ where necessary** | Yes |

`pubspec.yaml` always holds the numeric `X.Y.Z+BUILD`: today
`1.0.3+1000034`. It never contains `-rc.N`.

### 7.2 What each platform embeds

| | Android | iOS |
|---|---|---|
| Staging | `versionName` = `X.Y.Z-rc.N`, `versionCode` = build | `CFBundleShortVersionString` = `X.Y.Z`, `CFBundleVersion` = build; **identifier visible in the app** |
| Production | `versionName` = `X.Y.Z`, `versionCode` = build | `CFBundleShortVersionString` = `X.Y.Z`, `CFBundleVersion` = build |

- Apple's version fields stay numeric. Flutter silently rewrites invalid values
  (iOS: every character that is not a digit or dot is deleted, so
  `1.0.3-rc.1` would become `1.0.3.1`), so no suffix may ever be passed to iOS.
- **Staging identifier on iOS (Decided):** the build must visibly identify itself
  as staging and show the **full** identifier (`v1.0.4-rc.1`) inside the app, and
  record it in release metadata. It is never silently dropped. **Proposed:** an
  application-level display fed by the staging configuration (shown before login
  and in the about/settings area), the display name "Cadena Signer STAGING", and
  a custom `Info.plist` entry carrying the identifier so a built `Runner.app` can
  be verified. Showing it is a small UI change (separate issue; not wallet, auth or
  signing code).
- Android may do the same (visible display) in addition to `versionName`.
- Production builds show no staging identifier anywhere.

### 7.3 Build numbers

- Each artifact uploaded to a store or testing service needs a build number never
  used before **on that platform** (Google Play and App Store Connect reject
  repeats).
- Android and iOS build numbers **may differ where necessary** (for example an iOS
  upload is rejected and repeated while Android is unaffected). The policy permits
  it permanently. Today both derive from `pubspec.yaml`, **no platform-specific
  override exists, and none is introduced by this policy**. If one is ever
  needed, it comes from an approved change that keeps the product version
  identical, keeps each platform's number strictly increasing, records both
  numbers, and updates the validation deliberately instead of bypassing it.
- The AAB and the APK of one production release share `versionName` and
  `versionCode`.
- **Version advancement (Decided, CTO 2026-11-17, option A).** Every successful merge into
  `staging` carries a build-number advance, **whatever the merge contains; a documentation-only
  merge is not exempt**. The advance is a **reviewed edit of `pubspec.yaml` that is part of the
  pull request** (practically, a reviewed commit on `development` that the promotion carries:
  `development` builds nothing, so numbers there are not consumed). The `-rc.N` identifier
  advances with it (7.4).
- **Validated before the merge, never rewritten after it.** A **required status check**
  (implementation requirement, not active; 2.3) runs on every pull request into a release
  branch, with no path filter, and fails the pull request unless the version is correct: the
  existing rules of 7.5 hold; the build number is **strictly above every number already
  consumed** (the highest at any commit reachable from the target branch and in the
  published-versions ledger); it is within Android's range; it is the same on both platforms
  (below); the identifier agrees with 7.4. No workflow writes, overrides or derives the version
  after the merge (`tool/verify_version.sh` and the existing tests already forbid it).
- **Consumed numbers are never reused; skipped numbers are acceptable.** A number is consumed
  when a commit carrying it reaches a release branch or a store has seen it. A failed or
  withdrawn candidate keeps its number. A retry of a delivery of the same artifact (2.4) is the
  same build, not a reuse.
- **Traceable.** The version is in the approved Git revision, in the artifact manifest and in
  the built artifact, and the existing checks compare the three
  ([RELEASE_VERSIONING.md](RELEASE_VERSIONING.md)).
- **Production is consistent with the established rules.** A merge into `production` promotes
  the `staging` source (equal tree, [RELEASE_VERSIONING.md](RELEASE_VERSIONING.md)), so it
  carries the version already validated on `staging`; nothing is added in the promotion. The
  production gate (`tool/build_manifest.py gate --channel production`) still requires the number
  to be above the published floor of the platform and the Android ID to be the published one.
  Staging and production share one number sequence because they share one source.
- **Hotfixes** use the same path: a pull request with an advance. Gaps are acceptable, so no
  waiting or renumbering is needed.
- Android and iOS numbers are the same today; a platform-specific number remains permitted by
  this policy but is not built (above).

> **Current mechanism versus approved target (REC-07).** The advancement procedure above is the current mechanism: a reviewed edit of `pubspec.yaml`, with consumption controlled by people, and the required check of this section is not implemented. The approved target replaces it with one shared allocation sequence and the encoding `XX.YY.ZZ.RRR`, allocated and recorded persistently by Magic before compilation, with inherited version information for later deliveries (`DEC-30` to `DEC-32`, `DEC-37`, `DEC-38`). Preserved requirements: the numerical encoding is validated, a consumed number is never reused, historical consumption is accounted for before the first allocation, and an unauthorized version override is rejected (`VER-08` to `VER-15`, `BRN-03`). The storage mechanism is under investigation (`FQ-01`, `FQ-02`). The alternative per-platform numbers of the first bullet are not part of the approved target (`DEC-31`).

### 7.4 Identifiers and tags

- Staging merge → `vX.Y.Z-rc.N`, `N` ≥ 1, counting candidates of that version.
  Production merge → `vX.Y.Z`. The numeric part must equal the product version.
- An identifier names exactly one Git commit and is never reused or moved. A
  rebuild needing a new commit or a new build number is the next `-rc.N`.
- The identifier is the signed annotated Git tag name, created under controlled
  authority (decision 5). No tag exists today.
- **Proposed source of `N` (it advances in the pull request, like the build number, 7.3):** a `RELEASE_IDENTIFIER` entry in the staging
  configuration, changed by the promotion pull request, so the identifier is part
  of the approved revision and does not depend on counting existing tags. The
  pipeline fails if the tag already exists.

### 7.5 Validation

Existing: `tool/verify_version.sh [--channel staging|production] [--release-id
vX.Y.Z[-rc.N]] [repo-root]` (read-only; no Flutter, Gradle or Xcode needed). It
fails unless:

- `pubspec.yaml` has exactly one `version:` of the form `X.Y.Z+BUILD`, build within
  the Android range, and no platform would rewrite it;
- Android `versionCode`/`versionName` come only from `flutter.versionCode` /
  `flutter.versionName` (no flavors, suffixes, ABI splits or property overrides) and
  iOS uses only `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`;
- no workflow passes `--build-name`/`--build-number`;
- with `--release-id`: well-formed, numeric part equals the product version; with
  `--channel`: staging requires `-rc.N`, production forbids it.

These checks describe the **current** wiring. Each later change adds its checks
**in the same pull request**: when flavors, application IDs and the staging
`versionName` are introduced the checker is updated to expect exactly that wiring
(and no other); when signed workflows are introduced they are the only ones
allowed to pass `--build-name`. Designed next steps:

1. Per-flavor identity assertions in source (application ID, bundle ID, display
   name, label).
2. Artifact mode: read `applicationId`, `versionName`, `versionCode` from the
   built APK/AAB (`aapt2`/`bundletool`) and the bundle ID, version fields and
   identifier from the built `Runner.app`/IPA, and compare them with the matrix.
3. Configuration/branch match (`staging` branch ⇒ staging configuration and
   identifier present; `production` ⇒ production configuration and identifier
   absent).

Out of scope for the checker: `ios/Flutter/AppFrameworkInfo.plist` (embedded
`App.framework`), the `RunnerTests` target and the plugin's own `version: 0.1.0`.

### 7.6 Future capabilities (not implemented; not part of the governance change)

Recorded so that later work starts from the existing rules, not decided or built here:

- **Version information on the application's dashboard.** The CTO intends to display the version
  in the dashboard. It is an application feature (a separate issue, outside wallet, authentication
  and signing code), and would read the version that 7.2 already embeds.
- **Development-only Android APKs without staging promotion.** The CTO intends to support them
  eventually. They would be a distinct kind of build (section 4), never official, never
  distributed publicly (8.2), and would need their own design for application identity, signing,
  retention and access. They do not change 2.3 or 7.3: a release branch merge still runs its
  pipeline and carries its version advance.

## 8. Distribution models

| | Staging (internal) | Production (public) |
|---|---|---|
| Backend / network | Staging backend, Bitcoin **Signet**; coins have no value | Production backend, Bitcoin **mainnet** |
| Application | Separate "Cadena Signer STAGING" apps | "Cadena Signer" apps |
| Audience | Internal testers named by the CTO | The public |
| iOS | **Restricted TestFlight** of the staging App Store Connect record (mandatory, 8.1); no public link, no open beta, never submitted for review | App Store, via the production App Store Connect record |
| Android | Signed APK, internal testing only; **never public**; mechanism undecided (8.2, decision 7) | APK on Cadena's website; AAB on Google Play |
| Support | **None**: no stability, compatibility, upgrade or data guarantee; may be reset or withdrawn | Updates within the official update family; support as defined in `SECURITY.md` once it exists |
| Publication | The merge into `staging` is the authorization to build, sign and deliver to the configured internal destinations; tester access is controlled | The merge into `production` is the authorization of the configured delivery operations, per channel (2.3): non-public upload only; automatic App Review submission and public publication are outside the configured scope until an architectural extension; Apple's and Google's review and acceptance still apply |

- Staging builds are never presented as production and never enter a production
  channel; the separate application identity makes that structural rather than
  procedural.
- Testers use disposable test accounts; nobody tests staging with a wallet that
  holds value (`CLAUDE.md` section 5).
- The record of a delivery shows what was authorized: version, identifier,
  commit, the merge and its pull request, channel (section 9).

### 8.1 Restricted iOS staging distribution through TestFlight (mandatory)

**Decided:** delivering the signed staging iOS build to authorized testers through
TestFlight, restricted to the staging App Store Connect record, is a **mandatory
acceptance requirement** of the staging pipeline, not an optional step. The
milestone is not complete without it. Acceptance means at least:

- a merge into `staging` produces a signed iOS build of the **staging bundle ID**
  with the staging configuration, Signet, and the staging identifier visible in
  the app;
- the build reaches the **staging** App Store Connect record via TestFlight, and
  only individually authorized or named internal testers can install it (no public
  link, no open beta, never submitted for App Store review);
- the release record is produced and no one needs to build or sign locally.

**Decided (Issue #71):** the first delivery target is **internal-only TestFlight** (members of
the Cadena App Store Connect team; no external group, public link or Beta App Review).
Under the merge-authorized policy (2.3) the pipeline delivers to the configured internal group on
every `staging` merge; before a pipeline exists, a manual assignment to internal testers is an
operation the CTO authorizes in writing (the iOS 1.0.4 procedure). Controlled signed
testing is also how the minimum-iOS runtime requirement of [IOS_CI.md](IOS_CI.md) is
established. Details and status: [IOS_SIGNING.md](IOS_SIGNING.md).

*Resolved by 2.3, as amended by P1:* the TestFlight **upload** needs no additional release authorization; the authorized promotion carries it. The environment approval of the signing job confirms the deployment. The build is delivered through TestFlight only, and tester access stays restricted.

### 8.2 Signed Android staging APKs are not public

**Decided:** signed Android staging APKs must not be publicly distributed. The
internal distribution mechanism is **open** (decision 7), but any candidate must
satisfy:

- **GitHub Actions artifacts and logs are not a private channel here.** The
  repository is public, so an artifact uploaded by a workflow run can be
  downloaded by anyone with a GitHub account. A signed staging APK must not be
  uploaded with an ordinary public artifact step, attached to a GitHub Release or
  pull request, or printed in logs.
- Access is limited to authorized testers and is revocable and auditable.
- The mechanism is chosen and reviewed before the first signed staging APK is
  produced. Examples to evaluate (not decisions): an internal testing track of a
  separate staging app record in Google Play, access-controlled storage outside
  the public repository, or an authenticated distribution service.
- Until it exists, the pipeline may verify and record an APK (digest, version,
  signing fingerprint) without publishing the file.

The same applies to the iOS staging build: it goes to TestFlight, not to a public
Actions artifact. For production artifacts, nothing is publicly retrievable before
the release authority authorizes the channel.

## 9. Release record

Every pipeline build has a record attached to its artifacts:

| Item | Content |
|---|---|
| Release identifier | `vX.Y.Z-rc.N` or `vX.Y.Z` (the tag name) |
| Product version | `X.Y.Z` |
| Platform build number | `versionCode` and `CFBundleVersion`, each stated |
| Source Git commit | Full SHA |
| Approved build configuration | Environment, flavor, application ID, backend URL, network, configuration file name and SHA-256 |
| Build toolchain | Flutter, Dart, JDK/Gradle/AGP/Kotlin/NDK; Xcode, SDK, CocoaPods; runner image |
| Native binaries | SHA-256 of the committed Rust `.so`/`.a` files used |
| Signing identity | Certificate SHA-256 fingerprint (public) per artifact; never key material |
| Distribution channel | Intended and actual channel |
| Artifact digests | SHA-256 of each artifact |
| Build run and authorization | Workflow run URL; the merge commit, its pull request and the merging account (the authorization of section 2.3) |
| Verification and delivery outcome | The result of each automated check; each delivery operation executed and its result; on failure, the step at which delivery stopped |

The Git SHA and this record, not the displayed version, prove two artifacts
contain the same application logic (`GOVERNANCE.md` section 3). A signed artifact
without a record, or from a commit that was not approved, is not official.

## 10. What exists today

Implementation status is maintained in the [as-built overview (STA-01)](70-state/as-built.adoc), which states what exists, what is an approved target and what is under investigation, with the evidence for each. This section no longer carries a status table. The earlier table, written at the start of Issue #54, remains available in the Git history.

## 11. Open decisions

1. **Signing custodians** (continuity of credentials and recovery, not authorization) are
   unnamed (`GOVERNANCE.md` section 1). At least two, so that no credential has one holder.
   The release authority is defined by principle 9 and needs no further naming.
2. **Existing production signing lineage** (Android key, Apple team and
   certificates, Play and App Store Connect accounts) is undocumented and must be
   inventoried before anything is generated.
3. **Android app-signing model** (signing architecture section 3).
4. **Resolved (7.3, option A):** the build number is advanced in the reviewed pull request and
   validated before the merge; the pipeline never assigns it.
5. **Tags:** who creates them and with what identity (7.4).
6. **Staging identifier source** (`RELEASE_IDENTIFIER` in the staging
   configuration, 7.4) and its in-app presentation.
7. **Android staging internal distribution mechanism.** Mandatory constraint: not
   public (8.2). The mechanism itself is open.
8. **Production display name** ("Cadena Signer" in the target; "Cadena Bitcoin"
   today).
9. **Approvals: resolved (2.3), as amended by P1.** The reviewed promotion, carrying the CTO's written
   version-bound decision, is the release authorization for both pipelines; there is no extra TestFlight
   approval and no separate publication approval. The protected signing environment's reviewer approval
   confirms the deployment and is not an authorization.
10. **Independent builds and branding:** whether forks must change name and ID.
11. **Support policy:** `SECURITY.md` still defers it; it should state that only
    the latest official release is supported.
12. **Minimum supported iOS version (production release approval requires verified runtime
    compatibility).** The app declares iOS
    14.0, five embedded frameworks are built for 15.5 and eight secp256k1 objects of the Rust
    library for 18.5 ([IOS_CI.md](IOS_CI.md#release-compatibility-requirement-open-recorded-by-issue-70-accepted-2026-10-21)).
    The effective minimum must be decided and **tested on real iOS versions before a production
    release is approved**. The controlled, signed testing that establishes this (the restricted
    TestFlight delivery of 8.1, to authorized testers) is not blocked by it. The Rust library is not
    replaced or modified without separate authorization. Green compile and link runs do not satisfy
    this.
13. **Second, independent approver: withdrawn.** Principle 9 no longer requires one
    (CTO decision, 2026-11-17).
14. **Apple account facts** that decide the iOS pipeline: account ownership, the exact live
    bundle ID and highest build number, App ID registration, existing certificates and
    profiles, available API permissions, capabilities, export compliance. Collected with
    [APPLE_ACCOUNT_QUESTIONNAIRE.md](APPLE_ACCOUNT_QUESTIONNAIRE.md).
15. **Resolved (7.3, option A, CTO 2026-11-17):** the version advance is made in the reviewed
    pull request and validated before the merge; no workflow writes it.
16. **Exact non-public delivery destinations of the production pipeline (2.3).** The scope is
    decided: upload only, no automatic App Review submission or public publication. Still open:
    the destination of each artifact (for example the App Store Connect and TestFlight state, the
    Play track or draft, and where the production APK is placed, since placing it on the website
    would be public publication and is outside the automated scope).
