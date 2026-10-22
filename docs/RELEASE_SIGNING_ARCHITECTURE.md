# Release signing architecture (intended)

> **Status: corrected design for maintainer approval (parent issue #54).
> Signing infrastructure is NOT implemented.** No signing key, certificate,
> provisioning profile, store account setting, API key, GitHub environment or
> release workflow has been created by this work, and none may be created from this
> document alone. It follows [RELEASE_POLICY.md](RELEASE_POLICY.md) (the five
> signed artifacts, the separate staging and production applications) and uses
> the roles of [GOVERNANCE.md](../GOVERNANCE.md). *Decided* = fixed by the project
> owners; *Proposed* = not decided; **DECISION** = needs an explicit answer
> ([section 10](#10-decisions-needed)). The iOS-specific readiness record (verified facts,
> approved architecture, unresolved decisions, the Apple authentication analysis and the
> public-repository security model) is [IOS_SIGNING.md](IOS_SIGNING.md) (Issue #71).

## 1. Starting point (verified in the repository)

| Fact | Source |
|---|---|
| Android `release` signs with the **debug** config | `android/app/build.gradle.kts` |
| No `key.properties`, keystore, certificate or profile is committed (required) | `CLAUDE.md` section 5 |
| iOS uses Automatic signing with a committed `DEVELOPMENT_TEAM` (`D65458CPDP`, an identifier, not a secret); CI builds are `--no-codesign` | `ios/Runner.xcodeproj`, [IOS_CI.md](IOS_CI.md) |
| Android production is `com.cadenabitcoin.mobile.signer`, the package published on Google Play (settled in #72), staging `com.cadenabitcoin.mobile.signer.staging` (not registered). iOS production is `com.app.cadenabitcoin`, staging `com.app.cadenabitcoin.staging`; what Apple has registered is unconfirmed | Gradle, Xcode project, `config/release/published_versions.json`, [IOS_SIGNING.md](IOS_SIGNING.md) |
| The signing identities of the already released app are undocumented | `GOVERNANCE.md` |
| The iOS CI toolchain is Xcode 26.3 with an iOS 26 SDK (Issue #70; status in [IOS_CI.md](IOS_CI.md)); App Store Connect uploads require Xcode 26 and the iOS 26 SDK since 2026-04-28 | [IOS_CI.md](IOS_CI.md); [Apple](https://developer.apple.com/news/upcoming-requirements/) |
| No GitHub environments and no tags. The `production` branch exists (Issue #68). The two `Maintainers` accounts are controlled by one individual, so they are one approver (section 6) | GitHub, checked 2026-10-21 |
| Validation workflows: `contents: read`, no secrets, SHA-pinned actions | [ANDROID_CI.md](ANDROID_CI.md), [IOS_CI.md](IOS_CI.md) |

**Prerequisite.** If the production app is already published, its Android key and
Apple team already exist. They must be inventoried and their holders identified
**before** anything is generated: a new Android key cannot replace the key of
installed apps, and the bundle ID belongs to the Apple team that registered it.

## 2. Two signing contexts, five artifacts

**Decided:** every one of the five artifacts is signed under Cadena-controlled
authority, and staging and production are distinct signing and deployment
contexts: a staging job cannot read production signing material, and the reverse.

| Artifact | Context | Signing material | Identity |
|---|---|---|---|
| Android staging APK | Staging | Android **staging app-signing key** | `<staging application ID>` |
| iOS staging distribution build | Staging | Apple distribution certificate + **staging** App Store provisioning profile | Staging bundle ID |
| Android production APK (website) | Production | Android **official app-signing key** | Production application ID |
| Android production AAB (Google Play) | Production | Play **upload key**; Play re-signs with the official app-signing identity | Production application ID |
| iOS production distribution build | Production | Apple distribution certificate + **production** App Store provisioning profile | Production bundle ID |

### Android: app-signing key vs. Google Play upload key

- The **app-signing key** decides which installs can update which. Loss or
  leakage is effectively permanent. The production APK (website) and the app Play
  delivers must carry the **same** official app-signing identity
  (one update family).
- The **upload key** only authenticates AAB uploads to Play and can be reset
  through Play. It is a different key with different custody, and it can never
  sign an installable APK that devices accept as an update.
- The staging key is different from the production key. Together with the
  different application ID, a staging build can never update, or be updated by,
  production.

### Apple: distribution signing vs. App Store Connect authentication

- **Distribution signing** (an Apple distribution certificate and a provisioning
  profile per bundle ID) makes the binary acceptable to TestFlight and the App
  Store.
- **App Store Connect API key** (issuer ID, key ID, `.p8`) only authenticates
  uploads and TestFlight management. Compromising one does not give the other.
- **Separate application identities (Decided):** staging and production use
  different bundle IDs, different App Store Connect records and different
  provisioning profiles. The distribution certificate **may** be shared at team
  level where appropriate, but sharing it means the staging context holds the
  production signing certificate. **Proposed:** separate distribution certificates
  per context where Apple's per-team certificate limit allows. For authentication,
  Apple's **team** API keys reach every app of the team ("not isolated to a single app"),
  whereas an **individual** key has the access of its user, so a service user restricted to
  one app gives per-context isolation. App-restricted individual keys are the preferred
  direction, and the model is **not final** until the account capabilities are confirmed
  ([IOS_SIGNING.md](IOS_SIGNING.md) section 5). **DECISION** (section 10).

## 3. Android production: one update family across website and Google Play

The APK (website) and the AAB (Google Play) come out of one production merge and
must belong to one update family, with identical `versionName`, `versionCode` and
application ID.

- **Proposed: Cadena-held app-signing key (option A).** Cadena generates and
  guards the key under the custody rules below and enrolls it in Play App Signing;
  the production pipeline signs the APK with it and the AAB with the separate
  upload key. This fits the target that a production merge **produces a signed
  APK**.
- **Option B (Google-held app-signing key)** would make the website APK a
  Play-derived download after upload, so the merge could not itself produce the
  signed APK. It does not fit the target without a manual post-Play step, and it
  makes Google the custodian of the identity. Not recommended.
- If the app is already on Play, only the key lineage already in use is
  acceptable (section 1). **DECISION** (section 10).

**Decided (Issue #72): the Google-held app-signing key stays; the upload key is replaced.**
Google Play App Signing remains enabled and the existing Google-managed app-signing key
(certificate SHA-256 `13:52:D9:EE:…:AC:9F:CB`, recorded in `config/release/android_signing.json`)
is unchanged. The upload key is replaced by a new, CadenaBitcoin-controlled key generated by the
CFO; the old upload key is not used. This is the shape of option B above, with its consequence: a
locally built APK is signed with the upload key, not the app-signing key, so it is **not**
update-compatible with installations from Google Play. The release tools distinguish the two
(`release-local` and `play-signed`). Implementation, verification and the local procedure:
[ANDROID_RELEASE.md](ANDROID_RELEASE.md). Signing in a protected CI environment is still not
implemented.

The pipeline compares the signing-certificate SHA-256 fingerprint of the APK with
the expected fingerprint, and records it in the release record.

## 4. Where credentials live

```text
public repository       : nothing: no keys, certificates, profiles, passwords, .p8, key.properties
protected GitHub envs   : the only place a workflow can read operational secrets
custody register        : private; who holds what, where backups are; no secret values
offline backups        : the irreplaceable material (section 7)
```

**Protected environments (Proposed names; none exist):**

| Environment | Deployable from | Holds | Used for |
|---|---|---|---|
| `staging-android` | `staging` only | Android staging key | Signed staging APK |
| `staging-ios` | `staging` only | Staging distribution signing material, staging profile, ASC API key (staging scope) | Signed staging IPA, TestFlight upload |
| `production-android` | `production` only | Android official app-signing key, Play upload key | Signed APK and AAB |
| `production-ios` | `production` only | Production distribution signing material, production profile, ASC API key (production scope) | Signed production IPA |

For every environment:

- **Deployment branch restriction** to the one branch above, so the credentials
  are unreachable from other branches, pull requests and forks.
- **Required reviewers** from the release authority, with the person who triggered
  the run unable to approve it. Mandatory for the production environments. **Genuinely
  independent approval is required for production signing and delivery:** accounts
  controlled by the same individual are one approver, so at least one other human must be
  a reviewer of `production-ios` before production signing is authorized (section 6).
  Whether the staging environments need reviewers beyond the protected-branch merge
  is open (**DECISION**).
- Secrets only at environment level; none at repository or organization level.
- Administration limited to Organization Owners; secret changes are logged.

Workflow rules (checked in each workflow's pull request):

- Release workflows trigger on push to their protected branch (and manual dispatch
  for re-runs), never on `pull_request` or `pull_request_target`; job permissions
  are explicit and minimal (`contents: write` only where a tag or release record is
  written; `id-token`/`attestations: write` only where provenance is produced).
- Actions pinned by commit SHA (as today); no third-party action receives signing
  material without review.
- Key material is written to the runner's temporary directory, used and deleted;
  secrets never appear in logs, artifacts or the release record.
- **Signed artifacts are not uploaded as public Actions artifacts.** The
  repository is public, so any GitHub account can download a run's artifacts and
  read its logs. Signed APKs and IPAs go only to their authorized destination (for
  iOS staging: restricted TestFlight, which is mandatory; for Android staging: an
  internal mechanism that is not public, still open; see RELEASE_POLICY.md
  section 8). Digests and the release record may be public.
- Changes to release workflows go through protected pull requests reviewed by the
  Maintainers.
- **A merge triggers building and signing. It never publishes publicly.** Uploading
  to the website, Google Play, App Store review or any public channel is a separate
  job or action behind its own approval (RELEASE_POLICY.md section 8). The one
  delivery that belongs to the staging pipeline itself is the mandatory restricted
  TestFlight delivery of the iOS staging build (RELEASE_POLICY.md section 8.1).

## 5. iOS in CI: no local signing, no individual dependency

**Decided:** the Apple Developer account administrator may administer Apple's
signing infrastructure, and must not be required to build or sign locally for the
automated pipeline to operate.

- The pipeline signs in the cloud runner with certificate, profile and API key
  held in the protected environments. Automatic signing does not work on a
  runner; the project is built with manual signing and an export configuration,
  which is a build-configuration change in the implementation plan.
- Apple-side administration (the Apple Developer account administrator) is
  needed for: registering the App IDs and creating the App Store Connect records,
  creating distribution certificate(s) and provisioning profiles, creating the
  App Store Connect API keys and TestFlight groups, accepting agreements,
  renewing the membership. See the implementation plan section 5 for the full list.
- Initial creation of a certificate needs a key pair somewhere. After it is
  exported once and placed into the protected environment by the custodians, no
  one's laptop is part of the build. Renewal and rotation must be possible without
  that one person: **Proposed** to evaluate letting the pipeline create the
  certificate itself through the App Store Connect API (private key generated on
  the runner, stored directly into the environment) so that nobody needs a Mac.
  *Readiness note (Issue #71):* Apple documents that individual API keys cannot use the
  Provisioning endpoints, so certificate creation through the API would need a team key,
  which is not app-isolated. That makes this option less attractive; it stays undecided.
- That role is administration only. If the person holding it becomes unavailable, a
  second Apple account administrator must exist (section 10); the Apple account is
  owned by the Cadena organization, not by an individual.

## 6. Operators and authorization

Roles (GOVERNANCE.md section 1): **Maintainers** review and merge; the **release
authority** decides what is published; **signing custodians** hold and recover
credentials. Today only the first exists; no person is implicitly any other role.
The Apple administrator and the Google Play account owners are account roles to
assign, not implied by any of the above.

Intended flow:

1. A change reaches `development`, then `staging` by approved pull request. The
   merge triggers the **staging pipeline**: verification, build, sign, release
   record; iOS goes to restricted TestFlight (mandatory; whether the upload needs an
   extra approval is a DECISION); the Android staging APK goes to an internal,
   non-public mechanism that is still to be chosen.
2. After testing, a pull request `staging → production` is approved and merged. The
   **production pipeline** starts, waits at the production environments for the
   release authority's reviewer (not the person who merged), then builds and signs
   the APK, AAB and iOS build.
3. Publication (website, Google Play track, App Store submission) is authorized
   separately by the release authority, per channel, and recorded.

Nobody can both trigger and approve a production signing run, and no single
person's account or device is required for a release. **A person with several accounts
is one person**: while every eligible reviewer is the same individual, a production
environment's "prevent self-review" setting does not give independent approval, and
production signing and delivery stay unauthorized until a second, independent human is
named and added as a reviewer. Staging may start with one human, with a required reviewer so
that each run is an explicit act. Assigning a processed iOS build to internal testers needs
explicit approval at first; automatic distribution may be considered after the pipeline is
verified.

## 7. Custody and recovery

For every irreplaceable credential (above all an Android app-signing key under
option A):

- generated once, in a controlled environment, by two custodians, never on a
  shared CI runner;
- stored in at least two independent encrypted offline backups in separate places,
  unlockable only with the cooperation of two custodians;
- the GitHub environment secret is only a working copy that can be re-created from
  the backups; its passphrase differs from the backup passphrases;
- a private custody register (outside the public repository) records holders,
  locations, certificate fingerprints, creation and expiry dates and rotation
  history, with no secret values;
- a recovery drill at least yearly and whenever a custodian leaves: restore from
  backup in a clean environment and sign and verify a test artifact;
- custodians are replaced before leaving; credentials are rotated after an unclean
  departure.

| Credential | If lost | If leaked |
|---|---|---|
| Android production app-signing key | Existing installs cannot be updated by Cadena unless Play can upgrade the key; otherwise users must reinstall | Anyone can ship updates devices accept as official; rotate through Play where possible |
| Android staging key | Re-create; testers reinstall | Re-create; low impact (staging only) |
| Play upload key | Reset through Play support | Rotate via Play |
| Apple distribution certificate | Revoke and re-create | Revoke; re-sign and re-upload |
| App Store Connect API key | Create a new one | Revoke immediately |

## 8. Provenance of signed artifacts

For each of the five artifacts the pipeline produces:

- the artifact and its SHA-256 digest;
- the **release record** (RELEASE_POLICY.md section 9), including the signing
  certificate fingerprint, build configuration, toolchain, commit and run;
- a **GitHub artifact attestation** (build provenance) binding digest, repository,
  workflow, commit and run (a pinned attestation action, chosen at implementation);
- a **signed annotated tag** named by the release identifier (`vX.Y.Z-rc.N` on
  `staging`, `vX.Y.Z` on `production`), never embedded in the app. **DECISION**:
  who creates it. Tag creation under `v*` should be restricted to the release
  workflow identity.

Anyone must be able to answer from public data: which commit produced the
artifact, with which configuration and toolchain, signed by which certificate,
approved by whom, and sent to which channel.

## 9. Verification inside the pipelines

1. The trigger branch matches the configuration: `staging` ⇒ staging configuration
   and a release identifier; `production` ⇒ production configuration and none.
2. `tool/verify_version.sh --channel <branch> --release-id <id>` passes; the
   identifier's numeric part equals the product version; the tag does not exist.
3. Configuration is complete and consistent, and equals the flavor; the build fails
   rather than defaulting (RELEASE_POLICY.md section 6).
4. Committed native binaries match their recorded SHA-256 (as the iOS CI already
   does for the Rust static library).
5. After building: the artifact's application/bundle ID, version fields and
   identifier equal the policy matrix; the AAB and APK share `versionName`,
   `versionCode` and ID; the signing certificate fingerprint equals the expected
   one for that context; a debug certificate is never accepted; a staging
   artifact never contains the production ID, backend or network, and the reverse.

## 10. Decisions needed

1. Name release maintainers, the release authority, at least two signing
   custodians and a second Apple account administrator.
2. Inventory the existing signing identities and account ownership (Apple team
   `D65458CPDP`, Play Console, any Android keystore), confirming they belong to the
   Cadena organization.
3. Android: option A (recommended) or B.
4. Apple: shared or per-context distribution certificate; API key scope; whether
   the pipeline may create certificates through the API.
5. Whether staging environments need approvers (Issue #71 proposal: yes at first);
   whether the staging TestFlight upload (itself mandatory) is automatic on merge or needs
   an extra approval. **Decided (Issue #71):** assigning a processed build to internal
   testers needs explicit approval at first. Also the internal, non-public mechanism for the
   Android staging APK.
6. Who creates tags and with which identity.
7. Whether secrets live as GitHub environment secrets, or the keys stay in an
   external key service reached with short-lived OIDC credentials (later
   hardening).
8. Whether iOS signing uses manually managed secrets or a tool such as fastlane
   `match`, which adds a private repository to protect.
9. **The second, independent approver** for production signing and delivery (section 6),
   and who holds each signing role. A prerequisite of any production signing.
10. **The Apple authentication model** (individual key of an app-restricted service user,
    preferred, or the lowest-role team key), after the account owner has confirmed the
    permissions ([IOS_SIGNING.md](IOS_SIGNING.md) section 5).

## 11. Out of scope here

Generating any credential, creating environments, secrets, accounts, App IDs or
App Store Connect records, changing Gradle or the Xcode project, writing release
workflows, and publishing anything. Each is a separate, explicitly approved issue
([RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md)).
