#!/usr/bin/env bash
# Tests the release-trigger logic of .github/workflows/build-variants.yml without compiling
# anything (run from anywhere; it is run by the `plan` job before every other job):
#
#   1. tool/plan_build_variants.sh   which variants each event/branch requires, and what it refuses
#   2. tool/commit_parents.sh        merge-commit detection, in real shallow clones
#   3. tool/check_verdict.sh         failure propagation of the aggregate verdict
#   4. the workflow definition       triggers, selector options, job graph, guards, permissions
#
#   tool/test_release_triggers.sh
#
# Needs only bash, git, awk, sed and grep (all on every GitHub-hosted runner): no YAML parser
# and no package installation. Part 4 reads the workflow as text and is meant to fail when the
# lines it pins are edited, so that such an edit gets a deliberate review.
# Exit 0 only if every check passes.
# The workflow lines pinned by part 4 contain literal ${{ ... }} and $VAR text on purpose.
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plan="$root/tool/plan_build_variants.sh"
parents_tool="$root/tool/commit_parents.sh"
verdict="$root/tool/check_verdict.sh"
workflow="$root/.github/workflows/build-variants.yml"

pass=0
failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

STAGING="android-staging-apk ios-staging"
PRODUCTION="android-production-apk android-production-aab ios-production"
ALL="android-staging-apk ios-staging android-production-apk android-production-aab ios-production"

# --- 1. planner ----------------------------------------------------------------------------
# plan_ok NAME "EXPECTED VARIANTS" ARGS...   : exits 0 and selects exactly those variants
plan_ok() {
  local name="$1" expected="$2" out rc got count
  shift 2
  out="$("$plan" "$@" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then bad "$name" "exit $rc: $out"; return; fi
  got="$(printf '%s\n' "$out" | sed -n 's/^variants=//p')"
  count="$(printf '%s\n' "$out" | sed -n 's/^count=//p')"
  # shellcheck disable=SC2086
  set -- $expected
  if [ "$got" = "$expected" ] && [ "$count" = "$#" ]; then ok "$name"; else bad "$name" "variants='$got' count='$count', expected '$expected'"; fi
}
# plan_rejected NAME ARGS... : exits 2 (refused) and prints no plan
plan_rejected() {
  local name="$1" out rc
  shift
  out="$("$plan" "$@" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$out" ]; then ok "$name"; else bad "$name" "exit $rc, output '$out'"; fi
}

# push ARGS: EVENT REF VARIANT PARENTS CREATED
plan_ok "push to staging (merge commit) -> the 2 staging builds" "$STAGING" push refs/heads/staging "" 2 false
plan_ok "push to production (merge commit) -> the 3 production builds" "$PRODUCTION" push refs/heads/production "" 2 false
for v in $ALL; do
  plan_ok "manual $v -> only $v" "$v" workflow_dispatch refs/heads/issue/68-x "$v"
done
plan_ok "manual all -> all five" "$ALL" workflow_dispatch refs/heads/development all
plan_ok "manual selection does not depend on the ref" "ios-staging" workflow_dispatch refs/tags/v1 ios-staging

plan_rejected "push to development starts nothing" push refs/heads/development "" 2 false
plan_rejected "push to a feature branch starts nothing" push refs/heads/issue/68-release-branch-triggers "" 2 false
plan_rejected "push to main starts nothing" push refs/heads/main "" 2 false
plan_rejected "a tag named staging is not the branch" push refs/tags/staging "" 2 false
plan_rejected "a bare branch name is not a ref" push staging "" 2 false
plan_rejected "a lookalike branch is refused" push refs/heads/staging-test "" 2 false
plan_rejected "push to staging with a single parent (not a PR merge)" push refs/heads/staging "" 1 false
plan_rejected "push to production with a single parent" push refs/heads/production "" 1 false
plan_rejected "push to production with no parent (initial commit)" push refs/heads/production "" 0 false
plan_rejected "push to staging with unknown parents (fail closed)" push refs/heads/staging "" "" false
plan_rejected "push to staging with an octopus commit" push refs/heads/staging "" 3 false
plan_rejected "creating production is not a promotion" push refs/heads/production "" 2 true
plan_rejected "creating staging is not a promotion" push refs/heads/staging "" 2 true
plan_rejected "an unknown creation flag fails closed" push refs/heads/production "" 2 ""
plan_rejected "a garbled creation flag fails closed" push refs/heads/production "" 2 maybe
plan_rejected "push carrying a variant selection" push refs/heads/staging ios-staging 2 false
plan_rejected "pull_request is unsupported" pull_request refs/heads/staging "" 2 false
plan_rejected "pull_request closed on production is unsupported" pull_request refs/heads/production "" 2 false
plan_rejected "pull_request with a selection is unsupported" pull_request refs/heads/staging ios-staging
plan_rejected "an unknown event with a selection is unsupported" repository_dispatch refs/heads/staging all
plan_rejected "schedule is unsupported" schedule refs/heads/staging "" 2 false
plan_rejected "manual run without a selection" workflow_dispatch refs/heads/staging ""
plan_rejected "manual run with an unknown variant" workflow_dispatch refs/heads/staging android-stagin-apk
plan_rejected "manual group name staging is not a variant" workflow_dispatch refs/heads/staging staging
plan_rejected "manual group name production is not a variant" workflow_dispatch refs/heads/staging production
plan_rejected "manual two variants at once" workflow_dispatch refs/heads/staging "ios-staging ios-production"
plan_rejected "no event" ""

# The matrices handed to the build jobs hold exactly the selected variants, each of the
# branch's own environment (the "other" key of an iOS item names the opposite environment
# for its rejection step and is not a build).
matrix_envs() { printf '%s\n' "$1" | grep -o '"env":"[a-z]*"' | sort -u | tr '\n' ' '; }
for branch in staging production; do
  out="$("$plan" push "refs/heads/$branch" "" 2 false)"
  envs="$(matrix_envs "$(printf '%s\n' "$out" | sed -n 's/^\(android\|ios\)_matrix=//p')")"
  if [ "$envs" = "\"env\":\"$branch\" " ]; then ok "push to $branch: every matrix item is $branch"; else bad "push to $branch: every matrix item is $branch" "$envs"; fi
done
out="$("$plan" push refs/heads/staging "" 2 false)"
if [ "$(printf '%s\n' "$out" | grep -o '"variant":' | wc -l)" -eq 2 ]; then ok "staging matrices hold exactly 2 items"; else bad "staging matrices hold exactly 2 items" "$out"; fi
out="$("$plan" push refs/heads/production "" 2 false)"
if [ "$(printf '%s\n' "$out" | grep -o '"variant":' | wc -l)" -eq 3 ]; then ok "production matrices hold exactly 3 items"; else bad "production matrices hold exactly 3 items" "$out"; fi
out="$("$plan" workflow_dispatch refs/heads/x ios-production)"
if [ "$(printf '%s\n' "$out" | sed -n 's/^has_android=//p')" = false ] && [ "$(printf '%s\n' "$out" | sed -n 's/^has_ios=//p')" = true ]; then
  ok "manual ios-production has no Android job"
else
  bad "manual ios-production has no Android job" "$out"
fi

# --- 2. merge-commit detection, in real repositories and real shallow clones ------------------
# The default checkout of GitHub Actions has depth 1. Every case below is measured in such a
# clone (the commit is the only one present), which is what the workflow sees.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
g() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
src="$tmp/src"
git init -q -b main "$src"
(
  cd "$src" || exit 1
  g commit -q --allow-empty -m "initial commit"
  g tag initial
  g commit -q --allow-empty -m "ordinary commit"
  g tag ordinary
  g commit -q --allow-empty -m "$(printf 'message that fakes headers\n\nparent 0000000000000000000000000000000000000000\nparent 1111111111111111111111111111111111111111')"
  g tag fakeheaders
  g switch -q -c side initial
  g commit -q --allow-empty -m "side one"
  g switch -q main
  g merge -q --no-ff -m "Merge pull request #1 from x/side" side
  g tag merge
  g switch -q -c side2 initial
  g commit -q --allow-empty -m "side two"
  g switch -q -c side3 initial
  g commit -q --allow-empty -m "side three"
  g switch -q main
  g merge -q --no-ff -m "octopus" side2 side3
  g tag octopus
) >/dev/null 2>&1
for t in initial ordinary fakeheaders merge octopus; do
  case "$t" in initial) want=0 ;; ordinary | fakeheaders) want=1 ;; merge) want=2 ;; octopus) want=3 ;; esac
  sha="$(git -C "$src" rev-parse "$t^{commit}")"
  clone="$tmp/shallow-$t"
  git clone -q --depth 1 --no-local "file://$src" "$clone" 2>/dev/null
  # Check out the commit itself, as actions/checkout does for the pushed SHA.
  git -C "$clone" fetch -q --depth 1 origin "$sha" 2>/dev/null
  shallow="$(git -C "$clone" rev-parse --is-shallow-repository)"
  got="$(cd "$clone" && "$parents_tool" "$sha" 2>/dev/null || echo error)"
  if [ "$shallow" = true ] && [ "$got" = "$want" ]; then ok "parents of '$t' = $want in a depth-1 clone"; else bad "parents of '$t' in a depth-1 clone" "shallow=$shallow got='$got' want=$want"; fi
done
# The same answers in the full repository.
for pair in initial:0 ordinary:1 fakeheaders:1 merge:2 octopus:3; do
  t="${pair%%:*}"
  got="$(cd "$src" && "$parents_tool" "$t" 2>/dev/null || echo error)"
  if [ "$got" = "${pair##*:}" ]; then ok "parents of '$t' = ${pair##*:} in the full repository"; else bad "parents of '$t' in the full repository" "got '$got'"; fi
done
# Not a commit: fails and prints nothing (the workflow step then fails: fail closed).
out="$(cd "$src" && "$parents_tool" 0123456789abcdef0123456789abcdef01234567 2>/dev/null)"
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then ok "an unknown commit fails closed"; else bad "an unknown commit fails closed" "rc=$rc out='$out'"; fi
# The detection result drives the planner: only the genuine merge is accepted.
for pair in initial:0 ordinary:1 fakeheaders:1 merge:2 octopus:3; do
  t="${pair%%:*}"
  n="$(cd "$tmp/shallow-$t" && "$parents_tool" "$(git -C "$src" rev-parse "$t^{commit}")")"
  if "$plan" push refs/heads/production "" "$n" false >/dev/null 2>&1; then accepted=yes; else accepted=no; fi
  if { [ "$t" = merge ] && [ "$accepted" = yes ]; } || { [ "$t" != merge ] && [ "$accepted" = no ]; }; then ok "planner accepts a promotion only for the merge commit ('$t': $accepted)"; else bad "planner on '$t'" "accepted=$accepted"; fi
done

# --- 3. verdict ----------------------------------------------------------------------------
# verdict_case NAME EXPECTED(pass|fail) "VARS" HAS_ANDROID HAS_IOS plan static reject android ios
verdict_case() {
  local name="$1" expect="$2" vars="$3" ha="$4" hi="$5" rc
  SELECTION=t REQUIRED_VARIANTS="$vars" HAS_ANDROID="$ha" HAS_IOS="$hi" \
    RESULT_PLAN="$6" RESULT_STATIC="$7" RESULT_REJECT="$8" RESULT_ANDROID="$9" RESULT_IOS="${10}" \
    "$verdict" results >/dev/null 2>&1
  rc=$?
  if { [ "$expect" = pass ] && [ "$rc" -eq 0 ]; } || { [ "$expect" = fail ] && [ "$rc" -eq 1 ]; }; then ok "verdict: $name"; else bad "verdict: $name" "exit $rc, expected $expect"; fi
}
S=success F=failure C=cancelled K=skipped
verdict_case "staging pair, all green" pass "$STAGING" true true $S $S $S $S $S
verdict_case "production triple, all green" pass "$PRODUCTION" true true $S $S $S $S $S
verdict_case "single ios variant, android jobs skipped" pass ios-staging false true $S $S $K $K $S
verdict_case "single android variant, ios skipped" pass android-production-aab true false $S $S $S $S $K
verdict_case "required android build failed" fail "$STAGING" true true $S $S $S $F $S
verdict_case "required ios build failed" fail "$STAGING" true true $S $S $S $S $F
verdict_case "required ios build cancelled" fail "$PRODUCTION" true true $S $S $S $S $C
verdict_case "required android build unexpectedly skipped" fail "$STAGING" true true $S $S $S $K $S
verdict_case "required ios build unexpectedly skipped" fail "$STAGING" true true $S $S $S $S $K
verdict_case "reject checks failed" fail "$PRODUCTION" true true $S $S $F $S $S
verdict_case "static checks failed" fail "$STAGING" true true $S $F $S $S $S
verdict_case "static checks cancelled" fail "$STAGING" true true $S $C $S $S $S
verdict_case "plan failed" fail "" false false $F $K $K $K $K
verdict_case "plan selected nothing" fail "" false false $S $S $K $K $K
verdict_case "unselected ios job ran anyway" fail android-staging-apk true false $S $S $S $S $S
verdict_case "unselected android job ran anyway" fail ios-staging false true $S $S $S $S $S
verdict_case "unselected job failed" fail ios-staging false true $S $S $K $F $S
verdict_case "a missing result is a failure" fail "$STAGING" true true $S $S $S "" $S

# evidence: exactly the required variants
evidence_case() { # NAME EXPECTED VARS files...
  local name="$1" expect="$2" vars="$3" d rc f
  shift 3
  d="$(mktemp -d "$tmp/ev.XXXX")"
  for f in "$@"; do
    case "$f" in empty:*) : >"$d/${f#empty:}" ;; *) echo "application_id=x" >"$d/$f" ;; esac
  done
  REQUIRED_VARIANTS="$vars" "$verdict" evidence "$d" >/dev/null 2>&1
  rc=$?
  if { [ "$expect" = pass ] && [ "$rc" -eq 0 ]; } || { [ "$expect" = fail ] && [ "$rc" -eq 1 ]; }; then ok "evidence: $name"; else bad "evidence: $name" "exit $rc, expected $expect"; fi
}
evidence_case "exactly the staging pair" pass "$STAGING" android-staging-apk.txt ios-staging.txt
evidence_case "exactly the production triple" pass "$PRODUCTION" android-production-apk.txt android-production-aab.txt ios-production.txt
evidence_case "a required variant has no evidence" fail "$STAGING" android-staging-apk.txt
evidence_case "a required variant has empty evidence" fail "$STAGING" android-staging-apk.txt empty:ios-staging.txt
evidence_case "evidence of an unselected variant" fail "$STAGING" android-staging-apk.txt ios-staging.txt ios-production.txt
evidence_case "an unexpected extra file" fail "$STAGING" android-staging-apk.txt ios-staging.txt notes.md
evidence_case "no evidence at all" fail "$STAGING"
if REQUIRED_VARIANTS="$STAGING" "$verdict" evidence "$tmp/does-not-exist" >/dev/null 2>&1; then bad "evidence: missing directory"; else ok "evidence: missing directory fails"; fi

# --- 4. workflow definition (read as text) ---------------------------------------------------
# Comment lines are removed first, so a comment cannot satisfy or violate a check.
wf="$tmp/workflow.yml"
grep -v '^[[:space:]]*#' "$workflow" >"$wf"
# block FILE AWK-START-REGEX AWK-END-REGEX : the lines from the first match up to (excluding) the next match of END
block() { awk -v s="$2" -v e="$3" 'f && $0 ~ e { exit } $0 ~ s { f = 1 } f' "$1"; }
on_block="$(block "$wf" '^on:' '^[a-z]')"
push_block="$(printf '%s\n' "$on_block" | awk '/^  push:/ { f = 1; next } f && /^  [a-z_]+:/ { exit } f')"
job() { block <(sed -n '/^jobs:/,$p' "$wf") "^  $1:\$" '^  [a-z_]+:$'; }

# t NAME COMMAND...  : passes when the command succeeds
t() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
eq() { [ "$1" = "$2" ]; }                       # eq ACTUAL EXPECTED
# here-strings, not pipes: `grep -q` exits at the first match and a pipe would then fail
# under pipefail (SIGPIPE) depending on the size of the text
has() { grep -qF -- "$2" <<<"$1"; }   # has TEXT FIXED-STRING
hasre() { grep -qE -- "$2" <<<"$1"; } # hasre TEXT REGEX
lacks() { ! has "$1" "$2"; }
lacksre() { ! hasre "$1" "$2"; }

events="$(printf '%s\n' "$on_block" | sed -n 's/^  \([a-z_]*\):.*/\1/p' | tr '\n' ' ')"
t "triggers are exactly push and workflow_dispatch" eq "$events" "push workflow_dispatch "
t "push branches are exactly [staging, production]" eq "$(printf '%s\n' "$push_block" | grep -v '^$')" "    branches: [staging, production]"
t "there is no pull_request trigger" lacks "$(cat "$wf")" "pull_request"
options="$(printf '%s\n' "$on_block" | sed -n 's/^          - //p' | tr '\n' ' ')"
t "the selector offers all + the five variants" eq "$options" "all $ALL "
catalogue_ids="$(sed -n "/^CATALOGUE='/,/'\$/p" "$plan" | sed "s/^CATALOGUE='//" | awk 'NF { printf "%s ", $1 }')"
t "the selector options match the planner's catalogue" eq "$catalogue_ids" "$ALL "
t "workflow permissions are exactly contents: read" eq "$(block "$wf" '^permissions:' '^[a-z]' | tr -d '\n')" "permissions:  contents: read"
t "no job widens its permissions" lacksre "$(cat "$wf")" '^    permissions:'
t "no secret is used" lacks "$(cat "$wf")" 'secrets.'

jobs="$(sed -n '/^jobs:/,$p' "$wf" | sed -n 's/^  \([a-z_]*\):$/\1/p' | tr '\n' ' ')"
t "the jobs are plan static reject android ios verdict" eq "$jobs" "plan static reject android ios verdict "
vj="$(job verdict)"
t "verdict needs every other job" has "$vj" "    needs: [plan, static, reject, android, ios]"
t "verdict runs always() (also after a failed or cancelled job)" has "$vj" 'if: ${{ always() && '
guard='!(github.event_name == '"'"'push'"'"' && github.event.created)'
for j in plan static; do
  t "$j does not run for a branch creation" has "$(job $j)" "    if: \${{ $guard }}"
done
t "verdict does not run for a branch creation" has "$vj" "$guard"
for j in reject android ios; do
  t "$j needs plan" has "$(job $j)" "    needs: [plan"
done
for j in reject android; do
  t "$j is gated by the plan's has_android" hasre "$(job $j)" "^    if: .*has_android == 'true'"
done
t "ios is gated by the plan's has_ios" hasre "$(job ios)" "^    if: .*has_ios == 'true'"
for j in android ios; do
  t "$j takes its matrix from the plan" has "$(job $j)" 'matrix: ${{ fromJSON(needs.plan.outputs'
  t "$j is not fail-fast" has "$(job $j)" "      fail-fast: false"
done
jplan="$(job plan)"
t "the plan step does not pipe its output (the default shell has no pipefail)" lacks "$jplan" '| tee'
t "the plan step gets the creation flag from the event" has "$jplan" 'CREATED: ${{ github.event.created }}'
t "the plan step reads the parents with tool/commit_parents.sh" has "$jplan" 'parents="$(tool/commit_parents.sh "$GITHUB_SHA")"'
t "the planner is called with the parent count and the creation flag" has "$jplan" 'tool/plan_build_variants.sh "$EVENT_NAME" "$REF" "$INPUT_VARIANT" "$parents" "$CREATED"'
t "the concurrency group of a push contains its commit" hasre "$(cat "$wf")" '^  group: .*github\.sha'

echo
echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
