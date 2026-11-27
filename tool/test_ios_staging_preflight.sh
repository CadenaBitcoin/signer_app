#!/usr/bin/env bash
# Tests the manual, credential-free staging archive PREFLIGHT (.github/workflows/ios-staging-archive-preflight.yml; Issues #54 and #71).
#
#   tool/test_ios_staging_preflight.sh
#
# What this proves, with no Apple credential and no macOS:
#   - the workflow is a manual run on development only, with no secret, no environment, no signing or upload command and no binary upload;
#   - its environment pins and the steps that make the archive are, comments removed, the TEXT of the delivery's `build` job, and the way it extracts
#     the archive, reads the pin and hashes the framework is that of the delivery's `sign` job (so the hash it reports is the one the delivery checks);
#   - the delivery workflow is not changed by it (it is still the blob the staging record binds);
#   - the comparison step behaves: MATCH passes, anything else fails loudly with the real value, on a synthetic archive (PlistBuddy replaced by a stub).
# What it does NOT prove: that Apple's tools produce the same bytes on the day (only a real run shows that).
# Exit 0 only if every check passes.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pf="$root/.github/workflows/ios-staging-archive-preflight.yml"
dl="$root/.github/workflows/ios-staging-delivery.yml"
rec="$root/docs/release-records/ios-staging-authorization.md"
pass=0; failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
chk() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "${3:-}"; fi; }

[ -f "$pf" ] && [ -f "$dl" ] || { echo "FAIL the preflight or the delivery workflow is missing"; exit 1; }
command -v python3 >/dev/null && python3 -I -c 'import yaml' 2>/dev/null || { echo "FAIL python3 with PyYAML is required"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

code="$(grep -vE '^[[:space:]]*#' "$pf")"
dcode="$(grep -vE '^[[:space:]]*#' "$dl")"
step_of() { printf '%s\n' "$1" | awk -v n="$2" '/^      - name:/ {f = (index($0, n) > 0)} f'; }
job_of() { printf '%s\n' "$1" | sed -n '/^jobs:/,$p' | awk -v j="$2" '$0 ~ "^  "j":$" {f=1; next} /^  [a-z][a-z-]*:$/ {f=0} f'; }
pjob="$(job_of "$code" preflight)"
dbuild="$(job_of "$dcode" build)"
dsign="$(job_of "$dcode" sign)"

echo "== shape, trigger, permissions"
[ "$(printf '%s\n' "$code" | sed -n '/^jobs:/,$p' | grep -cE '^  [a-z][a-z-]*:$')" -eq 1 ] && [ -n "$pjob" ]; chk "exactly one job, preflight" $?
triggers="$(printf '%s\n' "$code" | sed -n '/^on:/,/^permissions:/p' | grep -E '^  [a-z_]+:' | tr -d ' :' | tr '\n' ' ')"
[ "$triggers" = "workflow_dispatch " ]; chk "starts only manually (found: $triggers)" $?
! printf '%s\n' "$code" | grep -E '^\s+(push|pull_request|pull_request_target|workflow_run|schedule|repository_dispatch|workflow_call|tags|paths|branches|inputs):' >/dev/null; chk "no push, pull-request, scheduled, reusable or other trigger and no input" $?
perm="$(printf '%s\n' "$code" | sed -n '/^permissions:/,/^env:/p' | grep -E '^  [a-z-]+:' | tr -d ' ' | tr '\n' ' ')"
[ "$perm" = "contents:read " ]; chk "the permissions are exactly contents: read (found: $perm)" $?
! printf '%s\n' "$code" | grep -E '^[[:space:]]+(permissions:|id-token|contents: write|actions: write|packages:|pull-requests:|issues:|checks:|statuses:|deployments:)' >/dev/null; chk "no job asks for more permission" $?
printf '%s\n' "$pjob" | grep -E '^    runs-on: macos-15$' >/dev/null && printf '%s\n' "$pjob" | grep -E '^    timeout-minutes: [0-9]+$' >/dev/null; chk "runs on macos-15 (not macos-latest) with a timeout" $?
! printf '%s\n' "$code" | grep -E 'runs-on:.*self-hosted' >/dev/null; chk "no self-hosted runner (public repository)" $?
bad_uses="$(printf '%s\n' "$code" | grep -E '^[[:space:]]*-?[[:space:]]*uses:' | grep -vE '@[0-9a-f]{40}( |$)' || true)"
[ -z "$bad_uses" ]; chk "every action is pinned to a full commit SHA" $?
! printf '%s\n' "$code" | grep -E '\$\{\{[[:space:]]*(inputs|github\.event|github\.head_ref|github\.ref_name|github\.actor)' >/dev/null; chk "no input and no event or attacker-influenced value reaches a step" $?
! printf '%s\n' "$code" | grep -E 'continue-on-error' >/dev/null; chk "no continue-on-error" $?
first="$(printf '%s\n' "$pjob" | grep -E '^      - name:' | head -n1)"
second="$(printf '%s\n' "$pjob" | grep -E '^      - name:' | sed -n '2p')"
case "$first" in *"Refuse anything but a manual run on development"*) true;; *) false;; esac; chk "the first step refuses any run that is not manual on development" $?
step_of "$pjob" "Refuse anything but a manual run" | grep -F '"$GITHUB_EVENT_NAME" != "workflow_dispatch"' >/dev/null && step_of "$pjob" "Refuse anything but a manual run" | grep -F '"$GITHUB_REF" != "refs/heads/development"' >/dev/null && step_of "$pjob" "Refuse anything but a manual run" | grep -F 'exit 1' >/dev/null; chk "by failing (a skipped job would be a silent green), on the event and on the ref" $?
case "$second" in *Checkout*) true;; *) false;; esac; chk "and only then checks out" $?
step_of "$pjob" "Verify the source" | grep -F 'git ls-remote' >/dev/null && step_of "$pjob" "Verify the source" | grep -F 'refs/heads/development' >/dev/null && step_of "$pjob" "Verify the source" | grep -F 'is not the current tip of development' >/dev/null; chk "a run on a commit that is not the current tip of development is refused" $?

echo "== no credential, no signing, no upload, no Apple secret"
! printf '%s\n' "$code" | grep -E 'secrets\.|secrets:|environment:' >/dev/null; chk "no secret and no environment anywhere" $?
! printf '%s\n' "$code" | grep -iE 'APPLE_|API_KEY|\.p8|AuthKey|issuer|ios-hosted-signing|ios-staging-signing' >/dev/null; chk "no Apple credential name and no signing environment is named" $?
! printf '%s\n' "$code" | grep -E 'altool|notarytool|exportArchive|exportOptions|allowProvisioningUpdates|security (import|create-keychain|unlock-keychain|find-identity)|codesign -[a-zA-Z]*s |codesign --sign|provisioning|xcodebuild.*(archive|export)|--upload|upload-app|ExportOptions' >/dev/null; chk "no signing, export, provisioning, keychain or store-upload command" $?
cs="$(printf '%s\n' "$code" | grep -oE '(^|[^-a-zA-Z_/.])codesign +-[a-zA-Z]+' | sed -E 's/^[^c]*//' | sort -u | tr '\n' ' ')"
[ "$cs" = "codesign -dv " ]; chk "codesign appears only to READ (-dv): found '$cs'" $?
printf '%s\n' "$pjob" | grep -F -- 'flutter build ipa --release --no-codesign --flavor "$BUILD_ENV" --dart-define-from-file="$BUILD_CONFIG_FILE"' >/dev/null && [ "$(printf '%s\n' "$code" | grep -cE '^[[:space:]]+flutter build ')" -eq 1 ]; chk "the one compile is the unsigned flutter build ipa (--no-codesign), and it is the only flutter build" $?
! printf '%s\n' "$code" | grep -E -- '--build-name|--build-number' >/dev/null; chk "no version override of any kind" $?
printf '%s\n' "$code" | grep -E '^  BUILD_ENV: staging$' >/dev/null && printf '%s\n' "$code" | grep -E '^  BUILD_CONFIG_FILE: config/build/staging\.json$' >/dev/null && printf '%s\n' "$code" | grep -E '^  BUNDLE_ID: com\.app\.cadenabitcoin\.staging$' >/dev/null; chk "the build is the staging environment, configuration and bundle ID" $?
! printf '%s\n' "$code" | grep -E 'com\.app\.cadenabitcoin([^.[:alnum:]_-]|$)|production\.json|--flavor production|BUILD_ENV: production|6753348211' >/dev/null; chk "no production identity, configuration, flavor or application" $?
nup="$(printf '%s\n' "$code" | grep -cE 'uses: actions/upload-artifact@')"
[ "$nup" -eq 1 ] && step_of "$pjob" "Upload the evidence" | grep -E '^          path: evidence/$' >/dev/null && step_of "$pjob" "Upload the evidence" | grep -E '^        if: always\(\)$' >/dev/null; chk "the only upload is the text evidence directory (and it is kept when the run fails)" $?
! printf '%s\n' "$code" | grep -E 'path:.*(handover|\.tar|xcarchive|\.ipa|Runner\.app|build/)' >/dev/null; chk "no archive, tar, IPA or app is ever uploaded" $?
! printf '%s\n' "$code" | grep -E 'actions/download-artifact|gh release|gh api|curl |wget ' >/dev/null; chk "nothing is downloaded or published (the tip is read with git ls-remote only)" $?

echo "== equivalence with the delivery's build job (the text, comments removed)"
for k in BUILD_ENV BUILD_CONFIG_FILE BUNDLE_ID DISPLAY_NAME TEAM_ID XCODE_APP EXPECTED_XCODE EXPECTED_MIN_SDK_MAJOR EXPECTED_COCOAPODS EXPECTED_FLUTTER EXPECTED_FLUTTER_REVISION EXPECTED_DART RUST_LIB EXPECTED_RUST_LIB_SHA256; do
  a="$(printf '%s\n' "$code" | grep -E "^  $k:" | head -n1)"; b="$(printf '%s\n' "$dcode" | grep -E "^  $k:" | head -n1)"
  [ -n "$a" ] && [ "$a" = "$b" ]; chk "environment pin $k is the delivery's" $? "preflight: $a / delivery: $b"
done
for s in "Select Xcode 26.3" "Set up Flutter 3.35.3" "Record and verify toolchain" "Resolve dependencies exactly as the lockfiles say" "Repository checks (configuration, version wiring)" "Check that the prebuilt Rust static library is the audited one" "Build the unsigned archive (flutter build ipa --no-codesign)" "Verify the unsigned app (bundle ID, name, version, unsigned, environment)" "Pack the unsigned archive and fix its digest"; do
  a="$(step_of "$pjob" "$s")"; b="$(step_of "$dbuild" "$s")"
  [ -n "$a" ] && [ "$a" = "$b" ]; chk "step '$s' is identical to the delivery's build job" $?
done
echo "== the extraction, the pin and the hashed path are the signing job's"
fwline='fw="$ARCHIVE/Products/Applications/Runner.app/Frameworks/dlc_wallet.framework/dlc_wallet"'
printf '%s\n' "$dsign" | grep -F -- "$fwline" >/dev/null && printf '%s\n' "$pjob" | grep -F -- "$fwline" >/dev/null; chk "the hashed file is the same path of the extracted archive" $?
for frag in 'python3 -I tools/tool/validate_handover_archive.py list handover/Runner.xcarchive.tar --top Runner.xcarchive' 'tar -xf handover/Runner.xcarchive.tar -C "$RUNNER_TEMP/archive"' 'python3 -I tools/tool/validate_handover_archive.py tree "$RUNNER_TEMP/archive"'; do
  mine="$(printf '%s' "$frag" | sed 's#tools/tool#tool#')"
  printf '%s\n' "$dsign" | grep -F -- "$frag" >/dev/null && printf '%s\n' "$pjob" | grep -F -- "$mine" >/dev/null; chk "extraction command as in the signing job: ${mine%% --*}" $?
done
printf '%s\n' "$dsign" | grep -F -- '--print-field G2S-STAGING-DLC-WALLET-SHA256' >/dev/null && printf '%s\n' "$pjob" | grep -F -- '--print-field G2S-STAGING-DLC-WALLET-SHA256 --record docs/release-records/ios-staging-authorization.md' >/dev/null; chk "the pin is read from the record by the gate script, as in the signing job" $?
printf '%s\n' "$dsign" | grep -F -- 'actual="$(shasum -a 256 "$fw" | awk '"'"'{print $1}'"'"')"' >/dev/null && printf '%s\n' "$pjob" | grep -F -- 'actual="$(shasum -a 256 "$fw" | awk '"'"'{print $1}'"'"')"' >/dev/null; chk "the hash is computed with the same command" $?
printf '%s\n' "$pjob" | grep -F -- '[ "$pbid" = "$BUNDLE_ID" ] && [ "$pbname" = "$DISPLAY_NAME" ] && [ "$pbver+$pbbld" = "$pubspec_version" ]' >/dev/null; chk "the archived app's identity and version are checked (bundle ID, name, pubspec version)" $?
printf '%s\n' "$pjob" | grep -F 'preflight_result=$result' >/dev/null && printf '%s\n' "$pjob" | grep -F '[ "$result" != "MATCH" ]' >/dev/null; chk "a result other than MATCH fails the run (no silent green)" $?

echo "== the delivery and the production workflows are untouched"
want="$(grep -E '^G2S-STAGING-WORKFLOW-BLOB: ' "$rec" | sed 's/^[^:]*: //')"
have="$(git -C "$root" hash-object .github/workflows/ios-staging-delivery.yml 2>/dev/null)"
[ -n "$want" ] && [ "$want" = "$have" ]; chk "ios-staging-delivery.yml is still the blob the staging record binds ($have)" $?
grep -E '^G2S-STAGING-STATUS: WITHDRAWN$' "$rec" >/dev/null; chk "this change authorizes nothing: the staging record is still WITHDRAWN" $?
! grep -F 'ios-staging-archive-preflight' "$root/tool/check_staging_authorization.sh" "$root/.github/workflows/ios-staging-delivery.yml" >/dev/null; chk "neither the gate nor the delivery refers to the preflight (it cannot influence an authorization)" $?

echo "== the comparison step, run on a synthetic archive (PlistBuddy replaced by a stub; no macOS, no Apple tool)"
python3 -I - "$pf" "$tmp/compare.sh" <<'PYEOF'
import sys, yaml
w = yaml.safe_load(open(sys.argv[1]))
steps = w["jobs"]["preflight"]["steps"]
s = [x for x in steps if x["name"].startswith("Extract the archive as the signing job does")]
assert len(s) == 1
open(sys.argv[2], "w").write(s[0]["run"].replace("/usr/libexec/PlistBuddy", "$STUB_PLISTBUDDY"))
PYEOF
cat > "$tmp/plistbuddy" <<'EOF'
#!/usr/bin/env bash
# stub: PlistBuddy -c 'Print :Key' file  ->  the value of $FAKE_Key
key="${2#Print :}"; var="FAKE_$key"; printf '%s\n' "${!var}"
EOF
chmod +x "$tmp/plistbuddy"
mkarchive() { # $1 dir, $2 framework mode (file|missing|symlink), $3 framework content
  python3 -I - "$1" "$2" "$3" <<'PYEOF'
import os, sys, tarfile, io
d, mode, content = sys.argv[1], sys.argv[2], sys.argv[3].encode()
os.makedirs(os.path.join(d, "handover"), exist_ok=True)
def add(t, name, data=None, kind="file", link=None, perm=0o644):
    ti = tarfile.TarInfo(name); ti.mtime = 0
    if kind == "dir": ti.type = tarfile.DIRTYPE; ti.mode = 0o755; t.addfile(ti)
    elif kind == "sym": ti.type = tarfile.SYMTYPE; ti.linkname = link; ti.mode = 0o755; t.addfile(ti)
    else: ti.size = len(data); ti.mode = perm; t.addfile(ti, io.BytesIO(data))
with tarfile.open(os.path.join(d, "handover", "Runner.xcarchive.tar"), "w") as t:
    base = "Runner.xcarchive/Products/Applications/Runner.app"
    for p in ("Runner.xcarchive", "Runner.xcarchive/Products", "Runner.xcarchive/Products/Applications", base, base + "/Frameworks", base + "/Frameworks/dlc_wallet.framework"):
        add(t, p, kind="dir")
    add(t, base + "/Info.plist", b"stub")
    fw = base + "/Frameworks/dlc_wallet.framework/dlc_wallet"
    if mode == "file": add(t, fw, content, perm=0o755)
    elif mode == "symlink": add(t, base + "/Frameworks/real", content); add(t, fw, kind="sym", link="../real")
PYEOF
}
sha() { printf '%s' "$1" | shasum -a 256 | awk '{print $1}'; }
setup() { # $1 name $2 fw mode $3 fw content $4 pin ('' = no line)
  local w="$tmp/$1"; rm -rf "$w"; mkdir -p "$w/docs/release-records" "$w/runner_temp" "$w/evidence"
  cp -R "$root/tool" "$w/tool"
  cp -R "$root/.github" "$w/.github"   # the gate's record parser is the production gate's and wants the whole checkout
  sed -E "s/^G2S-STAGING-DLC-WALLET-SHA256: .*/G2S-STAGING-DLC-WALLET-SHA256: $4/" "$rec" > "$w/docs/release-records/ios-staging-authorization.md"
  [ -n "$4" ] || grep -vE '^G2S-STAGING-DLC-WALLET-SHA256:' "$rec" > "$w/docs/release-records/ios-staging-authorization.md"
  printf 'version: 1.0.5+10005001\n' > "$w/pubspec.yaml"
  mkarchive "$w" "$2" "$3"
}
runcmp() { # $1 name; env FAKE_* set by caller
  ( cd "$tmp/$1" && env RUNNER_TEMP="$tmp/$1/runner_temp" GITHUB_STEP_SUMMARY="$tmp/$1/summary.md" RUST_LIB="$tmp/$1/rust.a" BUNDLE_ID="com.app.cadenabitcoin.staging" DISPLAY_NAME="Cadena Signer STAGING" STUB_PLISTBUDDY="$tmp/plistbuddy" \
      FAKE_CFBundleIdentifier="${F_ID:-com.app.cadenabitcoin.staging}" FAKE_CFBundleDisplayName="${F_NAME:-Cadena Signer STAGING}" FAKE_CFBundleShortVersionString="${F_VER:-1.0.5}" FAKE_CFBundleVersion="${F_BLD:-10005001}" \
      bash "$tmp/compare.sh" ) > "$tmp/$1.out" 2>&1
}
FW="synthetic-dlc-wallet-framework-bytes"; GOOD="$(sha "$FW")"; OTHER="$(sha "something else")"

setup match file "$FW" "$GOOD"; printf 'rust' > "$tmp/match/rust.a"; runcmp match; rc=$?
[ "$rc" -eq 0 ] && grep -F 'preflight_result=MATCH' "$tmp/match.out" >/dev/null && grep -F "dlc_wallet_archive_binary_sha256=$GOOD" "$tmp/match.out" >/dev/null && grep -F 'iOS staging archive preflight: MATCH' "$tmp/match/summary.md" >/dev/null; chk "the framework equals the pin: MATCH, exit 0, the value and the summary are written" $? "$(tail -n 5 "$tmp/match.out")"
setup different file "$FW" "$OTHER"; printf 'rust' > "$tmp/different/rust.a"; runcmp different; rc=$?
[ "$rc" -ne 0 ] && grep -F 'preflight_result=DIFFERENT' "$tmp/different.out" >/dev/null && grep -F "dlc_wallet_archive_binary_sha256=$GOOD" "$tmp/different.out" >/dev/null && grep -F "dlc_wallet_proposed_pin_sha256=$OTHER" "$tmp/different.out" >/dev/null && grep -F '::error::' "$tmp/different.out" >/dev/null; chk "a different framework: DIFFERENT, exit non-zero, the real and the proposed value are both shown" $? "$(tail -n 4 "$tmp/different.out")"
setup nofw missing "" "$GOOD"; printf 'rust' > "$tmp/nofw/rust.a"; runcmp nofw; rc=$?
[ "$rc" -ne 0 ] && grep -F 'no regular file Frameworks/dlc_wallet.framework/dlc_wallet' "$tmp/nofw.out" >/dev/null; chk "an archive without the framework fails" $?
setup symlink symlink "$FW" "$GOOD"; printf 'rust' > "$tmp/symlink/rust.a"; runcmp symlink; rc=$?
[ "$rc" -ne 0 ]; chk "a framework that is a symbolic link is refused (by the archive validator or by the regular-file rule)" $?
setup noline file "$FW" ""; printf 'rust' > "$tmp/noline/rust.a"; runcmp noline; rc=$?
[ "$rc" -ne 0 ] && grep -F 'no single, valid G2S-STAGING-DLC-WALLET-SHA256 line' "$tmp/noline.out" >/dev/null; chk "a record without the pin line fails" $?
setup badid file "$FW" "$GOOD"; printf 'rust' > "$tmp/badid/rust.a"; F_ID="com.app.cadenabitcoin" runcmp badid; rc=$?
[ "$rc" -ne 0 ] && grep -F 'The archived app says' "$tmp/badid.out" >/dev/null; chk "a production bundle ID in the archive fails" $?
setup badver file "$FW" "$GOOD"; printf 'rust' > "$tmp/badver/rust.a"; F_BLD="1000035" runcmp badver; rc=$?
[ "$rc" -ne 0 ] && grep -F 'The archived app says' "$tmp/badver.out" >/dev/null; chk "a build number that is not the pubspec's fails" $?

echo "preflight: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
