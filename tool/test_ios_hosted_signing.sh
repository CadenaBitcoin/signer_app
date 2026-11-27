#!/usr/bin/env bash
# Static tests of the hosted iOS signing workflow of Issue #71: .github/workflows/ios-hosted-signing.yml
# (docs/IOS_HOSTED_SIGNING.md). They READ the file; they run nothing on macOS, contact no Apple service and start nothing
# on GitHub.
#
#   tool/test_ios_hosted_signing.sh
#
# What they protect: the workflow must stay manual, development-only and gated by the release record; it uploads NOTHING unless the record's
# operation is sign-verify-and-upload, and then only through ONE gated step after every verification; and the two steps that hold the Apple API key
# (export, upload) must stay small, isolated and cleaned up. Exit 0 only if every check passes.
# (No `grep -q` at the end of a pipeline: under pipefail an early-closed pipe is a SIGPIPE failure.)
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="${HOSTED_SIGNING_WORKFLOW:-$root/.github/workflows/ios-hosted-signing.yml}"
pass=0; failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
chk() { # DESCRIPTION CONDITION_EXIT_CODE [DETAIL]
  if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "${3:-}"; fi
}

[ -f "$wf" ] || { echo "FAIL the workflow file is missing: $wf"; exit 1; }
code="$(grep -vE '^[[:space:]]*#' "$wf")"                       # no full-line comments
jobs="$(printf '%s\n' "$code" | sed -n '/^jobs:/,$p')"
job_text() { printf '%s\n' "$jobs" | awk -v j="$1" '$0 ~ "^  "j":$" {f=1; next} /^  [a-z][a-z-]*:$/ {f=0} f'; }
step_of() { # JOB_TEXT NAME_FRAGMENT -> the text of the step whose "- name:" line contains the fragment
  printf '%s\n' "$1" | awk -v n="$2" '/^      - name:/ {f = (index($0, n) > 0)} f'
}
authorize="$(job_text authorize)"; build="$(job_text build)"; sign="$(job_text sign)"
[ -n "$authorize" ] && [ -n "$build" ] && [ -n "$sign" ]; chk "the workflow has exactly the jobs authorize, build and sign" $?
[ "$(printf '%s\n' "$jobs" | grep -cE '^  [a-z][a-z-]*:$')" -eq 3 ]; chk "and no other job" $?

# ---- triggers and permissions ----
triggers="$(printf '%s\n' "$code" | sed -n '/^on:/,/^permissions:/p' | grep -E '^  [a-z_]+:' | tr -d ' :' | tr '\n' ' ')"
[ "$triggers" = "workflow_dispatch " ]; chk "starts only by hand (workflow_dispatch), not on push, pull request or schedule (found: $triggers)" $?
! printf '%s\n' "$code" | grep -E 'pull_request|workflow_run|schedule:|repository_dispatch|workflow_call' >/dev/null; chk "no pull_request, pull_request_target, workflow_run, schedule, repository_dispatch or workflow_call" $?
perm="$(printf '%s\n' "$code" | sed -n '/^permissions:/,/^concurrency:/p' | grep -E '^  [a-z-]+:' | tr -d ' ' | tr '\n' ' ')"
[ "$perm" = "contents:read " ]; chk "the workflow permissions are exactly contents: read (found: $perm)" $?
! printf '%s\n' "$code" | grep -E '^[[:space:]]+(permissions:|id-token|contents: write|actions: write|packages:|pull-requests:|issues:|checks:|statuses:|deployments:)' | grep -v '^permissions:' >/dev/null; chk "no job widens the permissions and the OIDC token is never requested" $?
printf '%s\n' "$code" | grep -E '^  group: ios-hosted-signing$' >/dev/null && printf '%s\n' "$code" | grep -E '^  cancel-in-progress: false$' >/dev/null; chk "one run at a time (concurrency group, never cancelled mid-signing)" $?
for j in build sign; do
  t="$(job_text $j)"
  printf '%s\n' "$t" | grep -E '^    runs-on: macos-15$' >/dev/null; chk "job $j runs on macos-15 (not macos-latest)" $?
  printf '%s\n' "$t" | grep -E '^    timeout-minutes: [0-9]+$' >/dev/null; chk "job $j has a timeout" $?
done
printf '%s\n' "$authorize" | grep -E '^    runs-on: ubuntu-latest$' >/dev/null && printf '%s\n' "$authorize" | grep -E '^    timeout-minutes: [0-9]+$' >/dev/null; chk "job authorize runs on a hosted Linux runner with a timeout" $?
! printf '%s\n' "$code" | grep -E 'runs-on:.*self-hosted' >/dev/null; chk "no self-hosted runner (public repository)" $?

# ---- actions, inputs ----
bad_uses="$(printf '%s\n' "$code" | grep -E '^[[:space:]]*-?[[:space:]]*uses:' | grep -vE '@[0-9a-f]{40}( |$)' || true)"
[ -z "$bad_uses" ]; chk "every action is pinned to a full commit SHA" $?
loose="$(printf '%s\n' "$code" | grep -E '\$\{\{[[:space:]]*(inputs|github\.event\.inputs)' | grep -vE '^[[:space:]]+[A-Z][A-Z0-9_]*: \$\{\{ inputs\.[a-z0-9_]+ \}\}$' | grep -vE '^[[:space:]]+ref: \$\{\{ inputs\.approved_sha \}\}$' || true)"
[ -z "$loose" ]; chk "workflow inputs reach the shell only through env variables (the one other use is a validated checkout ref)" $? "$loose"
! printf '%s\n' "$code" | grep -E 'github\.event\.(pull_request|head_commit|comment|issue|review)|github\.head_ref' >/dev/null; chk "no attacker-controllable event field is used" $?
! printf '%s\n' "$code" | grep -E -- '--build-name|--build-number' >/dev/null; chk "no version override of any kind" $?

# ---- the secrets: three, one step, one job ----
nsec="$(printf '%s\n' "$code" | grep -c 'secrets\.')"
[ "$nsec" -eq 6 ]; chk "exactly six secret references: three in the export step and the same three in the upload step (found $nsec)" $?
names="$(printf '%s\n' "$code" | grep -o 'secrets\.[A-Z0-9_]*' | sort | tr '\n' ' ')"
[ "$names" = "secrets.APPLE_API_ISSUER_ID secrets.APPLE_API_ISSUER_ID secrets.APPLE_API_KEY_ID secrets.APPLE_API_KEY_ID secrets.APPLE_API_KEY_P8 secrets.APPLE_API_KEY_P8 " ]; chk "they are APPLE_API_KEY_P8, APPLE_API_KEY_ID and APPLE_API_ISSUER_ID, each twice (found: $names)" $?
! printf '%s\n' "$authorize" "$build" | grep 'secrets\.' >/dev/null; chk "the authorize and build jobs have no secret" $?
! printf '%s\n' "$code" | grep -E 'secrets:[[:space:]]*inherit|\$\{\{[[:space:]]*secrets[[:space:]]*\}\}|toJSON\(secrets' >/dev/null; chk "secrets are never passed wholesale" $?
# the step that holds them
step_name='Export and sign with the cloud-managed Distribution certificate (the only step with secrets)'
secret_step="$(printf '%s\n' "$sign" | awk -v n="      - name: $step_name" '$0==n {f=1; print; next} /^      - name:/ {f=0} f')"
[ -n "$secret_step" ]; chk "the signing job has the one named secret step" $?
[ "$(printf '%s\n' "$secret_step" | grep -c 'secrets\.')" -eq 3 ]; chk "all three secrets are in that step, at step level (env) and nowhere else" $?
printf '%s\n' "$sign" | grep -E '^    environment: ios-hosted-signing$' >/dev/null; chk "the signing job uses the protected environment ios-hosted-signing" $?
[ "$(printf '%s\n' "$code" | grep -c 'environment:')" -eq 1 ]; chk "and it is the only job with an environment" $?
printf '%s\n' "$sign" | grep -E "^    if: needs\.authorize\.outputs\.authorized == 'true'$" >/dev/null && printf '%s\n' "$sign" | grep -E '^    needs: \[authorize, build\]$' >/dev/null; chk "the signing job runs only when the authorize job said yes, after the build" $?
printf '%s\n' "$code" | grep -F '"$GITHUB_REF" != "refs/heads/development"' >/dev/null && printf '%s\n' "$sign" | grep -F '"$GITHUB_REF" = "refs/heads/development"' >/dev/null; chk "both gates refuse any ref other than refs/heads/development" $?
# ordering inside the signing job: the re-check of the authorization precedes the secret step
l_gate="$(printf '%s\n' "$sign" | grep -n 'check_signing_authorization.sh' | head -1 | cut -d: -f1)"
l_sec="$(printf '%s\n' "$sign" | grep -n 'secrets\.' | head -1 | cut -d: -f1)"
[ -n "$l_gate" ] && [ -n "$l_sec" ] && [ "$l_gate" -lt "$l_sec" ]; chk "the authorization is re-checked before the first secret reference" $?
printf '%s\n' "$authorize" | grep 'check_signing_authorization.sh' >/dev/null; chk "the authorize job runs tool/check_signing_authorization.sh" $?
# the step content
ss() { printf '%s\n' "$secret_step" | grep -E -- "$1" >/dev/null; }
ss '^          umask 077$' && ss 'chmod 600 "\$KEYFILE"'; chk "the key file is created with umask 077 and mode 600" $?
ss 'KEYFILE="\$RUNNER_TEMP/' && ! ss 'KEYFILE="\$GITHUB_WORKSPACE|KEYFILE="\./|KEYFILE="evidence'; chk "the key file lives in RUNNER_TEMP, outside the workspace and every artifact path" $?
ss 'trap cleanup EXIT' && ss 'rm -P -f "\$KEYFILE"'; chk "a trap removes the key file on every exit (rm -P overwrites first)" $?
ss -- '-allowProvisioningUpdates' && ss -- '-authenticationKeyPath "\$KEYFILE"' && ss -- '-authenticationKeyID' && ss -- '-authenticationKeyIssuerID'; chk "xcodebuild authenticates with the team API key (-authenticationKeyPath, ID and issuer ID)" $?
ss -- '-exportArchive' && ss '<key>signingStyle</key><string>automatic</string>' && ss '<key>method</key><string>app-store-connect</string>'; chk "it exports with automatic signing for app-store-connect (cloud-managed certificate)" $?
ss '<key>destination</key><string>export</string>' && ! ss '<string>upload</string>'; chk "the export destination is export, never upload" $?
ss '<key>manageAppVersionAndBuildNumber</key><false/>' && ss '<key>testFlightInternalTestingOnly</key><false/>'; chk "Xcode may not manage the build number, and the build is not 'TestFlight Internal Only' (D9)" $?
! ss 'signingCertificate|provisioningProfiles|signingStyle</key><string>manual'; chk "no manual certificate or profile is named in the export options" $?
ss 'redact\.py' && ss '\[REDACTED\]'; chk "everything kept from the step passes through the redaction filter" $?
ss '^          unset APPLE_API_KEY_P8$' && ss 'env -u APPLE_API_KEY_P8 -u APPLE_API_KEY_ID -u APPLE_API_ISSUER_ID'; chk "the key text leaves the environment before xcodebuild, and no secret is in xcodebuild's environment (behaviour: test_ios_hosted_signing_behavior.sh)" $?
l_unset="$(printf '%s\n' "$secret_step" | grep -n '^          unset APPLE_API_KEY_P8$' | head -1 | cut -d: -f1)"; l_chmod="$(printf '%s\n' "$secret_step" | grep -n '^          chmod 600 "\$KEYFILE"$' | head -1 | cut -d: -f1)"; l_print="$(printf '%s\n' "$secret_step" | grep -n 'printf .%s.n. "\$APPLE_API_KEY_P8"' | head -1 | cut -d: -f1)"
[ -n "$l_unset" ] && [ -n "$l_chmod" ] && [ -n "$l_print" ] && [ "$l_print" -lt "$l_unset" ] && [ "$l_unset" -lt "$l_chmod" ]; chk "the key text is unset right after it is written and BEFORE any other process starts (chmod included)" $?
ss 'eyJ' && ss '\(bearer\|authorization'; chk "the redaction filter knows JWT-shaped and bearer tokens (behaviour: test_ios_hosted_signing_behavior.sh)" $?
ss '^          set \+e$'; chk "the credential step does not run under errexit (a failing xcodebuild must still leave redacted evidence)" $?
! ss 'xcodebuild .*\| *tee|echo .*APPLE_API|printf .*APPLE_API_KEY_ID|set -x|set -[a-z]*x'; chk "the step prints neither the secrets nor an unredacted xcodebuild log, and does not trace" $?
[ "$(printf '%s\n' "$sign" | grep -cE '^[[:space:]]+xcodebuild -exportArchive')" -eq 1 ] && [ "$(printf '%s\n' "$secret_step" | grep -cE '^[[:space:]]+xcodebuild -exportArchive')" -eq 1 ]; chk "xcodebuild -exportArchive runs once, in the secret step only" $?
! printf '%s\n' "$code" | grep -E 'set -[a-z]*x|xtrace|ACTIONS_STEP_DEBUG|ACTIONS_RUNNER_DEBUG' >/dev/null; chk "nothing traces (no set -x, xtrace or debug logging)" $?
! printf '%s\n' "$code" | grep -E 'printenv|^[[:space:]]*env[[:space:]]*(\||$)|^[[:space:]]*set[[:space:]]*\|' >/dev/null; chk "nothing dumps the environment" $?
kstep="$(step_of "$sign" 'Check that the key file is gone')"
printf '%s\n' "$kstep" | grep -F 'key_file_removed=yes' >/dev/null && printf '%s\n' "$kstep" | grep -E '^        if: always\(\)$' >/dev/null; chk "a step that runs even after a failure checks that no key file remains" $?

# ---- what the signing job runs: no build, no dependency, no third-party code ----
! printf '%s\n' "$sign" | grep -E '(^|[;&|(])[[:space:]]*(flutter|dart|pod|gem|bundle|npm|yarn|pip3?|brew|gradle|gradlew|cargo|make|swift|fastlane)[[:space:]]' >/dev/null; chk "the signing job runs no build tool, package manager or dependency installer" $?
xb="$(printf '%s\n' "$sign" | grep -oE 'xcodebuild -[A-Za-z]+' | sort -u | tr '\n' ',')"
[ "$xb" = "xcodebuild -exportArchive,xcodebuild -version," ]; chk "the only xcodebuild commands of the signing job are -exportArchive and -version (found: $xb)" $?
! printf '%s\n' "$sign" | grep -E 'security (import|create-keychain|unlock-keychain|set-key-partition|default-keychain|list-keychains|add-trusted-cert)|\.p12|import-certificate|pkcs12' >/dev/null; chk "no keychain, .p12 or certificate import (cloud-managed signing only; a .p12 route is a separate decision)" $?
! printf '%s\n' "$sign" | grep -E 'codesign (-s|--sign|-f|--force)' >/dev/null; chk "the job never calls codesign to sign (it only verifies)" $?
printf '%s\n' "$sign" | grep -E 'verify_ipa\.py.* verify production' >/dev/null && printf '%s\n' "$sign" | grep -F -- '--forbid-entitlement aps-environment' >/dev/null && printf '%s\n' "$sign" | grep -E 'verify_ipa\.py.* certificate' >/dev/null && printf '%s\n' "$sign" | grep -E 'verify_ipa\.py.* compare' >/dev/null; chk "it runs verify_ipa.py verify (with --forbid-entitlement aps-environment), certificate and compare" $?
printf '%s\n' "$sign" | grep -F -- '--unsigned-app "$BASELINE_APP"' >/dev/null; chk "V8 compares against the app of the archive that was exported (no second compile)" $?
printf '%s\n' "$sign" | grep -E 'sha256|shasum' >/dev/null && printf '%s\n' "$sign" | grep -F 'ipa_sha256_after_verification' >/dev/null; chk "the IPA digest is recorded after export and again after verification" $?

# ---- the hand-over from the build job is validated before and after extraction, and no code of it runs ----
printf '%s\n' "$sign" | grep -F 'validate_handover_archive.py list' >/dev/null && printf '%s\n' "$sign" | grep -F 'validate_handover_archive.py tree' >/dev/null; chk "the archive is validated before and after extraction by tool/validate_handover_archive.py" $?
! printf '%s\n' "$sign" | grep -E 'approved/tool|bash approved|python3? .*approved/|cd approved' >/dev/null; chk "no script of the approved commit is executed in the signing job" $?
printf '%s\n' "$sign" | grep -F 'name: Enforce the authorized dlc_wallet framework hash (no secret yet)' >/dev/null && printf '%s\n' "$sign" | grep -F -- '--print-field G2S-DLC-WALLET-SHA256' >/dev/null && printf '%s\n' "$sign" | grep -F '[ "$actual" != "$authorized" ]' >/dev/null; chk "the archive's dlc_wallet binary is compared with the authorized hash before the secret step (behaviour: test_ios_hosted_signing_behavior.sh)" $?
printf '%s\n' "$sign" | grep -F -- '--repo "$VERIFIER_REPO"' >/dev/null; chk "the verifier's repository view is the assembled one (script of this commit, pubspec of the approved commit as data)" $?
printf '%s\n' "$code" | grep -F 'git ls-remote' >/dev/null && ! printf '%s\n' "$code" | grep -E 'git ls-remote .*(push|--heads .*://[^e])' >/dev/null; chk "the current tip of development is read with git ls-remote (stale-run check)" $?

# ---- nothing is uploaded, nothing is released ----
# ONLY the approved upload steps may name Apple's upload tool; every other line of the workflow stays free of it, and nothing anywhere may use another route.
up_names=('Probe Apple' 'Re-check the upload authorization' 'Validate and upload the verified IPA')
rest="$(printf '%s\n' "$code" | awk -v a="${up_names[0]}" -v b="${up_names[1]}" -v c="${up_names[2]}" '/^      - name:/ { skip = (index($0, a) > 0 || index($0, b) > 0 || index($0, c) > 0) } !skip')"
! printf '%s\n' "$rest" | grep -iE 'altool|iTMSTransporter|Transporter\.app|--upload|upload-app|upload-package|validate-app|api\.appstoreconnect|appstoreconnect\.apple|reviewSubmissions|betaAppReview|submitForReview|fastlane|pilot|deliver' >/dev/null; chk "outside the three approved upload steps: no upload, validation, review, TestFlight or App Store Connect call of any kind" $?
! printf '%s\n' "$code" | grep -iE 'iTMSTransporter|Transporter\.app|api\.appstoreconnect|appstoreconnect\.apple|reviewSubmissions|betaAppReview|submitForReview|fastlane|pilot|deliver|<string>upload</string>|destination.*upload' >/dev/null; chk "nowhere: no Transporter, no direct App Store Connect API call, no review or tester call, no export destination upload" $?
probe_step="$(step_of "$sign" 'Probe Apple')"; pre_step="$(step_of "$sign" 'Re-check the upload authorization')"; up_step="$(step_of "$sign" 'Validate and upload the verified IPA')"
[ "$(printf '%s\n' "$sign" | grep -cE '^      - name: (Probe Apple|Re-check the upload authorization|Validate and upload the verified IPA)')" -eq 3 ] && [ -n "$probe_step" ] && [ -n "$pre_step" ] && [ -n "$up_step" ]; chk "upload: the signing job has exactly one probe step, one pre-check step and one upload step" $?
[ "$(printf '%s\n' "$up_step" | grep -c -- '--upload-package')" -eq 1 ] && [ "$(printf '%s\n' "$up_step" | grep -c -- '--upload-app')" -eq 1 ] && [ "$(printf '%s\n' "$rest" | grep -c -- '--upload-')" -eq 0 ]; chk "upload: the upload command appears once per interface (package, legacy), both in the upload step only" $?
[ "$(printf '%s\n' "$code" | grep -c 'altool')" -eq "$(printf '%s\n' "$probe_step" "$up_step" | grep -c 'altool')" ]; chk "upload: altool is named only in the probe and the upload step" $?
[ "$(printf '%s\n' "$probe_step" | grep -cE "^        if: needs\.authorize\.outputs\.upload_authorized == 'true'$")" -eq 1 ] && [ "$(printf '%s\n' "$pre_step" | grep -cE "^        if: needs\.authorize\.outputs\.upload_authorized == 'true'$")" -eq 1 ] && [ "$(printf '%s\n' "$up_step" | grep -cE "^        if: needs\.authorize\.outputs\.upload_authorized == 'true'$")" -eq 1 ]; chk "upload: the probe, the pre-check and the upload run only when the authorize job said upload_authorized" $?
! printf '%s\n%s\n%s\n' "$probe_step" "$pre_step" "$up_step" | grep -E 'always\(\)|failure\(\)|cancelled\(\)|continue-on-error|success\(\) *\|\|' >/dev/null; chk "upload: none of them can run after a failed step (no always(), failure(), cancelled() or continue-on-error): a failed verification means no upload" $?
printf '%s\n' "$authorize" | grep -F 'upload_authorized: ${{ steps.gate.outputs.upload_authorized }}' >/dev/null && printf '%s\n' "$authorize" | grep -F -- '--print-field G2S-OPERATION' >/dev/null && printf '%s\n' "$authorize" | grep -F '[ "$op" = "sign-verify-and-upload" ] && upload_authorized=true' >/dev/null; chk "upload: the authorize job grants the upload only when the gate passed AND the record's operation is sign-verify-and-upload" $?
! printf '%s\n%s\n' "$probe_step" "$pre_step" | grep -E 'secrets\.|APPLE_API|\.p8|keychain' >/dev/null; chk "upload: the probe and the pre-check hold no secret and touch no key" $?
[ "$(printf '%s\n' "$up_step" | grep -c 'secrets\.')" -eq 3 ] && ! printf '%s\n' "$secret_step" | grep -F 'altool' >/dev/null; chk "upload: the three secrets are in the upload step, and the export step does not upload" $?
us() { printf '%s\n' "$up_step" | grep -E -- "$1" >/dev/null; }
us '^          umask 077$' && us 'chmod 600 "\$KEYFILE"' && us 'trap cleanup EXIT' && us 'rm -P -f "\$KEYFILE"' && us '^          set \+e$'; chk "upload: umask 077, mode 600, a trap that removes the key file on every exit, no errexit" $?
us 'KEYFILE="\$KEYDIR/AuthKey_' && us 'KEYDIR="\$RUNNER_TEMP/' && ! us 'KEYFILE="\$GITHUB_WORKSPACE|KEYFILE="evidence|KEYFILE="\./'; chk "upload: the key file lives in a directory of RUNNER_TEMP, outside the workspace and every artifact path" $?
us '^          unset APPLE_API_KEY_P8$' && us 'env -u APPLE_API_KEY_P8 -u APPLE_API_KEY_ID -u APPLE_API_ISSUER_ID xcrun altool'; chk "upload: the key text leaves the environment before any process starts, and altool runs without any secret in its environment" $?
l_unset="$(printf '%s\n' "$up_step" | grep -n '^          unset APPLE_API_KEY_P8$' | head -1 | cut -d: -f1)"; l_chmod="$(printf '%s\n' "$up_step" | grep -n '^          chmod 600 "\$KEYFILE"' | head -1 | cut -d: -f1)"; l_print="$(printf '%s\n' "$up_step" | grep -n 'printf .%s.n. "\$APPLE_API_KEY_P8"' | head -1 | cut -d: -f1)"
[ -n "$l_unset" ] && [ -n "$l_chmod" ] && [ -n "$l_print" ] && [ "$l_print" -lt "$l_unset" ] && [ "$l_unset" -lt "$l_chmod" ]; chk "upload: the key text is unset right after it is written and BEFORE any other process starts (chmod included)" $?
us 're_key=.\^\[A-Z0-9\]\{10\}\$.' && us 're_issuer=' && us '\[\[ "\$APPLE_API_KEY_ID" =~ \$re_key \]\]'; chk "upload: the key ID and the issuer ID must have the shape Apple issues before the first file name or argument is built from them" $?
us 'redact\.py' && us '\[REDACTED\]' && us 'redact "\$RUNNER_TEMP/upload.raw.log" evidence/upload.log' && us 'redact "\$RUNNER_TEMP/validate.raw.log" evidence/upload-validate.log'; chk "upload: everything kept from altool passes through the redaction filter, and the raw logs are never printed or kept" $?
! us 'tail -n [0-9]+ "?\$RUNNER_TEMP|cat "?\$RUNNER_TEMP/(upload|validate)\.raw|set -x|echo .*APPLE_API|printf .*APPLE_API_KEY_ID'; chk "upload: it prints neither the secrets nor an unredacted altool log, and does not trace" $?
l_val="$(printf '%s\n' "$up_step" | grep -n -- '"\${VALIDATE\[@\]}"' | head -1 | cut -d: -f1)"; l_if="$(printf '%s\n' "$up_step" | grep -n '^          if \[ "\$vrc" -eq 0 \]; then$' | head -1 | cut -d: -f1)"; l_upl="$(printf '%s\n' "$up_step" | grep -n -- '"\${UPLOAD\[@\]}"' | head -1 | cut -d: -f1)"
l_proc="$(printf '%s\n' "$up_step" | grep -n '^          if \[ "\$proceed" -eq 1 \]; then$' | head -1 | cut -d: -f1)"; l_set="$(printf '%s\n' "$up_step" | grep -n '^              proceed=1$' | head -1 | cut -d: -f1)"
l_sha2="$(printf '%s\n' "$up_step" | grep -n '!= "\$UPLOAD_IPA_SHA256"' | head -1 | cut -d: -f1)"; l_red="$(printf '%s\n' "$up_step" | grep -n 'if \[ "\$red" -ne 0 \]; then' | head -1 | cut -d: -f1)"
[ -n "$l_val" ] && [ -n "$l_if" ] && [ -n "$l_upl" ] && [ -n "$l_proc" ] && [ -n "$l_set" ] && [ "$l_val" -lt "$l_if" ] && [ "$l_if" -lt "$l_set" ] && [ "$l_set" -lt "$l_proc" ] && [ "$l_proc" -lt "$l_upl" ] && [ "$(printf '%s\n' "$up_step" | grep -c -- '"\${UPLOAD\[@\]}"')" -eq 1 ] && [ "$(printf '%s\n' "$up_step" | grep -c '^              proceed=1$')" -eq 1 ]; chk "upload: Apple's validation runs first, the single upload runs only inside 'if proceed', proceed is set once and only after a successful validation, and there is no second attempt" $?
[ -n "$l_sha2" ] && [ -n "$l_red" ] && [ "$l_val" -lt "$l_red" ] && [ "$l_red" -lt "$l_sha2" ] && [ "$l_sha2" -lt "$l_set" ] && us 'the redaction of the validation log failed' && us 'the IPA changed after the validation'; chk "upload: after a successful validation, a failed redaction of the validation log and a changed IPA (its digest computed again against the verified one) each stop the step BEFORE the upload" $?
up_sh="$(printf '%s\n' "$up_step" | awk '/<<.PY.$/ {skip=1; next} /^          PY$/ {skip=0; next} !skip')"   # the shell of the step, without its embedded python filter
! printf '%s\n' "$up_sh" | grep -E '^[[:space:]]*(for [A-Za-z_]+ in |while |until )|(^|[[:space:];])(sleep|retry)[[:space:]]' >/dev/null; chk "upload: no loop, no retry, no sleep (a failed upload is reported, never repeated)" $?
us 'IPA changed since it was re-checked' && printf '%s\n' "$pre_step" | grep -F 'ipa_sha256_after_export' >/dev/null && printf '%s\n' "$pre_step" | grep -F 'ipa_sha256_after_verification' >/dev/null && printf '%s\n' "$pre_step" | grep -F '"$now" = "$exported" ] && [ "$now" = "$verified"' >/dev/null; chk "upload: the file uploaded is the file exported and verified (its digest is compared with the export's, the verification's and, again, just before the upload)" $?
printf '%s\n' "$pre_step" | grep -F 'git ls-remote' >/dev/null && printf '%s\n' "$pre_step" | grep -F 'check_signing_authorization.sh --record' >/dev/null && printf '%s\n' "$pre_step" | grep -F '[ "$op" = "sign-verify-and-upload" ]' >/dev/null && printf '%s\n' "$pre_step" | grep -F -- '--development-tip "$tip"' >/dev/null; chk "upload: the authorization (and the operation) is read again right before the upload with the live tip of development" $?
l_v7u="$(printf '%s\n' "$sign" | grep -n 'verify_ipa.py verify production' | head -1 | cut -d: -f1)"; l_v9u="$(printf '%s\n' "$sign" | grep -n 'name: Native library identity' | head -1 | cut -d: -f1)"; l_dgu="$(printf '%s\n' "$sign" | grep -n 'name: Fix the IPA digest again' | head -1 | cut -d: -f1)"
l_pre="$(printf '%s\n' "$sign" | grep -n 'name: Re-check the upload authorization' | head -1 | cut -d: -f1)"; l_up="$(printf '%s\n' "$sign" | grep -n 'name: Validate and upload the verified IPA' | head -1 | cut -d: -f1)"; l_exp="$(printf '%s\n' "$sign" | grep -n 'name: Export and sign' | head -1 | cut -d: -f1)"; l_probe="$(printf '%s\n' "$sign" | grep -n 'name: Probe Apple' | head -1 | cut -d: -f1)"
l_k2="$(printf '%s\n' "$sign" | grep -n 'name: Check again that no key file remains' | head -1 | cut -d: -f1)"; l_seal2="$(printf '%s\n' "$sign" | grep -n 'name: Seal the evidence' | head -1 | cut -d: -f1)"
[ -n "$l_v7u" ] && [ -n "$l_v9u" ] && [ -n "$l_dgu" ] && [ -n "$l_pre" ] && [ -n "$l_up" ] && [ "$l_v7u" -lt "$l_v9u" ] && [ "$l_v9u" -lt "$l_dgu" ] && [ "$l_dgu" -lt "$l_pre" ] && [ "$l_pre" -lt "$l_up" ]; chk "upload: the order is V7, V8 and V9, the digest check, the pre-check, the upload (so every verification is an earlier step of the job)" $?
[ -n "$l_probe" ] && [ -n "$l_exp" ] && [ "$l_probe" -lt "$l_exp" ]; chk "upload: Apple's upload tool is probed BEFORE the export, so a tool that cannot be used stops the run before any credential is used" $?
[ -n "$l_k2" ] && [ -n "$l_seal2" ] && [ "$l_up" -lt "$l_k2" ] && [ "$l_k2" -lt "$l_seal2" ] && printf '%s\n' "$(step_of "$sign" 'Check again that no key file remains')" | grep -E '^        if: always\(\)$' >/dev/null; chk "upload: a step that always runs checks again, after the upload, that no key file remains" $?
k2step="$(step_of "$sign" 'Check again that no key file remains')"
! printf '%s\n' "$k2step" | grep -E 'echo[^|]*\$\{?left|::error::[^"]*\$\{?left|rm -P -f \$left *$|rm -rf [^>]*$' >/dev/null && printf '%s\n' "$k2step" | grep -F 'rm -P -f $left >/dev/null 2>&1 || rm -f $left >/dev/null 2>&1' >/dev/null; chk "upload: the final key-file check never prints a key file's name (it names the key ID): not in its error, and the removal commands' own messages are discarded" $?
grep -F 'APP_APPLE_ID: "6753348211"' "$wf" >/dev/null; chk "constant APP_APPLE_ID is the production App Store Connect record of the release record (section 5 item 2)" $?
! printf '%s\n' "$code" | grep -E 'gh (release|api|pr|issue)|curl |wget |git (push|commit|tag)|actions/create-release|softprops' >/dev/null; chk "no release, tag, push, API or network download command" $?
bad_paths="$(printf '%s\n' "$code" | grep -E '^[[:space:]]+path: ' | sed 's/^[[:space:]]*path: //' | grep -vxE 'evidence/|handover|handover/Runner\.xcarchive\.tar|tools|approved' || true)"
[ -z "$bad_paths" ]; chk "every artifact or checkout path is evidence/, the unsigned tar, or a checkout directory" $? "$bad_paths"
! printf '%s\n' "$code" | grep -E '^[[:space:]]+path:.*(\.ipa|export|RUNNER_TEMP|\.p8|\.p12|mobileprovision|keychain)' >/dev/null; chk "no artifact path can reach the IPA, the export directory, a key, a profile or a keychain" $?
[ "$(printf '%s\n' "$code" | grep -c 'uses: actions/upload-artifact@')" -eq 3 ] && ! printf '%s\n' "$sign" | grep -E 'path: .*(handover|Runner)' | grep -A0 upload >/dev/null; chk "three artifacts only: the unsigned tar (1 day), the build evidence and the signing evidence" $?
printf '%s\n' "$build" | grep -B1 -A4 'name: ios-hosted-unsigned-archive_' | grep -F 'retention-days: 1' >/dev/null; chk "the unsigned archive is kept one day" $?
printf '%s\n' "$sign" | grep -F 'PRIVATE KEY|BEGIN PKCS7|eyJ' >/dev/null && printf '%s\n' "$sign" | grep -F 'refusing to keep them' >/dev/null; chk "the signing evidence is scanned for key material and JWT-shaped tokens and kept as text only" $?
ustep="$(step_of "$sign" 'Upload the text evidence')"
printf '%s\n' "$ustep" | grep -E '^        if: always\(\)$' >/dev/null && printf '%s\n' "$ustep" | grep -F 'name: ios-hosted-signing-evidence_' >/dev/null; chk "the evidence is uploaded even after a failed step" $?

# ---- Phase 7C: the V8 and DER evidence capture. Read-only, no secret, no signal of its own: it must not become a way to change a verdict ----
cstep="$(step_of "$sign" 'Capture the Info.plist and DER entitlements evidence')"
[ "$(printf '%s\n' "$sign" | grep -c '^      - name: Capture the Info.plist and DER entitlements evidence')" -eq 1 ]; chk "capture: exactly one evidence-capture step in the signing job" $?
printf '%s\n' "$cstep" | grep -E '^        if: always\(\)$' >/dev/null; chk "capture: it runs after a failed V7 or V8 too (if: always())" $?
! printf '%s\n' "$code" | grep -E 'continue-on-error' >/dev/null; chk "capture: no step of the workflow is continue-on-error (a failing step stays a failing job)" $?
! printf '%s\n' "$cstep" | grep -E 'secrets\.|APPLE_API|env:|id-token|curl |wget |gh |git (push|clone|fetch)|upload-artifact|\.p8|keychain|security ' >/dev/null; chk "capture: it uses no secret, no credential, no network command and uploads nothing itself" $?
printf '%s\n' "$cstep" | grep -F 'python3 -I tools/tool/verify_ipa.py capture-evidence' >/dev/null && printf '%s\n' "$cstep" | grep -F -- '--out evidence/v8-capture' >/dev/null && printf '%s\n' "$cstep" | grep -F -- '--evidence-dir evidence' >/dev/null; chk "capture: it runs the read-only subcommand and writes only under evidence/v8-capture" $?
! printf '%s\n' "$cstep" | grep -E '(^|[[:space:]])(cp|mv|ditto|rm|tee|cat >|>) ' | grep -vE 'mkdir|>/dev/null|2>/dev/null' >/dev/null; chk "capture: it copies, moves and removes nothing (the IPA is read by path, never kept)" $?
l_v7="$(printf '%s\n' "$sign" | grep -n 'verify_ipa.py verify production' | head -1 | cut -d: -f1)"
l_dg="$(printf '%s\n' "$sign" | grep -n 'name: Fix the IPA digest again' | head -1 | cut -d: -f1)"
l_cap="$(printf '%s\n' "$sign" | grep -n 'name: Capture the Info.plist and DER entitlements evidence' | head -1 | cut -d: -f1)"
l_seal="$(printf '%s\n' "$sign" | grep -n 'name: Seal the evidence' | head -1 | cut -d: -f1)"
[ -n "$l_v7" ] && [ -n "$l_dg" ] && [ -n "$l_cap" ] && [ -n "$l_seal" ] && [ "$l_v7" -lt "$l_cap" ] && [ "$l_dg" -lt "$l_cap" ] && [ "$l_cap" -lt "$l_seal" ]; chk "capture: it comes after the IPA verification (V7, V8, V9, the digest) and before the evidence is sealed" $?
l_key="$(printf '%s\n' "$sign" | grep -n 'name: Check that the key file is gone' | head -1 | cut -d: -f1)"
[ -n "$l_key" ] && [ "$l_key" -lt "$l_cap" ]; chk "capture: it runs only after the key file has been removed and checked" $?
printf '%s\n' "$sign" | grep -F 'verify_ipa.py verify production "$IPA" --team-id "$TEAM_ID" --repo "$VERIFIER_REPO"' >/dev/null && printf '%s\n' "$sign" | grep -F -- '--unsigned-app "$BASELINE_APP"' >/dev/null && printf '%s\n' "$sign" | grep -F 'verify_ipa.py compare "$BASELINE_APP" "$APP"' >/dev/null; chk "capture: V7 and V8 are still the same commands on the same inputs (V8 compares the archive's app with the exported one, byte for byte)" $?
! printf '%s\n' "$sign" | grep -E 'capture-evidence' | grep -vE 'python3 -I tools/tool/verify_ipa.py capture-evidence' >/dev/null; chk "capture: the subcommand is called in one way only" $?
# the failed-export distribution log: THIS run's bundle only, through the same redaction, inside the credential step
printf '%s\n' "$secret_step" | grep -F 'findlog.py' >/dev/null && printf '%s\n' "$secret_step" | grep -F '.export-start' >/dev/null && printf '%s\n' "$secret_step" | grep -F 'redact "$logdir/Packaging.log" evidence/Packaging.log' >/dev/null; chk "packaging log: after a failed export the log of this run is collected, through the redaction" $?
! printf '%s\n' "$secret_step" | grep -E '(cp|mv|ditto|cat) [^|]*(logdir|xcdistributionlogs)' >/dev/null; chk "packaging log: it is never copied unredacted" $?
printf '%s\n' "$secret_step" | grep -F 'os.path.realpath(os.path.dirname(path)) != tmpdir' >/dev/null; chk "packaging log: the bundle must lie directly inside the step's own temporary directory" $?
printf '%s\n' "$secret_step" | grep -F 'os.path.islink(path)' >/dev/null && printf '%s\n' "$secret_step" | grep -F 'os.path.islink(log)' >/dev/null && printf '%s\n' "$secret_step" | grep -F 'st_mtime < os.stat(marker).st_mtime' >/dev/null; chk "packaging log: a link, or a bundle older than this export run, is refused" $?
l_find="$(printf '%s\n' "$secret_step" | grep -n 'findlog.py" "\$RUNNER_TEMP/export.raw.log"' | head -1 | cut -d: -f1)"
l_clean="$(printf '%s\n' "$secret_step" | grep -n '^          cleanup$' | tail -1 | cut -d: -f1)"
[ -n "$l_find" ] && [ -n "$l_clean" ] && [ "$l_find" -lt "$l_clean" ]; chk "packaging log: the redaction runs while the key file still exists (before the cleanup)" $?

# ---- the build job keeps the existing controls ----
for needle in 'Verify the source (SHA, production ancestry, reviewed content, clean tree, version)' 'tool/verify_build_config.sh verify' 'tool/verify_version.sh' 'EXPECTED_RUST_LIB_SHA256' 'tool/verify_artifact.sh ios' 'tool/check_build_drift.sh' 'flutter pub get --enforce-lockfile' 'flutter build ipa --release --no-codesign'; do
  printf '%s\n' "$build" | grep -F -- "$needle" >/dev/null; chk "build job keeps: $needle" $?
done
[ "$(printf '%s\n' "$build" | grep -cE '^[[:space:]]+flutter build ')" -eq 1 ]; chk "the build job compiles once (one flutter build command)" $?
printf '%s\n' "$build" | grep -F 'ref: ${{ inputs.approved_sha }}' >/dev/null && printf '%s\n' "$build" | grep -F 'persist-credentials: false' >/dev/null; chk "the build checks out exactly the approved commit, without credentials" $?
[ "$(printf '%s\n' "$code" | grep -c 'persist-credentials: false')" -eq "$(printf '%s\n' "$code" | grep -c 'uses: actions/checkout@')" ]; chk "every checkout drops the token (persist-credentials: false)" $?
# the pins must equal those of the iOS validation workflow
for key in XCODE_APP EXPECTED_XCODE EXPECTED_MIN_SDK_MAJOR EXPECTED_COCOAPODS EXPECTED_FLUTTER EXPECTED_FLUTTER_REVISION EXPECTED_DART EXPECTED_RUST_LIB_SHA256; do
  a="$(grep -E "^  $key:" "$wf" | head -1 | sed 's/[[:space:]]*#.*//')"
  b="$(grep -E "^  $key:" "$root/.github/workflows/ios-ci-validation.yml" | head -1 | sed 's/[[:space:]]*#.*//')"
  [ -n "$a" ] && [ "$a" = "$b" ]; chk "$key equals the pin of the iOS validation workflow" $?
done
# identity constants
for kv in 'BUNDLE_ID: com.app.cadenabitcoin' 'TEAM_ID: D65458CPDP' 'BUILD_ENV: production'; do grep -E "^  $kv\$" "$wf" >/dev/null; chk "constant $kv" $?; done
grep -F 'D65458CPDP' "$root/ios/Runner.xcodeproj/project.pbxproj" >/dev/null; chk "the team ID equals DEVELOPMENT_TEAM of the Xcode project" $?

# ---- statements the file must make ----
grep -F 'sign and verify ONLY' "$wf" >/dev/null && grep -F 'NOT an upload' "$wf" >/dev/null; chk "the header says sign-and-verify only and not an upload" $?
grep -F 'not an Apple approval' "$wf" >/dev/null; chk "it says a green run is not an Apple approval" $?

# ---- supporting files, and every embedded shell block parses ----
[ -x "$root/tool/check_signing_authorization.sh" ]; chk "tool/check_signing_authorization.sh exists and is executable" $?
[ -f "$root/docs/IOS_HOSTED_SIGNING.md" ]; chk "docs/IOS_HOSTED_SIGNING.md exists" $?
if python3 -c 'import yaml' 2>/dev/null; then
  out="$(python3 -I - "$wf" <<'PY'
import sys, subprocess, tempfile, os, yaml
d = yaml.safe_load(open(sys.argv[1]))
bad = 0
for j, v in d["jobs"].items():
    for i, st in enumerate(v["steps"]):
        if "run" in st:
            with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as f:
                f.write(st["run"])
            r = subprocess.run(["bash", "-n", f.name], capture_output=True, text=True)
            os.unlink(f.name)
            if r.returncode:
                bad += 1
                print("syntax error in %s step %d (%s): %s" % (j, i, st.get("name"), r.stderr.strip()))
print("bad=%d" % bad)
sys.exit(1 if bad else 0)
PY
)"; rc=$?
  chk "the workflow is valid YAML and every embedded shell block passes bash -n" $rc "$out"
else
  ok "the workflow YAML and shell blocks were NOT parsed (PyYAML is not installed here; the hosted Linux runner has it)"
fi

echo
echo "test_ios_hosted_signing: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
