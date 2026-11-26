# Release-branch build triggers

How a promotion into `staging` or `production` starts the build workflow, which builds it
starts, what its result means, and what GitHub settings it depends on.

**Status: compile validation only.** These triggers build and verify; they do not sign,
upload a binary, tag, publish or deliver anything. Official signing, TestFlight and store
delivery are separate, separately authorized work (see
[RELEASE_IMPLEMENTATION_PLAN.md](RELEASE_IMPLEMENTATION_PLAN.md)). Policy:
[RELEASE_POLICY.md](RELEASE_POLICY.md). Branch authority: [../GOVERNANCE.md](../GOVERNANCE.md).

**The one exception is a separate workflow, not `build-variants.yml`:** a push to `staging` also starts
`ios-staging-delivery.yml`, which signs the iOS staging app and uploads it to the staging TestFlight application,
but only when the staging authorization record says so (committed as WITHDRAWN), and its signing job then waits for the
approval of the protected environment `ios-staging-signing`, whose credential the CTO provisions temporarily for that run. It is
described, with its prerequisites and authorization, in [IOS_STAGING_DELIVERY.md](IOS_STAGING_DELIVERY.md); the workflows below
remain credential-free.

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
| Manual run (Actions → *Build variants* → *Run workflow*), always **MANUALLY GENERATED** | `all`, or exactly one variant | 5, or 1 |

**Every** push to `staging` or `production` runs its branch's builds, whatever it changes: the
planner has no path filter, no change classification and no release-intent input, and the
policy forbids adding any (RELEASE_POLICY.md 2.3). The branch decides **which variants run**. It does not decide what a variant *is*: the
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

Once the workflow file exists on the default branch (`development`; GitHub offers *Run workflow*, and
`gh workflow run`, only for such a workflow, with the inputs of that version):
*Actions → Build variants → Run workflow*, choose a branch and **one** of `all`,
`android-staging-apk`, `ios-staging`, `android-production-apk`, `android-production-aab`,
`ios-production`. A single variant runs only its own build job plus the shared checks
(`static`, and for an Android variant `reject`); the other jobs show *skipped*. Manual
runs do not need, and do not imitate, a promotion: they are for validating a feature
branch, re-checking a variant, or the pre-merge test of workflow changes.

The group names `staging` / `production` are not manual choices; they exist only for pushes.
Two further inputs control retention and nothing else: **retain** (default off) and **recipient**
(an age *public* key; never a secret key). See "Retained artifacts" below. Manual runs take no input that
chooses a commit: the commit built is the commit of the workflow itself (next section).

### Manually generated staging build

A manual run is **the same pipeline as a promotion, started by hand**: the same `plan`, `static`,
`reject`, `android`, `ios` and `verdict` jobs, the same configuration file per environment
(`config/build/<env>.json`), the same flavors and application identities, the same verification
(`tool/verify_artifact.sh`, `tool/build_manifest.py`), the same retention rules. There is no second
build implementation: the build commands exist once, in the jobs both triggers run, and
`tool/test_release_triggers.sh` pins that. Whatever those jobs gain later (a signed Android staging APK,
issue #57; signed iOS staging delivery to TestFlight, issue #71) is gained by both ways of starting them.

What differs is only the trigger, the source and the marking:

| | Promotion (push to `staging`) | Manual run |
|---|---|---|
| Source built | the pushed merge commit | the commit of the workflow itself (`github.sha`) |
| Workflow from | `staging` | for a staging variant: **`development` only** |
| Commit allowed | the merge commit | for a staging variant: **the current tip of `development` only** |
| `source.origin` in every manifest | `automatic` | **`MANUALLY GENERATED`** |
| `source.on_development` | `null` | `true` / `false` (a staging build must be `true`) |
| Run summary | plan table | begins with **MANUALLY GENERATED**, the source commit and "no branch was modified" |
| Uploaded artifact names | `build-evidence_<variant>_a<n>`, `retained_<variant>_a<n>` | `MANUALLY_GENERATED_` in front of both |
| File names (retained bundle, `build_manifest.py name`) | `NON-DISTRIBUTABLE_INTERNAL-EVALUATION_cadena-signer-...` | `MANUALLY_GENERATED_NON-DISTRIBUTABLE_INTERNAL-EVALUATION_cadena-signer-...` |

The marker is a prefix and a manifest field. It is **not** part of the version, the build number, an
application ID or bundle ID, the backend configuration, the Bitcoin network or any signing identity, and
no job reads any of those from it. `source.commit` is the commit that was built, `source.ref` is the branch the workflow was
started from, and `source.on_development` says whether the commit is on `development`; none is ever replaced
to satisfy a validator. A manual run
never writes to `staging`, `production` or any other branch.

**Why only the current tip of `development`.** Every job checks out the workflow's own commit, and the
scripts it then runs (`tool/plan_build_variants.sh`, `verify_artifact.sh`, `build_manifest.py`,
`check_verdict.sh`, the tests) are the ones of that checkout. If a manual run could build an older commit,
it would run that commit's older scripts under today's workflow file: the staging rules, the marking and the
current verification would not be guaranteed (a check of `6f30f11`, from before this feature, showed its
planner, manifest tool and verdict script know nothing of the origin, the schema or the staging rules). So
the workflow and the scripts always come from one commit, and a staging selection is accepted only while that
commit **is** the tip of `development` (GitHub's compare API must report `identical`). A run that is started
from another branch or a tag, a re-run of an older run after `development` moved on, and a run that lost a
race with a merge are all refused before anything is built; start a new run. Building an older revision is
not supported; it can be added later only together with a way to run the current scripts against it.

**How a manual staging build is launched**

1. *Actions → Build variants → Run workflow* (the workflow must be on `development`, the default branch).
2. *Use workflow from*: **`development`**. Any other ref is refused for a staging variant.
3. *variant*: `android-staging-apk`, `ios-staging`, or `all` (`all` contains the staging variants and so
   follows the same rule).
4. *retain* and *recipient*: unchanged (Retained artifacts, below).
5. Run it. The run summary starts with **MANUALLY GENERATED** and the commit built, and the *Source
   commit relative to development* step shows `identical`.

The same with the GitHub CLI (it does the same thing; it does not bypass any rule):

```
gh workflow run build-variants.yml --ref development -f variant=android-staging-apk
```

Production-only manual runs (a single production variant) keep their earlier freedom to run from any ref, are
marked the same way, and deliver nothing; the workflow file and the scripts of that ref are what runs. This
is also the way to try a change to this workflow before it is merged: dispatch a production variant from the
branch (a staging variant is refused there by design).

**Manifest schema.** The two source fields are a new version of the manifest, `cadena-build-manifest/2`.
Every new manifest is written in schema 2, and the build jobs and the verdict (`verify --require-current`,
`verify-dir`) accept nothing else for a run, with both fields required and checked (the origin follows from
the event; a manual staging build must be `on_development`). Every manifest made before this change is
schema 1 and **stays verifiable** under exactly its own rules: `tool/build_manifest.py verify` accepts it, says
that it records no origin, and keeps checking everything else; the file name is the unprefixed canonical name
it always had. A schema-1 manifest may not carry the new fields and a schema-2 manifest may not lack them,
so neither can be turned into the other, and a new manual manifest downgraded to schema 1 no longer fits its
file name. A plain `verify` of a schema-1 file cannot tell a forged downgrade from a historical manifest
(manifests are recorded provenance, not authenticated); the CI paths therefore never accept schema 1. Real
schema-1 files written by the previous tool are kept as test fixtures (`tool/fixtures/manifest-schema1/`).
`tool/verify_ipa.py` accepts a schema-1 build manifest too, because the unsigned build job of a hosted signing
run can use an older commit's tools.

**Which manual run gives an installable APK.** Two workflows can be started by hand, and they do different jobs:

| I want | Start | Result |
|---|---|---|
| **An installable Android staging APK of the current `development`** | *Actions → Android CI validation build → Run workflow*, workflow from `development` | a downloadable, debug-signed, labelled APK (14 days) plus a notice file with the commit SHA, marked **MANUALLY GENERATED** |
| Compile validation of the variants, with manifests and evidence (no binary) | *Actions → Build variants → Run workflow* | verified evidence and manifests, marked **MANUALLY GENERATED** |

The first is the existing workflow that already publishes the APK of a staging merge
([ANDROID_CI.md](ANDROID_CI.md)); a manual run of it is the same build, verification and upload, with two
differences: the MANUALLY GENERATED marking (artifact name, APK file name, notice, run summary) and the rule
above (workflow from `development`, commit still the tip of `development`, decided by the same
`tool/plan_build_variants.sh`; a refused run builds nothing). It runs independently of iOS: nothing in the
iOS jobs can prevent the APK. The APK is the same kind of file a staging merge produces today and is what
that policy already allows: a **debug-signed validation build** (ephemeral CI key, `staging` flavor, staging
configuration, staging icon), installable next to the production app, **not** a release or a signed staging
build. It cannot update an earlier run's APK (each run signs with a new key: uninstall first).

**Why the APK is not published by `build-variants.yml`.** That workflow is the one that keeps artifacts only
encrypted and uploads no plaintext binary (this is pinned by tests and by `CLAUDE.md`). Adding a readable APK
upload to it would need an explicit policy exception. No exception is needed for the route above, because
`android-ci-validation.yml` is the workflow `ANDROID_CI.md` and `RELEASE_POLICY.md` section 3 already allow to
publish a labelled debug-signed validation APK. The policy limits are unchanged and still apply: a
**release-signed** staging APK must not be an ordinary public Actions artifact (`RELEASE_POLICY.md` section
8.2), so Android staging signing and its private delivery channel (#57, reconciling #72) are still open, as
are iOS signing and TestFlight delivery (#71) and the build-number rules (`docs/RELEASE_VERSIONING.md`).
Because the repository is public, any signed-in GitHub account can download this validation APK; it contains
the staging configuration only and no secret.

**Scope: this is not yet a reproduction of all three workflows of a staging merge.** The manual path does
not start `ios-ci-validation.yml`, and `build-variants.yml` and `android-ci-validation.yml` are started
separately, not by one click. No Android signing, no signed APK download, no iOS signing and no TestFlight
upload exist for either path, and nothing in them allocates, increments or consumes a build number: both
ways of starting them build the version in `pubspec.yaml` as it is, so a manual run cannot use up a store
build identity and a later promotion remains possible.

**What a successful `build-variants.yml` manual run is, and is not.** It is exactly what a successful
promotion run of that workflow is today: the staging variants were compiled and verified (identity, version,
staging configuration and icon, signing status), and their evidence and manifests were uploaded; no
plaintext binary is uploaded by it. A successful run that contains only manifests, logs or evidence is **not**
an installable APK and must not be reported as one: use the Android CI validation build for the APK.

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
  - each required variant must have a non-empty evidence file **and manifest**, and **no**
    evidence may exist for any other variant (the "exactly N builds" proof);
  - every manifest must be valid for the checked-out commit and agree with its text evidence,
    and the manifests of the run must agree with each other (one commit, one run, one
    version, unique build identifiers; `tool/build_manifest.py verify-dir`);
  - then the cross-artifact checks: APK/AAB consistency (production), and staging and
    production are different applications on each platform.

The `plan` job first runs `tool/test_release_triggers.sh` (the planner, merge-commit
detection in real shallow clones, the verdict logic, and the workflow's shape: triggers,
selector options, job graph, `always()`, the branch-creation guards, permissions). It needs
only `bash`, `git`, `awk`, `sed` and `grep`, which every GitHub-hosted runner has, so no
package is installed and no YAML parser is involved: the workflow is read as text, and the
test fails when a pinned line is edited, which asks for a deliberate review. It needs no
Flutter and can be run locally. The job then runs `tool/test_release_versioning.sh` (the
version rules, the build manifests and the published-version gate; it also needs `python3`,
present on every runner) and `tool/test_android_release.sh` (the Android release signing and
verification, credential-free and without artifacts, Issue #72; `docs/ANDROID_RELEASE.md`).

## Tests on pull requests (not a build, not a promotion)

`build-variants.yml` never starts from a pull request (above). A separate, test-only workflow,
`.github/workflows/android-release-tests.yml` (Issue #72), does: on every pull request to `development`,
`staging` or `production` it runs the credential-free Android release tests (the verifier and ledgers,
the identity matrix and version wiring, and the release-signing rules in real Gradle dry runs;
`docs/ANDROID_RELEASE.md` section 7). It builds no application, produces no artifact, has read-only
permissions and no secret, and uses `pull_request`, never `pull_request_target`. It is therefore not a
release trigger and does not touch the policy above; `tool/test_android_release.sh` pins its shape and
that `build-variants.yml` still has no `pull_request` trigger. That workflow deliberately has **no path filter**, because a
filter would leave a required check "skipped". The version-advancement check required by RELEASE_POLICY.md 7.3
(not implemented) must follow the same rule: it runs on every pull request into a release branch.

## Concurrency

Every promotion is built; none is superseded. The concurrency group of a push contains
its commit SHA, because GitHub keeps only one *pending* run per group and a plain per-branch
group would silently drop the build of a middle merge. Manual runs of different variants
never cancel each other; repeating the same variant on the same commit replaces the older
run. Runs of the existing Android and iOS validation workflows are independent.

## Evidence and what a green run means

Text evidence (identity, version, signing status, SHA-256, run metadata) and a JSON build
manifest (`tool/build_manifest.py`, see [RELEASE_VERSIONING.md](RELEASE_VERSIONING.md)), one
of each per variant, uploaded per run. **No plaintext application binary is uploaded.** A green
`verdict` means:
the selected variants compiled, were read back as the right application, and nothing else
ran. It does **not** mean the build is installable as an official app, signed, tested on a
device, tagged or approved for release.

## Retained artifacts (Stage 2)

A run can also **keep** the verified artifact, encrypted to public keys, so that a later signing
stage can sign exactly what was verified ([RETAINED_ARTIFACTS.md](RETAINED_ARTIFACTS.md)). The
plan job decides it (`tool/retain_artifact.py plan`): a push to `staging` or `production` retains
only if `config/release/artifact_recipients.txt` lists a key (it is empty: nothing changes for
promotions); a manual run retains when **retain** is ticked, with the committed keys plus an
optional public key in **recipient**. Retention is not a new variant and not a new job: it is the
last steps of the existing build jobs and two extra checks of the `verdict` job, and a run that
retains is green only if every required variant produced a verified bundle. The artifacts are
ciphertext (`retained_<variant>_a<attempt>`, 14 days), so the permissions stay `contents: read`
and no secret or environment is involved.

## Failure handling

- A red run on a release branch does not undo the merge and publishes nothing, because
  nothing is published. Read the failed job's log, fix forward on `development`, and promote
  again through the normal pull request. Do not push to the release branch to "repair" it.
- *Re-run failed jobs* on the same commit is acceptable (the evidence is keyed by run
  attempt). Re-running does not change which variants are required. This is the repair of an
  infrastructure failure of a **compile-only** build. The eventual signed pipeline retries a
  failed delivery with the same retained, verified artifact, with no recompilation and no new
  version, and records each attempt (RELEASE_POLICY.md 2.4, not implemented).
- A defective application or an artifact that fails verification is repaired through source
  control and gets a new version and build number (RELEASE_POLICY.md 2.4).
- A red `plan` job (for example "not a merge commit") means the push was not a promotion in
  the sense above: find out how it reached the branch.
- A red `verdict` with green builds means a job was skipped, missing or unselected-but-run;
  the `::error::` lines name it.

## CI validation versus authorized release distribution

| | This workflow | Release distribution (not implemented) |
|---|---|---|
| Starts on | promotion merge, or manual | promotion merge (the merge is the authorization; no separate step, RELEASE_POLICY.md 2.3) |
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
- `production` was created after this change (Issue #68); until then the entry in the
  trigger list was inert.
- The literal `production` trigger was demonstrated by the first merge into the branch
  (PR #75, run 39237471969: the three production variants). The branch-creation behavior
  depends on GitHub's `created` event field; creating `production` ran no workflow at all,
  because its baseline commit predates the workflow files, so the `created` guard is still
  covered only by the planner tests and by review.

## Verification record

Local: see the pull request. Hosted: recorded in the pull request and in issue #68 after the
runs have completed; this document makes no claim about them.
