# Governance

Cadena Bitcoin Signer is a public, open-source repository, but **official Cadena
project authority remains controlled**. Anyone may read, fork and propose
changes; only explicitly authorized people may merge, promote, release or sign.

> **Status.** The repository is owned by the `CadenaBitcoin` GitHub
> Organization. `development` is the GitHub default and active integration
> branch; `staging` is a protected promotion branch. GitHub rulesets enforce the
> maintainer-controlled pull-request workflow on both branches. `production` has
> not yet been created because authoritative release provenance must be
> established first.

## 1. Authority

Authority is split on purpose. Holding one role never implies another, although
one person may eventually hold several.

| Role | Held by | Authority |
|---|---|---|
| **Organization ownership / administration** | `CadenaBitcoin` Organization Owners | Organization and repository administration, access management and governance settings |
| **Authorized maintainers (merge authority)** | `CadenaBitcoin/Maintainers`: `CadenaWizard`, `sziller` | Review and merge accepted changes according to the branch rules; perform promotions |
| **Authorized contributors** | `CadenaBitcoin/Contributors` | Work directly on normal repository work branches and submit pull requests; no protected-branch merge authority |
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
| `staging` | Signet promotion branch. Promotion target from `development`; not a place for ordinary feature development. It is protected now. The intended staging build is manually triggered once the build pipeline is established; branch updates alone must not deploy the staging application. |
| `production` | Planned Mainnet release branch and promotion target from `staging`. It has **not yet been created** because authoritative production source/artifact provenance must be established first. When established, it will receive the strongest protection and drive the official production build; store publication remains a separately controlled release action. |

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

`production` protection will be configured when that branch is established
after release provenance is known.

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
- `staging` is a protected promotion branch;
- the `Maintainers` and `Contributors` Teams provide the technical access model;
- branch rulesets enforce Maintainer-controlled pull-request merges on
  `development` and `staging`; and
- GitHub Private Vulnerability Reporting is enabled.

`main` remains a legacy branch and is not an integration or promotion target.

`production` has not been created. It will be initialized only after the
authoritative currently released source commit and artifact lineage are
confirmed.

## Pending follow-ups

- Establish `production` once release provenance is known, then configure its
  protection and release/build semantics.
- Decide what to do with the legacy `main` branch.
- Designate release maintainers and signing custodians.
- Build the CI, staging and production release pipelines, including
  pipeline-controlled environment configuration and Android/iOS version
  representation.
- Where useful, add required CI/status checks and automated promotion-source
  verification to the branch rulesets.
