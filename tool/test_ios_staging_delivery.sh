#!/usr/bin/env bash
# Static tests of the automatic iOS STAGING delivery: .github/workflows/ios-staging-delivery.yml (docs/IOS_STAGING_DELIVERY.md), and of the
# Android staging APK delivery it sits beside (.github/workflows/android-ci-validation.yml). They READ files; they run nothing on macOS, contact
# no Apple service and start nothing on GitHub.
#
#   tool/test_ios_staging_delivery.sh
#
# What they protect: the workflow starts only for a push to `staging`; it can handle only the STAGING identity; it signs and uploads only after the
# staging gate; the two steps that hold the Apple key stay small, isolated and cleaned up; and every step that holds a secret or judges the IPA is the
# SAME TEXT as the production workflow's, which signed and uploaded a real IPA (run 45221165334), apart from a short, listed set of re-pointings.
# The production workflow itself must stay byte-identical to the blob its release record binds. Exit 0 only if every check passes.
# (No `grep -q` at the end of a pipeline: under pipefail an early-closed pipe is a SIGPIPE failure.)
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="${STAGING_DELIVERY_WORKFLOW:-$root/.github/workflows/ios-staging-delivery.yml}"
prod="$root/.github/workflows/ios-hosted-signing.yml"
acv="$root/.github/workflows/android-ci-validation.yml"
pass=0; failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
chk() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "${3:-}"; fi; }

[ -f "$wf" ] || { echo "FAIL the workflow file is missing: $wf"; exit 1; }
[ -f "$prod" ] || { echo "FAIL the production workflow is missing: $prod"; exit 1; }
code="$(grep -vE '^[[:space:]]*#' "$wf")"
jobs="$(printf '%s\n' "$code" | sed -n '/^jobs:/,$p')"
job_text() { printf '%s\n' "$jobs" | awk -v j="$1" '$0 ~ "^  "j":$" {f=1; next} /^  [a-z][a-z-]*:$/ {f=0} f'; }
step_of() { printf '%s\n' "$1" | awk -v n="$2" '/^      - name:/ {f = (index($0, n) > 0)} f'; }
authorize="$(job_text authorize)"; build="$(job_text build)"; sign="$(job_text sign)"

echo "== shape, triggers, permissions"
[ -n "$authorize" ] && [ -n "$build" ] && [ -n "$sign" ] && [ "$(printf '%s\n' "$jobs" | grep -cE '^  [a-z][a-z-]*:$')" -eq 3 ]; chk "exactly the jobs authorize, build and sign" $?
triggers="$(printf '%s\n' "$code" | sed -n '/^on:/,/^permissions:/p' | grep -E '^  [a-z_]+:' | tr -d ' :' | tr '\n' ' ')"
[ "$triggers" = "push " ]; chk "starts only on push (found: $triggers)" $?
branches="$(printf '%s\n' "$code" | sed -n '/^on:/,/^permissions:/p' | grep -E '^    branches:' | tr -d ' ')"
[ "$branches" = "branches:[staging]" ]; chk "and only for the branch staging (found: $branches)" $?
! printf '%s\n' "$code" | grep -E 'workflow_dispatch|pull_request|workflow_run|schedule:|repository_dispatch|workflow_call|tags:|paths:|paths-ignore:' >/dev/null; chk "no manual, pull-request, scheduled, reusable, tag or path trigger" $?
perm="$(printf '%s\n' "$code" | sed -n '/^permissions:/,/^concurrency:/p' | grep -E '^  [a-z-]+:' | tr -d ' ' | tr '\n' ' ')"
[ "$perm" = "contents:read " ]; chk "the workflow permissions are exactly contents: read (found: $perm)" $?
! printf '%s\n' "$code" | grep -E '^[[:space:]]+(permissions:|id-token|contents: write|actions: write|packages:|pull-requests:|issues:|checks:|statuses:|deployments:)' | grep -v '^permissions:' >/dev/null; chk "no job widens the permissions and the OIDC token is never requested" $?
printf '%s\n' "$code" | grep -E '^  group: ios-staging-delivery$' >/dev/null && printf '%s\n' "$code" | grep -E '^  cancel-in-progress: false$' >/dev/null; chk "one run at a time, never cancelled mid-signing" $?
for j in build sign; do
  t="$(job_text $j)"
  printf '%s\n' "$t" | grep -E '^    runs-on: macos-15$' >/dev/null; chk "job $j runs on macos-15 (not macos-latest)" $?
  printf '%s\n' "$t" | grep -E '^    timeout-minutes: [0-9]+$' >/dev/null; chk "job $j has a timeout" $?
done
printf '%s\n' "$authorize" | grep -E '^    runs-on: ubuntu-latest$' >/dev/null && printf '%s\n' "$authorize" | grep -E '^    timeout-minutes: [0-9]+$' >/dev/null; chk "job authorize runs on a hosted Linux runner with a timeout" $?
! printf '%s\n' "$code" | grep -E 'runs-on:.*self-hosted' >/dev/null; chk "no self-hosted runner (public repository)" $?
bad_uses="$(printf '%s\n' "$code" | grep -E '^[[:space:]]*-?[[:space:]]*uses:' | grep -vE '@[0-9a-f]{40}( |$)' || true)"
[ -z "$bad_uses" ]; chk "every action is pinned to a full commit SHA" $?
! printf '%s\n' "$code" | grep -E '\$\{\{[[:space:]]*(inputs|github\.event)' >/dev/null; chk "no input and no event payload field is used (nothing can name a version, bundle, application or commit)" $?
! printf '%s\n' "$code" | grep -E 'github\.head_ref|github\.ref_name|github\.actor|github\.event_name' | grep -E '\$\{\{' >/dev/null; chk "no attacker-influenced context value reaches the shell through an expression" $?
! printf '%s\n' "$code" | grep -E -- '--build-name|--build-number' >/dev/null; chk "no version override of any kind" $?
! printf '%s\n' "$code" | grep -E 'continue-on-error' >/dev/null; chk "no continue-on-error anywhere" $?

echo "== the staging identity, and no production"
printf '%s\n' "$code" | grep -E '^  BUILD_ENV: staging$' >/dev/null && printf '%s\n' "$code" | grep -E '^  BUILD_CONFIG_FILE: config/build/staging\.json$' >/dev/null; chk "the build environment is staging and the configuration file config/build/staging.json" $?
printf '%s\n' "$code" | grep -E '^  BUNDLE_ID: com\.app\.cadenabitcoin\.staging$' >/dev/null && printf '%s\n' "$code" | grep -E '^  DISPLAY_NAME: Cadena Signer STAGING$' >/dev/null; chk "the bundle ID is com.app.cadenabitcoin.staging and the display name Cadena Signer STAGING" $?
printf '%s\n' "$code" | grep -E '^  TEAM_ID: D65458CPDP$' >/dev/null; chk "the team is the committed one (D65458CPDP)" $?
! printf '%s\n' "$code" | grep -E 'com\.app\.cadenabitcoin([^.[:alnum:]_-]|$)' >/dev/null; chk "the production bundle ID com.app.cadenabitcoin appears nowhere" $?
! printf '%s\n' "$code" | grep -E 'production\.json|--flavor production|verify_ipa\.py verify production|6753348211|APP_ENV=production|BUILD_ENV: production' >/dev/null; chk "no production configuration, flavor, verifier mode or Apple application appears" $?
! printf '%s\n' "$code" | grep -E '^  APP_APPLE_ID:' >/dev/null; chk "the App Store Connect application is not a constant of the workflow (it comes from the record, and the gate refuses the production one)" $?
printf '%s\n' "$build" | grep -F -- 'flutter build ipa --release --no-codesign --flavor "$BUILD_ENV" --dart-define-from-file="$BUILD_CONFIG_FILE"' >/dev/null; chk "the one compile is flutter build ipa --release --no-codesign with the staging flavor and the staging configuration file" $?
[ "$(printf '%s\n' "$code" | grep -cE '^[[:space:]]+flutter build ')" -eq 1 ]; chk "and it is the only flutter build in the workflow" $?
printf '%s\n' "$sign" | grep -E 'verify_ipa\.py.* verify staging' >/dev/null && printf '%s\n' "$sign" | grep -F -- '--expect-cert-sha256 "$pin"' >/dev/null && printf '%s\n' "$sign" | grep -F -- '--forbid-entitlement aps-environment' >/dev/null && printf '%s\n' "$sign" | grep -E 'verify_ipa\.py.* certificate' >/dev/null && printf '%s\n' "$sign" | grep -E 'verify_ipa\.py compare' >/dev/null; chk "the IPA is verified in staging mode, pinned on the recorded certificate, no push entitlement, and compared with the archive (V3, V7, V8)" $?
printf '%s\n' "$sign" | grep -F -- '--unsigned-app "$BASELINE_APP"' >/dev/null && printf '%s\n' "$sign" | grep -F -- '--repo "$VERIFIER_REPO"' >/dev/null; chk "V8 compares with the archive that was exported (no second compile); the verifier's repository view is the assembled one" $?
printf '%s\n' "$sign" | grep -F 'verify_build_config.sh check-binary "$BUILD_ENV"' >/dev/null; chk "V6 checks the staging URL is in the app and the production URL is not" $?
printf '%s\n' "$sign" | grep -F 'CFBundleDisplayName' >/dev/null && printf '%s\n' "$sign" | grep -F '[ "$name" = "$DISPLAY_NAME" ]' >/dev/null && printf '%s\n' "$sign" | grep -F '[ "$bid" = "$BUNDLE_ID" ]' >/dev/null; chk "V1 checks the signed IPA's bundle ID and display name against the staging identity" $?
printf '%s\n' "$sign" | grep -F 'application-identifier=$TEAM_ID.$BUNDLE_ID' >/dev/null; chk "V4 checks the profile is the staging bundle's, for the team" $?

echo "== the authorization"
printf '%s\n' "$authorize" | grep -F 'check_staging_authorization.sh' >/dev/null && printf '%s\n' "$authorize" | grep -F -- '--bundle-id "$BUNDLE_ID" --team-id "$TEAM_ID"' >/dev/null && printf '%s\n' "$authorize" | grep -F -- '--remote "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY.git"' >/dev/null; chk "the authorize job runs the staging gate against the repository's own remote, with the workflow's constants" $?
printf '%s\n' "$authorize" | grep -F '"$GITHUB_REF" != "refs/heads/staging"' >/dev/null && printf '%s\n' "$authorize" | grep -F '"$GITHUB_EVENT_NAME" != "push"' >/dev/null; chk "the authorize job refuses any ref but refs/heads/staging and any event but push" $?
printf '%s\n' "$authorize" | grep -E '^          fetch-depth: 0$' >/dev/null; chk "the authorize job has the full history (the gate shows where the merged side came from)" $?
printf '%s\n' "$authorize" | grep -F 'if [ "$authorized" != true ]; then' >/dev/null && printf '%s\n' "$authorize" | grep -E '^            exit 1$' >/dev/null; chk "an unauthorized promotion makes the run FAIL (visibly red), never a silent green" $?
printf '%s\n' "$authorize" | grep -F 'upload_authorized: ${{ steps.gate.outputs.upload_authorized }}' >/dev/null && printf '%s\n' "$authorize" | grep -F -- '--print-field G2S-STAGING-OPERATION' >/dev/null && printf '%s\n' "$authorize" | grep -F '[ "$op" = "sign-verify-and-upload" ] && upload_authorized=true' >/dev/null; chk "the upload is authorized only when the record names the operation sign-verify-and-upload" $?
printf '%s\n' "$build" | grep -E '^    needs: \[authorize\]$' >/dev/null; chk "the build job runs only after the authorize job passed" $?
printf '%s\n' "$sign" | grep -E "^    if: needs\.authorize\.outputs\.authorized == 'true'$" >/dev/null && printf '%s\n' "$sign" | grep -E '^    needs: \[authorize, build\]$' >/dev/null; chk "the signing job runs only when the authorize job said yes, after the build" $?
! printf '%s\n' "$authorize" "$build" | grep 'secrets\.' >/dev/null; chk "the authorize and build jobs have no secret" $?
printf '%s\n' "$build" | grep -E '^    environment:' >/dev/null && bad_env=1 || bad_env=0; [ "$bad_env" -eq 0 ]; chk "the build job (third-party code) has no environment" $?
l_gate="$(printf '%s\n' "$sign" | grep -n 'check_staging_authorization.sh' | head -1 | cut -d: -f1)"
l_sec="$(printf '%s\n' "$sign" | grep -n 'secrets\.' | head -1 | cut -d: -f1)"
[ -n "$l_gate" ] && [ -n "$l_sec" ] && [ "$l_gate" -lt "$l_sec" ]; chk "the authorization is re-checked before the first secret reference" $?
printf '%s\n' "$sign" | grep -F -- '--head "$GITHUB_SHA"' >/dev/null && printf '%s\n' "$sign" | grep -F -- '--tools-root tools --repo tools' >/dev/null; chk "the signing job's gate checks the commit it runs on, with the full-history checkout of its own tools" $?
printf '%s\n' "$sign" | grep -F 'G2S-STAGING-CERT-SHA256' >/dev/null && printf '%s\n' "$sign" | grep -F 'echo "EXPECTED_CERT_SHA256=$pin" >> "$GITHUB_ENV"' >/dev/null; chk "the certificate pin is the RECORDED fingerprint, set before any signing (never discovered at run time)" $?
printf '%s\n' "$sign" | grep -F 'G2S-STAGING-APP-APPLE-ID' >/dev/null && printf '%s\n' "$sign" | grep -F 'echo "APP_APPLE_ID=$app_apple_id" >> "$GITHUB_ENV"' >/dev/null; chk "the Apple application the IPA goes to is read from the record, immediately before the upload" $?
printf '%s\n' "$sign" | grep -F 'name: Enforce the authorized dlc_wallet framework hash (no secret yet)' >/dev/null && printf '%s\n' "$sign" | grep -F -- '--print-field G2S-STAGING-DLC-WALLET-SHA256' >/dev/null && printf '%s\n' "$sign" | grep -F '[ "$actual" != "$authorized" ]' >/dev/null; chk "the native crypto library's framework must equal the recorded hash, before Xcode and before any secret" $?
l_dlc="$(printf '%s\n' "$sign" | grep -n 'Enforce the authorized dlc_wallet framework hash' | head -1 | cut -d: -f1)"
[ -n "$l_dlc" ] && [ -n "$l_sec" ] && [ "$l_dlc" -lt "$l_sec" ]; chk "(and that step is before the first secret reference)" $?

echo "== the secrets: three, two steps, one job, one environment"
nsec="$(printf '%s\n' "$code" | grep -c 'secrets\.')"
[ "$nsec" -eq 6 ]; chk "exactly six secret references: three in the export step and the same three in the upload step (found $nsec)" $?
names="$(printf '%s\n' "$code" | grep -o 'secrets\.[A-Z0-9_]*' | sort | tr '\n' ' ')"
[ "$names" = "secrets.APPLE_API_ISSUER_ID secrets.APPLE_API_ISSUER_ID secrets.APPLE_API_KEY_ID secrets.APPLE_API_KEY_ID secrets.APPLE_API_KEY_P8 secrets.APPLE_API_KEY_P8 " ]; chk "they are APPLE_API_KEY_P8, APPLE_API_KEY_ID and APPLE_API_ISSUER_ID, each twice" $?
! printf '%s\n' "$code" | grep -E 'secrets:[[:space:]]*inherit|\$\{\{[[:space:]]*secrets[[:space:]]*\}\}|toJSON\(secrets' >/dev/null; chk "secrets are never passed wholesale" $?
printf '%s\n' "$sign" | grep -E '^    environment: ios-hosted-signing-stg$' >/dev/null && [ "$(printf '%s\n' "$code" | grep -c 'environment:')" -eq 1 ]; chk "the signing job is the only job with an environment, and it is ios-hosted-signing-stg" $?
step_name='Export and sign with the cloud-managed Distribution certificate (the only step with secrets)'
secret_step="$(printf '%s\n' "$sign" | awk -v n="      - name: $step_name" '$0==n {f=1; print; next} /^      - name:/ {f=0} f')"
[ -n "$secret_step" ] && [ "$(printf '%s\n' "$secret_step" | grep -c 'secrets\.')" -eq 3 ]; chk "the export step exists and holds all three secrets at step level" $?
up_step="$(step_of "$sign" 'Validate and upload the verified IPA')"
[ "$(printf '%s\n' "$up_step" | grep -c 'secrets\.')" -eq 3 ]; chk "the upload step holds the other three" $?
! printf '%s\n' "$code" | grep -E 'set -[a-z]*x|xtrace|ACTIONS_STEP_DEBUG|ACTIONS_RUNNER_DEBUG' >/dev/null; chk "nothing traces (no set -x, xtrace or debug logging)" $?
! printf '%s\n' "$code" | grep -E 'printenv|^[[:space:]]*env[[:space:]]*(\||$)|^[[:space:]]*set[[:space:]]*\|' >/dev/null; chk "nothing dumps the environment" $?
! printf '%s\n' "$sign" | grep -E '(^|[;&|(])[[:space:]]*(flutter|dart|pod|gem|bundle|npm|yarn|pip3?|brew|gradle|gradlew|cargo|make|swift|fastlane)[[:space:]]' >/dev/null; chk "the signing job runs no build tool, package manager or dependency installer" $?
xb="$(printf '%s\n' "$sign" | grep -oE 'xcodebuild -[A-Za-z]+' | sort -u | tr '\n' ',')"
[ "$xb" = "xcodebuild -exportArchive,xcodebuild -version," ]; chk "the only xcodebuild commands of the signing job are -exportArchive and -version (found: $xb)" $?
! printf '%s\n' "$sign" | grep -E 'security (import|create-keychain|unlock-keychain|set-key-partition|default-keychain|list-keychains|add-trusted-cert)|\.p12|import-certificate|pkcs12|codesign (-s|--sign|-f|--force)' >/dev/null; chk "no keychain, .p12, certificate import or codesign signing (cloud-managed certificate only)" $?
! printf '%s\n' "$sign" | grep -E 'approved/tool|bash approved|python3? .*approved/|cd approved' >/dev/null; chk "no script of the promotion commit's checkout is executed in the signing job" $?

echo "== nothing is uploaded except through the gated steps"
up_names=('Probe Apple' 'Re-check the upload authorization' 'Validate and upload the verified IPA')
rest="$(printf '%s\n' "$code" | awk -v a="${up_names[0]}" -v b="${up_names[1]}" -v c="${up_names[2]}" '/^      - name:/ { skip = (index($0, a) > 0 || index($0, b) > 0 || index($0, c) > 0) } !skip')"
! printf '%s\n' "$rest" | grep -iE 'altool|iTMSTransporter|Transporter\.app|--upload|upload-app|upload-package|validate-app|api\.appstoreconnect|appstoreconnect\.apple|reviewSubmissions|betaAppReview|submitForReview|fastlane|pilot|(^|[^A-Za-z])deliver([^A-Za-z]|$)' >/dev/null; chk "outside the three upload steps nothing names Apple's upload tool or any App Store Connect, TestFlight or review route" $?
! printf '%s\n' "$code" | grep -iE 'iTMSTransporter|Transporter\.app|api\.appstoreconnect|appstoreconnect\.apple|reviewSubmissions|betaAppReview|submitForReview|fastlane|pilot|(^|[^A-Za-z])deliver([^A-Za-z]|$)|<string>upload</string>|destination.*upload' >/dev/null; chk "nowhere: no Transporter, no App Store Connect API, no tester or review call, no export destination upload" $?
probe_step="$(step_of "$sign" 'Probe Apple')"; pre_step="$(step_of "$sign" 'Re-check the upload authorization')"
[ "$(printf '%s\n' "$sign" | grep -cE '^      - name: (Probe Apple|Re-check the upload authorization|Validate and upload the verified IPA)')" -eq 3 ]; chk "the signing job has exactly the three upload steps" $?
for s in "$probe_step" "$pre_step" "$up_step"; do printf '%s\n' "$s" | grep -E "^        if: needs\.authorize\.outputs\.upload_authorized == 'true'$" >/dev/null || { bad_if=1; }; done; [ "${bad_if:-0}" -eq 0 ]; chk "each runs only when the authorize job said the upload is authorized" $?
! printf '%s\n%s\n%s\n' "$probe_step" "$pre_step" "$up_step" | grep -E 'always\(\)|failure\(\)|cancelled\(\)|success\(\) *\|\|' >/dev/null; chk "none of them can run after a failed step (no always(), failure(), cancelled())" $?
! printf '%s\n%s\n' "$probe_step" "$pre_step" | grep -E 'secrets\.|APPLE_API|\.p8|keychain' >/dev/null; chk "the probe and the pre-check hold no secret and touch no key" $?
[ "$(printf '%s\n' "$up_step" | grep -c -- '--upload-package')" -eq 1 ] && [ "$(printf '%s\n' "$code" | grep -c 'altool')" -eq "$(printf '%s\n' "$probe_step" "$up_step" | grep -c 'altool')" ]; chk "the upload command appears once, and altool is named only in the probe and the upload step" $?
l_pre="$(printf '%s\n' "$sign" | grep -n 'Re-check the upload authorization' | head -1 | cut -d: -f1)"; l_up="$(printf '%s\n' "$sign" | grep -n 'Validate and upload the verified IPA' | head -1 | cut -d: -f1)"; l_v9="$(printf '%s\n' "$sign" | grep -n 'Native library identity' | head -1 | cut -d: -f1)"
[ -n "$l_pre" ] && [ -n "$l_up" ] && [ -n "$l_v9" ] && [ "$l_v9" -lt "$l_pre" ] && [ "$l_pre" -lt "$l_up" ]; chk "the verifications V1 to V9 come before the pre-check, and the pre-check before the upload" $?
printf '%s\n' "$up_step" | grep -F -- '--apple-id "$APP_APPLE_ID"' >/dev/null && printf '%s\n' "$up_step" | grep -F -- '--bundle-id "$UPLOAD_BUNDLE_ID"' >/dev/null; chk "the upload names the application from the record and the bundle ID read from the verified IPA" $?

echo "== traceability and failure handling"
printf '%s\n' "$sign" | grep -F 'name: Record the delivery' >/dev/null && printf '%s\n' "$sign" | grep -F 'evidence/delivery-record.txt' >/dev/null && printf '%s\n' "$sign" | grep -F 'delivery_uuid=' >/dev/null && printf '%s\n' "$sign" | grep -F 'promotion_commit=$GITHUB_SHA' >/dev/null; chk "a delivery record ties the promotion commit to version, build, IPA digest and Apple's delivery identifier" $?
step_of "$sign" 'Record the delivery' | grep -E '^        if: always\(\)$' >/dev/null; chk "and it is written even when the delivery failed" $?
! step_of "$sign" 'Record the delivery' | grep -E 'secrets\.|APPLE_API|\.p8' >/dev/null; chk "(it holds no secret)" $?
kstep="$(step_of "$sign" 'Check that the key file is gone')"; k2="$(step_of "$sign" 'Check again that no key file remains')"
printf '%s\n' "$kstep" | grep -E '^        if: always\(\)$' >/dev/null && printf '%s\n' "$k2" | grep -E '^        if: always\(\)$' >/dev/null; chk "steps that run even after a failure check that no key file remains (after the export and after the upload)" $?
printf '%s\n' "$sign" | grep -E 'name: Upload the text evidence' >/dev/null && step_of "$sign" 'Upload the text evidence' | grep -E '^        if: always\(\)$' >/dev/null && step_of "$sign" 'Upload the text evidence' | grep -E '^          retention-days: 30$' >/dev/null; chk "the text evidence is kept for 30 days even after a failure" $?
step_of "$build" 'Upload the unsigned archive' | grep -E '^          retention-days: 1$' >/dev/null; chk "the unsigned hand-over archive is kept for one day only" $?
printf '%s\n' "$sign" | grep -F 'grep -rlE '"'"'PRIVATE KEY|BEGIN PKCS7' >/dev/null; chk "the evidence is scanned for key, profile and token material before it is uploaded" $?
up_paths="$(printf '%s\n' "$code" | awk '/^      - name:/ {u = 0} /actions\/upload-artifact@/ {u = 1} u && /^          path:/ {print $2}' | sort | tr '\n' ' ')"
[ "$up_paths" = "evidence/ evidence/ handover/Runner.xcarchive.tar " ]; chk "the only artifact paths are the text evidence (twice) and the one-day unsigned archive: no IPA, key or profile (found: $up_paths)" $?

echo "== parity with the production workflow (steps that hold a secret or judge the IPA are the same text)"
norm_step() { # FILE JOB FRAGMENT -> comment-free step text with the listed re-pointings undone
  local file="$1" job="$2" frag="$3" t
  t="$(grep -vE '^[[:space:]]*#' "$file" | sed -n '/^jobs:/,$p' | awk -v j="$job" '$0 ~ "^  "j":$" {f=1; next} /^  [a-z][a-z-]*:$/ {f=0} f')"
  step_of "$t" "$frag" | sed \
    -e 's/ios-hosted-signing-stg is missing (docs\/IOS_STAGING_DELIVERY\.md section 5)/ios-hosted-signing is missing (docs\/IOS_HOSTED_SIGNING.md section 4)/' \
    -e 's/\${{ needs\.authorize\.outputs\.version }}/${{ inputs.expected_version }}/' \
    -e 's/\${{ github\.sha }}/${{ inputs.approved_sha }}/' \
    -e 's/promotion commit/approved commit/g' \
    -e 's/(decision D6: no push entitlement)/(decision D6: none in 1.0.4)/' \
    -e 's/ios-staging-unsigned-archive_/ios-hosted-unsigned-archive_/; s/ios-staging-build-evidence_/ios-hosted-build-evidence_/; s/ios-staging-delivery-evidence_/ios-hosted-signing-evidence_/' \
    -e 's/Look in App Store Connect (the staging application) for build \$UPLOAD_SHORT_VERSION (\$UPLOAD_BUILD) BEFORE/Look in App Store Connect for a build 1.0.4 (1000035) BEFORE/'
}
same() { # JOB FRAGMENT DESCRIPTION
  local a b
  a="$(norm_step "$prod" "$1" "$2")"; b="$(norm_step "$wf" "$1" "$2")"
  if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "identical to production: $3"; else bad "identical to production: $3" "$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -n 6)"; fi
}
same sign 'Export and sign with the cloud-managed' "the export step (the first step with the key)"
same sign 'Validate and upload the verified IPA' "the upload step (the second step with the key)"
same sign 'Probe Apple' "the probe of Apple's upload tool"
same sign 'Check that the key file is gone' "the key-file check after the export"
same sign 'Check again that no key file remains' "the key-file check after the upload"
same sign 'Record the signing material' "the signing-material record"
same sign 'Select Xcode 26.3' "the Xcode selection (sign)"
same sign 'Check the archive digest' "the hand-over validation, before and after extraction"
same sign 'Download the unsigned archive' "the hand-over download"
same sign "Assemble the verifier" "the verifier's repository view"
same sign 'Unpack the exported IPA' "V1 (identity and version of the signed IPA)"
same sign 'Embedded profile and entitlements' "V4 and V5 (profile and entitlements)"
same sign 'Native library identity' "V9 (native library symbols)"
same sign 'Fix the IPA digest again' "the IPA digest check"
same sign 'Capture the Info.plist' "the V8 evidence capture"
same sign 'Seal the evidence' "the evidence seal (binary and secret scan)"
same sign 'Upload the text evidence' "the evidence upload (apart from its name)"
for f in 'Select Xcode 26.3' 'Set up Flutter 3.35.3' 'Record and verify toolchain' 'Resolve dependencies exactly' 'Repository checks' 'Check that the prebuilt Rust' 'Build the unsigned archive' 'Verify the unsigned app' 'Pack the unsigned archive' 'Seal the build evidence'; do
  same build "$f" "build job: $f"
done

echo "== the production workflow is untouched"
want_blob="$(bash "$root/tool/check_signing_authorization.sh" --print-field G2S-WORKFLOW-BLOB --record "$root/docs/release-records/ios-1.0.4-1000035.md" --tools-root "$root" 2>/dev/null)"
have_blob="$(git hash-object "$prod")"
[ -n "$want_blob" ] && [ "$want_blob" = "$have_blob" ]; chk "ios-hosted-signing.yml is byte-identical to the blob its production release record binds ($have_blob)" $? "record names '$want_blob'"
trg="$(grep -vE '^[[:space:]]*#' "$prod" | sed -n '/^on:/,/^permissions:/p' | grep -E '^  [a-z_]+:' | tr -d ' :' | tr '\n' ' ')"
[ "$trg" = "workflow_dispatch " ]; chk "and it is still manual-only (found: $trg)" $?

echo "== Android staging APK delivery stays operational (android-ci-validation.yml, not modified by this change)"
acode="$(grep -vE '^[[:space:]]*#' "$acv")"
atr="$(printf '%s\n' "$acode" | sed -n '/^on:/,/^permissions:/p' | tr -d ' ' | tr '\n' ' ')"
printf '%s\n' "$atr" | grep -F 'push: branches:[staging]' >/dev/null; chk "it still runs on every push to staging" $?
printf '%s\n' "$acode" | grep -E '^  BUILD_CONFIG_FILE: config/build/staging\.json$' >/dev/null && printf '%s\n' "$acode" | grep -E '^  BUILD_FLAVOR: staging$' >/dev/null; chk "it still builds the staging flavor with the staging configuration" $?
printf '%s\n' "$acode" | grep -F 'flutter build apk --debug --flavor "$BUILD_FLAVOR" --dart-define-from-file="$BUILD_CONFIG_FILE"' >/dev/null; chk "it still builds the APK with the explicit flavor and configuration file" $?
printf '%s\n' "$acode" | grep -F 'tool/verify_artifact.sh apk "$BUILD_FLAVOR"' >/dev/null && printf '%s\n' "$acode" | grep -F -- '--signing debug' >/dev/null; chk "it still verifies the APK (application ID, name, icon, version) and classifies its signing" $?
printf '%s\n' "$acode" | grep -E 'actions/upload-artifact@' >/dev/null && printf '%s\n' "$acode" | grep -E '^          retention-days: 14$' >/dev/null; chk "it still uploads the APK as a GitHub Actions artifact, kept 14 days" $?
printf '%s\n' "$acode" | grep -F 'short_sha' >/dev/null && printf '%s\n' "$acode" | grep -F '_staging_' >/dev/null || printf '%s\n' "$acode" | grep -F 'app_env' >/dev/null; chk "its artifact name still carries the version, the environment and the source commit" $?
! printf '%s\n' "$acode" | grep -E 'secrets\.|CADENA_SIGNING' >/dev/null; chk "it holds no credential (debug-signed with an ephemeral key; no Android signing infrastructure is needed for staging)" $?

echo "== the credential model: temporary Admin key, approval before signing (CTO decision on Issue #71, 2026-11-26)"
doc="$root/docs/IOS_STAGING_DELIVERY.md"; rec="$root/docs/release-records/ios-staging-authorization.md"
[ -f "$doc" ] && [ -f "$rec" ]; chk "the design document and the record exist" $?
printf '%s\n' "$sign" | grep -E '^    environment: ios-hosted-signing-stg$' >/dev/null && printf '%s\n' "$sign" | grep -E '^    needs: \[authorize, build\]$' >/dev/null; chk "the signing job is the one that declares the approval environment, after authorize and build" $?
! printf '%s\n' "$authorize" | grep -E '^    environment:' >/dev/null && ! printf '%s\n' "$build" | grep -E '^    environment:' >/dev/null; chk "so the credential-free jobs authorize and build have no environment and never wait" $?
grep -E '^# WHAT STARTS IT\.' "$wf" >/dev/null && grep -F 'waits for the approval of the protected environment `ios-hosted-signing-stg`' "$wf" >/dev/null && grep -F 'removes the secrets after the run' "$wf" >/dev/null; chk "the workflow header states the approval and the temporary credential" $?
! grep -F 'No person starts anything afterwards' "$wf" >/dev/null && ! grep -F 'No required reviewers' "$wf" >/dev/null; chk "and no longer claims that nobody acts after the merge or that no reviewers exist" $?
arch_step="$(step_of "$build" 'Upload the unsigned archive')"
printf '%s\n' "$arch_step" | grep -E '^          retention-days: 1$' >/dev/null && printf '%s\n' "$arch_step" | grep -E 'handover/Runner\.xcarchive\.tar' >/dev/null; chk "the unsigned archive handed to the signing job is kept exactly ONE day" $?
grep -F '### 1.2 The one-day retention constraint' "$doc" >/dev/null && grep -F 'retention-days: 1' "$doc" >/dev/null && grep -F 'before any secret is read' "$doc" >/dev/null; chk "the document states the one-day retention constraint and its consequence" $?
order_ok=0; prev=0
for k in '| 1 | Maintainers |' '| 2 | GitHub |' '| 3 | GitHub |' '| 4 | CTO |' '| 5 | CTO |' '| 6 | GitHub |' '| 7 | CTO |'; do
  n="$(grep -nF -- "$k" "$doc" | head -n1 | cut -d: -f1)"
  if [ -n "$n" ] && [ "$n" -gt "$prev" ]; then prev="$n"; else order_ok=1; fi
done
[ "$order_ok" -eq 0 ]; chk "the document lists the seven steps of one delivery in order (merge, checks, wait, provision, approve, sign and upload, remove)" $?
step3="$(grep -F '| 3 | GitHub |' "$doc")"; step4="$(grep -F '| 4 | CTO |' "$doc")"; step7="$(grep -F '| 7 | CTO |' "$doc")"
printf '%s\n' "$step3" | grep -F 'Waiting' >/dev/null && printf '%s\n' "$step4" | grep -F 'APPLE_API_KEY_P8' >/dev/null && printf '%s\n' "$step7" | grep -F 'Removes the three secrets' >/dev/null; chk "waiting precedes provisioning, and removal is the last step" $?
bad_perm="$(grep -i 'permanent' "$doc" "$rec" "$wf" | grep -viE 'not authorized|never|NOT|no indefinite' || true)"
[ -z "$bad_perm" ]; chk "no sentence asks for or allows permanent storage of the key (every mention is a prohibition)" $? "$bad_perm"
! grep -E 'No required reviewers|unattended signing|signs without a person' "$doc" "$rec" >/dev/null; chk "neither the document nor the record still says no reviewers or unattended signing" $?
srow="$(grep -E '^\| S2 \|' "$rec")"
printf '%s\n' "$srow" | grep -F 'temporary provisioning' >/dev/null && printf '%s\n' "$srow" | grep -F 'Permanent storage of the key in GitHub is not authorized' >/dev/null && printf '%s\n' "$srow" | grep -F 'removes the three secrets' >/dev/null; chk "decision S2 in the record is temporary provisioning, with removal after the run" $?
grep -E '^\| S3 \|' "$rec" | grep -F 'confirms the deployment only' >/dev/null; chk "decision S3 keeps the record as the authorization and the approval as a confirmation only" $?
grep -E '^G2S-STAGING-STATUS: AUTHORIZED$' "$rec" >/dev/null && [ "$(grep -cE '^G2S-STAGING-[A-Z0-9-]+: PENDING$' "$rec")" -eq 0 ] && [ "$(grep -cE '^G2S-STAGING-DECISION-S[1-4]: Decided by CadenaWizard on 2026-11-27$' "$rec")" -eq 4 ] && grep -E '^G2S-STAGING-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-[0-9]+$' "$rec" >/dev/null; chk "the record is AUTHORIZED on the CTO's decision of 2026-11-27: no PENDING value is left, S1 to S4 are decided, the authorization is a comment on Issue #71" $?
grep -E '^G2S-STAGING-APP-APPLE-ID: 6839776198$' "$rec" >/dev/null && grep -F '`6839776198`' "$doc" >/dev/null; chk "the verified staging application (Apple ID 6839776198, never the production one) is recorded and documented" $?
grep -F 'Cadena Internal Testing - staging only' "$doc" >/dev/null; chk "the staging TestFlight group is documented" $?
printf '%s\n' "$sign" | grep -E 'APPLE_API_KEY_P8' >/dev/null && ! printf '%s\n%s\n' "$authorize" "$build" | grep -E 'secrets\.' >/dev/null; chk "the secrets are still read only by the signing job" $?
probe="$(awk '/^## Appendix A/{a=1} a && /^```yaml$/{f=1; next} a && /^```$/{f=0} f' "$doc")"
[ -n "$probe" ]; chk "the document carries the harmless secret-timing probe (Appendix A)" $?
PROBE_YAML="$probe" python3 -I -c '
import os, yaml
text = os.environ["PROBE_YAML"]
w = yaml.safe_load(text)
on = w.get(True, w.get("on"))
jobs = w["jobs"]
assert list(on) == ["workflow_dispatch"], on
assert list(jobs) == ["probe"] and jobs["probe"]["environment"] == "secret-timing-probe"
assert w["permissions"] == {"contents": "read"}
assert text.count("secrets.") == 1 and "secrets.PROBE_DUMMY" in text
assert "APPLE" not in text.upper()
assert "echo \"$PROBE_VALUE\"" not in text and "printenv" not in text and "set -x" not in text
assert "${#PROBE_VALUE}" in text
'
chk "and the probe is a dispatch-only job with one dummy secret that prints its length, never its value, with no Apple name in it" $?
grep -F 'dummy-not-a-credential' "$doc" >/dev/null && [ "$(printf '%s' 'dummy-not-a-credential' | wc -c | tr -d ' ')" = "22" ] && grep -F 'RESULT: present, length 22' "$doc" >/dev/null; chk "the probe's expected result matches the dummy value (22 characters)" $?

echo
echo "== the staging environment is ios-hosted-signing-stg (the maintainer's GitHub environment), distinct from the production one"
! grep -P 'ios-hosted-signing(?!-stg|\.yml)' "$wf" >/dev/null && grep -qF 'environment: ios-hosted-signing-stg' "$wf"; chk "the staging workflow names exactly the environment ios-hosted-signing-stg and never the production environment ios-hosted-signing (only its workflow file is mentioned)" $?
! grep -rE 'ios-staging-signing' "$wf" "$doc" "$rec" "$root/docs/RELEASE_TRIGGERS.md" "$root/tool/check_staging_authorization.sh" >/dev/null; chk "the old name ios-staging-signing is gone from the workflow, document, record, triggers document and gate" $?
grep -E '^    environment: ios-hosted-signing-stg$' "$wf" | wc -l | grep -qx 1; chk "exactly one job declares that environment" $?
grep -F 'only `staging`' "$doc" >/dev/null && grep -F 'sziller' "$doc" >/dev/null && grep -F 'CadenaWizard' "$doc" >/dev/null; chk "the document keeps the staging-only branch restriction and the two required reviewers" $?

echo "== the native-library pin is the STAGING archive's own hash (preflight runs 45967581978 and 45969558826), never the production value"
STAGING_DLC="92231f38c71864833cd6bcdf03c4849c72e6e0a7d66bd59b826dd2798680646d"; PROD_DLC="9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13"
[ "$(grep -cE '^G2S-STAGING-DLC-WALLET-SHA256: ' "$rec")" -eq 1 ] && grep -E "^G2S-STAGING-DLC-WALLET-SHA256: $STAGING_DLC\$" "$rec" >/dev/null; chk "the staging record carries the staging archive's framework hash on its one line" $?
! grep -E "^G2S-STAGING-DLC-WALLET-SHA256: $PROD_DLC" "$rec" >/dev/null; chk "and not the production value" $?
grep -E "^G2S-DLC-WALLET-SHA256: $PROD_DLC\$" "$root/docs/release-records/ios-1.0.4-1000035.md" >/dev/null; chk "the production record's pin is unchanged" $?
grep -F '45967581978' "$rec" >/dev/null && grep -F '45969558826' "$rec" >/dev/null && grep -F '2aac65d2b3ee33918f4a636c7442d52e139abdec' "$rec" >/dev/null && grep -F 'macos15 20261118.0550.1' "$rec" >/dev/null && grep -F 'Xcode 26.3 (17C529)' "$rec" >/dev/null; chk "the record documents both preflight runs, the source commit and the toolchain" $?
grep -F 'Release-production-iphoneos' "$rec" >/dev/null && grep -F 'Release-staging-iphoneos' "$rec" >/dev/null && grep -F 'can never equal the production hash' "$rec" >/dev/null; chk "the record explains why the production hash cannot be reused" $?
grep -F 'can change this hash' "$rec" >/dev/null && grep -F 'equality across images is **not** shown' "$rec" >/dev/null; chk "the record states the limitation (Xcode, runner image, paths; one image only)" $?
grep -F 'measured three times, and matched the corrected pin once' "$rec" >/dev/null && grep -F '45976062284' "$rec" >/dev/null && grep -F 'accepted this value as decision C2 on 2026-11-27' "$rec" >/dev/null; chk "the record distinguishes three measurements from the single MATCH against the pin, and states the CTO's acceptance of C2" $?
grep -F '### 10.1' "$doc" >/dev/null && grep -F '45967581978' "$doc" >/dev/null && grep -F '45969558826' "$doc" >/dev/null && grep -F "$STAGING_DLC" "$doc" >/dev/null; chk "the document records both runs and the staging hash (section 10.1)" $?
! grep -E "proposal is the production value|The proposed pin \(.9a2d1d98" "$doc" >/dev/null; chk "no sentence in the document calls the production value the expected staging hash" $?
grep -E '^G2S-STAGING-VERSION: 1.0.5\+10005001$' "$rec" >/dev/null && grep -E '^version: 1.0.5\+10005001$' "$root/pubspec.yaml" >/dev/null; chk "the record authorizes exactly the version of pubspec.yaml (1.0.5+10005001), no other" $?

echo "ios-staging-delivery: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
