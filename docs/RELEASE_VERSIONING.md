# Release versioning and artifact traceability

How a built artifact is tied to its source revision, its version, its build run and its
signing status, and how a version is chosen so that a published version is never reused.
This is the procedure under [RELEASE_POLICY.md](RELEASE_POLICY.md) (sections 7 and 9): it
adds no rule to the policy. Where the policy leaves a decision open, this document says so
([open decisions](#open-decisions)) instead of deciding it.

**Status: compile validation only.** Everything below is implemented for the unsigned,
compile-only builds of [RELEASE_TRIGGERS.md](RELEASE_TRIGGERS.md). Nothing here signs,
uploads a binary, tags or publishes. Official signing and delivery are #72 (Android), #71
(iOS), #66 (signing-key governance).

## Why this exists

A published Android application (`com.cadenabitcoin.mobile.signer`, 1.0.3, versionCode
1000034) could not be traced to a commit: no tag, no release record, the version number
named two different code bases, and the application ID is not in any commit. The build
evidence below exists so that this cannot happen to a build made by the pipeline.

## The identifiers, and where each one comes from

| Identifier | Example | Single source | Changes by |
|---|---|---|---|
| Source revision | `7b63c9791fccc8f9711ed853e2294967899be972` | Git (the commit the run built) | every commit |
| Product version `X.Y.Z` | `1.0.3` | `pubspec.yaml` `version:` | a reviewed commit |
| Build number | `1000034` | `pubspec.yaml` `version:` (`+BUILD`) | a reviewed commit |
| Release identifier | `v1.0.4-rc.1`, `v1.0.4` | not yet defined (open decision 6); `null` in a compile-validation build | the promotion that names a candidate |
| **CI build identifier** | `39237471969.1:android-production-apk` | the GitHub run: `<run id>.<attempt>:<variant>` | **every execution** |
| Canonical artifact name | `cadena-signer-production-1.0.3+1000034-android-apk-7b63c97-run39237471969.1.apk` | derived from the manifest | never typed |

The **CI build identifier is not a version.** Many executions can build one application
version; each is unique without anyone raising the build number. The application version
changes only when a person changes `pubspec.yaml` in a reviewed commit; no workflow writes
it, passes `--build-name`/`--build-number`, or derives a version from a branch name, a
date or a run number (checked by `tool/verify_version.sh` and by the tests).

### Platform mapping (checked in source and in every built artifact)

| | Flutter | Android | iOS |
|---|---|---|---|
| Product version | `--build-name` ← `pubspec.yaml` | `versionName` = `flutter.versionName` | `CFBundleShortVersionString` = `$(FLUTTER_BUILD_NAME)` |
| Build number | `--build-number` ← `pubspec.yaml` | `versionCode` = `flutter.versionCode` | `CFBundleVersion` = `$(FLUTTER_BUILD_NUMBER)` |

- `tool/verify_version.sh` checks the **source** wiring (one version, no override, no
  suffix, no literal, the two flavors change only the identity).
- `tool/verify_artifact.sh` reads the **built artifact** (aapt2, bundletool, `Info.plist`)
  and compares it with `pubspec.yaml`.
- `tool/build_manifest.py verify` compares the manifest with the repository at that commit.
- Apple's fields stay numeric (`1.0.3-rc.1` would be rewritten to `1.0.3.1`). A candidate
  suffix therefore never goes into `pubspec.yaml` or into an Apple field; policy 7.2.
- Android and iOS build numbers **may** differ in future (policy 7.3), but no mechanism
  exists, and the tools reject a platform number that differs from `pubspec.yaml`. Adding
  one is a reviewed change to the tools, not a workaround.

## Published versions: a version code is never reused

`config/release/published_versions.json` records what is already published, as a fact
confirmed from the store console:

| Platform | Channel | Package | Version | Recorded |
|---|---|---|---|---|
| Android | Google Play | `com.cadenabitcoin.mobile.signer` | 1.0.3 (**1000034**), fully rolled out | 2026-10-19 (Issue #68) |

Not recorded: earlier Android releases (all below 1000034), website or internal-test
APKs, and anything on iOS. No iOS floor is enforced.

- **A release build must have a build number above every published one on its platform.**
  `tool/build_manifest.py gate --channel production` fails otherwise. The signed release
  pipeline (#72) must run it before building and must not bypass it. Compile validation
  does **not** run it: validation builds may equal the published number because they are
  not releases.
- **Today the repository is at `1.0.3+1000034`**, equal to the published number. The gate
  therefore fails for production, on purpose: a release from the current `pubspec.yaml`
  would reuse a published version code. The first production release needs a reviewed commit
  that raises the build number to at least `1000035`.
- The floor applies to the Google Play application. The repository builds
  `com.app.cadenabitcoin`, which is **not** that application; whichever ID #72 settles on,
  an update of the published app needs a versionCode above 1000034 *and* the published
  package ID and signing lineage. The floor is the conservative rule for either case.
- The ledger is edited only by a reviewed commit after a maintainer confirms the number in
  the store console. It records history; it authorizes nothing.

## The build manifest

Every build of `build-variants.yml` writes `evidence/<variant>.manifest.json` next to the
existing `evidence/<variant>.txt` (schema `cadena-build-manifest/1`, created by
`tool/build_manifest.py create`). The manifest adds no new fact about the artifact: the
artifact facts come from the text evidence written by `tool/verify_artifact.sh`, the run
metadata from the GitHub environment. Both files are uploaded together (14 days, text
only).

| Section | Content |
|---|---|
| `variant`, `platform`, `kind`, `environment` | which of the five builds; `kind` is `apk`, `aab` or `ios-app` |
| `classification` | `compile-validation` here; the other values are for later work (below) |
| `source` | full commit SHA, ref, ref type, event, `release_id` (or `null`) |
| `ci` | repository, workflow, **run id, run attempt, run URL, build identifier** |
| `version` | `pubspec` string, product version, pubspec build, the platform's version name and build number |
| `application` | application ID / bundle ID, display name |
| `configuration` | build configuration file, its **SHA-256**, the exact build command |
| `toolchain` | Flutter, Dart, Java (Android) / Xcode, SDK, CocoaPods (iOS), runner image, Android build-tools |
| `native_libs` | SHA-256 of the committed prebuilt Rust library per ABI / for iOS |
| `artifact` | file, canonical name, **SHA-256**, `digest_kind`, `digest_basis`, size |
| `signing` | `status`, signer DN, signer certificate SHA-256 |
| `distribution` | `distributable`, `binary_retained` (both `false`) |
| `verification` | the environment (backend URL) check result |
| `release_gate`, `known_issues` | derived from the published-versions ledger (see below) |

**Raw-file and composite digests are distinguished.** An APK or AAB has `digest_kind:
file`: the SHA-256 of the file itself. The iOS `Runner.app` is a directory and has
`digest_kind: directory-manifest`: the SHA-256 of the sorted list of the SHA-256 of every
file (`digest_basis` says so). The two are never compared with each other, and the
verifier rejects a mismatch between the kind of artifact and the kind of digest.

**Signing status** is exactly one of:

| `signing.status` | Meaning | Allowed today |
|---|---|---|
| `unsigned` | no signature (iOS `--no-codesign`) | iOS |
| `debug` | the temporary Android debug key; **not distributable**; the certificate is recorded | Android |
| `release` | signed with an official release key; needs a recorded certificate fingerprint and a release identifier | **nothing produces it yet** (#72) |

`debug` and `unsigned` artifacts can only be classified `compile-validation` or
`internal-evaluation`, never as a release candidate or a release, and are never
`distributable`. The verifier rejects these contradictions, and an iOS compile-validation
artifact that is not unsigned.

**Known issues** are recomputed from the ledger and must be present; a manifest that drops
one fails. Today the Android production manifests carry both:

- `application-id-differs-from-published-app`: the build is `com.app.cadenabitcoin`, the
  published app is `com.cadenabitcoin.mobile.signer` (outstanding release blocker, #72);
- `version-code-not-above-published-floor`: the build number is not above 1000034.

### What `verify` rejects

Missing or unknown keys; a commit that is not a full lowercase SHA; a push to `staging`
that built production (or the reverse); a malformed or inconsistent run identity; a
version that differs from `pubspec.yaml` (name, build, or between the platform and the
product version); a versionCode above Google Play's limit; an application ID or name that
is not the environment's; the wrong configuration file or a changed file; a build command
that overrides the version or disagrees with the flavor; missing toolchain entries or
native library digests; a digest of the wrong kind; a wrong canonical name; contradictory
signing/classification/distribution values; a release identifier of the wrong form for its
environment (`-rc.N` required on staging, forbidden on production) or for another
version; and a text evidence file that says something else.

`verify-dir` (run by the `verdict` job) additionally checks the manifests **of one run**
against each other: one commit, one run, one version, no repeated variant, build
identifier, canonical name or artifact digest, and the production APK and AAB are one
update family (same ID, name, version, signing). The verdict also still requires, from
`tool/check_verdict.sh`, a `.txt` and a `.manifest.json` for every required variant and
nothing for any other. The existing bash checks of the verdict (APK/AAB consistency,
staging ≠ production) are kept; they overlap on purpose, so that neither check is weaker
than before.

### A release cannot be claimed while the protections are open

A manifest that claims a release (classification `release-candidate` or `release`, signing
`release`, or `distributable: true`) is **rejected** while

- its build number is not above the published floor (`release_gate.status` is
  `blocked-not-above-floor`), or
- any known issue is open, for example `application-id-differs-from-published-app`.

With `--repo` both values are recomputed from the repository's ledger, so they cannot be
edited away in the manifest; the `verdict` job always verifies with `--repo`. The Android
application ID is the second protection: a build of `com.app.cadenabitcoin` can neither
borrow the published listing's version history nor be described as that application. The
issue is cleared only by a **reviewed** change: the ID of the build becomes the published
one (the #72 decision), or the ledger deliberately records the new listing. Neither is
changed here. Ordinary compile-validation builds are not releases, so they keep passing at
the current version (`1.0.3+1000034`); they are simply labelled with the open issues.

### Following a binary back to its source

1. `tool/build_manifest.py check-file MANIFEST FILE` recomputes the file's SHA-256 (for an
   iOS `Runner.app` directory, the directory digest of `tool/verify_artifact.sh`) and its
   size, compares them with the manifest, and prints what the manifest claims: variant,
   application ID and version, build number, commit, CI execution, configuration digest,
   signing status and classification. Without the manifest, hash the file and look the
   digest up in the manifests of the Actions run; the canonical file name also carries the
   commit, environment, version and run.
2. The manifest names the commit (`source.commit`), the run URL, the configuration file
   and its digest, and the toolchain.
3. Check out that commit, run `tool/build_manifest.py verify <manifest> --repo .`. It
   recomputes the pubspec version, the configuration digest and the ledger-derived fields.

A binary does not carry its own commit; the **digest links it to the manifest**. A binary
that is passed on without its digest or manifest cannot be traced, which is why a retained
binary must always travel with its manifest (below).

### Recorded provenance is not authenticated provenance

What the two files give you, and what they do not:

| | Established by | Strength |
|---|---|---|
| This file is the one the manifest describes | the SHA-256 (and size) recomputed by `check-file` | **cryptographic**, but only relative to that manifest |
| Application ID, version, build number, signing status | read from the artifact by `tool/verify_artifact.sh` (aapt2, bundletool, `Info.plist`) and recorded | recorded by the workflow; re-checkable from the file itself with the same script |
| Source commit, CI execution, variant, configuration digest, toolchain | **recorded by the workflow** from the GitHub environment | a **claim**, not a proof |
| The manifest was written by this workflow run | the run URL; the manifest is in that run's artifacts on GitHub | only as far as GitHub's own record is trusted; **nothing signs the manifest** |
| The binary was really built from that commit | nothing | not established: Flutter AOT output is not bit-reproducible, so a rebuild can be compared by commit, configuration digest, toolchain and the native library digests, not by the artifact digest |

Anyone who holds both files can change both consistently, and a debug signature (a key
created per machine or run) authenticates nothing. So: take the manifest from the run URL,
not from wherever the binary was passed on; run `verify --repo` on a checkout of the claimed
commit; treat the rest as recorded provenance. Cryptographically authenticated provenance
(for example GitHub artifact attestations, signed by the workflow identity) would need
`id-token: write` / `attestations: write`, which changes the workflow's permissions; it is
not part of #69 and needs its own authorization (open decision 8).

## Release candidates and production releases

Under the policy (7.1, 7.4), and unchanged by this document:

- A staging candidate is named `vX.Y.Z-rc.N` (`N` ≥ 1, counting candidates of that
  version); a production release is `vX.Y.Z`. The numeric part equals the product version
  in `pubspec.yaml`; `-rc.N` never enters `pubspec.yaml` or an Apple field.
- An identifier names exactly one commit and is never reused or moved. A rebuild that needs
  a new commit or a new build number is the next `-rc.N`.
- **Promoting a tested revision:** the production release is the *same source revision* that
  was tested as a candidate, reached by the normal `staging → production` pull request. If
  the production build needs a different build number, that is a new reviewed commit and
  therefore a new candidate, not an edit of the old one.
- **A failed or withdrawn candidate** keeps its identifier and its build number; both are
  consumed. The next candidate is `-rc.N+1` with a higher build number. Nothing is renamed
  or deleted; a withdrawal is recorded in the release record.
- **Rebuilding an existing release:** a build of the same commit is a new CI execution with
  a new CI build identifier and a new artifact digest, never a new version. Flutter AOT
  output is not reproducible bit for bit across machines, so equality of two builds is
  decided by the commit, the configuration digest and the toolchain in the manifest, not
  by the artifact digest.
- The tooling accepts a release identifier (`--release-id`) and checks its form against the
  version and the environment. Where the identifier is stored and who creates the tag are
  open decisions 5 and 6; until they are decided, compile-validation manifests carry
  `release_id: null`, and **no tag or release exists**.

## Retention of binaries (interface only)

**Today no binary is retained**: the workflow uploads text and JSON only (policy section 3
and 8.2: a binary is never left as an ordinary Actions artifact of this public repository
before its distribution is authorized; production binaries are deliberately never kept).
This work does not change that. It provides what a later, separately authorized retention
step must use:

- a **canonical file name** (`tool/build_manifest.py name`) so that two files from
  different builds can be told apart, and a labelled form for an internal evaluation copy,
  `NON-DISTRIBUTABLE_INTERNAL-EVALUATION_<canonical name>`;
- the manifest fields `classification`, `signing`, `distribution.binary_retained` and
  `known_issues`, with verifier rules that stop a retained debug-signed binary from being
  classified, named or described as a release;
- the requirement that a retained binary is stored **with its manifest**.

### The earliest safe point for a downloadable production-configured APK

A *production-configured, debug-signed APK for internal evaluation* is **not** an official
artifact. The earliest safe point to retain one is **after this issue is merged and after a
separate, written authorization** of the following (a new issue, not part of #69):

1. a manually started (`workflow_dispatch`) workflow, one Android variant only, on a ref the
   maintainer chooses; never on a push, never on a promotion;
2. a protected GitHub environment with a required reviewer (none exists today), so a person
   approves each retained binary;
3. the labelled file name above, the manifest next to it, a retention of days (not weeks),
   no tag, no release, no copy outside the run;
4. the maintainers' decision that retaining it in this public repository is acceptable
   (policy 8.2 says otherwise by default), or a private location instead.

Properties of such a file that the label and the manifest must keep explicit:

- debug-signed: the key is created on the runner, so every run is expected to have a
  different signer (compare the recorded `signer_cert_sha256` of two runs); one evaluation
  APK cannot update another and must be uninstalled first;
- application ID `com.app.cadenabitcoin`: a different application from the published
  `com.cadenabitcoin.mobile.signer`; it installs beside it and cannot update it;
- build number equal to the published 1000034, so it is not a candidate for any store;
- production configuration: it talks to the production backend and mainnet. Only disposable
  accounts, never a wallet holding value.

This is **not** an official, update-compatible Google Play artifact. That needs, beyond the
above: the signing-key governance (#66), the release signing pipeline in protected
environments (#72), a decision on the application ID (the published one or a new listing),
a build number above 1000034 (the gate), a release identifier and tag, the release record
of policy section 9, and the tester sign-off of policy 2.2.

## Version-transition test (needs explicit authorization)

Issue #69 requires one authorized version transition on staging. It is **not** run by this
change. Proposed procedure, to be started only on the owner's written authorization naming
the new version:

1. An issue branch changes only the `version:` line of `pubspec.yaml` (for example
   `1.0.3+1000034` → `1.0.3+1000035`), reviewed and merged into `development` like any PR.
2. `tool/verify_version.sh` and `tool/test_release_versioning.sh` pass; the PR states that
   production is not touched.
3. The reviewed `development → staging` promotion triggers `build-variants.yml` (two
   staging variants). Expected: both manifests say `1.0.3+1000035`, Android `versionCode`
   and iOS `CFBundleVersion` 1000035, the same commit and run, and `verdict` is green.
4. `tool/build_manifest.py gate --channel production` now passes locally (1000035 > 1000034).
5. `production` is **not** promoted; no tag, release or signing is involved.

## Open decisions

These need a maintainer decision (policy section 11); this change does not take them:

1. **Source of the release identifier and of `N`** (policy open decision 6; proposal:
   `RELEASE_IDENTIFIER` in the staging configuration).
2. **Who creates tags and with which identity** (decision 5), and when.
3. **Where the build number is raised for each promotion** (decision 4; proposal: in the
   promotion pull request, checked by the pipeline).
4. **Whether Android and iOS build numbers may differ** in practice (permitted, not built).
5. **The iOS published build number**, so an iOS floor can be recorded.
6. **Retention of an internal evaluation APK**, as described above, and where.
7. **The Android application ID** of the next release (#72), which decides whether the
   published listing can be updated.
8. **Authenticated provenance** (signed attestations of the manifest/binary), which needs a
   permission change and its own authorization.

## Checks

```bash
tool/test_release_versioning.sh              # version rules, manifests, gate, workflow shape
tool/test_release_triggers.sh                # triggers and the verdict (unchanged behavior)
tool/verify_version.sh                       # source wiring
tool/build_manifest.py verify M.json --repo . --evidence M.txt
tool/build_manifest.py check-file M.json app-production-release.apk   # does this file match its manifest?
tool/build_manifest.py gate --channel production   # a release build needs a new build number
```

Both test scripts run in the `plan` job of every run of `build-variants.yml` before any
build, need no Flutter, Android SDK or Xcode, and are mutation-tested: each rejection test
names the fragment it expects, so a rule that is silently removed fails a test.
