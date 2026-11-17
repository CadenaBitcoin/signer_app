# Governance

Cadena Bitcoin Signer is a public, open-source repository, but **official Cadena
project authority remains controlled**. Anyone may read, fork and propose
changes; only explicitly authorized people may merge, promote, release or sign.

> **Status.** The repository is owned by the `CadenaBitcoin` GitHub
> Organization. `development` is the GitHub default and active integration
> branch; `staging` and `production` are protected promotion branches. GitHub
> rulesets enforce the maintainer-controlled pull-request workflow on all three
> branches. `production` was created at the adopted initial baseline `7b63c97`
> (Issue #68).

## 1. Authority

Authority is split on purpose. Holding one role never implies another, although
one person may eventually hold several.

| Role | Held by | Authority |
|---|---|---|
| **Organization ownership / administration** | `CadenaBitcoin` Organization Owners | Organization and repository administration, access management and governance settings |
| **Authorized maintainers (merge authority)** | `CadenaBitcoin/Maintainers`: `CadenaWizard`, `sziller` | Review and merge accepted changes according to the branch rules; perform promotions |
| **Authorized contributors** | `CadenaBitcoin/Contributors` | Work directly on normal repository work branches and submit pull requests; no protected-branch merge authority |
| **Release authority** | The authorized merge into `staging` or `production` ([docs/RELEASE_POLICY.md](docs/RELEASE_POLICY.md) principle 9 and section 2.3), made through the CTO-controlled account `CadenaWizard` after `sziller` prepared the pull request | The merge authorizes that branch's complete pipeline; there is no further manual authorization |
| **Signing authority** | Signing credentials live in protected, branch-restricted environments, not in a person's account. Continuity custodians are not yet named | Hold and recover application-signing credentials |
| **Public contributor** | Anyone | Fork, open issues, submit pull requests from forks |

No continuity signing custodians are named yet; they must be designated explicitly and are
not implied by any other role. They hold and recover credentials; they are not an approval step.

**The authorized merge is the single human authorization boundary**
([docs/RELEASE_POLICY.md](docs/RELEASE_POLICY.md) principle 9 and section 2.3). `sziller`
(development and pull-request preparation) and `CadenaWizard` (CTO-controlled review and merge
authorization) are **the same person**. GitHub does not let an author approve their own pull
request, which is why there are two accounts. This repository neither requires nor pretends that
they are independent human reviewers, and no document, release record or workflow may say so.
Mandatory automated checks, not a second human, protect a release.

No contribution, review approval or AI assistance transfers merge, promotion,
release, signing, secret or administrative authority.

### Contributors

**Public contributors** may fork the repository, create issues and submit pull
requests from forks. They have no direct write access to the official
repository, no merge authority, and no release, signing or administrative
authority.

**Authorized contributors** are Organization members assigned to the
`CadenaBitcoin/Contributors` team. That team has repository `Write` access, so
contributors may create and push normal work branches directly in the official
repository and submit pull requests without maintaining a personal fork. They
do not have authority to update or merge protected lifecycle branches.

**Authorized maintainers** are members of the `CadenaBitcoin/Maintainers` team.
That team has repository `Maintain` access and is the technical review and merge
authority for protected branches. Organization ownership or company authority
does not by itself imply routine technical approval authority.

The Organization base repository permission is `Read`. Repository access should
normally be granted through Teams rather than permanent individual grants.

## 2. Branch model

```text
issue / feature branch
        ↓
development
        ↓
staging
        ↓
production
```

| Branch | Role |
|---|---|
| `development` | GitHub default branch and normal pull-request target. The active integration branch and normal issue completion point. Ordinary issues are **Done** when accepted into it, unless the issue explicitly carries staging or production scope. It does **not** automatically produce or deploy distributable application builds. Automatic CI verification (analyze, tests) may be added later and is distinct from application builds. |
| `staging` | Signet promotion branch. Promotion target from `development`; not a place for ordinary feature development. It is protected now. The intended design is that a merge triggers the staging build pipeline, which builds and signs the staging artifacts (Android and iOS, a separate staging application on Signet) for restricted internal testing. The merge is the authorization to run the complete staging pipeline: advance the build version, build, verify, sign, deliver to the internal testing destinations and record. See [docs/RELEASE_POLICY.md](docs/RELEASE_POLICY.md) section 2.3. Today only unsigned, compile-only workflows run on `staging`: the CI validation workflows and the two-build `build-variants` workflow ([docs/RELEASE_TRIGGERS.md](docs/RELEASE_TRIGGERS.md)). |
| `production` | Mainnet release branch and promotion target from `staging`. It exists and is protected. It was created at the adopted initial baseline `7b63c97` (Issue #68), the best-supported historical commit and not an exact reconstruction of the published application. A merge into it triggers the production build pipeline (Android APK, Android AAB, iOS). Today only unsigned, compile-only workflows run on `production` ([docs/RELEASE_TRIGGERS.md](docs/RELEASE_TRIGGERS.md)); the intended design is that a merge is the authorization to run the complete production pipeline (build, retain, verify, sign, verify again, upload to the configured non-public destinations, record; [docs/RELEASE_POLICY.md](docs/RELEASE_POLICY.md) section 2.3), with no further manual authorization. Automatic App Review submission and public publication are outside the configured scope; Apple's and Google's own review and acceptance still apply. Creation requirements and the promotion procedure: [docs/RELEASE_POLICY.md](docs/RELEASE_POLICY.md) section 2. |

Rules for all work:

- Normal work branches start from the current `development` branch.
- No direct normal development commits to `development`, `staging` or
  `production`; changes arrive by pull request.
- A pull request needs review before merge, and merge is by an authorized
  maintainer.
- No force-push to shared authoritative branches during normal development.
- Issue branches are deleted after a successful merge unless deliberately kept.
- Historical and reference branches (for example older cryptlib or Firebase
  work) are not merged mechanically and are not promotion sources.

## 3. Promotion invariant

Application logic is **not** developed independently on `staging` or
`production`. Source changes originate through `development` and are promoted
sequentially:

```text
development → staging → production
```

Promotion is a pull request between adjacent branches, merged by an authorized
maintainer. Environment differences must be explicit and controlled, and must
not become arbitrary source divergence.

It must be possible to prove whether a staging build and a production build
contain identical application logic. The authority is the **exact source Git
commit SHA and build provenance**, not the displayed version number.

Known gap: today the environment is selected by constants in
`lib/src/ui/controllers/appController.dart` (the committed values are the
production ones). A pipeline-controlled configuration mechanism is needed so
promotion does not require editing source. It belongs to the build and release
pipeline work.

## 4. Versions and provenance

- The **production version is authoritative.**
- Every staging build targets a defined future production version.
- Several staging builds may exist for one target production release.
- Staging builds need an unambiguous candidate/build identifier.
- Every staging and production artifact must record its exact Git commit SHA.
- Build numbers / version codes are managed monotonically.
- **Product version, platform build number and release identifier are three
  different things.** The product version `X.Y.Z` is the same on Android and iOS
  for one release and is always numeric. Build numbers may differ between the
  platforms where necessary. The release identifier names a staging candidate
  (`vX.Y.Z-rc.N`) or a production release (`vX.Y.Z`); it is shown by the staging
  apps and recorded in release metadata, never in Apple's numeric version fields.
- Staging and production are different applications with different application
  identities, backends and Bitcoin networks. The five signed artifacts, the
  version rules, the release record and the distinction between CI validation
  builds, pipeline builds and independent builds are defined in
  [docs/RELEASE_POLICY.md](docs/RELEASE_POLICY.md). Signing is described in
  [docs/RELEASE_SIGNING_ARCHITECTURE.md](docs/RELEASE_SIGNING_ARCHITECTURE.md) and
  the order of work in
  [docs/RELEASE_IMPLEMENTATION_PLAN.md](docs/RELEASE_IMPLEMENTATION_PLAN.md).

Illustrative example only (not a requirement):

```text
release identifier     embedded product version + build
staging:     v1.3.0-rc.1    1.3.0 (build 1000101)
             v1.3.0-rc.2    1.3.0 (build 1000102)
production:  v1.3.0         1.3.0 (build 1000103)
```

Every built artifact must eventually record enough to identify its environment,
public version, build number, exact source commit, build date and
pipeline/run identifier. The Git SHA and provenance are what prove two
artifacts contain the same application logic.

## 5. Issues and completion

```text
issue
  ↓
work branch
  ↓
pull request: "Implements #N"
  ↓
development
  ↓
a maintainer explicitly closes the issue
```

- Normal development is complete when accepted into `development`, unless the
  issue explicitly includes staging or production scope.
- Pull requests reference their issue with `Implements #N`. Ordinary
  development pull requests do **not** use automatic closing keywords such as
  `fixes #N`, `closes #N` or `resolves #N`. GitHub applies those only when
  merging into the default branch, and they can imply completion or release that
  has not happened.
- Release or production work is tracked in issues that say so explicitly.

## 6. GitHub-enforced branch protection

`development` and `staging` are protected by a combination of GitHub rulesets
and classic branch protection rules.

For each branch, a classic branch protection rule:

- uses **Restrict who can push to matching branches**;
- allows only the `CadenaBitcoin/Maintainers` team to update the branch; and
- does not allow administrators to bypass the protection.

This prevents Contributors with repository `Write` access from merging into or
otherwise updating `development` or `staging`, while allowing them to create and
push ordinary work branches.

Active rulesets additionally restrict deletion and block force pushes.

A separate pull-request policy ruleset for each branch requires:

- a pull request before merge;
- at least one approving review;
- at least one approving review from `CadenaBitcoin/Maintainers` for changes
  matching `**`;
- stale approvals to be dismissed when new reviewable commits are pushed; and
- all review conversations to be resolved before merge.

This permits authorized Contributors to work directly on ordinary repository
branches while preventing them from updating or merging into `development` or
`staging`.

`production` has its own pair of rulesets (a pull-request policy and a protection
ruleset). They require a pull request with an approval from
`CadenaBitcoin/Maintainers`, allow merge commits only, and block deletion and
force pushes; none of the release-branch rulesets has a bypass actor.

## 7. AI-assisted changes

AI-assisted or AI-generated changes follow exactly the same contribution,
review, security and merge requirements as human-authored changes. The
submitter remains responsible for the proposed change. See
[CLAUDE.md](CLAUDE.md) and
[docs/AI_DEVELOPMENT_WORKFLOW.md](docs/AI_DEVELOPMENT_WORKFLOW.md) for the
rules that apply to AI tools in this repository.

## Current repository state

The governance migration has been performed:

- the repository is owned by the `CadenaBitcoin` GitHub Organization;
- `development` exists and is the GitHub default / active integration branch;
- `staging` and `production` are protected promotion branches;
- the `Maintainers` and `Contributors` Teams provide the technical access model;
- branch rulesets enforce Maintainer-controlled pull-request merges on
  `development`, `staging` and `production`; and
- GitHub Private Vulnerability Reporting is enabled.

`main` remains a legacy branch and is not an integration or promotion target.

`production` was created at the adopted initial baseline `7b63c97` after the
released source lineage was examined (Issue #68). The baseline is the
best-supported historical commit, not an exact reconstruction of the published
application. The Android application ID of the repository was brought in line with
the published Google Play package in Issue #72; the signing lineage is still open.

## Pending follow-ups

- Establish the production release/build semantics: the branch exists
  (Issue #68), but its pipeline is compile-only and signing and publication are
  not established.
- Decide what to do with the legacy `main` branch.
- Designate continuity signing custodians (no approval role).
- Build the staging and production release pipelines (five signed artifacts), the
  explicit pipeline-controlled build configuration, the separate staging
  application identities and the signing infrastructure, in the order of
  [docs/RELEASE_IMPLEMENTATION_PLAN.md](docs/RELEASE_IMPLEMENTATION_PLAN.md).
- Where useful, add required CI/status checks and automated promotion-source
  verification to the branch rulesets.
