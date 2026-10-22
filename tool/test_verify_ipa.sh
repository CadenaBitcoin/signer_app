#!/usr/bin/env bash
# Tests the IPA verification tooling of Issue #71 with SYNTHETIC fixtures (no Apple credential, no
# Xcode, no macOS, no network). It runs anywhere that has bash, python3 and openssl (>= 1.1.1, with
# `openssl cms`).
#
#   tool/test_verify_ipa.sh
#   REAL_UNSIGNED_APP=/path/to/Runner.app tool/test_verify_ipa.sh     # also re-sign a real unsigned build
#
# What this proves: the verifier accepts a correctly signed synthetic IPA and REJECTS each defect
# below. What it does NOT prove: that Apple's codesign, App Store Connect or a device agree. The
# fixtures are made by tool/ipa_fixture.py, which writes the same structures Apple's codesign writes
# (the parser itself was also checked against real Apple- and Flutter-signed binaries; see
# docs/IOS_SIGNING.md). Real signed IPAs are the remaining evidence (docs/IOS_SIGNING.md section 3).
#
# (No `grep -q` at the end of a pipeline: under pipefail an early-closed pipe is a SIGPIPE failure.)
# Exit 0 only if every check passes.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verify="$root/tool/verify_ipa.py"
fixture="$root/tool/ipa_fixture.py"
inspect="$root/tool/ipa_inspect.py"

pass=0
failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }

if ! command -v openssl >/dev/null 2>&1 || ! openssl cms -help >/dev/null 2>&1; then
  echo "SKIP: this test needs an openssl with the 'cms' command (set OPENSSL for another one)."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
TEAM=SYNTH12345
NOW="$(python3 -c "import datetime;print((datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
fx() { python3 -I "$fixture" "$@" >/dev/null; }
common=(--team-id "$TEAM" --issuer-cn "Synthetic Test Intermediate CA" --leaf-prefix "Synthetic Distribution:" --now "$NOW")

fx certs "$tmp/certs"
mkdir -p "$tmp/staging" "$tmp/production"
fx unsigned "$tmp/staging" --env staging
fx unsigned "$tmp/production" --env production
PIN="$(python3 -I "$fixture" fingerprint "$tmp/certs/leaf.crt")"
OTHERPIN="$(python3 -I "$fixture" fingerprint "$tmp/certs/leaf2.crt")"
fx manifest "$tmp/staging/Runner.app" "$tmp/staging.json" --env staging

# mk NAME [ENV] [MUTATION...] -> $tmp/NAME.ipa
mk() {
  local name=$1 env=$2; shift 2
  local args=()
  for m in "$@"; do args+=(--mutate "$m"); done
  fx sign "$tmp/$env/Runner.app" "$tmp/$name.ipa" --certs "$tmp/certs" --team "$TEAM" "${args[@]+"${args[@]}"}"
}

# run VERIFY_ARGS... -> sets out and rc
run() { out="$(python3 -I "$verify" verify "$@" 2>&1)"; rc=$?; }
expect_ok() { # NAME ENV IPA [extra args]
  local name=$1 env=$2 ipa=$3; shift 3
  run "$env" "$ipa" "${common[@]}" "$@"
  if [ "$rc" -eq 0 ]; then ok "$name"; else bad "$name" "exit $rc: $(echo "$out" | grep -E 'FAIL|verify_ipa:' | head -3 | tr '\n' '|')"; fi
}
expect_fail() { # NAME PATTERN ENV IPA [extra args]
  local name=$1 pat=$2 env=$3 ipa=$4; shift 4
  run "$env" "$ipa" "${common[@]}" "$@"
  if [ "$rc" -ne 1 ]; then bad "$name" "expected exit 1, got $rc"; return; fi
  if [[ "$out" == *"FAIL  "*"$pat"* || "$out" == *"FAIL  $pat"* ]] || echo "$out" | grep -F "FAIL" | grep -F -e "$pat" >/dev/null; then
    ok "$name"
  else
    bad "$name" "exit 1 but no FAIL line containing '$pat': $(echo "$out" | grep FAIL | head -3 | tr '\n' '|')"
  fi
}

# ---- 1. acceptance -----------------------------------------------------------------------------
mk good staging
expect_ok "a correctly signed staging IPA passes (pinned certificate)" staging "$tmp/good.ipa" --expect-cert-sha256 "$PIN"
expect_ok "...with the build manifest and the unsigned bundle (provenance and same-code)" staging "$tmp/good.ipa" \
  --expect-cert-sha256 "$PIN" --manifest "$tmp/staging.json" --unsigned-app "$tmp/staging/Runner.app"
expect_ok "...with its own SHA-256 handed over" staging "$tmp/good.ipa" --expect-cert-sha256 "$PIN" \
  --expect-sha256 "$(python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$tmp/good.ipa")"
mk good_dual staging dual
expect_ok "an IPA with a SHA-1 primary and a SHA-256 alternate CodeDirectory passes" staging "$tmp/good_dual.ipa" --expect-cert-sha256 "$PIN"
mk good_prod production
expect_ok "a correctly signed production IPA passes with a pinned certificate" production "$tmp/good_prod.ipa" --expect-cert-sha256 "$PIN"
run staging "$tmp/good.ipa" "${common[@]}" --expect-cert-sha256 "$PIN" --evidence "$tmp/evidence.txt"
if [ -s "$tmp/evidence.txt" ] && grep -F "signer_sha256=$PIN" "$tmp/evidence.txt" >/dev/null && grep -F "checks_failed=0" "$tmp/evidence.txt" >/dev/null; then ok "the evidence file records the fingerprint and the result"; else bad "the evidence file records the fingerprint and the result"; fi
if grep -iE 'PRIVATE KEY|BEGIN ' "$tmp/evidence.txt" >/dev/null; then bad "the evidence contains no key material"; else ok "the evidence contains no key material"; fi

# ---- 2. identity: staging and production never mix ---------------------------------------------
expect_fail "a staging IPA verified as production is refused" "bundle identifier is" production "$tmp/good.ipa" --expect-cert-sha256 "$PIN"
expect_fail "a production IPA verified as staging is refused" "bundle identifier is" staging "$tmp/good_prod.ipa" --expect-cert-sha256 "$PIN"
mk wrongbundle staging wrong-bundle
expect_fail "a changed bundle identifier is refused" "bundle identifier is" staging "$tmp/wrongbundle.ipa" --expect-cert-sha256 "$PIN"
mk wrongversion staging wrong-version
expect_fail "a version different from pubspec.yaml is refused" "differs from pubspec.yaml" staging "$tmp/wrongversion.ipa" --expect-cert-sha256 "$PIN"
expect_fail "the wrong Team ID is refused" "team ID" staging "$tmp/good.ipa" --team-id ABCDE12345 --expect-cert-sha256 "$PIN"

# ---- 3. the signature and what changed after it ------------------------------------------------
mk tamperexe staging tamper-exe
expect_fail "an executable changed after signing is refused" "code pages do not match" staging "$tmp/tamperexe.ipa" --expect-cert-sha256 "$PIN"
mk tamperres staging tamper-resource
expect_fail "a resource changed after signing is refused" "was modified after signing" staging "$tmp/tamperres.ipa" --expect-cert-sha256 "$PIN"
mk tamperinfo staging tamper-info
expect_fail "an Info.plist changed after signing is refused" "Info.plist was changed after signing" staging "$tmp/tamperinfo.ipa" --expect-cert-sha256 "$PIN"
mk addfile staging add-file
expect_fail "a file added after signing is refused" "not covered by CodeResources" staging "$tmp/addfile.ipa" --expect-cert-sha256 "$PIN"
mk tampercms staging tamper-cms
expect_fail "a damaged CMS signature is refused" "CMS signature is not valid" staging "$tmp/tampercms.ipa" --expect-cert-sha256 "$PIN"
mk tamperalt staging dual tamper-altcd
expect_fail "a replaced alternate CodeDirectory is refused" "is not bound by the signature" staging "$tmp/tamperalt.ipa" --expect-cert-sha256 "$PIN"
mk adhoc staging adhoc-main
expect_fail "an ad-hoc signed executable is refused" "ad-hoc signed" staging "$tmp/adhoc.ipa" --expect-cert-sha256 "$PIN"
mk fwunsigned staging framework-unsigned
expect_fail "an unsigned embedded framework is refused" "is not signed" staging "$tmp/fwunsigned.ipa" --expect-cert-sha256 "$PIN"
mk fwother staging framework-other-signer
expect_fail "a framework signed by another certificate is refused" "different certificate" staging "$tmp/fwother.ipa" --expect-cert-sha256 "$PIN"
mk wrongcdteam staging wrong-cd-team
expect_fail "a CodeDirectory for another team is refused" "CodeDirectory team ID" staging "$tmp/wrongcdteam.ipa" --expect-cert-sha256 "$PIN"

# ---- 4. the certificate ------------------------------------------------------------------------
expect_fail "a pin that does not match the signing certificate is refused" "none of the pinned fingerprints" staging "$tmp/good.ipa" --expect-cert-sha256 "$OTHERPIN"
expect_fail "production without a pinned fingerprint is refused" "needs --expect-cert-sha256" production "$tmp/good_prod.ipa"
run staging "$tmp/good.ipa" --team-id "$TEAM" --issuer-cn "Synthetic Test Intermediate CA" --now "$NOW" --expect-cert-sha256 "$PIN"
if [ "$rc" -eq 1 ] && echo "$out" | grep -F "is not a distribution certificate" >/dev/null; then ok "a certificate that is not 'Apple Distribution' / 'iPhone Distribution' is refused by default"; else bad "a certificate that is not 'Apple Distribution' is refused by default" "rc=$rc"; fi
run staging "$tmp/good.ipa" --team-id "$TEAM" --leaf-prefix "Synthetic Distribution:" --now "$NOW" --expect-cert-sha256 "$PIN"
if [ "$rc" -eq 1 ] && echo "$out" | grep -F "issuer is 'Synthetic Test Intermediate CA', expected" >/dev/null; then ok "an issuer other than the expected CA is refused"; else bad "an issuer other than the expected CA is refused" "rc=$rc"; fi
run staging "$tmp/good.ipa" --team-id "$TEAM" --issuer-cn "Synthetic Test Intermediate CA" --leaf-prefix "Synthetic Distribution:" --now "2035-01-01T00:00:00Z" --expect-cert-sha256 "$PIN"
if [ "$rc" -eq 1 ] && echo "$out" | grep -F "signing certificate is not valid now" >/dev/null; then ok "an expired signing certificate is refused"; else bad "an expired signing certificate is refused" "rc=$rc"; fi
mk othercert staging other-team-cert
expect_fail "a signature by a certificate of another team is refused" "signing certificate OU" staging "$tmp/othercert.ipa" --expect-cert-sha256 "$OTHERPIN"

# ---- 5. the provisioning profile ---------------------------------------------------------------
mk noprofile staging no-profile
expect_fail "a missing provisioning profile is refused" "embedded.mobileprovision is missing" staging "$tmp/noprofile.ipa" --expect-cert-sha256 "$PIN"
mk expiredprofile staging expired-profile
expect_fail "an expired provisioning profile is refused" "profile expired on" staging "$tmp/expiredprofile.ipa" --expect-cert-sha256 "$PIN"
mk nearprofile staging near-expiry-profile
run staging "$tmp/nearprofile.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
if [ "$rc" -eq 0 ] && echo "$out" | grep -F "WARN  profile expires in" >/dev/null; then ok "a provisioning profile that expires soon passes with a warning"; else bad "a provisioning profile that expires soon passes with a warning" "rc=$rc"; fi
mk adhocprofile staging adhoc-profile
expect_fail "an ad-hoc provisioning profile (device list) is refused" "profile type is" staging "$tmp/adhocprofile.ipa" --expect-cert-sha256 "$PIN"
mk devprofile staging dev-profile
expect_fail "a development profile (get-task-allow) is refused" "profile type is" staging "$tmp/devprofile.ipa" --expect-cert-sha256 "$PIN"
mk wildprofile staging wildcard-profile
expect_fail "a wildcard App ID in the profile is refused" "wildcards are refused" staging "$tmp/wildprofile.ipa" --expect-cert-sha256 "$PIN"
mk wrongteamprofile staging wrong-team-profile
expect_fail "a profile of another team is refused" "profile TeamIdentifier" staging "$tmp/wrongteamprofile.ipa" --expect-cert-sha256 "$PIN"
mk profnocert staging profile-without-cert
expect_fail "a profile that does not contain the signing certificate is refused" "not one of the profile's DeveloperCertificates" staging "$tmp/profnocert.ipa" --expect-cert-sha256 "$PIN"

# ---- 6. entitlements ---------------------------------------------------------------------------
mk gta staging get-task-allow
expect_fail "get-task-allow in the app's entitlements is refused" "get-task-allow is true" staging "$tmp/gta.ipa" --expect-cert-sha256 "$PIN"
mk entnotprofile staging ent-not-in-profile
expect_fail "an entitlement the profile does not grant is refused" "entitlements not granted by the profile" staging "$tmp/entnotprofile.ipa" --expect-cert-sha256 "$PIN"
mk apsdev staging aps-development
expect_fail "aps-environment development in an App Store build is refused" "aps-environment is" staging "$tmp/apsdev.ipa" --expect-cert-sha256 "$PIN"
mk noents staging no-entitlements
expect_fail "an app without embedded entitlements is refused" "no embedded entitlements" staging "$tmp/noents.ipa" --expect-cert-sha256 "$PIN"

# ---- 7. the container --------------------------------------------------------------------------
echo "not a zip" >"$tmp/notzip.ipa"
expect_fail "a file that is not a zip archive is refused" "not a readable zip archive" staging "$tmp/notzip.ipa"
mk twoapps staging two-apps
expect_fail "an archive with two apps is refused" "exactly one Payload" staging "$tmp/twoapps.ipa"
mk traversal staging traversal
expect_fail "an archive member that escapes the target ('..') is refused" "unsafe member name" staging "$tmp/traversal.ipa"
expect_fail "an IPA whose digest differs from the handed-over digest is refused" "differs from the expected" staging "$tmp/good.ipa" \
  --expect-cert-sha256 "$PIN" --expect-sha256 0000000000000000000000000000000000000000000000000000000000000000

# ---- 8. provenance: is it the build that was verified? -----------------------------------------
cp -R "$tmp/staging" "$tmp/staging_changed"
printf 'changed\n' >>"$tmp/staging_changed/Runner.app/Frameworks/App.framework/flutter_assets/AssetManifest.json"
expect_fail "an unsigned bundle that is not the one in the manifest is refused" "differs from the manifest" staging "$tmp/good.ipa" \
  --expect-cert-sha256 "$PIN" --manifest "$tmp/staging.json" --unsigned-app "$tmp/staging_changed/Runner.app"
mkdir -p "$tmp/staging2"
fx unsigned "$tmp/staging2" --env staging --seed 2
expect_fail "an IPA built from different code than the unsigned build is refused (recompiled)" "executable content differs" staging "$tmp/good.ipa" \
  --expect-cert-sha256 "$PIN" --unsigned-app "$tmp/staging2/Runner.app"
fx manifest "$tmp/production/Runner.app" "$tmp/production.json" --env production
expect_fail "a manifest of another environment is refused" "build manifest environment is" staging "$tmp/good.ipa" \
  --expect-cert-sha256 "$PIN" --manifest "$tmp/production.json"
cp -R "$tmp/staging" "$tmp/staging_extra"
printf 'x' >"$tmp/staging_extra/Runner.app/extra.txt"
expect_fail "a file only in the unsigned build is reported missing from the IPA" "missing from the IPA" staging "$tmp/good.ipa" \
  --expect-cert-sha256 "$PIN" --unsigned-app "$tmp/staging_extra/Runner.app"

# ---- 9. the reader library, and the offline guarantee -------------------------------------------
python3 -I - "$inspect" <<'PYEOF' && ok "ipa_inspect reads BER indefinite lengths and rejects truncated input" || bad "ipa_inspect reads BER indefinite lengths and rejects truncated input"
import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("ipa_inspect", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
n = m.parse_der(bytes([0x30, 0x80, 0x02, 0x01, 0x05, 0x00, 0x00]))
assert n.constructed and n.children[0].value == b"\x05"
try:
    m.parse_der(bytes([0x30, 0x05, 0x02, 0x01]))
    sys.exit(1)
except m.Asn1Error:
    pass
assert m.oid_str(m.parse_der(bytes([0x06, 0x03, 0x2A, 0x86, 0x48]))) == "1.2.840"
PYEOF
if grep -nE '^\s*(import|from)\s+(socket|urllib|http|requests|ssl|ftplib|smtplib)' "$verify" "$inspect" "$fixture" >/dev/null; then bad "the verification tooling imports no network module"; else ok "the verification tooling imports no network module"; fi
if grep -nE 'os\.environ' "$verify" "$fixture" >/dev/null; then bad "verify_ipa.py / ipa_fixture.py read no environment variables"; else ok "verify_ipa.py / ipa_fixture.py read no environment variables"; fi
if grep -nE 'BEGIN (RSA |EC |)PRIVATE KEY' "$verify" "$inspect" "$fixture" "$0" >/dev/null; then bad "no key material is committed in the tooling"; else ok "no key material is committed in the tooling"; fi
run staging "$tmp/good.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
if echo "$out" | grep -F "NOT VERIFIED by this tool" >/dev/null; then ok "every run states what it cannot verify"; else bad "every run states what it cannot verify"; fi


# compare (the signing job's check) and the macOS spike script
python3 -I "$verify" compare "$tmp/staging/Runner.app" "$tmp/good.ipa" >"$tmp/cmp.txt" 2>&1; crc=$?
if [ "$crc" -eq 0 ] && grep -F "unsigned build plus signatures only" "$tmp/cmp.txt" >/dev/null; then ok "compare accepts the IPA as the unsigned build plus signatures"; else bad "compare accepts the IPA as the unsigned build plus signatures" "rc=$crc"; fi
python3 -I "$verify" compare "$tmp/staging2/Runner.app" "$tmp/good.ipa" >"$tmp/cmp.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "executable content differs" "$tmp/cmp.txt" >/dev/null; then ok "compare rejects an IPA built from different code"; else bad "compare rejects an IPA built from different code" "rc=$crc"; fi
mk cmpextra staging add-file
python3 -I "$verify" compare "$tmp/staging/Runner.app" "$tmp/cmpextra.ipa" >"$tmp/cmp.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "files added to the IPA" "$tmp/cmp.txt" >/dev/null; then ok "compare rejects an IPA with an injected file"; else bad "compare rejects an IPA with an injected file" "rc=$crc"; fi
spike="$root/tool/spike_resign_unsigned_ios.sh"
if bash -n "$spike"; then ok "the macOS spike script is syntactically valid"; else bad "the macOS spike script is syntactically valid"; fi
if [ "$(uname -s)" != "Darwin" ]; then
  bash "$spike" "$tmp/staging/Runner.app" "$tmp/spike" >/dev/null 2>&1; src=$?
  if [ "$src" -eq 2 ]; then ok "the macOS spike script refuses to run off macOS"; else bad "the macOS spike script refuses to run off macOS" "rc=$src"; fi
fi
if grep -vE '^[[:space:]]*#' "$spike" | grep -iE 'altool|notarytool|exportArchive|AuthKey|\.p8|appstoreconnect|curl|wget|gh api|security (delete|default|list)-keychains? -d (login|user)' >/dev/null; then bad "the spike script has no upload, API-key or login-keychain command"; else ok "the spike script has no upload, API-key or login-keychain command"; fi

# analyze-unsigned on the synthetic unsigned app
a="$(python3 -I "$verify" analyze-unsigned "$tmp/staging/Runner.app" 2>&1)"; arc=$?
if [ "$arc" -eq 0 ] && echo "$a" | grep -F "with no signature" >/dev/null && echo "$a" | grep -F "unsigned   Runner" >/dev/null; then ok "analyze-unsigned lists the unsigned executables"; else bad "analyze-unsigned lists the unsigned executables" "rc=$arc"; fi

# ---- 10. optional: re-sign a REAL unsigned build (synthetic identity) -----------------------------
if [ -n "${REAL_UNSIGNED_APP:-}" ]; then
  if [ ! -f "$REAL_UNSIGNED_APP/Info.plist" ]; then
    bad "REAL_UNSIGNED_APP is a Runner.app directory" "$REAL_UNSIGNED_APP"
  else
    renv=staging
    case "$(python3 -c "import plistlib,sys;print(plistlib.load(open(sys.argv[1],'rb'))['CFBundleIdentifier'])" "$REAL_UNSIGNED_APP/Info.plist")" in
      *.staging) renv=staging ;; *) renv=production ;;
    esac
    fx sign "$REAL_UNSIGNED_APP" "$tmp/real.ipa" --certs "$tmp/certs" --team "$TEAM"
    expect_ok "a REAL unsigned build, re-signed with the synthetic identity, passes and equals the unsigned build apart from signatures" "$renv" "$tmp/real.ipa" \
      --expect-cert-sha256 "$PIN" --unsigned-app "$REAL_UNSIGNED_APP"
  fi
fi

echo
echo "test_verify_ipa: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
