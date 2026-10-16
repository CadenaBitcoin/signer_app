# Release implementation plan

> **Status: plan for maintainer approval (parent issue #54).** It orders the work
> needed to reach the five signed artifacts of [RELEASE_POLICY.md](RELEASE_POLICY.md)
> and the signing design of
> [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md). **None of the
> steps below is started or authorized by this document.** Each step is its own
> issue and pull request, with human approval where architecture, security or
> signing is involved (`CLAUDE.md` sections 6 and 8).

## 1. Target

| Trigger | Artifacts |
|---|---|
| Merge into `staging` | Android staging APK (internal, never public); iOS staging build (restricted TestFlight, mandatory) |
| Merge into `production` | Android production APK (website); Android production AAB (Google Play); iOS production build (App Store) |

All five signed under Cadena-controlled authority; staging and production are
separate applications and separate signing/deployment contexts; a merge builds,
publication is authorized separately.

## 2. Dependency-ordered sequence

**Priority milestone M1: signed iOS staging build delivered through restricted
TestFlight.** It is a mandatory acceptance requirement
([RELEASE_POLICY.md](RELEASE_POLICY.md) section 8.1). Everything M1 depends on is
on the critical path and is scheduled first; Android staging signing (step 10) may run
in parallel when convenient but does not delay M1.

Steps marked **∥** can run in parallel with their neighbours. "Human" tasks are
account and policy work no code change can replace.

| # | Step | Depends on | Notes |
|---|---|---|---|
| 1 | **Release governance and versioning** (this issue, #54): policy, signing design, plan, version checker, `GOVERNANCE.md` | none | Documentation and a read-only script. |
| 2 | **Human: people, lineage, Apple** ∥ | none | Name the release authority, signing custodians and a second Apple administrator; inventory the existing Android key, Apple team, Play and App Store Connect accounts; confirm ownership by the Cadena organization; start the Apple items of section 5 for the **staging** application. Gates steps 8, 11, 12. |
| 3 | **Production-grade iOS toolchain** ∥ **start immediately** | none to start | App Store Connect uploads have required Xcode 26 and the iOS 26 SDK since 2026-04-28; TestFlight delivery goes through App Store Connect, so the same requirement is expected to apply (Apple's page does not say so explicitly; confirm early). Prove (unsigned, on a branch, from a copy of the validation workflow) that Flutter 3.35.3, CocoaPods with Sumsub and Fingerprint Pro, and the committed Rust `libdlcplazacryptlib.a` build with Xcode 26; confirm a hosted runner image with Xcode 26. The outcome may require a Flutter upgrade, a separate explicitly approved issue (`CLAUDE.md` sections 3 and 7). Highest risk and longest lead: gates M1. |
| 4 | **Shared explicit build configuration** (successor of Issue #57 B1) | 1 | Merge or rebase B1 onto `development` and adapt it: no default, fail on missing/inconsistent/unsuitable configuration, branch check, release identifier, flavor cross-check (sections 3 and 4). Touches environment selection (sensitive): investigation report first. |
| 5 | **Network-specific XPUB/address validation** ∥ with 4 | investigation | Existing code validates nothing for Signet (policy section 6). Investigation, then an approved change in sensitive code. Must exist before staging builds are handed to testers as the Signet-validating build. |
| 6 | **Application identities on both platforms**, **iOS staging first** | 4 | Flavors `staging`/`production`; separate application ID and bundle ID, names, icons; per-variant `Info.plist`/manifest values. Check third-party and backend coupling to application IDs and the `BGTaskSchedulerPermittedIdentifiers` mismatch first. Changes both CI build commands (section 3). Updates the version checker and the bootstrap in `CLAUDE.md`. |
| 7 | **In-app staging identifier display** | 4, 6 | Small UI change outside wallet/auth/signing code: staging shows `vX.Y.Z-rc.N`, production shows nothing. Required for the iOS acceptance. |
| 8 | **Signing infrastructure, staging context, iOS first** | 2, 6 (staging bundle ID), Apple items of section 5 | Protected environment `staging-ios` and its secrets, the staging App Store Connect record and profile, TestFlight group of authorized testers, custody procedure. `staging-android` follows in step 10. No credential is created before step 2. |
| **9** | **M1: signed iOS staging build and restricted TestFlight delivery** | 3, 4, 5, 6, 7, 8 | Push to `staging` builds, signs and delivers to the staging TestFlight record. **Acceptance:** policy section 8.1. Whether the upload needs an additional approval is decided during this step. |
| 10 | **Signed Android staging build** ∥ with 9, if convenient | 4, 6, 8 (Android staging key) | Same pipeline pattern, no Xcode 26 dependency. **Prerequisite:** the internal, non-public distribution mechanism (policy section 8.2) is chosen first; until then the pipeline only verifies and records the APK and publishes nothing. |
| 11 | **Create `production` branch** | 2 (lineage), production context of step 8 | Policy section 2.1. Needs explicit approval. Must exist, protected and with its pipeline reviewed, before its first merge. |
| 12 | **Signed production builds** (APK, AAB, iOS) | 9, 10, 11, production signing context | Publication still not automatic. |
| 13 | **Publication and release automation** | 12 | Website upload procedure, Google Play track, App Store submission, release notes, release-record publication, rollbacks. Each channel behind its own approval. |

Every requirement of the policy is covered: governance and versioning (1),
people and accounts (2), iOS toolchain (3), shared configuration (4), network
validation (5), identities (6, 7), signing (8), signed iOS staging with
TestFlight (9), signed Android staging (10), `production` and signed production
(11, 12), publication (13). The order differs from the first request only where a
dependency justifies it: the toolchain (3) starts at once because it is
independent and the riskiest item on the M1 path, and iOS staging (9) is ahead of
Android staging (10).

## 3. Transition from validation CI to the signed pipeline

Today's workflows stay and keep their meaning:

| Workflow | Output | Not |
|---|---|---|
| `android-ci-validation.yml` | Debug-signed validation APK (14 days) | Not one of the five artifacts |
| `ios-ci-validation.yml` | **Unsigned** `Runner.app` (14 days) | Not an installable or signed build |

Neither is modified by this issue. The transition, each stage an approved pull
request:

| Stage | Change | Existing CI |
|---|---|---|
| T0 (now) | Policy and version checker only | Untouched |
| T1 | Optional new workflow that runs only `tool/verify_version.sh` (pull requests and manual) | Untouched (new file) |
| T2 | **Configuration lands (step 4), then flavors (step 6).** While the legacy path still works, the new mechanism is additive and the validation workflows keep passing. Fail-closed is then switched on **in the same pull request that adds the explicit configuration (and `--flavor`) to both validation workflows' build commands.** | **Must change, deliberately.** Once configuration is mandatory, `flutter build apk --debug` and `flutter build ios --release --no-codesign` without it fail, as intended. The change is small, reviewed, and shown green with a manual run before merge. |
| T3 | New signed workflows as **new files**: staging on push to `staging`, production on push to `production`, using the protected environments | Validation workflows keep running beside them. No dependency between the two sets unless later decided. |
| T4 | Decide whether validation stays as a fast unsigned check (for example as a required status check) or retires | Never removed without approval |

Other consequences to schedule: the iOS validation workflow stays on Xcode 16.4
until step 3 proves the new toolchain, then moves in a separate approved change;
validation artifacts keep their "NOT APPROVED FOR PUBLIC DISTRIBUTION" labels and
are never renamed into release artifacts; `CLAUDE.md` section 4 and the PR
template need the explicit-configuration commands in steps 4 and 6.

## 4. Conflicts with the unfinished Issue #57 B1

Reviewed read-only from the local branch `issue/57-build-time-environment-config`
(checkpoint commit `2a98b62`); that worktree is untouched.

| # | B1 today | Policy requires | Resolution |
|---|---|---|---|
| 1 | With no configuration, **built-in production defaults** apply (`isExplicit == false`) | No defaults; missing configuration fails | Remove the fallback in step 4 |
| 2 | Environment is `APP_ENV`, backend, network only | Also flavor/identity and, for staging, the release identifier | Extend the configuration contract; fail on flavor ≠ environment |
| 3 | Branch is deliberately irrelevant to selection | The pipeline of each branch must verify the branch/configuration match | Keep "the app never reads the branch"; add the check in the workflows |
| 4 | Branch is based on `f5d2a2d`, **before PR #61**. A plain diff against `development` makes the iOS workflow and `IOS_CI.md` look deleted, but a merge is textually clean (checked read-only with `git merge-tree`: no conflicts). B1 does not touch the iOS workflow, so the iOS validation keeps building the committed (production) constants | Must not regress the iOS CI, and must not leave it unconfigured once configuration is mandatory | Bring B1 onto current `development` (merge or rebase) before any pull request; the iOS workflow adopts the explicit configuration in stage T2 (section 3) |
| 5 | Rewrites `android-ci-validation.yml` to build staging | Validation workflows change only by the approved T2 pull request | Fold into T2; do not push B1 as is |
| 6 | Validation APK is configured as staging but keeps the production application ID | Staging is a different application | Resolved by step 6 |
| 7 | `appController.dart` constants become aliases of `BuildConfig` | Environment selection is sensitive code | Investigation report and approval (already `CLAUDE.md` section 6) |
| 8 | No Signet/mainnet XPUB or address validation | Required per environment | Separate step 5; not B1's scope |
| 9 | Its tools (`tool/verify_build_config.sh`, probe) | Version checker `tool/verify_version.sh` | No filename clash; both are used by the pipelines |

B1 is a sound starting point (compile-time constant assertions fail in release
builds; shared Dart code for both platforms). It is **not** modified here.

## 5. Dependencies on Apple administration

Needed from the Apple Developer account administrator (named by the project
owners) and the Cadena organization. None of it is done by this work, and none
requires that person to build or sign locally.

1. Confirm the Apple Developer Program membership and team `D65458CPDP` belong to
   the Cadena organization; assign at least a second administrator.
2. Confirm the production App ID `com.app.cadenabitcoin` exists in that team and
   its App Store Connect record. The staging App ID `com.app.cadenabitcoin.staging`
   is **not** assumed registered: register it and create its **own** App Store
   Connect record (name, SKU, categories, privacy information as required).
3. Create the App Store distribution provisioning profiles, one per bundle ID.
4. Decide shared or per-context Apple distribution certificates and create them
   within Apple's per-team limits; hand the material to the protected GitHub
   environments through the custody procedure.
5. Create App Store Connect API keys scoped per context with the least role that can
   upload and manage TestFlight; create the TestFlight tester groups for the staging
   record.
6. Accept current agreements; track membership renewal and certificate expiry in
   the custody register.
7. Decide whether the pipeline may create certificates through the API (nobody
   needs a Mac) or the one-time key pair is generated by the administrator under
   the custody rules.

Other external dependencies: Google Play Console ownership, the production app
record and Play App Signing enrollment; the process for putting the APK on
Cadena's website; GitHub Organization settings (environments, `production` branch
ruleset, tag rules); the DLC Plaza backend and the Sumsub/Fingerprint Pro
configuration for the new staging application ID (to be checked in step 6).

## 6. Not decided here

Any code, build file, workflow, branch, tag, credential, account or store change.
