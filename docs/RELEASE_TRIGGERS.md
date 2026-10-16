# Release-branch build triggers

How a promotion into `staging` or `production` starts the build workflow, which builds it
starts, what its result means, and what GitHub settings it depends on.

**Status: compile validation only.** These triggers build and verify; they do not sign,
upload a binary, tag, publish or deliver anything. Official signing, TestFlight and store
delivery are separate, separately authorized work (see
[RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md)). Policy:
[RELEASE_POLICY.md](RELEASE_POLICY.md). Branch authority: [../GOVERNANCE.md](../GOVERNANCE.md).

## What starts what

Workflow: `.github/workflows/build-variants.yml`. The mapping lives in one place,
`tool/plan_build_variants.sh`.

| Event | Variants built | Count |
|---|---|---|
| Push to `development` (including every merged feature PR) | none | 0 |
| Push to a feature branch, tag, or any pull-request event | none | 0 |
| **Push to `staging`** (a promotion merge) | `android-staging-apk`, `ios-staging` | **2** |
| **Push to `production`** (a promotion merge) | `android-production-apk`, `android-production-aab`, `ios-production` | **3** |
| The push that **creates** `staging` or `production` | none (every job is skipped) | 0 |
| Manual run (Actions → *Build variants* → *Run workflow*) | `all`, or exactly one variant | 5, or 1 |

The branch decides **which variants run**. It does not decide what a variant *is*: the
application identity and environment of every build still come from its explicit `--flavor`
and `config/build/<env>.json`, and the build fails if the two disagree
([BUILD_CONFIGURATION.md](BUILD_CONFIGURATION.md)). A push to `staging` cannot build a
production variant, and the planner refuses to if its own catalogue were ever edited that way.

## Why a push trigger, and what it relies on

A "promotion" is a pull request merged into a protected release branch. The workflow listens
to the resulting **push** to that branch rather than to `pull_request`, because:

- the push event carries the exact merged commit, which is what the builds must compile;
- `pull_request` events fire for unmerged closures, for forks and for every PR update, and
  would need extra logic to tell a merge from a closure.

A push is a reliable representation of an authorized promotion **only while the branch
rules hold**. The repository rulesets currently active on `staging` (readable through the
public rules API) are: pull request required with one approving review from the
`Maintainers` team and only the **merge** method allowed (`staging PR policy`), and deletion
and non-fast-forward (force push) blocked (`staging protection`). `development` has the same.

This change modifies no ruleset. The effective rulesets, including bypass actors, are to be
verified through authorized GitHub administration **before any live promotion**.

Required settings for `staging`, and for `production` before it is created:

1. Pull request required, at least one approval from `CadenaBitcoin/Maintainers`, review
   threads resolved.
2. Merge method **merge commit** only (no squash, no rebase).
3. Deletion and force push blocked.
4. **No bypass actors.** Whoever can bypass the pull-request rule can push directly, and
   that push would start these builds. The bypass list is not readable without
   administrator rights, so it is **not verified by this document**; a maintainer must check
   it. Release authority is not delegated to the workflow.
5. `production` only: creation restricted to authorized maintainers (see "Creating a release
   branch").

Defence in depth in the workflow: the `plan` job refuses a push whose commit is not a
merge commit (exactly two parents), because the allowed merge method produces nothing else.
**This is a safety net, not the control.** The control is the branch rules above; a merge
commit can also be made locally and pushed by someone the rules let through.

How the parents are counted: `tool/commit_parents.sh` reads the `parent` lines from the
header of the commit object (`git cat-file commit`). `git rev-list --parents` must not be
used: the default checkout is shallow (depth 1) and there it reports **no** parents for a
genuine merge commit (observed: commit `40d05f6`, a real two-parent merge, shows none with
`rev-list` and 2 with the script). The script stops reading at the end of the header, so
a commit message containing a line that starts with `parent ` is not miscounted. If the
parents cannot be determined the step fails and nothing runs (fail closed). Zero parents
(an initial commit), one parent (an ordinary commit) and three or more (an octopus merge)
are all refused; the tests run every case in a real depth-1 clone.

Things that deliberately start nothing: `development` activity, feature-branch pushes (use a
manual run), tags (the branch filter does not match them, and the planner checks the full
ref, so a tag named `staging` is refused), unmerged or closed pull requests, and a push
that carries a variant selection.

## Manual execution

Any ref, once the workflow file exists on the default branch (`development`):
*Actions → Build variants → Run workflow*, choose a branch and **one** of `all`,
`android-staging-apk`, `ios-staging`, `android-production-apk`, `android-production-aab`,
`ios-production`. A single variant runs only its own build job plus the shared checks
(`static`, and for an Android variant `reject`); the other jobs show *skipped*. Manual
runs do not need, and do not imitate, a promotion: they are for validating a feature
branch, re-checking a variant, or the pre-merge test of workflow changes.

The group names `staging` / `production` are not manual choices; they exist only for pushes.

## One implementation, three decision points

- **Builds:** written once, in the `android` and `ios` jobs. The `plan` job hands them their
  matrix. A push and a manual run use the same jobs.
- **Plan** (`tool/plan_build_variants.sh`): trigger → variants. Exits non-zero, and runs
  nothing, for an unsupported event, an unsupported ref, a push without a merge commit, a
  push that carries a selection, an unknown variant, or a count/environment that does not
  match the branch (exactly 2 staging, exactly 3 production).
- **Verdict** (`tool/check_verdict.sh`, run by the `verdict` job with `if: always()`):
  - every **required** job must be `success`; failed, cancelled and *unexpectedly skipped*
    all fail the run;
  - every job that was **not selected** must be `skipped`; one that ran anyway fails the
    run, so "intentionally unselected" and "missing" stay distinct;
  - each required variant must have a non-empty evidence file, and **no** evidence may exist
    for any other variant (the "exactly N builds" proof);
  - then the cross-artifact checks: APK/AAB consistency (production), and staging and
    production are different applications on each platform.

The `plan` job first runs `tool/test_release_triggers.sh` (the planner, merge-commit
detection in real shallow clones, the verdict logic, and the workflow's shape: triggers,
selector options, job graph, `always()`, the branch-creation guards, permissions). It needs
only `bash`, `git`, `awk`, `sed` and `grep`, which every GitHub-hosted runner has, so no
package is installed and no YAML parser is involved: the workflow is read as text, and the
test fails when a pinned line is edited, which asks for a deliberate review. It needs no
Flutter and can be run locally.

## Concurrency

Every promotion is built; none is superseded. The concurrency group of a push contains
its commit SHA, because GitHub keeps only one *pending* run per group and a plain per-branch
group would silently drop the build of a middle merge. Manual runs of different variants
never cancel each other; repeating the same variant on the same commit replaces the older
run. Runs of the existing Android and iOS validation workflows are independent.

## Evidence and what a green run means

Text evidence only (identity, version, signing status, SHA-256, run metadata), one file per
variant, uploaded per run. **No application binary is uploaded.** A green `verdict` means:
the selected variants compiled, were read back as the right application, and nothing else
ran. It does **not** mean the build is installable as an official app, signed, tested on a
device, tagged or approved for release.

## Failure handling

- A red run on a release branch does not undo the merge and publishes nothing, because
  nothing is published. Read the failed job's log, fix forward on `development`, and promote
  again through the normal pull request. Do not push to the release branch to "repair" it.
- *Re-run failed jobs* on the same commit is acceptable (the evidence is keyed by run
  attempt). Re-running does not change which variants are required.
- A red `plan` job (for example "not a merge commit") means the push was not a promotion in
  the sense above: find out how it reached the branch.
- A red `verdict` with green builds means a job was skipped, missing or unselected-but-run;
  the `::error::` lines name it.

## CI validation versus authorized release distribution

| | This workflow | Release distribution (not implemented) |
|---|---|---|
| Starts on | promotion merge, or manual | promotion merge, then a separate authorized step |
| Signing | none (Android temporary debug key, iOS unsigned) | official keys in protected environments |
| Output | text evidence | signed artifacts, TestFlight / Play / website |
| Authority | `contents: read`, no secrets | maintainers; see the signing architecture |

## Other workflows on a push to `staging`

`android-ci-validation.yml` and `ios-ci-validation.yml` also trigger on a push to `staging`
(the release plan, decision T4, keeps them until it is decided otherwise; they are not
changed by this work). A staging merge therefore starts **three workflow runs**:

| Workflow | Starts on a staging merge | Builds |
|---|---|---|
| `build-variants.yml` (this document) | yes | exactly **two** variants: `android-staging-apk`, `ios-staging` (verified, evidence only) |
| `android-ci-validation.yml` | yes, independently | a staging debug APK (kept 14 days, labelled not for distribution) |
| `ios-ci-validation.yml` | yes, independently | an unsigned staging `Runner.app` (kept 14 days) |

"Exactly two" describes the release-variant builds of `build-variants.yml` only. It is
**not** a statement that only two application compilations happen across all GitHub
workflows on a staging merge. The validation workflows are a separate, older check; they
neither feed into nor depend on this workflow's verdict.

## Creating a release branch

Creating `production` (or `staging`) is a push, but it is not a promotion and starts no
build: the push event says `created: true`, every job of this workflow is skipped
(`plan`, `static` and `verdict` carry the guard `!(push && github.event.created)`, and the
build jobs depend on `plan`), and the planner independently refuses a creation push if it
were ever reached. The **first pull-request merge after the creation** is the first
promotion and starts the three production builds. The creation itself still needs
authorization: this change does not create the branch, and the rulesets must restrict who
can.

## First runs and what cannot be pre-tested

- A push runs the workflow file **as it is on the pushed commit**. The first promotion that
  brings this file to `staging` therefore starts it on that very merge.
- `production` does not exist and is not created by this change. The entry in the trigger
  list is inert until it does.
- The literal `production` trigger cannot be demonstrated on GitHub before the branch
  exists and receives its first merge; until then it is covered by the planner tests and by
  review. The branch-creation behavior depends on GitHub's `created` event field and is
  likewise demonstrated only by the real creation (a skipped run is the expected result).

## Verification record

Local: see the pull request. Hosted: recorded in the pull request and in issue #68 after the
runs have completed; this document makes no claim about them.
