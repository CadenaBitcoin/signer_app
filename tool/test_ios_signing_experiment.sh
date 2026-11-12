#!/usr/bin/env bash
# Static tests of the hosted signing feasibility experiment of Issue #71 (stage D): the workflow
# .github/workflows/ios-signing-feasibility.yml and tool/spike_resign_unsigned_ios.sh. They read the files;
# they run nothing on macOS and start nothing on GitHub.
#
#   tool/test_ios_signing_experiment.sh
#
# What they protect: the experiment must stay manual, credential-free, upload-free and without contact
# to Apple services, and must say that success does not prove Apple distribution compatibility.
# (No `grep -q` at the end of a pipeline: under pipefail an early-closed pipe is a SIGPIPE failure.)
# Exit 0 only if every check passes.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spike="$root/tool/spike_resign_unsigned_ios.sh"
pass=0
failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }

# the hosted experiment workflow (static checks: it must stay credential-free, manual and upload-free)
wf="$root/.github/workflows/ios-signing-feasibility.yml"
wfcode="$(grep -vE '^[[:space:]]*#' "$wf")"
wfchk() { # DESCRIPTION CONDITION(0 = good)
  if [ "$2" -eq 0 ]; then ok "experiment workflow: $1"; else bad "experiment workflow: $1"; fi
}
on_block="$(echo "$wfcode" | sed -n '/^on:/,/^permissions:/p')"
triggers="$(echo "$on_block" | grep -E '^  [a-z_]+:' | tr -d ' :' | tr '\n' ' ')"
[ "$triggers" = "workflow_dispatch " ]; wfchk "starts only by hand (workflow_dispatch), not on push, pull request or schedule (found: $triggers)" $?
perm="$(echo "$wfcode" | sed -n '/^permissions:/,/^concurrency:/p' | grep -E '^  [a-z-]+:' | tr -d ' ' | tr '\n' ' ')"
[ "$perm" = "contents:read actions:read " ]; wfchk "permissions are exactly contents: read and actions: read (found: $perm)" $?
! echo "$wfcode" | grep -E 'secrets\.|environment:|upload-artifact|download-artifact|id-token|workflow_run|pull_request' >/dev/null; wfchk "no secret, environment, artifact upload/download action, OIDC token or pull-request trigger" $?
! echo "$wfcode" | grep -iE 'altool|notarytool|testflight|appstoreconnect|app-store-connect|developer\.apple|exportArchive|\.p8|AuthKey|\.mobileprovision|provisioning' >/dev/null; wfchk "no Apple service, TestFlight, export, API-key or provisioning-profile reference" $?
bad_uses="$(echo "$wfcode" | grep -E '^[[:space:]]*-?[[:space:]]*uses:' | grep -vE '@[0-9a-f]{40}( |$)' || true)"
[ -z "$bad_uses" ]; wfchk "every action is pinned to a full commit SHA" $?
inputs_outside_env="$(echo "$wfcode" | grep -E '\$\{\{[[:space:]]*(inputs|github\.event\.inputs)' | grep -vE '^[[:space:]]+SOURCE_[A-Z0-9_]+: \$\{\{ inputs\.[a-z0-9_]+ \}\}$' || true)"
[ -z "$inputs_outside_env" ]; wfchk "workflow inputs reach the shell only through env variables (no script injection)" $?
echo "$wfcode" | grep -F "runs-on: macos-15" >/dev/null; wfchk "runs on macos-15" $?
for key in XCODE_APP EXPECTED_XCODE EXPECTED_MIN_SDK_MAJOR; do
  a="$(grep -E "^  $key:" "$wf" | head -1 | sed 's/[[:space:]]*#.*//')"
  b="$(grep -E "^  $key:" "$root/.github/workflows/ios-ci-validation.yml" | head -1 | sed 's/[[:space:]]*#.*//')"
  [ -n "$a" ] && [ "$a" = "$b" ]; wfchk "$key equals the pin of the iOS validation workflow" $?
done
[ "$(echo "$wfcode" | grep -c 'if: always()')" -ge 2 ]; wfchk "the cleanup check and the report run even after a failure" $?
echo "$wfcode" | grep -E '^    timeout-minutes: [0-9]+' >/dev/null; wfchk "the job has a timeout" $?
grep -F "SUCCESS HERE DOES NOT PROVE APPLE DISTRIBUTION COMPATIBILITY" "$wf" >/dev/null && grep -F "does not prove Apple distribution compatibility" "$wf" >/dev/null; wfchk "it states that success does not prove Apple distribution compatibility (header and report)" $?
spike_code="$(grep -vE '^[[:space:]]*#' "$spike")"
echo "$spike_code" | grep -F -- "--timestamp=none" >/dev/null && ! echo "$spike_code" | grep -E -- '--timestamp([^=]|$)' >/dev/null; wfchk "codesign never contacts a timestamp server (--timestamp=none)" $?
echo "$spike_code" | grep -F "security delete-keychain" >/dev/null && echo "$spike_code" | grep -F "trap cleanup EXIT" >/dev/null; wfchk "the script deletes its throwaway keychain on exit" $?
! echo "$spike_code" | grep -E 'list-keychains|default-keychain|login\.keychain' >/dev/null; wfchk "the script never changes the keychain search list or touches the login keychain" $?


if bash -n "$spike"; then ok "the spike script is syntactically valid"; else bad "the spike script is syntactically valid"; fi

echo
echo "test_ios_signing_experiment: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
