# Governance

Cadena Bitcoin Signer is a public, open-source repository, but **official Cadena
project authority remains controlled**. Anyone may read, fork and propose
changes; only explicitly authorized people may merge, promote, release or sign.

> **Status.** This document defines the adopted branch and authority model.
> The branch migration to `development` / `staging` / `production` and the GitHub
> protection rules described below have **not been applied yet**. Until the
> migration is complete, `main` is the legacy GitHub default branch and `staging`
> is the only integration branch; pull requests target `staging` (see
> [Migration status](#migration-status)).

## 1. Authority

Authority is split on purpose. Holding one role never implies another, although
one person may eventually hold several.

| Role | Held by | Authority |
|---|---|---|
| **Repository owner / administration** | `CadenaWizard` | Repository settings, rulesets, access management and collaborator invitations |
| **Authorized maintainers (merge authority)** | `CadenaWizard`, `sziller` | Review and merge accepted changes according to the branch rules; perform promotions |
| **Release authority** | Authorized release maintainers (not yet named) | Decide that a build is an official release and authorize its publication |
| **Signing authority** | Authorized signing custodians (not yet named) | Hold and use application-signing credentials |
| **Public contributor** | Anyone | Fork, open issues, submit pull requests from forks |

No individual release maintainers or signing custodians are named yet; they
must be designated explicitly and are not implied by any other role.

No contribution, review approval or AI assistance transfers merge, promotion,
release, signing, secret or administrative authority.

### Contributors

**Public contributors** may fork the repository, create issues and submit pull
requests from forks. They have no direct write access to the official
repository, no merge authority, and no release, signing or administrative
authority.

**Authorized collaborators / maintainers** are explicitly invited by
`CadenaWizard` and may work directly in the official repository. The repository
belongs to a **personal GitHub account**, so a collaborator receives the
permissions GitHub gives collaborators on such a repository. Collaborator status
is therefore granted only to people trusted at that authority level, and merge
authority remains limited to the authorized maintainers listed above.

Future option: if granular roles are needed (for example trusted contributors
with direct write access but no merge authority), the repository can be moved to
a GitHub Organization and use organization roles and Teams.

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
| `staging` | Signet. Promotion target from `development`; not a place for ordinary feature development. Has a **manually triggered** application build pipeline; branch updates alone must not build or deploy the staging application. Uses staging/Signet configuration. |
| `production` | Mainnet. Promotion target from `staging`, with the strongest protection. It is the official production source. An authorized promotion/merge triggers the **official production application build**. A build does not imply automatic Play Store or App Store publication: store publication remains an explicitly controlled release action. Uses production/Mainnet configuration. |

Rules for all work:

- Normal work branches from the current integration branch (`development` once
  the migration is complete; until then `staging`).
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
- The exact Android and iOS representation of a candidate version will be
  established together with the build pipelines.

Illustrative example only (not a requirement):

```text
staging:     1.3.0-rc.1   1.3.0-rc.2
production:  1.3.0
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
- Until the branch migration is completed, acceptance into `staging` is the
  equivalent completion point. The future model uses `development`; the current
  repository still uses `staging`.
- Pull requests reference their issue with `Implements #N`. Ordinary
  development pull requests do **not** use automatic closing keywords such as
  `fixes #N`, `closes #N` or `resolves #N`. GitHub applies those only when
  merging into the default branch, and they can imply completion or release that
  has not happened.
- Release or production work is tracked in issues that say so explicitly.

## 6. Planned protection (not yet configured)

Separate GitHub rulesets are to be created after this documentation is merged:

- `development`: pull request required; maintainer-controlled merge; block force
  pushes; block deletion.
- `staging`: promotion pull requests only; maintainer-controlled merge; block
  force pushes and deletion; no ordinary feature development.
- `production`: strongest protection; promotion only from `staging`; restricted
  merge and bypass; no ordinary direct pushes; official build trigger.

Until those rules are in force, the review and merge restrictions in this
document are policy, not GitHub-enforced settings.

## 7. AI-assisted changes

AI-assisted or AI-generated changes follow exactly the same contribution,
review, security and merge requirements as human-authored changes. The
submitter remains responsible for the proposed change. See
[CLAUDE.md](CLAUDE.md) and
[docs/AI_DEVELOPMENT_WORKFLOW.md](docs/AI_DEVELOPMENT_WORKFLOW.md) for the
rules that apply to AI tools in this repository.

## Migration status

Not performed. Current state: `main` is the legacy GitHub default branch, stale
and pending migration; `staging` is the active integration branch and the
pull-request target; no `development` or `production` branch exists.

`production` will be initialized only after the authoritative currently released
source commit and artifact lineage are confirmed. The fate of the legacy `main`
branch is decided separately.

## Pending follow-ups

- Create `development`, make it the GitHub default, and establish `staging` as
  promotion-only.
- Establish `production` once release provenance is known.
- Decide what to do with the legacy `main` branch.
- Create the three rulesets in section 6.
- Enable GitHub Private Vulnerability Reporting.
- Designate release maintainers and signing custodians.
- Build and release pipelines, including pipeline-controlled environment
  configuration and the Android/iOS version representation.
- Consider an organization-owned repository if granular roles are needed.
