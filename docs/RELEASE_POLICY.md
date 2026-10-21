# Release policy

> **Status: draft (parent issue #54).** The architecture below was approved by the
> project owners on 2026-10-12; the document itself still goes through the normal
> pull-request review.
>
> **Nothing described here exists yet.** There is no `production` branch, no
> signing credential, no signed build, no separate staging application, no
> release workflow and no protected release environment. What exists today is
> listed in [section 10](#10-what-exists-today). *Decided* marks requirements
> fixed by the project owners on 2026-10-12; *Proposed* marks mechanisms that
> are not decided; open points are in [section 11](#11-open-decisions).

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
3. **Two protected release branches, one pipeline each.** A merge into `staging`
   builds and signs the two staging artifacts; a merge into `production` builds
   and signs the three production artifacts. A merge triggers **builds**, never an
   uncontrolled public release; publication is a separate authorization
   ([section 2](#2-release-branches-and-triggers)).
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
| Merge triggers | Staging pipeline: build and sign 2 artifacts | Production pipeline: build and sign 3 artifacts |
| Build configuration | Staging (backend, Signet) | Production (backend, mainnet) |
| Distribution | iOS: restricted TestFlight (mandatory). Android: internal only, never public (section 8) | Not by the merge. Separately authorized publication |
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
   - Proposed: two approvals, and creation of release tags `v*` restricted to the
     release workflow identity.
3. Protected environments for the production signing context exist and accept
   deployments from `production` only
   ([RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md)).
4. The production pipeline is merged and reviewed **before** the first merge into
   `production`, so that the branch's first update already builds under control.

### 2.2 Promotion procedure

1. Work reaches `development` by pull request (`Implements #N`).
2. `development → staging` by pull request. The merge builds and signs the
   staging artifacts. Testers verify them.
3. `staging → production` by pull request containing only commits already on
   `staging`. The merge builds and signs the production artifacts from the same
   source with the production configuration. The environment differences are the
   configuration and identity inputs, not diverging source
   (`GOVERNANCE.md` section 3).
4. Publication of any production artifact needs a separate, explicit
   authorization by the release authority (section 8).

## 3. The five signed artifacts

Target state (**Decided**). None of these exists yet.

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

- **A pipeline output is a signed build artifact, not a release.** Uploading to
  the website, Google Play or the App Store, and submitting for review, are
  separate authorized acts.
- The APK and the AAB of one production release share `versionName`,
  `versionCode`, application ID and update family. The official APK is the
  universal APK (`--split-per-abi` changes the `versionCode`).
- The artifact name carries identifier, platform, build number and short commit
  SHA, and its release record is attached (section 9).
- **No signed artifact is stored where the public can retrieve it.** The
  repository is public, and the artifacts and logs of its workflow runs are
  readable by any GitHub account (the CI documents already note this). A signed
  artifact is therefore never left as an ordinary Actions artifact, a GitHub
  Release or a pull request attachment before its distribution is authorized
  (section 8.2). Digests and the release record, which contain no binary, may be
  public.
- Successful compilation is not signing and signing is not distribution. The CI
  validation builds (section 4) are none of the five.

## 4. Kinds of build

| | CI validation build | Staging pipeline build | Production pipeline build | Independent build |
|---|---|---|---|---|
| Exists today | **Yes** ([ANDROID_CI.md](ANDROID_CI.md), [IOS_CI.md](IOS_CI.md)) | No | No | n/a |
| Trigger | Push to `staging`, or manual | Merge into `staging` | Merge into `production` | The builder |
| Output | Android: **debug-signed** APK. iOS: **unsigned** `Runner.app` | 2 signed artifacts | 3 signed artifacts | Builder's choice |
| Signing | Ephemeral debug key / none | Cadena, staging context | Cadena, production context | Builder's own keys |
| Distributable | **Never** | Restricted only: iOS via TestFlight (mandatory), Android internal and non-public | After separate authorization | Builder's responsibility |
| Official | No | Candidate | Yes, once published | No |

- Validation builds stay as they are until a deliberate, approved transition
  ([RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md) section 3).
  They are not promoted, renamed or signed into release artifacts.
- The Android `release` build type currently uses the **debug signing config**
  (`CLAUDE.md` section 10). A release build made from the repository today is not
  official and must not be distributed.
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
| Android `applicationId` | `com.app.cadenabitcoin` | `com.app.cadenabitcoin.staging` |
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
| Android `applicationId` and `namespace` | Both `com.app.cadenabitcoin` (`build.gradle.kts`) | Only `applicationId` must vary; `namespace`/`MainActivity` package can stay, so no source rename is needed |
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
- Where the build number comes from for each merge is open (decision 4). **Proposed
  baseline:** raised in `pubspec.yaml` by the promotion pull request and checked
  for uniqueness by the pipeline, so it is visible in the approved Git revision.

### 7.4 Identifiers and tags

- Staging merge → `vX.Y.Z-rc.N`, `N` ≥ 1, counting candidates of that version.
  Production merge → `vX.Y.Z`. The numeric part must equal the product version.
- An identifier names exactly one Git commit and is never reused or moved. A
  rebuild needing a new commit or a new build number is the next `-rc.N`.
- The identifier is the signed annotated Git tag name, created under controlled
  authority (decision 5). No tag exists today.
- **Proposed source of `N`:** a `RELEASE_IDENTIFIER` entry in the staging
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

## 8. Distribution models

| | Staging (internal) | Production (public) |
|---|---|---|
| Backend / network | Staging backend, Bitcoin **Signet**; coins have no value | Production backend, Bitcoin **mainnet** |
| Application | Separate "Cadena Signer STAGING" apps | "Cadena Signer" apps |
| Audience | Authorized testers named by the release authority | The public |
| iOS | **Restricted TestFlight** of the staging App Store Connect record (mandatory, 8.1); no public link, no open beta, never submitted for review | App Store, via the production App Store Connect record |
| Android | Signed APK, internal testing only; **never public**; mechanism undecided (8.2, decision 7) | APK on Cadena's website; AAB on Google Play |
| Support | **None**: no stability, compatibility, upgrade or data guarantee; may be reset or withdrawn | Updates within the official update family; support as defined in `SECURITY.md` once it exists |
| Publication | The merge into `staging` is the authorization to build; tester access is controlled | Needs **separate authorization** by the release authority, per channel |

- Staging builds are never presented as production and never enter a production
  channel; the separate application identity makes that structural rather than
  procedural.
- Testers use disposable test accounts; nobody tests staging with a wallet that
  holds value (`CLAUDE.md` section 5).
- Authorization to publish records who approved what: version, identifier,
  commit, channel (section 9).

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

*Open (implementation decision):* whether the TestFlight upload itself needs an
additional approval, or runs automatically after the merge. Either way the build
is delivered through TestFlight only, and tester access stays restricted.

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
| Build run and approvers | Workflow run URL; who approved signing and publication |

The Git SHA and this record, not the displayed version, prove two artifacts
contain the same application logic (`GOVERNANCE.md` section 3). A signed artifact
without a record, or from a commit that was not approved, is not official.

## 10. What exists today

| Item | State |
|---|---|
| `development`, `staging` | Exist, protected |
| `production` | Exists, protected (created at the adopted baseline `7b63c97`, Issue #68); compile-only builds only |
| Android CI validation (debug-signed APK), iOS CI validation (unsigned `Runner.app`) | Working; unchanged; **not** among the five artifacts |
| Signing credentials, protected release environments, release workflows | **None** |
| Tags, GitHub Releases | None |
| Separate staging application ID / bundle ID / App Store Connect record | **None**; both CI validation builds use `com.app.cadenabitcoin` |
| Build-time configuration | Unfinished (Issue #57 B1, local branch only); committed constants are production |
| iOS toolchain | Xcode 26.3 on `macos-15` with an iOS 26 SDK, pinned by Issue #70 (accepted hosted runs: [IOS_CI.md](IOS_CI.md#verification-status); compile and link only). App Store Connect uploads have required Xcode 26 and the iOS 26 SDK since 2026-04-28 ([Apple](https://developer.apple.com/news/upcoming-requirements/)) |
| `tool/verify_version.sh` | Exists (this issue), read-only |

## 11. Open decisions

1. **Release maintainers and signing custodians** are unnamed
   (`GOVERNANCE.md` section 1). Two of each at least.
2. **Existing production signing lineage** (Android key, Apple team and
   certificates, Play and App Store Connect accounts) is undocumented and must be
   inventoried before anything is generated.
3. **Android app-signing model** (signing architecture section 3).
4. **Build-number source** per merge (7.3), and whether platform numbers are ever
   assigned by the pipeline.
5. **Tags:** who creates them and with what identity (7.4).
6. **Staging identifier source** (`RELEASE_IDENTIFIER` in the staging
   configuration, 7.4) and its in-app presentation.
7. **Android staging internal distribution mechanism.** Mandatory constraint: not
   public (8.2). The mechanism itself is open.
8. **Production display name** ("Cadena Signer" in the target; "Cadena Bitcoin"
   today).
9. **Approvals:** whether the staging environment needs a reviewer beyond the
   merge itself; whether the TestFlight upload needs an additional approval (the
   restricted TestFlight delivery itself is mandatory, 8.1); and how production
   signing and publication approvals are split.
10. **Independent builds and branding:** whether forks must change name and ID.
11. **Support policy:** `SECURITY.md` still defers it; it should state that only
    the latest official release is supported.
12. **Minimum supported iOS version (blocks distribution approval).** The app declares iOS
    14.0, five embedded frameworks are built for 15.5 and eight secp256k1 objects of the Rust
    library for 18.5 ([IOS_CI.md](IOS_CI.md#release-compatibility-requirement-open-recorded-by-issue-70-accepted-2026-10-21)).
    The effective minimum must be decided and tested on real iOS versions before any iOS
    distribution build is approved. The Rust library is not replaced or modified without
    separate authorization. Green compile and link runs do not satisfy this.
