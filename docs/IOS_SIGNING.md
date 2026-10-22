# iOS signing and TestFlight delivery (Issue #71)

> **Status: readiness documentation. iOS signing and TestFlight delivery are NOT
> implemented.** No certificate, provisioning profile, App Store Connect API key,
> App Store Connect record, GitHub environment or signing workflow has been created, and
> none may be created from this document alone. The only iOS builds that exist are the
> unsigned compile-validation builds of [IOS_CI.md](IOS_CI.md). This page records what is
> verified, what is approved, and what is still undecided, so that nobody mistakes one
> for another. Parent issue: #54. It follows [RELEASE_POLICY.md](RELEASE_POLICY.md) and
> [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) and adds no rule to
> either.

Every statement below carries one of three labels:

| Label | Meaning |
|---|---|
| **Verified** | Checked in the repository, on GitHub or in Apple's documentation, on the stated date. |
| **Approved** | Decided by the project owners. It is the architecture to build, not a statement of fact about the world. |
| **Unresolved** | Not decided, or not yet confirmable. Nothing may assume an answer. |

## 1. Verified facts (checked 2026-10-21 on `development` `b7e523a`)

### Repository

| Fact | Where |
|---|---|
| Two flavors exist, `staging` and `production`, with their own Xcode schemes and `Debug/Profile/Release-<flavor>` configurations. | `ios/Runner.xcodeproj`, `ios/Flutter/*-staging.xcconfig`, `*-production.xcconfig` |
| Bundle IDs: staging `com.app.cadenabitcoin.staging` ("Cadena Signer STAGING"), production `com.app.cadenabitcoin` ("Cadena Bitcoin"). | `ios/Flutter/Flavor-*.xcconfig` |
| `DEVELOPMENT_TEAM = D65458CPDP` is committed (an identifier, not a secret). The Runner target sets no `CODE_SIGN_STYLE`, profile specifier or signing identity, so Xcode's default (automatic) applies. | `ios/Runner.xcodeproj/project.pbxproj` |
| No entitlements file, no `ExportOptions.plist`, no certificate, profile, `.p8`, keystore or `key.properties` is tracked. | `git ls-files` |
| The app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). `CFBundleShortVersionString` and `CFBundleVersion` come from `pubspec.yaml` (`1.0.3+1000034`). | project, `Info.plist` |
| `Info.plist` has no `ITSAppUsesNonExemptEncryption`. It lists `UIBackgroundModes` `fetch` and `remote-notification` and one `BGTaskSchedulerPermittedIdentifiers` entry; there is no `processing` mode and no push entitlement. The app has no `PrivacyInfo.xcprivacy`. The App Store icon `1024.png` is a JPEG with a `.png` name. | `ios/Runner` |
| `RELEASE_IDENTIFIER` and an in-app staging identifier do not exist yet. | `lib`, `config`, `tool` |
| Both iOS workflows use `contents: read`, no secrets, SHA-pinned actions, `--no-codesign`. They run on `macos-15` with Xcode 26.3. | `.github/workflows`, [IOS_CI.md](IOS_CI.md) |
| The minimum-iOS requirement of [IOS_CI.md](IOS_CI.md) is open: app 14.0, five frameworks 15.5, eight Rust objects 18.5. | [IOS_CI.md](IOS_CI.md) |
| No iOS build number is recorded as published, so no iOS floor is enforced. The published **Android** package is `com.cadenabitcoin.mobile.signer`, which differs from the bundle ID used here. Git history shows the iOS bundle ID has never been anything but `com.app.cadenabitcoin`, so nothing in the repository shows what Apple has registered. | `config/release/published_versions.json`, `git log` |

### GitHub

| Fact | Source |
|---|---|
| The repository is **public**. Run logs and artifacts are readable by any GitHub account. | GitHub API |
| No GitHub environment exists (`total_count` 0). | GitHub API |
| `CadenaBitcoin/Maintainers` has two accounts. **They are controlled by one individual** (statement of the project owner, 2026-10-21), so they are **one** approver, not two. | owner statement; [GOVERNANCE.md](../GOVERNANCE.md) |
| No release maintainers or signing custodians are named. | [GOVERNANCE.md](../GOVERNANCE.md) |

### Apple (documentation read 2026-10-21)

| Fact | Source |
|---|---|
| There are two kinds of App Store Connect API key: team keys ("access to all apps, with varying levels of access based on selected roles") and individual keys ("access and roles of the associated user"). | [Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) |
| "Team keys give access that's not isolated to a single app, but individual key access is tied to the apps and permissions of the user." "Team API keys are applied across all apps, so app access can't be limited for an API key." | same; [App Store Connect Help](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api) |
| Individual keys "aren't able to use Provisioning endpoints, access Sales and Finance, or notaryTool". | [Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) |
| "Each user can only have one active API key at a time." A key's name and access cannot be edited after it is generated. Generating a team key needs the Account Holder or Admin role. Generating an individual key needs the "Generate Individual API Keys" permission, which an Admin can remove. | [App Store Connect Help](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api) |
| The private key can be downloaded **once**; Apple keeps no copy. A revoked key cannot be reinstated. | both pages |
| The role-permission matrix has rows "Upload builds", "Submit apps", "Manage internal TestFlight groups and add builds" and "Manage app access". Certificate and profile tasks are marked as needing access to Certificates, Identifiers & Profiles, "granted as a separate permission in Users and Access". | [Roles](https://developer.apple.com/support/roles/) |
| "Users with the Developer role can create and revoke development certificates, submit certificate signing requests, download provisioning profiles, upload binaries to App Store Connect, manage internal TestFlight users, and more. Their access can be limited to certain apps." | [Developer role](https://developer.apple.com/help/glossary/developer) |
| "If you're enrolled as an individual and add users in App Store Connect, users receive access only to App Store Connect and are not considered part of your team in the Apple Developer Program." | [Developer role](https://developer.apple.com/help/glossary/developer) |

The role matrix's per-role marks could not be extracted from the page text, so **which role may
upload, which may submit for review, and which needs Certificates, Identifiers & Profiles
access is not verified** here (section 4, item 3).

## 2. Approved architecture

Decided by the project owners (Issue #71 audit and approval, 2026-10-21). Staging and
production contexts and the five-artifact target are in [RELEASE_POLICY.md](RELEASE_POLICY.md).

1. **First delivery target: internal-only TestFlight** of a separate staging record. No
   external tester group, no public link, no Beta App Review, no App Store submission.
2. **Separate GitHub environments** for staging and production, each deployable from one
   protected branch only.
3. **No public App Store submission or publication** by any pipeline, ever; production
   signing and production upload each need **separate authorization**.
4. **Controlled signed testing is permitted** to establish runtime compatibility. The
   effective minimum supported iOS version remains an **open release-readiness
   requirement** ([IOS_CI.md](IOS_CI.md)); a production release needs verified runtime
   compatibility, and this issue does not change a deployment target.
5. **Independent approval of production** (section 6).
6. **Assigning a processed build to internal testers needs explicit approval** at first.
   Automatic distribution may be considered only after the pipeline has been verified.
7. **Least-privilege Apple authentication**, with app-restricted individual API
   credentials as the preferred direction. The model is **not final** (section 5).
8. Signed IPAs are never stored as GitHub artifacts, Releases or log content.

## 3. Planned pipeline (proposed; not built; shape subject to a spike)

Everything in this section, and every "will" or imperative in sections 5 to 8, describes the
intended design. None of it exists yet.

```text
push to staging (reviewed PR merge)
  -> build job, NO secrets: dependencies, compile, unsigned archive, digest
  -> signing job, environment staging-ios: sign, export, verify, record evidence
  -> upload to the staging App Store Connect record, read processing state
  -> STOP: a build is assigned to internal testers only after explicit approval
```

- **Two-job split (Proposed).** Everything that downloads or runs third-party code (`pod install`,
  Flutter, Gradle-style fetches) runs in a job with no secrets. The job that holds signing
  material runs only scripts owned and tested in this repository and Apple's own tools, and
  checks the archive digest produced by the first job. The unsigned archive would be a
  one-day artifact (it is the open-source app, like today's unsigned validation artifact).
  **Open technical question:** whether an unsigned archive can be exported and re-signed
  cleanly, or the signing job must codesign and package the IPA itself. A spike on a
  hosted runner with a throwaway self-signed identity (no Apple credentials) answers it. If
  it fails, a single job is the fallback and its extra exposure is documented.
- **New workflow files** (stage T3 of [RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md));
  the unsigned validation workflows keep their meaning.
- **Verification before upload** (`tool/verify_ipa.sh`, to be written): bundle ID, version and
  build number against the manifest and `pubspec.yaml`, Team ID, signing authority and
  certificate fingerprint, provisioning-profile type, team, App ID and expiry, entitlements
  (`get-task-allow` absent), signature integrity. Evidence is text only.
- **Build numbers** stay single-sourced from `pubspec.yaml`. Apple rejects a repeated build
  number, and the pipeline treats that as a hard stop, never as something to work around.
- A static test must fail if any workflow uses `pull_request_target`, or contains a
  review-submission or release call to App Store Connect.

## 4. Unresolved decisions and prerequisites

| # | Item | Needed from |
|---|---|---|
| 1 | Apple account identity, ownership, administrators, renewal | Apple account owner (questionnaire part A) |
| 2 | Whether an iOS app is live, its exact bundle ID, version and highest build number; whether `com.app.cadenabitcoin` is that ID | Apple account owner. **No production signing work starts until this is known.** |
| 3 | The role matrix: which role can upload a build, read processing status, and submit for review; whether a restricted service user can be created without Certificates, Identifiers & Profiles access, and who would hold its Apple ID sign-in | Apple account owner (the live Roles page and Users and Access) |
| 4 | App ID registration and App Store Connect record for `com.app.cadenabitcoin.staging` (not assumed registered) | Apple account owner |
| 5 | Existing distribution certificates, profiles and their custodians; shared or per-context certificates | Apple account owner, signing custodians |
| 6 | Capabilities and entitlements the app really needs (`remote-notification`, background tasks) | Apple account owner, maintainers |
| 7 | Export-compliance answer and App Privacy answers; then `ITSAppUsesNonExemptEncryption` in `Info.plist` (a native-config change, separate approval) | Apple account owner, legal |
| 8 | Internal tester list and who administers the tester group | Apple account owner |
| 9 | Release authority, signing custodians, and a second, independent approver (section 6) | project owners |
| 10 | Release identifier scheme, in-app staging identifier, Signet XPUB/address validation (prerequisites of [RELEASE_POLICY.md](RELEASE_POLICY.md) 8.1) | maintainers; separate issues |
| 11 | Whether the staging environment needs reviewers beyond the protected-branch merge (staging should require approval at first) | project owners |
| 12 | The effective minimum iOS version and its device testing | product decision; [IOS_CI.md](IOS_CI.md) |

## 5. Apple authentication model (investigated; not final)

Goal: the credential in the pipeline must be able to upload a build and read its processing
state, and must **not** be able to submit for review, release, create certificates or touch
another app. The model is **not finalized** before items 2 and 3 of section 4 are confirmed.

| Option | Isolation | Notes |
|---|---|---|
| **A. Team API key** | None: "access to all apps"; only the role limits it | Every team key reaches the production app too. Rejected as the staging credential, because a staging leak would reach production data. |
| **B. Individual API key of a dedicated, app-restricted service user (Preferred, to be confirmed)** | The key has "the access and roles of the associated user", so it is limited to the apps that user may see | One active key per user, so staging and production need **two** service users. No Provisioning endpoints, so it cannot create certificates (an advantage). Needs the "Generate Individual API Keys" permission, and the user's role must allow the upload. |
| C. Admin-level key or Xcode cloud-managed signing | None | Rejected: far above what an upload needs. |
| D. Apple ID app-specific password | A personal account | Rejected. |

Open points the account owner must confirm: that a service user can be restricted to the
staging app only; the lowest role that still shows **Upload builds**; that this role does not
show **Submit apps**; and that the organization accepts a dedicated service user. If B is not
possible, the fallback is the lowest-role team key, with the loss of app isolation recorded
and compensated by reviewer approval on the staging environment.

### Certificates, Identifiers & Profiles (CIP) access

- **The preferred credential cannot reach provisioning.** Individual keys "aren't able to use
  Provisioning endpoints" (section 1). The pipeline therefore can never create or download a
  certificate, a profile or an App ID with it, and it must not be designed to. This is a
  least-privilege advantage, and it has a cost: the distribution certificate, the provisioning
  profiles and the App IDs are created by the Apple account administrator **in the developer
  portal** (a role with CIP access) and handed to the custodians as environment secrets.
  Profiles and certificates expire, so renewal is a **manual administrator task**, scheduled
  in the custody register; the planned `tool/verify_ipa.sh` checks expiry so that a lapse fails
  visibly before an upload.
- **The service user must not receive CIP access.** The Developer role can, with that access,
  create and revoke development certificates and download profiles (section 1). The service
  user exists only to hold an upload-capable individual key limited to the staging app, so it
  gets no CIP access, no user-management permission and no access to other apps.
- **The service user is an Apple ID.** Someone must sign in once, with its second factor, to
  generate the key. Who holds that Apple ID's credentials and second factor, and how they are
  recovered, is a custody question for the account owner (questionnaire B4); the credentials are
  never shared with the pipeline or the repository.
- **Individual enrollment caveat.** If the team is an Individual enrollment, users added in
  App Store Connect are not part of the Developer Program team (section 1). Whether such a user
  can hold the upload role and generate an individual key is unconfirmed, and portal access is
  then limited to the Account Holder. If so, this model may be unavailable and the fallback of
  this section applies. Questionnaire A1 question 1 decides it.

The `.p8` is shown once; it is handed to the custodians through a secure channel, never through
chat, email, issues or the repository.

## 6. Independent approval of production signing and delivery

The two `Maintainers` accounts are controlled by one individual. **Accounts controlled by the same
individual are one approver, however many accounts exist.** Therefore:

- A GitHub environment's "required reviewers" and "prevent self-review" settings **cannot** by
  themselves provide independent approval while every eligible reviewer is the same person.
- **Production signing and production delivery must be approved by a person who is not the
  person who prepared, merged or triggered the run.** At least one such second human must be
  named (release authority or signing custodian) and added as a reviewer of `production-ios`
  **before** any production signing is authorized. Until then production signing stays
  disabled, and the production environment is not created.
- The same custodian separation applies to secrets: nobody is the only holder of a credential
  that can ship the production app (see [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) section 7).
- Staging can start with one human, but should still use a required reviewer so that a run is
  an explicit act. Independence is not claimed for it.

## 7. Public-repository security model

The repository is public. Anyone can read workflow logs, download artifacts, fork, and open
pull requests. The rules below are **requirements for the future signing workflows**. Today's
unsigned validation workflows already use `contents: read`, SHA-pinned actions and no secrets;
no signing workflow, environment or secret exists.

| Threat | Rule |
|---|---|
| Secrets or binaries leaving through logs and artifacts | No IPA, profile, certificate or key in an artifact, Release, comment or log. Only digests, fingerprints and verification text. No `set -x` near secrets. Derived values (a decoded profile, a base64 string) are never printed; masking only covers exact matches. |
| Pull requests from forks and from branches | No secret reaches them. Environments are restricted to one protected branch. No `pull_request_target`, and no `workflow_run` against untrusted code. |
| A contributor with Write access edits a workflow on a branch | The environment's deployment-branch rule refuses it. `staging` and `production` change only by reviewed pull request. |
| Third-party code seeing secrets | Two-job split (section 3). Actions pinned by SHA. No third-party action receives signing material. |
| Unsafe runners | GitHub-hosted, ephemeral runners only. **No self-hosted runner on this public repository.** |
| Credential scope | `GITHUB_TOKEN` is `contents: read`. Secrets only at environment level, never repository or organization level. Environment secrets are administered by Organization Owners only. The keychain is temporary and deleted in an `always()` step. |
| Tokens | A short-lived (20 minutes or less) JWT is derived per run from the `.p8`. |
| Accidental commits | Ask the Organization Owners to enable secret scanning and push protection. |
| Concurrency and duplicates | One upload at a time per environment; a build number already present is refused before upload. |
| Public publication | The credential cannot submit for review (section 5), the workflows contain no such call (tested), and production upload needs independent approval (section 6). |

## 8. Operating procedure (skeleton; every step is planned, none exists yet)

| Who | What |
|---|---|
| **Automated (after the pipeline exists and is approved)** | Build, sign, verify, record evidence, upload to the staging record, report processing state. |
| **Needs explicit authorization** | Starting a staging run (reviewer), assigning a processed build to internal testers (initially), any production signing, any production upload (independent approver). |
| **Apple account administrator (Noah)** | App IDs, App Store Connect records, certificates, profiles, service users and their keys, tester group, agreements and renewal, export-compliance and privacy answers. Not required to build or sign locally. |
| **Cadena maintainers** | Review and merge, workflow changes, environment settings (Owners), custody register (no secrets in the repository). |

- **Failed upload:** read the job's text evidence and the processing state; the commonest
  causes are a repeated build number, an expired or mismatched profile, a missing compliance
  answer, or a validation message from Apple. Fix the cause in a reviewed change; never rerun
  by editing a number outside `pubspec.yaml`.
- **Superseded build:** a newer reviewed version replaces it; the old build is expired in
  TestFlight by the account administrator. Build numbers are never reused.
- **Rotation and revocation:** revoke a leaked `.p8` immediately in App Store Connect (a
  revoked key cannot be reinstated); revoke a leaked certificate and re-sign; rotate secrets
  in the environment; record the event in the private custody register. A recovery drill is
  scheduled as in [RELEASE_SIGNING_ARCHITECTURE.md](RELEASE_SIGNING_ARCHITECTURE.md) section 7.

## 9. What can proceed without Apple credentials

| Work | Notes |
|---|---|
| This documentation and the questionnaire | Stages A and B. |
| Static workflow guards (no `pull_request_target`, no review-submission calls, explicit permissions, pinned actions) | Linux-testable. |
| `tool/verify_ipa.sh` parsing logic on captured `codesign`/`security` fixtures | Linux-testable; separate approval. |
| Signing spike with a throwaway self-signed identity; unsigned archive job; privacy-manifest check of the pods | Hosted macOS run; proves plumbing, not Apple acceptance; separate approval. |
| Release identifier scheme, in-app staging display, Signet validation | Separate issues, partly sensitive code. |
| Everything that needs a real certificate, profile, API key or App Store Connect record | Blocked on section 4 items 1 to 5. |

Questionnaire: [APPLE_ACCOUNT_QUESTIONNAIRE.md](APPLE_ACCOUNT_QUESTIONNAIRE.md).
