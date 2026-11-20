#!/usr/bin/env bash
# Static tests of the hosted iOS signing workflow of Issue #71: .github/workflows/ios-hosted-signing.yml
# (docs/IOS_HOSTED_SIGNING.md). They READ the file; they run nothing on macOS, contact no Apple service and start nothing
# on GitHub.
#
#   tool/test_ios_hosted_signing.sh
#
# What they protect: the workflow must stay manual, upload-free, development-only, gated by the release record, and it must
# keep the one step that holds the Apple API key small, isolated and cleaned up. Exit 0 only if every check passes.
# (No `grep -q` at the end of a pipeline: under pipefail an early-closed pipe is a SIGPIPE failure.)
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/ios-hosted-signing.yml"
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
[ "$nsec" -eq 3 ]; chk "exactly three secret references (found $nsec)" $?
names="$(printf '%s\n' "$code" | grep -o 'secrets\.[A-Z0-9_]*' | sort | tr '\n' ' ')"
[ "$names" = "secrets.APPLE_API_ISSUER_ID secrets.APPLE_API_KEY_ID secrets.APPLE_API_KEY_P8 " ]; chk "they are APPLE_API_KEY_P8, APPLE_API_KEY_ID and APPLE_API_ISSUER_ID (found: $names)" $?
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

# ---- nothing is uploaded, nothing is released ----
! printf '%s\n' "$code" | grep -iE 'altool|iTMSTransporter|Transporter\.app|--upload|upload-app|upload-package|validate-app|api\.appstoreconnect|appstoreconnect\.apple|reviewSubmissions|betaAppReview|submitForReview|fastlane|pilot|deliver' >/dev/null; chk "no upload, validation, review, TestFlight or App Store Connect call of any kind" $?
! printf '%s\n' "$code" | grep -E 'gh (release|api|pr|issue)|curl |wget |git (push|commit|tag)|actions/create-release|softprops' >/dev/null; chk "no release, tag, push, API or network download command" $?
bad_paths="$(printf '%s\n' "$code" | grep -E '^[[:space:]]+path: ' | sed 's/^[[:space:]]*path: //' | grep -vxE 'evidence/|handover|handover/Runner\.xcarchive\.tar|tools|approved' || true)"
[ -z "$bad_paths" ]; chk "every artifact or checkout path is evidence/, the unsigned tar, or a checkout directory" $? "$bad_paths"
! printf '%s\n' "$code" | grep -E '^[[:space:]]+path:.*(\.ipa|export|RUNNER_TEMP|\.p8|\.p12|mobileprovision|keychain)' >/dev/null; chk "no artifact path can reach the IPA, the export directory, a key, a profile or a keychain" $?
[ "$(printf '%s\n' "$code" | grep -c 'uses: actions/upload-artifact@')" -eq 3 ] && ! printf '%s\n' "$sign" | grep -E 'path: .*(handover|Runner)' | grep -A0 upload >/dev/null; chk "three artifacts only: the unsigned tar (1 day), the build evidence and the signing evidence" $?
printf '%s\n' "$build" | grep -B1 -A4 'name: ios-hosted-unsigned-archive_' | grep -F 'retention-days: 1' >/dev/null; chk "the unsigned archive is kept one day" $?
printf '%s\n' "$sign" | grep -F 'grep -rlE '"'"'PRIVATE KEY|BEGIN PKCS7'"'"' evidence' >/dev/null && printf '%s\n' "$sign" | grep -F 'refusing to keep them' >/dev/null; chk "the signing evidence is scanned for key material and kept as text only" $?
ustep="$(step_of "$sign" 'Upload the text evidence')"
printf '%s\n' "$ustep" | grep -E '^        if: always\(\)$' >/dev/null && printf '%s\n' "$ustep" | grep -F 'name: ios-hosted-signing-evidence_' >/dev/null; chk "the evidence is uploaded even after a failed step" $?

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
