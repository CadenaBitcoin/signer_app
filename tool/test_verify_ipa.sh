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
common=(--team-id "$TEAM" --issuer-cn "Synthetic Test Intermediate CA" --leaf-prefix "Synthetic Distribution:" --now "$NOW" --allow-synthetic)

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
run production "$tmp/good_prod.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
nfail="$(echo "$out" | grep -c '^  FAIL')"
if [ "$rc" -eq 1 ] && [ "$nfail" -eq 1 ] && echo "$out" | grep -F "never accepted for production" >/dev/null; then ok "a production IPA is correct in every respect except that its identity is synthetic, which production never accepts"; else bad "a production IPA is correct in every respect except that its identity is synthetic" "rc=$rc fails=$nfail"; fi
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

# ---- 8b. regressions from the security review (each of these was a way to a false pass) --------------
# genuine versus synthetic identities
run staging "$tmp/good.ipa" --team-id "$TEAM" --issuer-cn "Synthetic Test Intermediate CA" --leaf-prefix "Synthetic Distribution:" --now "$NOW" --expect-cert-sha256 "$PIN"
if [ "$rc" -eq 1 ] && echo "$out" | grep -F "synthetic identity" >/dev/null; then ok "a synthetic identity is refused unless --allow-synthetic is given"; else bad "a synthetic identity is refused unless --allow-synthetic is given" "rc=$rc"; fi
expect_ok "...and a chain to the supplied trust anchor is verified for the app and the profile" staging "$tmp/good.ipa" --expect-cert-sha256 "$PIN" --trust-anchors "$tmp/certs/root.crt"
expect_fail "a signing chain that does not reach the supplied trust anchors is refused" "does not chain to the supplied trust anchors" staging "$tmp/good.ipa" --expect-cert-sha256 "$PIN" --trust-anchors "$tmp/certs/leaf2.crt"
run staging "$tmp/good.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
if echo "$out" | grep -F "issuer is checked by name only" >/dev/null; then ok "without trust anchors the report says the issuer is checked by name only"; else bad "without trust anchors the report says the issuer is checked by name only"; fi
# CMS signer binding: the certificate that is reported must be the one that signed
mk spoof staging spoof-signer
expect_fail "a CMS signature that names its signer by key identifier (so a pinned certificate could be listed first) is refused" "not identified by issuer and serial" staging "$tmp/spoof.ipa" --expect-cert-sha256 "$PIN"
# the signed range
mk shortcl staging short-codelimit tamper-late-byte
expect_fail "a CodeDirectory that hashes only part of the file is refused" "part of the file is not protected" staging "$tmp/shortcl.ipa" --expect-cert-sha256 "$PIN"
mk trail staging trailing-data
expect_fail "data appended after the signature is refused" "follow the code signature at the end" staging "$tmp/trail.ipa" --expect-cert-sha256 "$PIN"
mk padpass staging padding-nonzero
expect_ok "stale data inside the signature's reserved area passes (real Apple and Flutter signatures leave it there)" staging "$tmp/padpass.ipa" --expect-cert-sha256 "$PIN"
# entitlements: the kernel enforces the DER form
mk derdiff staging der-differs
expect_fail "DER entitlements that differ from the XML entitlements are refused" "differ from the XML entitlements" staging "$tmp/derdiff.ipa" --expect-cert-sha256 "$PIN"
mk dertamper staging tamper-der
expect_fail "DER entitlements changed after signing are refused" "DER entitlements was changed after signing" staging "$tmp/dertamper.ipa" --expect-cert-sha256 "$PIN"
mk noder staging no-der
expect_ok "an IPA without DER entitlements (older signing) passes" staging "$tmp/noder.ipa" --expect-cert-sha256 "$PIN"
# code the tool cannot read must never be skipped
mk x86 staging x86-main
expect_fail "an executable that is not built for arm64 is refused" "not built for arm64" staging "$tmp/x86.ipa" --expect-cert-sha256 "$PIN"
mk m32 staging unsigned-macho32
expect_fail "a 32-bit Mach-O file is reported, not skipped as 'not code'" "64-bit Mach-O" staging "$tmp/m32.ipa" --expect-cert-sha256 "$PIN"
mk plug staging plugin
expect_fail "a nested app extension is refused (it would need its own profile check)" "nested apps or extensions" staging "$tmp/plug.ipa" --expect-cert-sha256 "$PIN"
mk exetrav staging exe-traversal
expect_fail "a CFBundleExecutable that is a path is refused" "not a plain file name" staging "$tmp/exetrav.ipa" --expect-cert-sha256 "$PIN"
# the bundle seal
mk crdots staging cr-dotdot-key
expect_fail "a CodeResources path with '..' is refused" "unsafe path" staging "$tmp/crdots.ipa" --expect-cert-sha256 "$PIN"
mk crok staging cr-cdhash-ok
expect_ok "a nested-bundle cdhash in CodeResources that matches the nested code passes" staging "$tmp/crok.ipa" --expect-cert-sha256 "$PIN"
mk crbad staging cr-cdhash-bad
expect_fail "a nested-bundle cdhash in CodeResources that is not the nested code's is refused" "not the nested code's cdhash" staging "$tmp/crbad.ipa" --expect-cert-sha256 "$PIN"
mk stale staging stale-seal
expect_fail "a nested binary signed again after the app was sealed is refused (stale seal)" "Flut.framework/Flut was modified after signing" staging "$tmp/stale.ipa" --expect-cert-sha256 "$PIN"
mk csextra staging cs-extra-file
expect_fail "an extra file hidden in _CodeSignature is refused" "unexpected file in _CodeSignature" staging "$tmp/csextra.ipa" --expect-cert-sha256 "$PIN"
python3 -I "$verify" compare "$tmp/staging/Runner.app" "$tmp/csextra.ipa" >"$tmp/cmp.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "files added to the IPA" "$tmp/cmp.txt" >/dev/null; then ok "compare refuses a file hidden in _CodeSignature"; else bad "compare refuses a file hidden in _CodeSignature" "rc=$crc"; fi
# malformed metadata: a failure, never a crash and never a pass
mk badplist staging garbage-info-plist
expect_fail "a garbage Info.plist is a failure" "Info.plist is unreadable" staging "$tmp/badplist.ipa" --expect-cert-sha256 "$PIN"
if echo "$out" | grep -F "Traceback" >/dev/null; then bad "...without a Python traceback"; else ok "...without a Python traceback"; fi
mk badprof staging truncated-profile
expect_fail "a truncated provisioning profile is a failure" "embedded.mobileprovision is unreadable" staging "$tmp/badprof.ipa" --expect-cert-sha256 "$PIN"
if echo "$out" | grep -F "Traceback" >/dev/null; then bad "...without a Python traceback"; else ok "...without a Python traceback"; fi
mk tprof staging tamper-profile
expect_fail "a provisioning profile changed after signing is a failure" "embedded.mobileprovision" staging "$tmp/tprof.ipa" --expect-cert-sha256 "$PIN"
mk tvos staging profile-platform-tvos
expect_fail "a profile for another platform is refused" "profile platform is" staging "$tmp/tvos.ipa" --expect-cert-sha256 "$PIN"
# archives
python3 - "$tmp/good.ipa" "$tmp/dup.ipa" "$tmp/link.ipa" <<'PYEOF'
import shutil, sys, zipfile, warnings
src, dup, link = sys.argv[1:4]
shutil.copy(src, dup)
warnings.simplefilter("ignore")
with zipfile.ZipFile(dup, "a") as z:
    z.writestr("Payload/Runner.app/PkgInfo", b"APPL????")
shutil.copy(src, link)
with zipfile.ZipFile(link, "a") as z:
    zi = zipfile.ZipInfo("Payload/Runner.app/escape")
    zi.create_system = 3
    zi.external_attr = (0o120777 << 16)
    z.writestr(zi, "../../../outside")
PYEOF
expect_fail "an archive with a duplicated member name is refused" "duplicate member names" staging "$tmp/dup.ipa" --expect-cert-sha256 "$PIN"
expect_fail "a symbolic link that leaves the bundle is refused" "leaves the bundle" staging "$tmp/link.ipa" --expect-cert-sha256 "$PIN"
mkdir -p "$tmp/enc/Payload/Runner.app" && echo x >"$tmp/enc/Payload/Runner.app/Info.plist"
( cd "$tmp/enc" && zip -q -r -P secret ../enc.ipa Payload )
expect_fail "an archive with encrypted members is refused" "encrypted members" staging "$tmp/enc.ipa"
# damage anywhere in the executable's header or code is never a pass
python3 - "$tmp/good.ipa" "$tmp" <<'PYEOF'
import sys, zipfile
src, out = sys.argv[1:3]
offs = [0, 5, 17, 40, 300, 0x400, 0x1000, 0x1ABC, 0x2000, 0x3FFF, 0x4000, 0x40FF]
for n, off in enumerate(offs):
    with zipfile.ZipFile(src) as zi, zipfile.ZipFile("%s/fuzz%d.ipa" % (out, n), "w", zipfile.ZIP_DEFLATED) as zo:
        for info in zi.infolist():
            data = zi.read(info.filename)
            if info.filename == "Payload/Runner.app/Runner":
                b = bytearray(data); b[off] ^= 0xFF; data = bytes(b)
            zo.writestr(info, data)
PYEOF
fz=0; fzbad=""
for n in 0 1 2 3 4 5 6 7 8 9 10 11; do
  run staging "$tmp/fuzz$n.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
  if [ "$rc" -ne 1 ] || echo "$out" | grep -F "Traceback" >/dev/null; then fz=1; fzbad="$fzbad $n"; fi
done
if [ "$fz" -eq 0 ]; then ok "a flipped byte at 12 places in the executable (header, code, link edit) is always a failure"; else bad "a flipped byte in the executable is always a failure" "passed or crashed for:$fzbad"; fi
trunc=0
for n in 100 5000 40000 60000; do
  head -c "$n" "$tmp/good.ipa" >"$tmp/trunc.ipa"
  run staging "$tmp/trunc.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
  if [ "$rc" -ne 1 ] || echo "$out" | grep -F "Traceback" >/dev/null; then trunc=1; fi
done
if [ "$trunc" -eq 0 ]; then ok "a truncated archive is always a clean failure"; else bad "a truncated archive is always a clean failure"; fi

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

cflags=(--leaf-prefix "Synthetic Distribution:" --allow-synthetic)
# ---- Apple cloud-managed signing support (Issue #54/#71): certificate collection, forbidden entitlements,
# ---- and a baseline taken from a signed archive. All synthetic; none of this proves Apple acceptance.
python3 -I "$verify" certificate "${cflags[@]}" "$tmp/good.ipa" --team-id "$TEAM" --pem "$tmp/collected.pem" --evidence "$tmp/cert-evidence.txt" >"$tmp/cert.txt" 2>&1; crc=$?
GOTPIN="$(python3 -I "$fixture" fingerprint "$tmp/collected.pem" 2>/dev/null)"
if [ "$crc" -eq 0 ] && [ "$GOTPIN" = "$PIN" ] && grep -F "RECORD (a public value; the pin for \`verify --expect-cert-sha256\`): $PIN" "$tmp/cert.txt" >/dev/null; then
  ok "certificate reports the signer's SHA-256 fingerprint and writes the same public certificate (no keychain needed)"
else bad "certificate reports the signer's SHA-256 fingerprint and writes the same public certificate" "rc=$crc got=$GOTPIN"; fi
if grep -F "signer_sha256=$PIN" "$tmp/cert-evidence.txt" >/dev/null && grep -F "embedded profile lists this certificate" "$tmp/cert.txt" >/dev/null; then ok "certificate records the fingerprint as evidence and compares it with the profile"; else bad "certificate records the fingerprint as evidence and compares it with the profile"; fi
if grep -E 'PRIVATE KEY' "$tmp/collected.pem" "$tmp/cert.txt" "$tmp/cert-evidence.txt" >/dev/null; then bad "certificate output holds no private key"; else ok "certificate output holds no private key"; fi
python3 -I "$verify" certificate "$tmp/good.ipa" --leaf-prefix "Synthetic Distribution:" >"$tmp/cert.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "synthetic identity, not a genuine Apple-issued one" "$tmp/cert.txt" >/dev/null && ! grep -F "RECORD (" "$tmp/cert.txt" >/dev/null; then ok "certificate refuses a synthetic identity unless told it is a test, and offers nothing to record"; else bad "certificate refuses a synthetic identity by default" "rc=$crc"; fi
python3 -I "$verify" certificate "${cflags[@]}" "$tmp/good.ipa" --team-id OTHER12345 >"$tmp/cert.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "is not Team ID OTHER12345" "$tmp/cert.txt" >/dev/null; then ok "certificate refuses an expected Team ID the certificate does not belong to"; else bad "certificate refuses a wrong Team ID" "rc=$crc"; fi
python3 -I "$verify" certificate "${cflags[@]}" "$tmp/adhoc.ipa" >"$tmp/cert.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "FAIL" "$tmp/cert.txt" >/dev/null; then ok "certificate refuses an ad-hoc signed IPA"; else bad "certificate refuses an ad-hoc signed IPA" "rc=$crc"; fi
python3 -I "$verify" certificate "${cflags[@]}" "$tmp/fwother.ipa" >"$tmp/cert.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "different certificates" "$tmp/cert.txt" >/dev/null; then ok "certificate refuses a bundle signed by more than one certificate"; else bad "certificate refuses a bundle signed by more than one certificate" "rc=$crc"; fi
python3 -I "$verify" certificate "${cflags[@]}" "$tmp/tampercms.ipa" >"$tmp/cert.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "CMS signature is not valid" "$tmp/cert.txt" >/dev/null && ! grep -F "RECORD (" "$tmp/cert.txt" >/dev/null; then ok "certificate refuses a signature whose CMS is not valid and offers no fingerprint to record"; else bad "certificate refuses an invalid CMS signature" "rc=$crc"; fi
python3 -I "$verify" certificate "${cflags[@]}" "$tmp/notzip.ipa" >"$tmp/cert.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "FAIL" "$tmp/cert.txt" >/dev/null; then ok "certificate refuses an archive that is not a zip"; else bad "certificate refuses an archive that is not a zip" "rc=$crc"; fi
python3 -I "$verify" certificate "${cflags[@]}" "$tmp/staging/Runner.app" >"$tmp/cert.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && ! grep -F "RECORD (" "$tmp/cert.txt" >/dev/null; then ok "certificate refuses an unsigned app and offers no fingerprint to record"; else bad "certificate refuses an unsigned app" "rc=$crc"; fi
python3 -I "$verify" certificate "${cflags[@]}" "$tmp/good.ipa" --trust-anchors "$tmp/certs/leaf2.crt" >"$tmp/cert.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "does not chain to the supplied trust anchors" "$tmp/cert.txt" >/dev/null; then ok "certificate checks the chain against supplied trust anchors when given"; else bad "certificate checks the chain against supplied trust anchors" "rc=$crc"; fi
python3 -I "$verify" certificate "${cflags[@]}" "$tmp/good.ipa" >"$tmp/cert.txt" 2>&1
if grep -F "no --trust-anchors" "$tmp/cert.txt" >/dev/null && grep -F "pins and approves nothing" "$tmp/cert.txt" >/dev/null; then ok "certificate says plainly that it pins nothing and verified no chain to Apple"; else bad "certificate says plainly that it pins nothing"; fi
if grep -F "WARN  revocation is never checked" "$tmp/cert.txt" >/dev/null; then ok "certificate says plainly (as a warning) that revocation is never checked"; else bad "certificate says plainly that revocation is never checked"; fi
python3 -I "$verify" certificate "${cflags[@]}" "$tmp/profnocert.ipa" >"$tmp/cert.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "the profile does not list this certificate" "$tmp/cert.txt" >/dev/null && ! grep -F "RECORD (" "$tmp/cert.txt" >/dev/null; then ok "certificate refuses a signer the embedded profile does not list, and offers nothing to record"; else bad "certificate refuses a signer the embedded profile does not list" "rc=$crc"; fi

# --forbid-entitlement: the release record's "no push capability" decision, enforced on the signed entitlements
expect_fail "--forbid-entitlement aps-environment refuses an IPA that carries it" "entitlement aps-environment is present" staging "$tmp/good.ipa" --expect-cert-sha256 "$PIN" --forbid-entitlement aps-environment
mk nopush staging no-push
expect_ok "an IPA without aps-environment passes with --forbid-entitlement aps-environment (the profile may still list it)" staging "$tmp/nopush.ipa" --expect-cert-sha256 "$PIN" --forbid-entitlement aps-environment
expect_ok "without the option, aps-environment stays optional (behaviour unchanged)" staging "$tmp/nopush.ipa" --expect-cert-sha256 "$PIN"
expect_fail "--forbid-entitlement refuses any named key, not only the push one" "entitlement beta-reports-active is present" staging "$tmp/nopush.ipa" --expect-cert-sha256 "$PIN" --forbid-entitlement beta-reports-active
run staging "$tmp/nopush.ipa" "${common[@]}" --expect-cert-sha256 "$PIN" --evidence "$tmp/ev-nopush.txt"
if grep -F "entitlement.application-identifier=" "$tmp/ev-nopush.txt" >/dev/null && ! grep -F "entitlement.aps-environment" "$tmp/ev-nopush.txt" >/dev/null; then ok "the evidence lists every signed entitlement with its value (and no aps-environment here)"; else bad "the evidence lists every signed entitlement"; fi

# a baseline taken from a SIGNED archive: its development profile is replaced at export, the code is not
rm -rf "$tmp/archbase" && cp -R "$tmp/staging" "$tmp/archbase"
printf 'development-profile-placeholder' >"$tmp/archbase/Runner.app/embedded.mobileprovision"
python3 -I "$verify" compare "$tmp/archbase/Runner.app" "$tmp/good.ipa" >"$tmp/cmp.txt" 2>&1; crc=$?
if [ "$crc" -eq 0 ]; then ok "compare accepts a baseline whose embedded profile differs (an archive signed for development)"; else bad "compare accepts a baseline whose embedded profile differs" "rc=$crc $(grep -E 'FAIL' "$tmp/cmp.txt" | head -2 | tr '\n' '|')"; fi
printf 'x' >>"$tmp/archbase/Runner.app/PkgInfo"
python3 -I "$verify" compare "$tmp/archbase/Runner.app" "$tmp/good.ipa" >"$tmp/cmp.txt" 2>&1; crc=$?
if [ "$crc" -eq 1 ] && grep -F "files that differ from the unsigned build" "$tmp/cmp.txt" >/dev/null; then ok "...but any other changed file is still refused"; else bad "...but any other changed file is still refused" "rc=$crc"; fi
spike="$root/tool/spike_resign_unsigned_ios.sh"
if bash -n "$spike"; then ok "the macOS spike script is syntactically valid"; else bad "the macOS spike script is syntactically valid"; fi
if [ "$(uname -s)" != "Darwin" ]; then
  bash "$spike" "$tmp/staging/Runner.app" "$tmp/spike" >/dev/null 2>&1; src=$?
  if [ "$src" -eq 2 ]; then ok "the macOS spike script refuses to run off macOS"; else bad "the macOS spike script refuses to run off macOS" "rc=$src"; fi
fi
if grep -vE '^[[:space:]]*#' "$spike" | grep -iE 'altool|notarytool|exportArchive|AuthKey|\.p8|appstoreconnect|curl|wget|gh api|security (delete|default|list)-keychains? -d (login|user)' >/dev/null; then bad "the spike script has no upload, API-key or login-keychain command"; else ok "the spike script has no upload, API-key or login-keychain command"; fi

# structure (reads the signing structure without judging the identity)
python3 -I "$verify" structure "$tmp/good.ipa" >"$tmp/st.txt" 2>&1; src=$?
if [ "$src" -eq 0 ] && grep -F "distinct signing certificate" "$tmp/st.txt" >/dev/null; then ok "structure accepts an intact signed IPA and reports the signers"; else bad "structure accepts an intact signed IPA" "rc=$src"; fi
python3 -I "$verify" structure "$tmp/tamperexe.ipa" >"$tmp/st.txt" 2>&1; src=$?
if [ "$src" -eq 1 ]; then ok "structure rejects a tampered executable"; else bad "structure rejects a tampered executable" "rc=$src"; fi
python3 -I "$verify" structure "$tmp/derdiff.ipa" >"$tmp/st.txt" 2>&1; src=$?
if [ "$src" -eq 1 ] && grep -F "differ from the XML entitlements" "$tmp/st.txt" >/dev/null; then ok "structure rejects DER entitlements that differ from the XML ones"; else bad "structure rejects DER entitlements that differ" "rc=$src"; fi
python3 -I "$verify" structure "$tmp/good_prod.ipa" >"$tmp/st.txt" 2>&1; src=$?
if [ "$src" -eq 0 ]; then ok "structure judges no identity (a synthetic production-named IPA has an intact structure)"; else bad "structure judges no identity" "rc=$src"; fi

# analyze-unsigned on the synthetic unsigned app
a="$(python3 -I "$verify" analyze-unsigned "$tmp/staging/Runner.app" 2>&1)"; arc=$?
if [ "$arc" -eq 0 ] && echo "$a" | grep -F "with no signature" >/dev/null && echo "$a" | grep -F "unsigned   Runner" >/dev/null; then ok "analyze-unsigned lists the unsigned executables"; else bad "analyze-unsigned lists the unsigned executables" "rc=$arc"; fi

# ---- 11. Phase 1 repair of the verifier (Issue #71; the first real Apple-signed IPA, run 44834801248) ----------------
# The forensic audit of that run found defects in how THIS verifier read genuine Apple structures; this section pins the
# repairs. What is REAL data here and what is SYNTHETIC:
#   REAL      tool/fixtures/apple_cloud_signing_cms_run44834801248.txt: the 16 CMS signatures Apple's cloud signing service
#             returned (public data; provenance in the file). tool/fixtures/apple_swift_runtime_embedded_info_plist.txt: the
#             embedded Info.plist section of Apple's Swift runtime library and the hashes its signature seals (public data).
#   SYNTHETIC the IPAs of tool/ipa_fixture.py (same structures, our own certificates), which cannot prove that Apple agrees.
# The DER entitlements layout is covered by REAL Apple blobs since Phase 6B (section 14). Not covered, because no genuine evidence
# exists yet: the V8 Info.plist comparison.
cmsfix="$root/tool/fixtures/apple_cloud_signing_cms_run44834801248.txt"
swiftfix="$root/tool/fixtures/apple_swift_runtime_embedded_info_plist.txt"

# pyunit ARGS...: runs the python script on stdin; its lines "ok   ..." / "FAIL ..." are counted like the checks above.
pyunit() {
  local pout prc line
  pout="$(python3 -I - "$@" 2>&1)"; prc=$?
  while IFS= read -r line; do
    case "$line" in
      "ok   "*) pass=$((pass + 1)); echo "$line" ;;
      "FAIL "*) failed=$((failed + 1)); echo "$line" ;;
      "") ;;
      *) echo "     $line" ;;
    esac
  done <<<"$pout"
  if [ "$prc" -ne 0 ]; then bad "the python checks ran to completion" "exit $prc"; fi
}

# 11a. synthetic IPAs. The default fixture already has Apple's real forms: a cdhashes attribute WITHOUT the XML declaration
# and a loose dylib that carries its own __TEXT,__info_plist section sealed in special slot 1.
run staging "$tmp/good.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
if [ "$rc" -eq 0 ] && grep -F "PASS  Frameworks/libswift_Embedded.dylib: signature intact" <<<"$out" >/dev/null && ! grep -F "NOT CHECKED" <<<"$out" >/dev/null; then
  ok "Apple's cdhashes form (no XML declaration) and a dylib with an embedded, sealed Info.plist section pass, with nothing left unchecked"
else
  bad "Apple's cdhashes form and an embedded, sealed Info.plist section pass" "exit $rc: $(echo "$out" | grep -E 'FAIL|NOT CHECKED' | head -3 | tr '\n' '|')"
fi
mk good_xmldecl staging cdhashes-plist-xmldecl
expect_ok "a cdhashes attribute in the older form, WITH the XML declaration, still passes" staging "$tmp/good_xmldecl.ipa" --expect-cert-sha256 "$PIN"
mk good_binplist staging cdhashes-plist-binary
expect_ok "a cdhashes attribute as a binary property list still passes" staging "$tmp/good_binplist.ipa" --expect-cert-sha256 "$PIN"
mk cdgarbage staging cdhashes-plist-garbage
expect_fail "a cdhashes attribute that is not a property list is refused" "CMS cdhashes attribute is unreadable" staging "$tmp/cdgarbage.ipa" --expect-cert-sha256 "$PIN"
mk cdshort staging cdhashes-short
expect_fail "cdhashes of the wrong length are refused" "CMS cdhashes attribute is unreadable" staging "$tmp/cdshort.ipa" --expect-cert-sha256 "$PIN"
mk cdempty staging cdhashes-plist-empty-list
expect_fail "an empty cdhashes list is refused" "CMS cdhashes attribute is unreadable" staging "$tmp/cdempty.ipa" --expect-cert-sha256 "$PIN"
mk cdomit staging dual cdhashes-omit-first
expect_fail "a CodeDirectory that the signed cdhashes do not list is refused (the binding is enforced)" "is not bound by the signature" staging "$tmp/cdomit.ipa" --expect-cert-sha256 "$PIN"
# control flow: a failing CMS stage must neither hide the independent checks nor pass anything by default
mk cdflow staging cdhashes-plist-garbage der-differs
run staging "$tmp/cdflow.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
if [ "$rc" -eq 1 ] && grep -F "FAIL" <<<"$out" | grep -F "CMS cdhashes attribute is unreadable" >/dev/null \
   && grep -F "FAIL" <<<"$out" | grep -F "differ from the XML entitlements" >/dev/null \
   && grep -F "NOT CHECKED" <<<"$out" | grep -F "CodeDirectory is bound" >/dev/null \
   && ! grep -F "no embedded entitlements" <<<"$out" >/dev/null && ! grep -F "PASS  main executable Runner: signature intact" <<<"$out" >/dev/null; then
  ok "an unreadable cdhashes attribute fails, the independent entitlement check still runs, the unavailable binding check is named, and nothing passes by default"
else
  bad "an unreadable cdhashes attribute fails, the independent checks still run, the dependent one is named unavailable" "exit $rc: $(echo "$out" | grep -E 'FAIL|NOT CHECKED' | head -5 | tr '\n' '|')"
fi
# ... and the same when the CMS STRUCTURE itself is unreadable (the original defect: a `continue` here skipped the entitlement checks and
# produced a misleading "no embedded entitlements")
mk cmsflow staging spoof-signer der-differs dual cdhashes-omit-first
run staging "$tmp/cmsflow.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
if [ "$rc" -eq 1 ] && grep -F "FAIL" <<<"$out" | grep -F "CMS signature is unreadable" >/dev/null \
   && grep -F "FAIL" <<<"$out" | grep -F "differ from the XML entitlements" >/dev/null \
   && grep -F "FAIL" <<<"$out" | grep -F "is not bound by the signature" >/dev/null \
   && grep -F "NOT CHECKED" <<<"$out" | grep -F "the signer" >/dev/null \
   && ! grep -F "no embedded entitlements" <<<"$out" >/dev/null && ! grep -F "PASS  main executable Runner: signature intact" <<<"$out" >/dev/null; then
  ok "an unreadable CMS structure fails, the entitlement and CodeDirectory-binding checks still run, the unavailable signer checks are named, and nothing passes by default"
else
  bad "an unreadable CMS structure fails, the independent checks still run, the dependent ones are named unavailable" "exit $rc: $(echo "$out" | grep -E 'FAIL|NOT CHECKED' | head -5 | tr '\n' '|')"
fi
mk emb_wrong staging embedded-info-slot-wrong
expect_fail "a seal that is not the hash of the embedded Info.plist section is refused" "the embedded Info.plist section was changed after signing" staging "$tmp/emb_wrong.ipa" --expect-cert-sha256 "$PIN"
mk emb_unsealed staging embedded-info-unsealed
expect_fail "an embedded Info.plist section that the CodeDirectory does not seal is refused" "does not seal the embedded Info.plist section" staging "$tmp/emb_unsealed.ipa" --expect-cert-sha256 "$PIN"
mk emb_tamper staging tamper-embedded-info
expect_fail "a modified embedded Info.plist section is refused (the special slot notices it)" "the embedded Info.plist section was changed after signing" staging "$tmp/emb_tamper.ipa" --expect-cert-sha256 "$PIN"
mk orphan staging slot1-orphan
expect_fail "a non-zero Info.plist seal with neither a file nor a section is refused, whatever the library is called (libswift_*)" "seals Info.plist, which is absent" staging "$tmp/orphan.ipa" --expect-cert-sha256 "$PIN"

# 11b. REAL data (public signing structures from run 44834801248) and unit checks of the readers
pyunit "$root" "$cmsfix" "$swiftfix" <<'PY'
import base64, hashlib, os, plistlib, subprocess, sys, tempfile
sys.dont_write_bytecode = True
root, cmsfix, swiftfix = sys.argv[1:4]
sys.path.insert(0, os.path.join(root, "tool"))
import ipa_inspect as I
import ipa_fixture as F


def ok(m): print("ok   " + m)
def bad(m, why=""):
    print("FAIL " + m)
    if why: print("     " + why)
def check(c, m, why=""): ok(m) if c else bad(m, why)


def raises(fn, *exc):
    try:
        fn()
    except exc:
        return True
    except Exception:
        return False
    return False


blobs = []
for line in open(cmsfix):
    if line.startswith("#") or not line.strip():
        continue
    path, digest, b64 = line.split()
    blobs.append((path, digest, base64.b64decode(b64)))
check(len(blobs) == 16 and all(hashlib.sha256(d).hexdigest() == h for _p, h, d in blobs), "the 16 real Apple cloud-signing CMS fixtures are intact (recorded SHA-256 of each)")


def attrs(der):
    root_ = I.parse_der(der)
    sd = root_.children[1].children[0]
    si = [p for p in sd.children if p.cls == 0 and p.tag == 17][-1].children[0]
    for k in si.children:
        if k.cls == 2 and k.tag == 0:
            return {I.oid_str(a.children[0]): a.children[1].children[0] for a in k.children}


texts = [I.octets(attrs(d)[I.OID_APPLE_CDHASHES]) for _p, _h, d in blobs]
check(all(t.startswith(b"<!DOCTYPE plist") and b"<?xml" not in t for t in texts),
      "REAL: every cdhashes attribute starts with <!DOCTYPE plist and has no XML declaration (the form that broke automatic detection)")
parsed = [I.parse_cms(d) for _p, _h, d in blobs]
check(len({c["signer"]["sha256"] for c in parsed}) == 1 and all(c["digest_oid"] in I.OID_SHA256_FAMILY for c in parsed),
      "REAL: all 16 CMS structures parse, with one signer certificate and a SHA-256 digest")
got = [(p, I.cms_cdhashes(d)) for p, _h, d in blobs]
check(all(len(hs) == (2 if p.endswith("libswift_Concurrency.dylib") else 1) and all(len(h) == 20 for h in hs) for p, hs in got),
      "REAL: cms_cdhashes reads all 16 attributes (one 20-byte hash each, two for the library with SHA-1 and SHA-256 CodeDirectories)")
md = {p: I.octets(attrs(d)["1.2.840.113549.1.9.4"]) for p, _h, d in blobs}
check(all(hs[0] == md[p][:20] for p, hs in got if not p.endswith("libswift_Concurrency.dylib")),
      "REAL: the listed cdhash is the first 20 bytes of the signed SHA-256 message digest of the CodeDirectory (the binding is consistent)")

exe = I.openssl_path()
empty = tempfile.NamedTemporaryFile(delete=False)
empty.close()


def sig_ok(der):
    # the RSA signature over the signed attributes (which include the cdhashes), WITHOUT the content digest comparison: the
    # CodeDirectory itself is not part of the fixture, so only the signature over the attributes can be checked here
    with tempfile.TemporaryDirectory() as td:
        f = os.path.join(td, "s.der")
        open(f, "wb").write(der)
        r = subprocess.run([exe, "cms", "-verify", "-inform", "DER", "-in", f, "-noverify", "-no_content_verify", "-binary",
                            "-content", empty.name, "-signer", os.path.join(td, "signer.pem"), "-out", os.devnull], capture_output=True)
        return r.returncode == 0


check(all(sig_ok(d) for _p, _h, d in blobs), "REAL: the RSA signature over the signed attributes of all 16 verifies with openssl")
d0 = bytearray(blobs[0][2])
i = d0.find(b"<data>") + 12
d0[i] = ord("A") if d0[i] != ord("A") else ord("B")  # one character of the signed cdhash, still a readable property list
mod = bytes(d0)
read_mod = I.cms_cdhashes(mod)
check(read_mod != got[0][1] and not sig_ok(mod),
      "REAL: a modified cdhash reads fine (parsing alone would accept it) but the CMS signature check REJECTS it")
d1 = bytearray(blobs[0][2])
j = d1.find(b"<!DOCTYPE plist")
d1[j:j + 40] = b"X" * 40
check(raises(lambda: I.cms_cdhashes(bytes(d1)), I.Asn1Error) and not sig_ok(bytes(d1)),
      "REAL: a cdhashes attribute replaced by garbage is refused by the reader and by the signature check")
check(raises(lambda: I.parse_cms(blobs[0][2][:len(blobs[0][2]) // 2]), I.Asn1Error, IndexError, ValueError),
      "REAL: a truncated CMS structure is refused")
check(raises(lambda: I.parse_cms(blobs[0][2] + b"\x00\x01"), I.Asn1Error), "REAL: bytes after the CMS structure are refused")

# the property-list reader, in isolation
good = {"cdhashes": [b"\x01" * 20]}
x = plistlib.dumps(good, fmt=plistlib.FMT_XML)
accepted = {
    "XML with the declaration": x,
    "XML without the declaration (Apple's cloud signing)": x.split(b"?>\n", 1)[1],
    "XML without the declaration, after white space": b"\n  " + x.split(b"?>\n", 1)[1],
    "XML starting at <plist": x.split(b"<plist", 1)[0] and b"<plist" + x.split(b"<plist", 1)[1],
    "binary property list": plistlib.dumps(good, fmt=plistlib.FMT_BINARY),
}
check(all(I.parse_cdhashes_plist(v) == [b"\x01" * 20] for v in accepted.values()), "cdhashes reader: accepts " + ", ".join(accepted))
body = x.split(b"?>\n", 1)[1]
refused = {
    "garbage": b"hello", "empty": b"", "a list, not a dictionary": plistlib.dumps([1], fmt=plistlib.FMT_XML),
    "no cdhashes key": plistlib.dumps({"x": 1}, fmt=plistlib.FMT_XML), "an empty list": plistlib.dumps({"cdhashes": []}, fmt=plistlib.FMT_XML),
    "a hash of 19 bytes": plistlib.dumps({"cdhashes": [b"\x01" * 19]}, fmt=plistlib.FMT_XML),
    "a hash of 32 bytes": plistlib.dumps({"cdhashes": [b"\x01" * 32]}, fmt=plistlib.FMT_XML),
    "a string element": plistlib.dumps({"cdhashes": ["abc"]}, fmt=plistlib.FMT_XML),
    "the same hash twice": plistlib.dumps({"cdhashes": [b"\x01" * 20, b"\x01" * 20]}, fmt=plistlib.FMT_XML),
    "a repeated cdhashes key": body.replace(b"</dict>", b"<key>cdhashes</key><array><data>AQEBAQEBAQEBAQEBAQEBAQEBAQE=</data></array></dict>"),
    "a DTD that declares entities": b'<!DOCTYPE plist [<!ENTITY a "b">]><plist version="1.0"><dict/></plist>',
    "an oversized attribute": b"<plist>" + b"x" * 70000, "truncated XML": body[:60], "a truncated binary list": plistlib.dumps(good, fmt=plistlib.FMT_BINARY)[:20],
}
bad_ones = [k for k, v in refused.items() if not raises(lambda v=v: I.parse_cdhashes_plist(v), I.Asn1Error)]
check(not bad_ones, "cdhashes reader: refuses " + ", ".join(refused), "accepted or crashed on: %s" % bad_ones)

# the embedded Info.plist reader and the seal, on REAL data
fx = {}
for line in open(swiftfix):
    if line.startswith("#") or not line.strip():
        continue
    k, *v = line.split()
    fx.setdefault(k, []).append(v)
emb = base64.b64decode(fx["section"][0][0])
check(len(emb) == 591 and b"com.apple.dt.runtime.swiftConcurrency" in emb, "REAL: the fixture holds the 591-byte embedded Info.plist section of Apple's Swift runtime library")
seals = {alg: bytes.fromhex(h) for alg, h in fx["slot1"]}
check(set(seals) == {"sha1", "sha256"} and all(hashlib.new(a, emb).digest() == h for a, h in seals.items()),
      "REAL: the Info.plist seal (special slot 1) of BOTH CodeDirectories (SHA-1 and SHA-256) is the hash of that embedded section")
check(all(hashlib.new(a, emb[:-1] + b"\x00").digest() != h for a, h in seals.items()), "REAL: any change to the embedded section changes the hashes the seals must equal")

# embedded_info_plist on synthetic Mach-O files
plain = F.make_macho("u1", filetype=6)
withp = F.make_macho("u2", filetype=6, info_plist=F.EMBEDDED_INFO_PLIST)
m1, m2 = I.parse_macho_slice(plain, 0, len(plain)), I.parse_macho_slice(withp, 0, len(withp))
check(I.embedded_info_plist(plain, m1) is None and I.embedded_info_plist(withp, m2) == F.EMBEDDED_INFO_PLIST,
      "embedded_info_plist: none without the section, exactly its bytes with it (no file name is consulted)")
SECT2 = 32 + 72 + 80  # the second section header of the synthetic __TEXT segment
twice = bytearray(withp)
twice[32 + 72:32 + 72 + 16] = b"__info_plist".ljust(16, b"\0")
check(raises(lambda: I.embedded_info_plist(bytes(twice), I.parse_macho_slice(bytes(twice), 0, len(twice))), I.MachOError), "embedded_info_plist: two such sections are refused")
zf = bytearray(withp)
zf[SECT2 + 64:SECT2 + 68] = (1).to_bytes(4, "little")
check(raises(lambda: I.embedded_info_plist(bytes(zf), I.parse_macho_slice(bytes(zf), 0, len(zf))), I.MachOError), "embedded_info_plist: a zero-fill section is refused")
big = bytearray(withp)
big[SECT2 + 40:SECT2 + 48] = (len(withp) * 2).to_bytes(8, "little")
check(raises(lambda: I.embedded_info_plist(bytes(big), I.parse_macho_slice(bytes(big), 0, len(big))), I.MachOError), "embedded_info_plist: a section outside the slice is refused")
other = bytearray(withp)
other[SECT2 + 16:SECT2 + 32] = b"__DATA".ljust(16, b"\0")
check(I.embedded_info_plist(bytes(other), I.parse_macho_slice(bytes(other), 0, len(other))) is None, "embedded_info_plist: a section of another segment is not the Info.plist")

# the REAL Apple-signed library, when it is at hand (not in CI: the file is Apple's and is not stored here)
real = os.environ.get("REAL_SWIFT_DYLIB")
if real:
    import verify_ipa as V

    class Rep:
        def __init__(self): self.fails, self.oks, self.warns = [], [], []
        def fail(self, m): self.fails.append(m)
        def ok(self, m): self.oks.append(m)
        def warn(self, m): self.warns.append(m)
        def info(self, m): pass
        def ev(self, k, v): pass
        def check(self, c, a, b): (self.oks if c else self.fails).append(a if c else b)

    r = Rep()
    res = V.check_code_signature(r, "REAL libswift_Concurrency.dylib", real, None, "com.app.cadenabitcoin", None, None, False)
    check(res["ok"] and not r.fails, "REAL FILE: the original Apple-signed Swift runtime library passes check_code_signature (page hashes, slots, CMS, cdhashes)", str(r.fails))
    data = bytearray(open(real, "rb").read())
    sl = I.macho_slices(bytes(data))[0]
    mm = I.parse_macho_slice(bytes(data), sl[1], sl[2])
    sect = I.embedded_info_plist(bytes(data[sl[1]:sl[1] + sl[2]]), mm)
    data[bytes(data).find(sect) + 100] ^= 1
    with tempfile.NamedTemporaryFile(delete=False) as t:
        t.write(bytes(data))
    r2 = Rep()
    res2 = V.check_code_signature(r2, "tampered", t.name, None, "com.app.cadenabitcoin", None, None, False)
    os.unlink(t.name)
    check(not res2["ok"] and any("embedded Info.plist section was changed after signing" in f for f in r2.fails),
          "REAL FILE: one changed byte of the embedded section is refused by the Info.plist seal")
os.unlink(empty.name)
PY

# ---- 12. Phase 2 diagnostics (Issue #71): HOW does the IPA's Info.plist differ, and what does an unreadable DER blob look like --
# Everything here is SYNTHETIC. These checks pin DIAGNOSTICS only: no acceptance rule was changed in Phase 2. In particular
# a difference of serialization only is still a FAILED comparison (an exact, type-preserving rule is proposed in
# docs/IOS_SIGNING.md, not activated), and a DER blob the parser refuses is still a failure. What the real Info.plist
# difference is, is NOT known (no genuine evidence kept). The real DER layout was unknown in Phase 2; it is now known (Phase 6B,
# section 14 below), and the synthetic DER blobs of this section follow it.

# cmpcase NAME PYCODE: a copy of the unsigned staging app whose Info.plist is rewritten by PYCODE (sees `d`, may set `fmt`),
# compared with the original by the signing job's check. -> $out, $rc
cmpcase() {
  rm -rf "$tmp/cc_$1"
  mkdir -p "$tmp/cc_$1"
  cp -R "$tmp/staging/Runner.app" "$tmp/cc_$1/Runner.app"
  python3 -I - "$tmp/cc_$1/Runner.app/Info.plist" "$2" <<'PY'
import plistlib, sys
path, code = sys.argv[1:3]
ns = {"d": plistlib.load(open(path, "rb")), "fmt": plistlib.FMT_BINARY, "plistlib": plistlib}
exec(code, ns)
open(path, "wb").write(plistlib.dumps(ns["d"], fmt=ns["fmt"]))
PY
  out="$(python3 -I "$verify" compare "$tmp/staging/Runner.app" "$tmp/cc_$1/Runner.app" 2>&1)"; rc=$?
}
# the difference is ALWAYS a failure; the diagnostic lines say how. $1 name, $2 pycode, remaining: fixed strings that must appear
cmpexpect() {
  local name=$1 code=$2; shift 2
  cmpcase "cc" "$code"
  local miss=""
  [ "$rc" -eq 1 ] || miss="exit $rc (a differing Info.plist must fail); "
  grep -F "FAIL  files that differ from the unsigned build: Info.plist" <<<"$out" >/dev/null || miss="${miss}no FAIL for the differing file; "
  local s
  for s in "$@"; do grep -F -e "$s" <<<"$out" >/dev/null || miss="${miss}missing '$s'; "; done
  if [ -z "$miss" ]; then ok "$name"; else bad "$name" "$miss"; fi
}

cmpcase same 'pass'
if [ "$rc" -eq 0 ] && ! grep -F "differs from the unsigned build" <<<"$out" >/dev/null; then ok "an Info.plist that is byte-identical is accepted and described as nothing (no diagnostic)"; else bad "a byte-identical Info.plist is accepted without a diagnostic" "rc=$rc"; fi
cmpexpect "a re-serialization only (binary -> XML, same content) is STILL refused, and is described as a difference of serialization only" \
  'fmt = plistlib.FMT_XML' "serialization only (binary -> xml)"
cmpexpect "an added key is refused and listed with its type and size, but NOT its value (the key is not on the display allowlist)" \
  'd["ZZAddedByTest"] = "x1"' "+ ZZAddedByTest (string) = <string, 2 character(s), 2 byte(s) in UTF-8; value not shown>" "DIFFERENT CONTENT: 1 added, 0 removed, 0 changed"
if grep -F "'x1'" <<<"$out" >/dev/null; then bad "the value of a key that is not approved is never printed"; else ok "the value of a key that is not approved is never printed"; fi
cmpexpect "a removed key is refused and listed (MinimumOSVersion is labelled as a platform key)" \
  'del d["MinimumOSVersion"]' "- MinimumOSVersion (string) was '14.0' [identity, version, platform or privilege key]"
cmpexpect "a changed value of a key that is not approved is refused and listed by type and size only" \
  'd["CFBundleDisplayName"] = "Other Name"' "~ CFBundleDisplayName (string value):" "value not shown> -> <string, 10 character(s)"
if grep -F "Other Name" <<<"$out" >/dev/null; then bad "neither the old nor the new text of an unapproved key is printed"; else ok "neither the old nor the new text of an unapproved key is printed"; fi
cmpexpect "a changed bundle identifier is refused and labelled" \
  'd["CFBundleIdentifier"] = "com.example.other"' "~ CFBundleIdentifier (string value):" "-> 'com.example.other' [identity, version, platform or privilege key]"
cmpexpect "a changed version is refused and labelled" \
  'd["CFBundleShortVersionString"] = "9.9.9"' "~ CFBundleShortVersionString (string value):" "-> '9.9.9' [identity"
cmpexpect "a changed build number is refused and labelled" \
  'd["CFBundleVersion"] = "1"' "~ CFBundleVersion (string value):" "-> '1' [identity"
cmpexpect "a changed value TYPE is refused: integer 1 became boolean true inside an array (Python's own 1 == True would call them equal)" \
  'd["UIDeviceFamily"] = [True]' "~ UIDeviceFamily[0] (integer -> bool): 1 -> True [identity"
cmpexpect "a changed value TYPE is refused: integer 1 became real 1.0 (1 == 1.0 in Python)" \
  'd["UIDeviceFamily"] = [1.0]' "~ UIDeviceFamily[0] (integer -> real): 1 -> 1.0"
cmpexpect "a string that became data is refused as a type change, both shown by type and size only" \
  'd["CFBundleName"] = b"signer"' "~ CFBundleName (string -> data): <string, 6 character(s), 6 byte(s) in UTF-8; value not shown> -> <data, 6 byte(s); value not shown>"
cmpexpect "a privilege-relevant array change (a background mode added) is refused and labelled" \
  'd["UIBackgroundModes"] = ["fetch", "voip"]' "~ UIBackgroundModes (array of 1 -> array of 2): <array of 1; elements not shown> -> <array of 2; elements not shown> [identity"
cmpexpect "a new key under a usage-description prefix is labelled as a privilege key, its text is not printed" \
  'd["NSContactsUsageDescription"] = "why-text"' "+ NSContactsUsageDescription (string) = <string, 8 character(s), 8 byte(s) in UTF-8; value not shown> [identity"
cmpexpect "a key that looks like a credential is added: refused, and its value is NOT printed" \
  'd["ApiTokenForTest"] = "s3cr3t-value-should-never-print"' "+ ApiTokenForTest (string) = <string, 31 character(s)"
if grep -F "s3cr3t-value-should-never-print" <<<"$out" >/dev/null; then bad "a credential-like value never reaches the output"; else ok "a credential-like value never reaches the output"; fi
cmpexpect "a secret under an INNOCENT key name is not printed either (there is no deny-list to get past, only an allowlist)" \
  'd["GoogleServicesHint"] = "AIzaSyD-not-a-real-key-0123456789abcdef"' "+ GoogleServicesHint (string) = <string, 39 character(s)"
if grep -F "AIzaSy" <<<"$out" >/dev/null; then bad "an innocently named key's value never reaches the output"; else ok "an innocently named key's value never reaches the output"; fi
cmpexpect "a long value of an unapproved key is reported by size only" \
  'd["CFBundleName"] = "n" * 300' "<string, 300 character(s), 300 byte(s) in UTF-8; value not shown>"
cmpexpect "an approved key whose value is outside the approved form (too long) is not shown either" \
  'd["CFBundleVersion"] = "9" * 200' "~ CFBundleVersion (string value): '1000035' ->" "<string, 200 character(s)"
cmpexpect "several differences are all listed (one added, one removed, one changed)" \
  'd["ZZAddedByTest"] = 1; del d["DTSDKName"]; d["CFBundleVersion"] = "2"' "+ ZZAddedByTest (integer) = <integer; value not shown>" "- DTSDKName (string)" "~ CFBundleVersion (string value)" "DIFFERENT CONTENT: 1 added, 1 removed, 1 changed"
rm -rf "$tmp/cc_garbage" && mkdir -p "$tmp/cc_garbage" && cp -R "$tmp/staging/Runner.app" "$tmp/cc_garbage/Runner.app" && printf 'not a property list' > "$tmp/cc_garbage/Runner.app/Info.plist"
out="$(python3 -I "$verify" compare "$tmp/staging/Runner.app" "$tmp/cc_garbage/Runner.app" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -F "FAIL  files that differ from the unsigned build: Info.plist" <<<"$out" >/dev/null && grep -F "not readable as a property list" <<<"$out" >/dev/null; then ok "an Info.plist that is not a property list is refused, and the description says it is unreadable"; else bad "an unreadable Info.plist is refused and described" "rc=$rc"; fi

cmpcase evid 'd["ZZAddedByTest"] = "x"'
python3 -I "$verify" compare "$tmp/staging/Runner.app" "$tmp/cc_evid/Runner.app" >/dev/null 2>&1
run_ev() { python3 - "$verify" "$tmp/staging/Runner.app" "$tmp/cc_evid/Runner.app" "$tmp/cmp_evidence.txt" <<'PY'
import sys
sys.dont_write_bytecode = True
import importlib.util
spec = importlib.util.spec_from_file_location("v", sys.argv[1]); V = importlib.util.module_from_spec(spec); spec.loader.exec_module(V)
rep = V.Report()
V.same_code_check(rep, sys.argv[2], sys.argv[3])
open(sys.argv[4], "w").write("".join("%s=%s\n" % kv for kv in rep.evidence))
PY
}
run_ev >/dev/null 2>&1
if grep -F "plist_difference_Info.plist=added=1 removed=0 changed=0" "$tmp/cmp_evidence.txt" >/dev/null; then ok "the evidence file records how the Info.plist differs (counts only)"; else bad "the evidence file records how the Info.plist differs" "$(cat "$tmp/cmp_evidence.txt" 2>/dev/null | head -3)"; fi

# R1: a flood of differences is counted exactly, listed in bounded form, and said to be incomplete (report and evidence file)
cmpcase flood 'for i in range(3000): d["ZZAdd%04d" % i] = i
for k in ("DTSDKName", "DTPlatformName", "MinimumOSVersion"): d.pop(k)
d["CFBundleVersion"] = "2"'
n_lines="$(grep -c "^INFO  Info.plist: [-+~] " <<<"$out")"
if [ "$rc" -eq 1 ] && grep -F "FAIL  files that differ from the unsigned build: Info.plist" <<<"$out" >/dev/null \
   && grep -F "DIFFERENT CONTENT: 3000 added, 3 removed, 1 changed" <<<"$out" >/dev/null \
   && [ "$n_lines" -le "$(python3 -I -c "import sys; sys.path.insert(0, '$root/tool'); import verify_ipa as V; print(V.MAX_PLIST_REPORT_LINES)")" ] \
   && grep -F "LISTING INCOMPLETE: " <<<"$out" >/dev/null && grep -E "LISTING INCOMPLETE: [0-9]+ of 3004 differences listed" <<<"$out" >/dev/null; then
  ok "3000 added + 3 removed + 1 changed: still a FAILURE, exact totals, a bounded listing ($n_lines line(s)) and an explicit 'LISTING INCOMPLETE: n of 3004'"
else bad "a flood of differences is bounded and reported as incomplete" "rc=$rc lines=$n_lines $(grep -F 'Info.plist' <<<"$out" | head -3)"; fi
python3 - "$verify" "$tmp/staging/Runner.app" "$tmp/cc_flood/Runner.app" "$tmp/flood_evidence.txt" >/dev/null 2>&1 <<'PY'
import sys
sys.dont_write_bytecode = True
import importlib.util
spec = importlib.util.spec_from_file_location("v", sys.argv[1]); V = importlib.util.module_from_spec(spec); spec.loader.exec_module(V)
rep = V.Report()
V.same_code_check(rep, sys.argv[2], sys.argv[3])
open(sys.argv[4], "w").write("".join("%s=%s\n" % kv for kv in rep.evidence))
PY
if grep -Fx "plist_difference_Info.plist=added=3000 removed=3 changed=1 listing_incomplete=1" "$tmp/flood_evidence.txt" >/dev/null && [ "$(grep -c '^plist_difference_' "$tmp/flood_evidence.txt")" -eq 1 ]; then ok "the evidence file holds the EXACT totals and says the listing is incomplete (one record)"; else bad "the evidence file states exact totals and an incomplete listing" "$(grep plist_difference "$tmp/flood_evidence.txt" 2>/dev/null | head -2)"; fi
cmpcase small 'd["ZZAdd"] = 1; d["CFBundleVersion"] = "2"'
if ! grep -F "LISTING INCOMPLETE" <<<"$out" >/dev/null && grep -F "DIFFERENT CONTENT: 1 added, 0 removed, 1 changed" <<<"$out" >/dev/null; then ok "a short list of differences is not reported as incomplete"; else bad "a short list is complete" "$(grep Info.plist <<<"$out" | head -3)"; fi
# a flood of ONE kind must not hide the other kinds from the totals
cmpcase hide 'for i in range(500): d["ZZAdd%04d" % i] = i
d["CFBundleVersion"] = "2"'
if grep -F "DIFFERENT CONTENT: 500 added, 0 removed, 1 changed" <<<"$out" >/dev/null; then ok "a flood of additions does not hide a change from the totals"; else bad "totals show every kind" "$(grep Info.plist <<<"$out" | head -3)"; fi

# DER diagnostics: a blob the parser refuses is still a failure, and the report now shows what the blob is
mk derv2 staging der-version2
run staging "$tmp/derv2.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
if [ "$rc" -eq 1 ] && grep -F "FAIL  main executable Runner: DER entitlements are unreadable: unsupported DER entitlements version or layout" <<<"$out" >/dev/null; then ok "a DER blob with an unsupported version is a FAILURE (the parser's rule is unchanged)"; else bad "a DER blob with an unsupported version is a failure" "rc=$rc"; fi
if grep -F "INFO  main executable Runner: DER outline: APPLICATION 16 constructed" <<<"$out" >/dev/null && grep -F "DER outline:   INTEGER, 1 byte(s): 0x02" <<<"$out" >/dev/null && grep -E "the DER entitlements blob is [0-9]+ byte\(s\), sha256 [0-9a-f]{64}; magic 0xfade7172" <<<"$out" >/dev/null; then ok "...and the report shows the blob's header and an ASN.1 outline that assumes no layout (classes, tags, lengths, small integers and booleans)"; else bad "the report of a refused DER blob shows header and outline" "$(grep -c 'DER' <<<"$out") DER lines"; fi
if ! grep -E "DER bytes|fade7172[0-9a-f]{20}" <<<"$out" >/dev/null && ! grep -F "DER" <<<"$out" | grep -F -e "application-identifier" -e "SYNTH12345" >/dev/null && grep -F "the bytes of a real IPA's DER blob are not printed" <<<"$out" >/dev/null; then ok "...but never its bytes and never the text of its strings (a real IPA's blob is reported by structure only)"; else bad "a real IPA's DER blob is not printed raw" "$(grep -E 'DER|application-identifier' <<<"$out" | head -3)"; fi
run staging "$tmp/good.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
if [ "$rc" -eq 0 ] && ! grep -F "DER outline" <<<"$out" >/dev/null; then ok "a DER blob that is read prints no diagnostic"; else bad "a readable DER blob prints no diagnostic" "rc=$rc"; fi

pyunit "$root" <<'PY'
import os, plistlib, struct, sys, datetime
sys.dont_write_bytecode = True
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, "tool"))
import ipa_inspect as I
import ipa_fixture as F


def ok(m): print("ok   " + m)
def bad(m, why=""):
    print("FAIL " + m)
    if why: print("     " + why)
def check(c, m, why=""): ok(m) if c else bad(m, why)


def b(d, fmt=plistlib.FMT_BINARY):
    return plistlib.dumps(d, fmt=fmt)


base = {"CFBundleIdentifier": "com.example.app", "CFBundleVersion": "7", "UIDeviceFamily": [1], "Flags": {"a": True, "b": 1},
        "Raw": b"\x00\x01", "When": datetime.datetime(2026, 1, 2, 3, 4, 5)}
d = I.plist_difference(b(base), b(base))
check(d["identical_bytes"] and d["semantic"] == "identical" and not d["serialization_only"] and not (d["added"] or d["removed"] or d["changed"]),
      "plist_difference: byte-identical files are identical, not 'serialization only', with no entries")
d = I.plist_difference(b(base), b(base, plistlib.FMT_XML))
check(not d["identical_bytes"] and d["serialization_only"] and d["old_format"] == "binary" and d["new_format"] == "xml",
      "plist_difference: the same content in binary and XML is serialization-only")
swapped = dict(reversed(list(base.items())))
d = I.plist_difference(b(base, plistlib.FMT_XML), plistlib.dumps(swapped, fmt=plistlib.FMT_XML, sort_keys=False))
check(d["semantic"] == "identical", "plist_difference: key order of a dictionary does not matter")
d = I.plist_difference(b(dict(base, UIDeviceFamily=[1, 2])), b(dict(base, UIDeviceFamily=[2, 1])))
check(d["semantic"] == "different" and len(d["changed"]) == 2, "plist_difference: the ORDER of an array matters")
check(I.plist_difference(b(dict(base, Flags={"a": True})), b(dict(base, Flags={"a": 1})))["semantic"] == "different",
      "plist_difference: True and 1 are different (type-strict, unlike Python's ==)")
check(I.plist_difference(b({"x": 1}), b({"x": 1.0}))["semantic"] == "different", "plist_difference: 1 and 1.0 are different")
check(I.plist_difference(b({"x": 0.0}), b({"x": -0.0}))["semantic"] == "different", "plist_difference: 0.0 and -0.0 are different (compared by their bits)")
check(I.plist_difference(b({"x": "a"}), b({"x": b"a"}))["changed"][0][1] == "string -> data", "plist_difference: a string and data of the same bytes are different")
check(I.plist_difference(b({"x": [{"y": 1}]}), b({"x": [{"y": 2}]}))["changed"][0][0] == "x[0].y", "plist_difference: a nested change is reported by its path")
check(I.plist_difference(b({"x": {}}), b({"x": []}))["changed"][0][1] == "dict -> array", "plist_difference: an empty dictionary and an empty array are different")
d = I.plist_difference(b(base), b(dict(base, When=datetime.datetime(2026, 1, 2, 3, 4, 6))))
check(d["semantic"] == "different" and d["changed"][0][0] == "When", "plist_difference: a date differing by a second is different")
d = I.plist_difference(b(base), b({k: v for k, v in base.items() if k != "Raw"}))
check([r[0] for r in d["removed"]] == ["Raw"] and d["removed"][0][3] is None, "plist_difference: a removed key is listed (data shown by size, never in full)")
check(d["removed"][0][2] == "<data, 2 byte(s); value not shown>", "plist_difference: data is shown as its size only (no digest, no prefix)")
many_a = {"k%03d" % i: i for i in range(300)}
many_b = {"k%03d" % i: i + 1 for i in range(300)}
d = I.plist_difference(b(many_a), b(many_b), max_items=60)
check(d["truncated"] and len(d["changed"]) == 60, "plist_difference: the number of listed differences is bounded")
check(d["counts"] == {"added": 0, "removed": 0, "changed": 300}, "plist_difference: the counts are exact totals (300 changed), not the number listed")
# R1: the bound holds for every kind of difference, in every container, and the totals stay exact
def keys(prefix, n, val=0): return {"%s%04d" % (prefix, i): val for i in range(n)}
for n in (61, 120, 2000):
    d = I.plist_difference(b({"keep": 1}), b(dict({"keep": 1}, **keys("add", n))))
    check(len(d["added"]) == 60 and d["counts"]["added"] == n and d["truncated"] and not d["removed"] and not d["changed"],
          "plist_difference: %d added keys list 60 and count %d (truncated, exact total)" % (n, n))
    d = I.plist_difference(b(dict({"keep": 1}, **keys("del", n))), b({"keep": 1}))
    check(len(d["removed"]) == 60 and d["counts"]["removed"] == n and d["truncated"],
          "plist_difference: %d removed keys list 60 and count %d (truncated, exact total)" % (n, n))
d = I.plist_difference(b(keys("c", 120, 0)), b(keys("c", 120, 1)))
check(len(d["changed"]) == 60 and d["counts"]["changed"] == 120 and d["truncated"], "plist_difference: 120 changed values list 60 and count 120")
d = I.plist_difference(b({"n": keys("a", 100)}), b({"n": keys("b", 100)}))
check(len(d["added"]) == 60 and len(d["removed"]) == 60 and d["counts"] == {"added": 100, "removed": 100, "changed": 0},
      "plist_difference: the bound also holds inside a nested dictionary (added and removed)")
d = I.plist_difference(b(dict(keys("m", 100, 0), **keys("r", 80))), b(dict(keys("m", 100, 1), **keys("a", 70))))
check(d["counts"] == {"added": 70, "removed": 80, "changed": 100} and (len(d["added"]), len(d["removed"]), len(d["changed"])) == (60, 60, 60) and d["truncated"],
      "plist_difference: mixed additions, removals and changes are each bounded and each counted exactly")
d = I.plist_difference(b(dict(keys("m", 10, 0), **keys("r", 3))), b(dict(keys("m", 10, 1), **keys("a", 2))))
check(d["counts"] == {"added": 2, "removed": 3, "changed": 10} and (len(d["added"]), len(d["removed"]), len(d["changed"])) == (2, 3, 10) and not d["truncated"],
      "plist_difference: below the bound nothing is cut and truncated is False")
d = I.plist_difference(b(keys("c", 60, 0)), b(keys("c", 60, 1)))
check(len(d["changed"]) == 60 and not d["truncated"], "plist_difference: exactly 60 differences is not truncated")
d = I.plist_difference(b(keys("c", 61, 0)), b(keys("c", 61, 1)))
check(len(d["changed"]) == 60 and d["truncated"] and d["counts"]["changed"] == 61, "plist_difference: 61 differences is truncated, with the exact count 61")
d = I.plist_difference(b({"l": [keys("x", 100, i) for i in range(2)]}), b({"l": [keys("x", 100, i + 5) for i in range(2)]}))
check(len(d["changed"]) == 60 and d["counts"]["changed"] == 200 and d["truncated"], "plist_difference: differences inside arrays are bounded and counted too")
d = I.plist_difference(b({"l": list(range(500))}), b({"l": list(range(501))}))
check(d["counts"]["changed"] == 1 and not d["truncated"], "plist_difference: arrays of different length are one change")
big_a = {"k%06d" % i: "v%d" % i for i in range(40000)}
big_b = dict(big_a); big_b.update(("k%06d" % i, "w%d" % i) for i in range(0, 40000, 2)); big_b.update(keys("n", 5000))
for k in list(big_b)[:3000:3]: big_b.pop(k, None)
pa, pb = b(big_a), b(big_b)
check(len(pa) < I.MAX_PLIST_DIFF_BYTES and len(pb) < I.MAX_PLIST_DIFF_BYTES, "a large valid plist test input is inside the size cap (%d and %d bytes)" % (len(pa), len(pb)))
import time
t0 = time.time()
d = I.plist_difference(pa, pb)
want_removed = len(set(big_a) - set(big_b)); want_added = len(set(big_b) - set(big_a))
want_changed = sum(1 for k in set(big_a) & set(big_b) if big_a[k] != big_b[k])
check(d["readable"] and d["counts"] == {"added": want_added, "removed": want_removed, "changed": want_changed}
      and (len(d["added"]), len(d["removed"]), len(d["changed"])) == (60, 60, 60) and d["truncated"] and time.time() - t0 < 30,
      "plist_difference: a large valid plist (40000 keys) is compared with exact counts and a bounded listing (%.1f s)" % (time.time() - t0))
check(not I.plist_difference(pa, pa)["truncated"] and I.plist_difference(pa, pa)["counts"] == {"added": 0, "removed": 0, "changed": 0}, "plist_difference: identical large plists have zero counts")
bad_cases = {
    "not a plist": b"hello",
    "truncated binary": b(base)[:-5],
    "an entity declaration": b'<?xml version="1.0"?><!DOCTYPE plist [<!ENTITY a "b">]><plist version="1.0"><dict/></plist>',
    "a duplicate key": b'<?xml version="1.0"?><plist version="1.0"><dict><key>a</key><string>1</string><key>a</key><string>2</string></dict></plist>',
    "oversized": b"bplist00" + b"\0" * (I.MAX_PLIST_DIFF_BYTES + 1),
}
for name, data in bad_cases.items():
    d = I.plist_difference(b(base), data)
    check(not d["readable"] and d["error"] and d["semantic"] is None and not d["serialization_only"], "plist_difference: %s is reported as unreadable, never as 'identical'" % name)
check(I.plist_difference(b"x", b"x")["readable"] is False, "plist_difference: two identical unreadable files are still reported as unreadable")
check(I.plist_sensitive("CFBundleIdentifier") and I.plist_sensitive("UIBackgroundModes[0]") and I.plist_sensitive("NSCameraUsageDescription")
      and not I.plist_sensitive("DTXcodeBuild") and not I.plist_sensitive("CFBundleDevelopmentRegion"), "plist_sensitive: labels identity, version, platform and privilege keys")
check(I.plist_show("MyApiKey", "v") == "<string, 1 character(s), 1 byte(s) in UTF-8; value not shown>" and I.plist_show("Name", "v") == "<string, 1 character(s), 1 byte(s) in UTF-8; value not shown>"
      and I.plist_show("CFBundleIdentifier", "com.example.app") == "'com.example.app'" and I.plist_show("DTXcode", "2630") == "'2630'",
      "plist_show: only an approved key shows its value; every other key, credential-like or innocent, shows type and size")
check(not I.plist_displayable("CFBundleIdentifier", "a\nb") and not I.plist_displayable("CFBundleIdentifier", "x" * 65) and not I.plist_displayable("CFBundleIdentifier", "a;b")
      and not I.plist_displayable("CFBundleIdentifier", "ok\n") and not I.plist_displayable("CFBundleIdentifier", "caf\u00e9") and I.plist_displayable("CFBundleIdentifier", "x" * 64),
      "plist_displayable: an approved key shows a string only of letters, digits and . _ + - space, at most 64 (a trailing newline does not slip through)")
check(not I.plist_displayable("CFBundleIdentifier", b"abc") and not I.plist_displayable("CFBundleIdentifier", ["a"]) and not I.plist_displayable("CFBundleIdentifier", {"a": 1}) and not I.plist_displayable("DTXcode", 10 ** 30),
      "plist_displayable: data, containers and an enormous integer are never displayable, whatever the key")
check(I.plist_displayable("UIDeviceFamily[0]", 1) and I.plist_displayable("UIBackgroundModes[1]", "fetch") and not I.plist_displayable("UIBackgroundModes", ["fetch"])
      and not I.plist_displayable("CFBundleURLTypes[0]", "x") and not I.plist_displayable("Nested.CFBundleIdentifier", "x") and not I.plist_displayable("UIBackgroundModes[1].x", "x"),
      "plist_displayable: an element of an approved array key may show; nested paths and other arrays may not")

# the generic ASN.1 outline never raises and assumes no layout
blob = struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, 8 + 4) + bytes([0xB0, 0x02, 0x04, 0x00])
dd = I.der_blob_diagnostic(blob)
check(dd["length"] == 12 and dd["outline"][0].startswith("CONTEXT 16 constructed") and dd["outline"][1].strip().startswith("OCTET STRING") and dd["hex"] is None and dd["raw"] is False,
      "der_blob_diagnostic: a [CONTEXT 16] element is outlined as such, with no layout assumed, and no raw bytes unless asked")
check(I.der_blob_diagnostic(b"\xfa\xde")["header"] == "shorter than the 8-byte blob header", "der_blob_diagnostic: a blob shorter than its header is described, not a crash")
bomb = struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, 8 + 2000) + b"\x30\x80" * 1000
check(len(I.describe_asn1(bomb[8:])) <= 90, "describe_asn1: a deeply nested or huge structure gives a bounded outline")
check(I.describe_asn1(b"\x30\x84\xff\xff\xff\xff")[-1].startswith("(not readable as ASN.1"), "describe_asn1: truncated or malformed ASN.1 is described as unreadable, never raises")
big = struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, 8 + 5000) + b"\x04\x82\x13\x84" + b"\xaa" * 4996
dg = I.der_blob_diagnostic(big, raw=True)
check(dg["hex_truncated"] and len(dg["hex"]) == 2 * I.DER_DIAG_MAX_BYTES and dg["raw"], "der_blob_diagnostic: the hex printed (synthetic input only) is bounded")
check(I.der_blob_diagnostic(big)["hex"] is None, "der_blob_diagnostic: without raw=True the bytes are never returned")
strs = I.der_blob_diagnostic(F.der_entitlements_blob({"secret-looking-key": "secret-looking-value"}))
strs_raw = I.der_blob_diagnostic(F.der_entitlements_blob({"secret-looking-key": "secret-looking-value"}), raw=True)
check(not any("secret-looking" in ln for ln in strs["outline"]) and any("secret-looking-key" in ln for ln in strs_raw["outline"]) and any("UTF8String, 18 byte(s)" in ln for ln in strs["outline"]),
      "describe_asn1: string content is shown only in raw (synthetic) mode; the structure mode shows the string's length")
check(any("BOOLEAN, 1 byte(s): 0xff" in ln for ln in I.der_blob_diagnostic(F.der_entitlements_blob({"a": True}))["outline"]) and any("INTEGER, 1 byte(s): 0x01" in ln for ln in I.der_blob_diagnostic(F.der_entitlements_blob({"a": 1}))["outline"]),
      "describe_asn1: small booleans and integers stay visible in structure mode (their encoding is part of the layout)")
# the parser reads the layout the fixture writes (Apple's observed layout, Phase 6B), and still refuses a wrong version
import ipa_fixture as F
gb = F.der_entitlements_blob({"a": True, "b": ["x", 3]})
check(I.parse_der_entitlements(gb) == {"a": True, "b": ["x", 3]}, "parse_der_entitlements: the layout the fixture writes (Apple's observed layout, Phase 6B) decodes")
for name, bl in (("a wrong version", F.der_entitlements_blob({"a": True}, b"\x02")),):
    try:
        I.parse_der_entitlements(bl)
        bad("parse_der_entitlements still refuses %s" % name)
    except I.Asn1Error:
        ok("parse_der_entitlements still refuses %s" % name)
PY

# ---- 13. Phase 2 hardening (Issue #71): output injection, what may be printed, and failure isolation of the diagnostics ------
# SYNTHETIC. The log and the evidence file are written from text that an IPA controls (member names, property list keys and
# values). These checks pin that such text can never end a line, start a GitHub workflow command, send a terminal escape sequence,
# add an evidence record or collide with another evidence key, that the file system and the checks still use the REAL names, and
# that a failing diagnostic can neither change a verdict nor hide a finding.

# 13a. a hostile IPA: member names with line breaks, workflow commands and escape sequences
python3 -I - "$tmp/good.ipa" "$tmp/hostile.ipa" <<'PY'
import sys, zipfile
src, dst = sys.argv[1:3]
zin = zipfile.ZipFile(src)
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
    for i in zin.infolist():
        zout.writestr(i, zin.read(i.filename))
    zout.writestr("Payload/Runner.app/evil\n::error::injected-by-member-name\nchecks_failed=0.txt", b"x")
    zout.writestr("Payload/Runner.app/esc\x1b[31m\x9b2J\u202e\r::stop-commands::x.txt", b"y")
PY
run staging "$tmp/hostile.ipa" "${common[@]}" --expect-cert-sha256 "$PIN" --evidence "$tmp/hostile.ev"
if [ "$rc" -eq 1 ] && grep -F "not covered by CodeResources" <<<"$out" >/dev/null; then ok "a hostile IPA with extra members is still refused (the original verdict is unchanged)"; else bad "a hostile IPA with extra members is refused" "rc=$rc"; fi
if ! grep -qE '^::' <<<"$out" && ! grep -qF $'\x1b' <<<"$out" && ! grep -qF $'\r' <<<"$out" && ! grep -qF $'\xc2\x9b' <<<"$out"; then ok "no line of the output starts with a workflow command, and no escape, carriage-return or C1 control character reaches it"; else bad "hostile member names cannot inject into the output" "$(grep -nE '^::' <<<"$out" | head -2)"; fi
if grep -F 'evil\x0a::error::injected-by-member-name\x0achecks_failed=0.txt' <<<"$out" >/dev/null; then ok "the hostile name is shown ESCAPED on one line, so it can still be recognised"; else bad "the hostile name is shown escaped" "$(grep -c evil <<<"$out") lines"; fi
nlines="$(grep -c '' "$tmp/hostile.ev")"
if [ "$(grep -c '^checks_failed=' "$tmp/hostile.ev")" -eq 1 ] && ! grep -vqE '^[A-Za-z0-9._%-]+=' "$tmp/hostile.ev"; then ok "the evidence file has only well-formed key=value records, and exactly one checks_failed record"; else bad "evidence records stay well-formed" "$(grep -vE '^[A-Za-z0-9._%-]+=' "$tmp/hostile.ev" | head -2)"; fi
rm -rf "$tmp/hn" && mkdir -p "$tmp/hn/u" "$tmp/hn/s"
printf 'same' > "$tmp/hn/u/$(printf 'a\nb::c.txt')"; printf 'same' > "$tmp/hn/s/$(printf 'a\nb::c.txt')"
cp -R "$tmp/staging/Runner.app/." "$tmp/hn/u/"; cp -R "$tmp/staging/Runner.app/." "$tmp/hn/s/"
out="$(python3 -I "$verify" compare "$tmp/hn/u" "$tmp/hn/s" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "a file with a hostile NAME is still found, read and compared by its real name (escaping happens only at output)"; else bad "a file with a hostile name is still compared" "rc=$rc $(grep FAIL <<<"$out" | head -2)"; fi
printf 'different' > "$tmp/hn/s/$(printf 'a\nb::c.txt')"
out="$(python3 -I "$verify" compare "$tmp/hn/u" "$tmp/hn/s" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -F 'a\x0ab::c.txt' <<<"$out" >/dev/null && ! grep -qE '^::|^b::c' <<<"$out"; then ok "...and a changed file with a hostile name is refused, with the name escaped"; else bad "a changed file with a hostile name is refused and escaped" "rc=$rc"; fi

# 13b. hostile plist keys and values in the Info.plist difference
cmpexpect "a plist KEY with a line break and a workflow command is refused and shown escaped on one line" \
  'd["evil\n::error::injected-by-key"] = "v"' 'evil\x0a::error::injected-by-key (string) = <string, 1 character(s)'
if grep -qE '^::' <<<"$out" || grep -qF $'\x1b' <<<"$out"; then bad "a hostile key never starts a workflow command"; else ok "a hostile key never starts a workflow command"; fi
cmpexpect "a plist key with a terminal escape sequence, a bidirectional override and a carriage return is shown escaped" \
  'd["k\x1b[31m\u202e\r\x9b"] = "v"' 'k\x1b[31m\u202e\x0d\x9b (string)'
if grep -qF $'\x1b' <<<"$out" || grep -qF $'\r' <<<"$out"; then bad "no escape or carriage return from a key reaches the output"; else ok "no escape or carriage return from a key reaches the output"; fi
cmpexpect "an approved key with a hostile VALUE is not displayed at all (outside the approved form)" \
  'd["CFBundleIdentifier"] = "a\n::error::b\x1b[31m"' "~ CFBundleIdentifier (string value): 'com.app.cadenabitcoin.staging' -> <string, 17 character(s)"
if grep -qE '^::' <<<"$out"; then bad "a hostile value never starts a workflow command"; else ok "a hostile value never starts a workflow command"; fi
cmpexpect "a very long key path is cut and says how much" \
  'd["K" * 500] = 1' "+ KKKKKKKKKKKKKKKK"
if grep -F "...[380 more character(s)]" <<<"$out" >/dev/null; then ok "...(120 characters, then the number cut)"; else bad "a long key path is cut to 120 characters" "$(grep -c K <<<"$out")"; fi

# 13c. oversized, malformed and deeply nested plist files, and the report limits (never a crash, always the original refusal)
rm -rf "$tmp/cc_big" && mkdir -p "$tmp/cc_big" && cp -R "$tmp/staging/Runner.app" "$tmp/cc_big/Runner.app"
python3 -I -c "
import sys
f = open(sys.argv[1], 'wb'); f.write(b'bplist00'); f.seek(5 * 1024 * 1024); f.write(b'\0'); f.close()" "$tmp/cc_big/Runner.app/Info.plist"
out="$(python3 -I "$verify" compare "$tmp/staging/Runner.app" "$tmp/cc_big/Runner.app" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -F "FAIL  files that differ from the unsigned build: Info.plist" <<<"$out" >/dev/null && grep -F "larger than 4194304 bytes and is not described" <<<"$out" >/dev/null; then ok "an Info.plist over the size cap is refused as before, and is not described (it is never read in full for the description)"; else bad "an oversized Info.plist is refused and not described" "rc=$rc"; fi
rm -rf "$tmp/cc_deep" && mkdir -p "$tmp/cc_deep" && cp -R "$tmp/staging/Runner.app" "$tmp/cc_deep/Runner.app"
python3 -I -c "
import sys
d = 100000
open(sys.argv[1], 'wb').write(b'<?xml version=\"1.0\"?><plist version=\"1.0\">' + b'<array>' * d + b'</array>' * d + b'</plist>')" "$tmp/cc_deep/Runner.app/Info.plist"
out="$(python3 -I "$verify" compare "$tmp/staging/Runner.app" "$tmp/cc_deep/Runner.app" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -F "FAIL  files that differ from the unsigned build: Info.plist" <<<"$out" >/dev/null && ! grep -F "Traceback" <<<"$out" >/dev/null && ! grep -F "internal error" <<<"$out" >/dev/null; then ok "an Info.plist nested 100000 levels deep is refused as before, without a crash"; else bad "a deeply nested Info.plist is refused without a crash" "rc=$rc $(tail -3 <<<"$out")"; fi
for i in 1 2 3 4 5; do
  rm -rf "$tmp/cc_many$i" && mkdir -p "$tmp/cc_many$i" && cp -R "$tmp/staging/Runner.app" "$tmp/cc_many$i/Runner.app"
done
rm -rf "$tmp/many_u" "$tmp/many_s" && mkdir -p "$tmp/many_u" "$tmp/many_s"
for i in 1 2 3 4 5; do python3 -I -c "
import plistlib,sys
for d, v in ((sys.argv[1], 'a'), (sys.argv[2], 'b')):
    open(d, 'wb').write(plistlib.dumps({'k': v}, fmt=plistlib.FMT_XML))" "$tmp/many_u/p$i.plist" "$tmp/many_s/p$i.plist"; done
out="$(python3 -I "$verify" compare "$tmp/many_u" "$tmp/many_s" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(grep -c 'differs from the unsigned build: ' <<<"$out")" -eq 3 ] && grep -F "2 further property list(s) differ and are not described" <<<"$out" >/dev/null; then ok "at most 3 differing property lists are described, and the rest are counted"; else bad "the number of described property lists is bounded" "rc=$rc described=$(grep -c 'differs from the unsigned build: ' <<<"$out")"; fi
cmpcase manyd 'd.update({"ZZ%03d" % i: i for i in range(120)})'
if [ "$rc" -eq 1 ] && [ "$(grep -c '  INFO  Info.plist: + ZZ' <<<"$out")" -eq 40 ] && grep -F "Info.plist: LISTING INCOMPLETE: 40 of 120 differences listed" <<<"$out" >/dev/null; then ok "at most 40 differences of one property list are listed, and the report says it stopped"; else bad "the number of listed differences is bounded" "listed=$(grep -c 'INFO  Info.plist: + ZZ' <<<"$out")"; fi

pyunit "$root" "$verify" <<'PY'
import importlib.util, io, contextlib, os, random, struct, sys, tempfile, tracemalloc
sys.dont_write_bytecode = True
root, verify = sys.argv[1:3]
sys.path.insert(0, os.path.join(root, "tool"))
import ipa_inspect as I
import ipa_fixture as F
spec = importlib.util.spec_from_file_location("v", verify)
V = importlib.util.module_from_spec(spec)
spec.loader.exec_module(V)


def ok(m): print("ok   " + m)
def bad(m, why=""):
    print("FAIL " + m)
    if why: print("     " + why)
def check(c, m, why=""): ok(m) if c else bad(m, why)


# ---- escape_text: every way to end a line, start a command or move a terminal
t = "A\nB\rC\x1b[31m\x9b2J\x7f\u0085\u2028\u2029\u202e\u200b\ufeff\ud800D::E"
e = I.escape_text(t)
check(all(ord(c) >= 0x20 and ord(c) != 0x7F and not (0x80 <= ord(c) <= 0x9F) for c in e) and "\n" not in e and "\r" not in e and "\x1b" not in e, "escape_text: no control, C1, line separator or escape character survives")
check(not any(c in e for c in "\u202e\u200b\ufeff\u2028\u2029\ud800"), "escape_text: bidirectional overrides, zero-width characters, the byte order mark, line and paragraph separators and surrogates are escaped")
check(e.startswith("A\\x0aB\\x0dC\\x1b[31m\\x9b2J\\x7f\\x85\\u2028\\u2029\\u202e\\u200b\\ufeff\\ud800D::E"), "escape_text: the escapes are readable and exact")
check(I.escape_text("::error::x").startswith("::"), "escape_text: ordinary text, including a leading `::`, is not altered (a line cannot START with it because every line has a prefix)")
check(I.escape_text("caf\u00e9 \u65e5\u672c") == "caf\u00e9 \u65e5\u672c", "escape_text: ordinary non-ASCII letters are kept")
check(I.escape_text(b"a\xffb\n") == "a\\xffb\\x0a", "escape_text: bytes are decoded safely (invalid UTF-8 becomes an escape)")
check(I.escape_text(None) == "None" and I.escape_text(12) == "12", "escape_text: a non-string is converted, never a crash")
check(I.escape_text("x" * 50, limit=10) == "x" * 10 + "...[40 more character(s)]", "escape_text: a long text is cut, and the cut says how much")
check(I.escape_text("a\\x0ab", backslash=True) == "a\\\\x0ab" and I.escape_text("a\nb", backslash=True) == "a\\x0ab", "escape_text(backslash=True): a literal backslash and a real line break give different results (reversible)")
random.seed(11)
alphabet = ["a", "b", "\\", "\n", "\r", "x", "0", "\x1b", "\u202e", "=", "%", "/", "_", " ", "\ud800", "\u00e9"]
texts = {"".join(random.choice(alphabet) for _ in range(random.randint(0, 7))) for _ in range(4000)}
check(len({I.escape_text(x, backslash=True) for x in texts}) == len(texts), "escape_text(backslash=True): 4000 different texts give 4000 different results (no collision)")
keys = {I.evidence_key(x) for x in texts}
check(len(keys) == len(texts), "evidence_key: 4000 different identifiers give 4000 different keys (no collision)")
check(all(all(c.isascii() and (c.isalnum() or c in "._-%") for c in k) and k for k in keys), "evidence_key: every key is ASCII letters, digits and . _ - % only, never empty (no =, space or line break)")
check(I.evidence_key("a/b") != I.evidence_key("a_b") and I.evidence_key("a/b") != I.evidence_key("a%2Fb") and I.evidence_key("") == "%", "evidence_key: `a/b`, `a_b` and the text `a%2Fb` stay different (replacing a slash by an underscore would not)")
check(I.evidence_key("signer_sha256") == "signer_sha256" and I.evidence_key("same_code_macho_files") == "same_code_macho_files", "evidence_key: the fixed keys are unchanged")

# ---- Report: lines and evidence
buf = io.StringIO()
rep = V.Report()
with contextlib.redirect_stdout(buf):
    rep.fail("x\n::error::y")
    rep.ok("z" * 10000)
    rep.warn("w\x1b[0m")
    rep.info("i\u202e")
    rep.ev("key=with space\nand/slash", "v1\nchecks_failed=0\\n")
    rep.ev("plist_difference_" + "a/b.plist", "added=1 removed=0 changed=0")
    rep.ev("plain", None)
lines = buf.getvalue().split("\n")
check(len(lines) == 5 and lines[-1] == "" and all(l.startswith("  ") for l in lines[:-1]), "Report: every message is exactly one line, and every line starts with its tag")
check(len(lines[1]) < 4100 and "more character(s)]" in lines[1], "Report: an absurdly long message is cut to a bounded line")
check(rep.failed == 1 and rep.passed == 1 and rep.warned == 1, "Report: the counters are the ones of the real calls")
check(rep.evidence[0] == ("key%3Dwith%20space%0Aand%2Fslash", "v1\\x0achecks_failed=0\\\\n") and rep.evidence[1] == ("plist_difference_a%2Fb.plist", "added=1 removed=0 changed=0") and rep.evidence[2] == ("plain", ""),
      "Report.ev: a key is encoded, a value is escaped (a line break and a backslash), ordinary records are unchanged")

# ---- failure isolation: the diagnostics may fail in any way; the outcome may not change
def run_same_code(unsigned_info, signed_info, patch=None):
    td = tempfile.mkdtemp()
    for side, content in (("u", unsigned_info), ("s", signed_info)):
        os.makedirs(os.path.join(td, side))
        open(os.path.join(td, side, "Info.plist"), "wb").write(content)
    rep = V.Report()
    buf = io.StringIO()
    restore = []
    if patch:
        for obj, name, fn in patch:
            restore.append((obj, name, getattr(obj, name)))
            setattr(obj, name, fn)
    try:
        with contextlib.redirect_stdout(buf):
            V.same_code_check(rep, os.path.join(td, "u"), os.path.join(td, "s"))
    finally:
        for obj, name, fn in restore:
            setattr(obj, name, fn)
    return rep, buf.getvalue()


import plistlib
A, B = plistlib.dumps({"k": "a"}, fmt=plistlib.FMT_BINARY), plistlib.dumps({"k": "b"}, fmt=plistlib.FMT_BINARY)
base_rep, base_out = run_same_code(A, B)
def boom(exc):
    def f(*a, **k):
        raise exc
    return f
for exc in (RuntimeError("x"), ValueError("y"), KeyError("z"), RecursionError(), MemoryError(), UnicodeError("u"), OSError("o"), ZeroDivisionError()):
    for target, name in ((I, "plist_difference"), (I, "read_capped"), (I, "plist_sensitive"), (I, "plist_show")):
        r, o = run_same_code(A, B, [(target, name, boom(exc))])
        same = (r.failed, r.passed, r.warned) == (base_rep.failed, base_rep.passed, base_rep.warned) and "FAIL  files that differ from the unsigned build: Info.plist" in o
        said = ("diagnostics unavailable (%s)" % type(exc).__name__ in o or "cannot be read for a description" in o or "too deeply nested or too large to compare" in o)
        check(same and said, "isolation: %s raised by %s inside the diagnostic changes no counter and no verdict, and the report says it could not describe the difference" % (type(exc).__name__, name))
r, o = run_same_code(A, B, [(V, "describe_one_plist", boom(RuntimeError("x")))])
check((r.failed, r.passed) == (base_rep.failed, base_rep.passed) and "diagnostics unavailable (RuntimeError)" in o, "isolation: a failure of the whole description of one plist is contained")
# KeyboardInterrupt is not swallowed
try:
    run_same_code(A, B, [(I, "plist_difference", boom(KeyboardInterrupt()))])
    bad("isolation: KeyboardInterrupt is not swallowed by the diagnostic")
except KeyboardInterrupt:
    ok("isolation: KeyboardInterrupt is not swallowed by the diagnostic")

# the DER diagnostic of read_signature: its failure must not replace the recorded problem
td = tempfile.mkdtemp()
certs = os.path.join(td, "certs"); os.makedirs(certs)
import subprocess
fx = lambda *a: subprocess.run([sys.executable, "-I", os.path.join(root, "tool", "ipa_fixture.py")] + list(a), capture_output=True, check=True)
fx("certs", certs); os.makedirs(os.path.join(td, "app"))
fx("unsigned", os.path.join(td, "app"), "--env", "staging")
fx("sign", os.path.join(td, "app", "Runner.app"), os.path.join(td, "v2.ipa"), "--certs", certs, "--team", "SYNTH12345", "--mutate", "der-version2")
import zipfile
zipfile.ZipFile(os.path.join(td, "v2.ipa")).extract("Payload/Runner.app/Runner", td)
exe = os.path.join(td, "Payload", "Runner.app", "Runner")
sig = I.read_signature(exe)
check(any("DER entitlements are unreadable" in p for p in sig["slices"][0]["problems"]) and "outline" in sig["slices"][0]["der_diag"], "read_signature: an unreadable DER blob records the problem and its structure diagnostic")
orig = I.der_blob_diagnostic
I.der_blob_diagnostic = boom(RuntimeError("x"))
try:
    sig2 = I.read_signature(exe)
finally:
    I.der_blob_diagnostic = orig
check(any("DER entitlements are unreadable" in p for p in sig2["slices"][0]["problems"]) and sig2["slices"][0]["der_diag"] == {"error": "RuntimeError"},
      "isolation: when the DER diagnostic itself fails, the recorded problem is still there and nothing crashes")
rep = V.Report()
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    res = V.check_code_signature(rep, "main", exe, None, "com.app.cadenabitcoin.staging", None, None, False)
    I.der_blob_diagnostic = boom(RuntimeError("x"))
    try:
        rep2 = V.Report()
        res2 = V.check_code_signature(rep2, "main", exe, None, "com.app.cadenabitcoin.staging", None, None, False)
    finally:
        I.der_blob_diagnostic = orig
check(res["ok"] is False and res2["ok"] is False and rep.failed == rep2.failed, "isolation: check_code_signature gives the same verdict and the same number of findings whether or not the DER diagnostic works")
orig2 = V.describe_der_failure
V.describe_der_failure = boom(RuntimeError("x"))
try:
    rep3 = V.Report()
    buf3 = io.StringIO()
    with contextlib.redirect_stdout(buf3):
        res3 = V.check_code_signature(rep3, "main", exe, None, "com.app.cadenabitcoin.staging", None, None, False)
finally:
    V.describe_der_failure = orig2
check(res3["ok"] is False and rep3.failed == rep.failed and "DER diagnostic: diagnostics unavailable (RuntimeError)" in buf3.getvalue(), "isolation: a failure of the DER report is contained and reported as unavailable")

# ---- size cap before reading
big = tempfile.NamedTemporaryFile(delete=False)
big.truncate(40 * 1024 * 1024)
big.close()
tracemalloc.start()
got = I.read_capped(big.name, 1024 * 1024)
peak = tracemalloc.get_traced_memory()[1]
tracemalloc.stop()
os.unlink(big.name)
check(got is None and peak < 3 * 1024 * 1024, "read_capped: a 40 MiB file over a 1 MiB cap is refused after reading at most cap+1 bytes (peak memory %d bytes)" % peak)
small = tempfile.NamedTemporaryFile(delete=False)
small.write(b"x" * 100); small.close()
check(I.read_capped(small.name, 100) == b"x" * 100 and I.read_capped(small.name, 99) is None and I.read_capped(small.name, 1000) == b"x" * 100, "read_capped: exactly the cap is read, one byte more is refused")
os.unlink(small.name)

# ---- deeply nested structures that DO parse
def nested(depth, leaf):
    x = leaf
    for _ in range(depth):
        x = [x]
    return x
for depth in (50, 300, 450):
    try:
        a = plistlib.dumps({"k": nested(depth, "a")}, fmt=plistlib.FMT_BINARY)
        b = plistlib.dumps({"k": nested(depth, "b")}, fmt=plistlib.FMT_BINARY)
    except RecursionError:
        continue
    try:
        d = I.plist_difference(a, b)
        check(d["semantic"] in ("different", None) and (d["readable"] or d["error"]) and not d["serialization_only"], "plist_difference: nesting depth %d gives a result or a clean 'too deep' error, never an exception" % depth)
    except Exception as e:
        bad("plist_difference: nesting depth %d raised %s" % (depth, type(e).__name__))
# a hand-made binary plist nested 5000 levels deep
n = 5000
objs = [bytes([0xA1]) + (i + 1).to_bytes(2, "big") for i in range(n - 1)] + [bytes([0xA0])]
body = b"bplist00"
offs = []
for o in objs:
    offs.append(len(body)); body += o
table = len(body)
body += b"".join(x.to_bytes(4, "big") for x in offs)
body += b"\0" * 6 + bytes([4, 2]) + n.to_bytes(8, "big") + (0).to_bytes(8, "big") + table.to_bytes(8, "big")
try:
    d = I.plist_difference(body, body[:-1] + b"\x00")
    check(not d["readable"] or d["semantic"] is not None, "plist_difference: a binary plist nested 5000 levels deep gives a clean result (%s)" % (d["error"] or d["semantic"]))
except Exception as e:
    bad("plist_difference: 5000 levels of binary nesting raised %s" % type(e).__name__)
junk_seed = random.Random(5)
bad_n = 0
for _ in range(2000):
    blob = bytes(junk_seed.getrandbits(8) for _ in range(junk_seed.choice([0, 3, 8, 40, 200])))
    try:
        I.plist_difference(blob, blob[::-1])
        I.der_blob_diagnostic(blob)
        I.der_blob_diagnostic(struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, len(blob) + 8) + blob, raw=True)
    except Exception:
        bad_n += 1
check(bad_n == 0, "fuzz: 2000 random blobs through the plist and DER diagnostics raise no exception")
bomb = struct.pack(">II", I.CSMAGIC_DER_ENTITLEMENTS, 8 + 6000) + b"\x30\x80" * 3000
out = I.der_blob_diagnostic(bomb)["outline"]
check(len(out) <= 90 and any("truncated" in l or "not readable" in l for l in out), "describe_asn1: an enormous or endlessly nested structure gives a bounded outline that says it was cut")
PY

# ---- 14. Phase 6B (Issue #71): the DER entitlements parser reads what Apple's codesign really writes ------------------
# REAL     tool/fixtures/apple_der_entitlements_d1_run44956044650.txt: the seven distinct DER entitlements blobs Apple's own
#          `codesign --generate-entitlement-der` wrote in Authorization D1 (run 44956044650). They were NOT made by tool/ipa_fixture.py.
#          Every expectation below is written out by hand from the entitlements the experiment signed
#          (tool/probe_der_entitlements.sh, `ent` lines), never derived from the parser or from the fixture writer.
# SYNTHETIC the negative cases: the real blobs with ONE byte changed, and small hand-built blobs.
# What this cannot show: that the blob of a Distribution-signed IPA equals that of an ad hoc one (strong evidence, not proof).
derfix="$root/tool/fixtures/apple_der_entitlements_d1_run44956044650.txt"
pyunit "$root" "$derfix" <<'PY'
import hashlib, os, struct, sys
sys.dont_write_bytecode = True
root, derfix = sys.argv[1:3]
sys.path.insert(0, os.path.join(root, "tool"))
import ipa_inspect as I
import ipa_fixture as F


def ok(m): print("ok   " + m)
def bad(m, why=""):
    print("FAIL " + m)
    if why: print("     " + why)
def check(c, m, why=""): ok(m) if c else bad(m, why)


REFUSED = (I.Asn1Error, IndexError, ValueError, struct.error)


def refuses(blob, needle=None):
    try:
        I.parse_der_entitlements(blob)
    except REFUSED as e:
        return needle is None or needle in str(e)
    return False


# ---- the seven real blobs, their recorded size and SHA-256 (the digests are repeated here on purpose: the file and the test must agree)
SHA = {
    "booleans": "8b648a060612c9dc3c4e1fcc123ee9187f89cf8a283ea237332f1ad77c4a6da8",
    "dicts": "990757663ef290272b7f06e68cc2d868fa29ff7c30e8297666d2669a475226de",
    "unsorted": "d0c499cb3a63c256a776952ead55ce467b929074d81e498a4042f1043f42c258",
    "arrays": "d6cdcb95e574eb1274b30364aa7ab7f24c7b14985737c8e298d4d517b8758677",
    "runner": "8afe8d8cbeab8c196ba1992e08c18f9bd696a4ace29555e2a8ca186bebdf2e3e",
    "integers": "16f81e571c23ab165989a51566ecde363032efb7d5e7ac5fbd7f2848d2250a2a",
    "many": "2d493d24574ab09de05f812d037581dde791d0185c1ec2626a6498378627b8db",
}
SIZE = {"booleans": 58, "dicts": 93, "unsorted": 130, "arrays": 165, "runner": 176, "integers": 285, "many": 1810}
real = {}
for line in open(derfix):
    if line.startswith("#") or not line.strip():
        continue
    name, size, digest, hx = line.split()
    real[name] = (int(size), digest, bytes.fromhex(hx))
check(sorted(real) == sorted(SHA), "the Apple DER fixture holds exactly the seven distinct blobs of Authorization D1")
check(all(len(b) == n == SIZE[k] and hashlib.sha256(b).hexdigest() == h for k, (n, h, b) in real.items()),
      "each Apple DER blob matches its recorded size and SHA-256")
check(all(struct.unpack(">II", b[:8]) == (0xFADE7172, len(b)) for _n, _h, b in real.values()),
      "each Apple DER blob starts with the magic 0xfade7172 and its own total length")

# ---- what each blob holds, written out by hand from the entitlements that were signed
TEAM, IDENT = "TESTTEAM00", "com.example.disposable"
EXPECTED = {
    "booleans": {"com.example.yes": True, "com.example.no": False},
    "dicts": {"com.example.empty": {}, "com.example.nested": {"b": "2", "a": {"z": True, "y": False}}},
    "unsorted": {"zzz": "last-in-order-first-in-file", "aaa": "first-in-order-last-in-file", "mmm": "middle", "AAA": "upper", "aa": "prefix"},
    "arrays": {"com.example.empty": [], "com.example.strings": ["a", "b"], "com.example.nested": [["x"]],
               "com.example.dicts": [{"k": "v"}], "com.example.mixed": ["s", True, 7]},
    "runner": {"application-identifier": TEAM + "." + IDENT, "beta-reports-active": True,
               "com.apple.developer.team-identifier": TEAM, "get-task-allow": False},
    "integers": {"com.example.i0": 0, "com.example.i1": 1, "com.example.i127": 127, "com.example.i128": 128, "com.example.i255": 255,
                 "com.example.i256": 256, "com.example.i65535": 65535, "com.example.neg1": -1, "com.example.neg128": -128,
                 "com.example.neg129": -129, "com.example.i32max": 2147483647},
    "many": {"com.example.key%02d" % i: "value%d" % i for i in range(1, 61)},
}
for name in SHA:
    blob = real[name][2]
    try:
        got = I.parse_der_entitlements(blob)
    except Exception as e:
        bad("the parser decodes the Apple blob `%s`" % name, "%s: %s" % (type(e).__name__, e))
        continue
    check(I.plist_equal_strict(got, EXPECTED[name]), "the parser decodes the Apple blob `%s` to exactly the entitlements that were signed (values AND types)" % name,
          "got %r" % (got,))

# ---- the structure Apple wrote, asserted from the raw bytes (independent of the parser's own reading)
def walk(node, seen):
    seen.add((node.cls, node.tag, node.constructed))
    for c in node.children:
        walk(c, seen)
    return seen

LENGTH_FORM = {"booleans": None, "dicts": None, "unsorted": None, "arrays": 0x81, "runner": 0x81, "integers": 0x82, "many": 0x82}
for name, (_n, _h, blob) in real.items():
    root_ = I.parse_der(blob[8:])
    seen = walk(root_, set())
    body = root_.children[1]
    check(blob[8] == 0x70 and (root_.cls, root_.tag, root_.constructed) == (1, 16, True) and root_.children[0].raw == b"\x02\x01\x01"
          and (body.cls, body.tag, body.constructed) == (2, 16, True) and (0, 17, True) not in seen,
          "Apple blob `%s`: [APPLICATION 16] { INTEGER 1, [CONTEXT 16] }, and no SET anywhere" % name)
    form = LENGTH_FORM[name]
    check((blob[9] & 0x80 == 0) if form is None else blob[9] == form,
          "Apple blob `%s`: the root length is written in the %s form" % (name, "short" if form is None else "long (%d length byte(s))" % (form & 0x7F)))
    keys = [pair.children[0].value for pair in body.children]
    check(keys == sorted(keys) and len(set(keys)) == len(keys), "Apple blob `%s`: its top-level keys are in ascending byte order, without duplicates" % name)
check([p.children[0].value for p in I.parse_der(real["unsorted"][2][8:]).children[1].children] == [b"AAA", b"aa", b"aaa", b"mmm", b"zzz"]
      and list(EXPECTED["unsorted"]) == ["zzz", "aaa", "mmm", "AAA", "aa"],
      "Apple sorted the entries of `unsorted`: written as zzz, aaa, mmm, AAA, aa, they are in the blob as AAA, aa, aaa, mmm, zzz")
nested = I.parse_der(real["dicts"][2][8:]).children[1].children[1].children[1]   # com.example.nested
check((nested.cls, nested.tag, nested.constructed) == (2, 16, True) and [p.children[0].value for p in nested.children] == [b"a", b"b"]
      and (nested.children[0].children[1].cls, nested.children[0].children[1].tag) == (2, 16), "Apple blob `dicts`: a nested dictionary is [CONTEXT 16] too, sorted, at every level")
arr = I.parse_der(real["arrays"][2][8:]).children[1].children[0].children[1]          # com.example.dicts: an array holding a dictionary
check((arr.cls, arr.tag, arr.constructed) == (0, 16, True) and (arr.children[0].cls, arr.children[0].tag) == (2, 16),
      "Apple blob `arrays`: an array is a SEQUENCE, and a dictionary inside it is [CONTEXT 16]")
ints = {p.children[0].value.decode(): p.children[1].value for p in I.parse_der(real["integers"][2][8:]).children[1].children}
check(ints["com.example.neg128"] == b"\x80" and ints["com.example.i128"] == b"\x00\x80" and ints["com.example.neg129"] == b"\xff\x7f" and ints["com.example.i0"] == b"\x00",
      "Apple blob `integers`: the shortest two's complement form (-128 is 80, 128 is 0080, -129 is ff7f)")

# the SYNTHETIC writer agrees with Apple's bytes (a consistency check of the test tool: it is NOT the proof, the blobs above are)
check(all(F.der_entitlements_blob(EXPECTED[k]) == real[k][2] for k in real), "the synthetic fixture writer reproduces all seven Apple blobs byte for byte")

# ---- one byte changed in a REAL blob: every wrong class, tag or form is refused
def patched(name, node_path, byte):
    blob = bytearray(real[name][2])
    node = I.parse_der(bytes(blob[8:]))
    for i in node_path:
        node = node.children[i]
    blob[8 + node.start] = byte
    return bytes(blob)

run_ = "runner"
check(refuses(patched(run_, [1], 0x31), "unsupported DER entitlements version or layout"), "the OBSOLETE layout (the dictionary as a SET, 0x31) is refused")
check(refuses(patched("dicts", [1, 1, 1], 0x31), "unsupported value"), "a nested dictionary written as a SET is refused (no layout is accepted besides Apple's)")
for byte, what in ((0x30, "a UNIVERSAL SEQUENCE"), (0xB1, "[CONTEXT 17]"), (0xA0, "[CONTEXT 0]"), (0xF0, "[PRIVATE 16]"), (0x70, "[APPLICATION 16]"), (0x90, "a PRIMITIVE [CONTEXT 16]")):
    check(refuses(patched(run_, [1], byte)), "a dictionary written as %s (class, tag or form wrong) is refused" % what)
for byte, what in ((0x50, "a PRIMITIVE [APPLICATION 16]"), (0xB0, "[CONTEXT 16]"), (0x30, "a UNIVERSAL SEQUENCE"), (0x71, "[APPLICATION 17]")):
    check(refuses(patched(run_, [], byte), "single [APPLICATION 16]"), "a root written as %s is refused" % what)
check(refuses(patched("dicts", [1, 1, 1], 0x90)) and refuses(patched("dicts", [1, 1, 1], 0xF0)) and refuses(patched("dicts", [1, 1, 1], 0xB1)),
      "a nested dictionary with a wrong class, tag or form is refused (primitive [CONTEXT 16], [PRIVATE 16], [CONTEXT 17])")
# A UNIVERSAL SEQUENCE is an ARRAY by definition, so a nested dictionary rewritten as one still parses, as an array: it can never equal the dictionary.
as_array = I.parse_der_entitlements(patched("dicts", [1, 1, 1], 0x30))["com.example.nested"]
check(isinstance(as_array, list) and not I.plist_equal_strict(I.parse_der_entitlements(patched("dicts", [1, 1, 1], 0x30)), EXPECTED["dicts"]),
      "a nested dictionary rewritten as a UNIVERSAL SEQUENCE is an array, never the dictionary (the XML comparison then differs)")
check(all(refuses(patched("arrays", [1, 0, 1], byte)) for byte in (0x10, 0x31, 0xB0, 0x70)),
      "an array written as a PRIMITIVE SEQUENCE (it would read as an empty array), a SET, [CONTEXT 16] or [APPLICATION 16] is refused")
check(refuses(patched(run_, [1, 0], 0x10), "malformed entry") and refuses(patched(run_, [1, 0], 0x31), "malformed entry") and refuses(patched(run_, [1, 0], 0xB0), "malformed entry"),
      "an entry that is a PRIMITIVE SEQUENCE, a SET or [CONTEXT 16] is a malformed entry")
check(refuses(patched(run_, [1, 0, 0], 0x2C, ), "malformed entry") and refuses(patched(run_, [1, 0, 0], 0x16, ), "malformed entry") and refuses(patched(run_, [1, 0, 0], 0x04, ), "malformed entry"),
      "a key that is a CONSTRUCTED UTF8String, an IA5String or an OCTET STRING is a malformed entry")
for byte, what in ((0x21, "a constructed BOOLEAN"), (0x04, "an OCTET STRING"), (0x05, "NULL"), (0x31, "a SET"), (0x81, "[CONTEXT 1]"), (0x41, "[APPLICATION 1]")):
    check(refuses(patched(run_, [1, 1, 1], byte), "unsupported value"), "a value written as %s is an unsupported value" % what)
check(refuses(patched("integers", [1, 0, 1], 0x22), "unsupported value") and refuses(patched(run_, [1, 0, 1], 0x2C), "unsupported value"),
      "a constructed INTEGER and a constructed UTF8String are unsupported values")
check(refuses(patched(run_, [0], 0x03), "version") and refuses(patched(run_, [0], 0x42), "version") and refuses(patched(run_, [0], 0x22), "version"),
      "a version that is not a primitive UNIVERSAL INTEGER (BIT STRING, [APPLICATION 2], constructed) is refused")
v2 = bytearray(real[run_][2]); v2[8 + I.parse_der(bytes(v2[8:])).children[0].vstart] = 0x02
check(refuses(bytes(v2), "version"), "DER version 2 is refused")

# ---- truncated and trailing input, header damage
blob = real[run_][2]
check(all(refuses(struct.pack(">II", 0xFADE7172, cut) + blob[8:cut]) for cut in range(8, len(blob))),
      "a real blob cut at every possible length (header length corrected to match) is always refused, never accepted")
check(refuses(blob[:-1], "header is wrong") and refuses(blob + b"\x00", "header is wrong"), "a blob shorter or longer than its declared length is refused")
check(refuses(struct.pack(">II", 0xFADE7172, len(blob) + 1) + blob[8:] + b"\x00", "single [APPLICATION 16]") and refuses(struct.pack(">II", 0xFADE7171, len(blob)) + blob[8:], "header is wrong"),
      "bytes after the root element, and a wrong magic, are refused")
check(refuses(b"\xfa\xde\x71") and refuses(struct.pack(">II", 0xFADE7172, 8)), "a blob shorter than its header, and an empty body, are refused")

# ---- hand-built blobs: duplicate keys, malformed entries, unsupported values
def utf(k): return F.der(0x0C, k)
def entry(k, v): return F.d_seq(utf(k), v)
def blob_of(*entries):
    body = F.der(0x70, F.der(0x02, b"\x01") + F.der(0xB0, b"".join(entries)))
    return struct.pack(">II", 0xFADE7172, 8 + len(body)) + body
T, FALSE = F.der(1, b"\xff"), F.der(1, b"\x00")
check(I.parse_der_entitlements(blob_of(entry(b"a", T), entry(b"b", FALSE))) == {"a": True, "b": False}, "(control) a hand-built two-entry blob in Apple's layout decodes")
check(refuses(blob_of(entry(b"a", T), entry(b"a", FALSE)), "duplicate key"), "a duplicate top-level key is refused")
check(refuses(blob_of(entry(b"n", F.der(0xB0, entry(b"x", T) + entry(b"x", FALSE)))), "duplicate key"), "a duplicate key inside a nested dictionary is refused")
check(refuses(blob_of(entry(b"n", F.d_seq(F.der(0xB0, entry(b"x", T) + entry(b"x", T))))), "duplicate key"), "a duplicate key inside a dictionary inside an array is refused")
check(I.parse_der_entitlements(blob_of(entry(b"a", T), entry(b"n", F.der(0xB0, entry(b"a", FALSE))))) == {"a": True, "n": {"a": False}},
      "(control) the same key in DIFFERENT dictionaries is not a duplicate")
check(refuses(blob_of(F.d_seq(utf(b"a"))), "malformed entry") and refuses(blob_of(F.d_seq(utf(b"a"), T, T)), "malformed entry") and refuses(blob_of(F.d_seq(T, T)), "malformed entry")
      and refuses(blob_of(T), "malformed entry"), "an entry with one child, three children, a non-string key, or no SEQUENCE at all is refused")
for what, v in (("OCTET STRING", F.der(4, b"x")), ("NULL", F.der(5, b"")), ("a SET", F.der(0x31, b"")), ("a REAL", F.der(9, b"\x00")), ("a GeneralizedTime", F.der(0x18, b"20260101000000Z")),
                ("an OID", F.der(6, b"\x2a\x03")), ("[CONTEXT 0]", F.der(0xA0, b""))):
    check(refuses(blob_of(entry(b"a", v)), "unsupported value"), "%s as an entitlement value is refused" % what)
check(refuses(blob_of(entry(b"a", F.der(0x31, entry(b"k", T)))), "unsupported value"), "a SET of entries where a dictionary is expected, inside a value, is refused")
check(I.parse_der_entitlements(blob_of(entry(b"a", F.der(0xB0, b"")), entry(b"b", F.d_seq()))) == {"a": {}, "b": []}, "(control) an empty dictionary and an empty array decode to {} and []")
check(type(I.parse_der_entitlements(blob_of(entry(b"a", T), entry(b"b", F.der(2, b"\x01")))).get("a")) is bool and type(I.parse_der_entitlements(blob_of(entry(b"b", F.der(2, b"\x01"))))["b"]) is int,
      "a BOOLEAN decodes to bool and an INTEGER to int (never confused)")

# ---- XML versus DER: value AND type (the entitlement values the parser can produce)
S = I.plist_equal_strict
check(S({"a": True}, {"a": True}) and S({"a": False, "b": 0}, {"b": 0, "a": False}), "(control) equal entitlements pass, whatever the key order")
check(not S({"a": True}, {"a": 1}) and not S({"a": 1}, {"a": True}) and not S({"a": False}, {"a": 0}) and not S({"a": 0}, {"a": False}), "a boolean and an integer of the same value are NOT interchangeable")
check({"a": 1} == {"a": True} and {"a": 1} == {"a": 1.0}, "(why: Python's own == calls them equal)")
check(not S({"a": [True]}, {"a": [1]}) and not S({"a": ["x", True]}, {"a": [True, "x"]}) and not S({"a": [1, 2]}, {"a": [2, 1]}) and S({"a": [1, "x", True, [False]]}, {"a": [1, "x", True, [False]]}),
      "arrays keep their element types and their order")
check(not S({"a": {"b": {"c": True}}}, {"a": {"b": {"c": 1}}}) and not S({"a": {"b": 1}}, {"a": {"b": 1, "c": 2}}) and not S({"a": {"b": 1}}, {"a": {"c": 1}}) and S({"a": {"b": {"c": [True]}}}, {"a": {"b": {"c": [True]}}}),
      "nested dictionaries are compared recursively, in value, type and keys")
check(not S({"a": "1"}, {"a": 1}) and not S({"a": "x"}, {"a": "y"}) and not S({"a": 1}, {"a": 2}) and not S({"a": True}, {"a": False}) and not S({"a": 1}, {}) and not S({}, {"a": 1}),
      "different strings, integers, booleans, and missing or extra keys are different")
import datetime
check(not S({"a": 1}, {"a": 1.0}) and not S({"a": "x"}, {"a": b"x"}) and not S({"a": 1}, {"a": datetime.datetime(2026, 1, 1)}) and not S({"a": []}, {"a": {}}) and not S({"a": {}}, {"a": []}),
      "XML types DER cannot hold (real, data, date) and an array against a dictionary never equal a DER value")
check(all(S(I.parse_der_entitlements(real[k][2]), EXPECTED[k]) for k in real), "every entitlement the parser reads from a real Apple blob equals its XML form under the strict comparison")
PY

# the same, end to end through the verifier: the first mismatch is only a TYPE (BOOLEAN against INTEGER), and the obsolete layout is unreadable
mk dertype staging der-type-differs
expect_fail "DER entitlements that differ from the XML entitlements only in TYPE (a BOOLEAN against an INTEGER) are refused" "differ from the XML entitlements" staging "$tmp/dertype.ipa" --expect-cert-sha256 "$PIN"
mk derset staging der-set-layout
expect_fail "an IPA whose DER entitlements use the OBSOLETE layout (a SET) is refused as unreadable" "DER entitlements are unreadable: unsupported DER entitlements version or layout" staging "$tmp/derset.ipa" --expect-cert-sha256 "$PIN"

# ---- the entitlements must also agree ACROSS the slices of a universal executable, in value AND type
# (check_code_signature compared them with Python's ==, which calls <false/> and <integer>0</integer> equal). A fat executable with two
# arm64 slices is the only fat shape the verifier can otherwise accept, so that is what these build.
mk fat staging fat-main
expect_ok "(control) a universal executable whose two arm64 slices carry identical entitlements passes" staging "$tmp/fat.ipa" --expect-cert-sha256 "$PIN"
mk fattype staging fat-slice-type
run staging "$tmp/fattype.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
# the refusal must be consistent: a FAIL for the slices and NO "signature intact" PASS for the same executable
if [ "$rc" -eq 1 ] && grep -F "FAIL" <<<"$out" | grep -F "the entitlements differ between architecture slices" >/dev/null && ! grep -F "PASS  main executable Runner: signature intact" <<<"$out" >/dev/null; then
  ok "a universal executable whose second slice declares an entitlement with the same value in another TYPE (a boolean against an integer) is refused (and the executable is not also reported intact)"
else
  bad "a universal executable whose second slice declares an entitlement with the same value in another TYPE (a boolean against an integer) is refused" "exit $rc: $(echo "$out" | grep -E 'FAIL|signature intact' | head -3 | tr '\n' '|')"
fi
mk fatvalue staging fat-slice-value
run staging "$tmp/fatvalue.ipa" "${common[@]}" --expect-cert-sha256 "$PIN"
# the refusal must be consistent: a FAIL for the slices and NO "signature intact" PASS for the same executable
if [ "$rc" -eq 1 ] && grep -F "FAIL" <<<"$out" | grep -F "the entitlements differ between architecture slices" >/dev/null && ! grep -F "PASS  main executable Runner: signature intact" <<<"$out" >/dev/null; then
  ok "a universal executable whose slices carry different entitlement values is refused (and the executable is not also reported intact)"
else
  bad "a universal executable whose slices carry different entitlement values is refused" "exit $rc: $(echo "$out" | grep -E 'FAIL|signature intact' | head -3 | tr '\n' '|')"
fi

# ---- 15. Phase 6C-B (Issue #71): the DER entitlements reader is a STRICT DER reader --------------------------------------------
# DER has one encoding per value; refusing the others removes specific encoding ambiguities and reduces the risk that this reader and the
# kernel's read one blob differently. It does not prove the two equivalent (Apple's reader was not examined). These tests pin what is
# refused: what DER forbids (an indefinite or non-minimal length, a non-canonical high-tag form, a BOOLEAN other than 00/ff, an empty or
# padded INTEGER) and two limits of THIS application that DER does not require (a root that is not exactly two elements, nesting beyond
# the limit); and what must still be accepted (everything Apple wrote). The blobs here are
# hand-built with a LOCAL encoder that shares no code with tool/ipa_fixture.py (which is used only to sign a file for read_signature);
# the real blobs are the seven of Authorization D1.
pyunit "$root" "$derfix" <<'PY'
import hashlib, inspect, os, plistlib, struct, sys, tempfile
sys.dont_write_bytecode = True
root, derfix = sys.argv[1:3]
sys.path.insert(0, os.path.join(root, "tool"))
import ipa_inspect as I


def ok(m): print("ok   " + m)
def bad(m, why=""):
    print("FAIL " + m)
    if why: print("     " + why)
def check(c, m, why=""): ok(m) if c else bad(m, why)


# a local, independent DER writer (and the means to write it WRONG on purpose)
def lenb(n):
    if n < 0x80: return bytes([n])
    b = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(b)]) + b
def tlv(tag, body, length=None): return bytes([tag]) + (lenb(len(body)) if length is None else length) + body
def blob(root_der): return struct.pack(">II", 0xFADE7172, 8 + len(root_der)) + root_der
def utf(k): return tlv(0x0C, k)
def entry(k, v): return tlv(0x30, utf(k) + v)
def dic(*entries): return tlv(0xB0, b"".join(entries))
VER = tlv(2, b"\x01")
def top(*entries, extra=b""): return blob(tlv(0x70, VER + dic(*entries) + extra))
TRUE, FALSE = tlv(1, b"\xff"), tlv(1, b"\x00")
KEY = utf(b"a")


def parse(b):
    try: return ("ok", I.parse_der_entitlements(b))
    except (I.Asn1Error, IndexError, ValueError, struct.error) as e: return ("refused", str(e))
    except RecursionError: return ("RECURSION", "")
def refuses(b, needle): r = parse(b); return r[0] == "refused" and needle in r[1]
def accepts(b, want): r = parse(b); return r[0] == "ok" and r[1] == want


# ---- the seven real Apple blobs go through the strict reader unchanged: the same bytes, the same values
real = {}
for line in open(derfix):
    if line.startswith("#") or not line.strip(): continue
    n, size, sha, hx = line.split()
    real[n] = (int(size), sha, bytes.fromhex(hx))
check(sorted(real) == ["arrays", "booleans", "dicts", "integers", "many", "runner", "unsorted"], "all seven Apple blobs of Authorization D1 are present")
check(hashlib.sha256(open(derfix, "rb").read()).hexdigest() == "067905aebc352bf48c8ad40c1ce4471b2b5f5869557c3829e75c36ba3bf73576",
      "the Apple fixture file is byte-identical to the one committed in Phase 6B (its SHA-256)")
check(all(len(b) == n and hashlib.sha256(b).hexdigest() == h for n, h, b in real.values()), "every Apple blob still has its recorded size and SHA-256")
for name, (_n, _h, b) in sorted(real.items()):
    r = parse(b)
    check(r[0] == "ok" and len(r[1]) > 0, "the strict reader accepts the real Apple blob `%s` (its values are checked in full in section 14)" % name, str(r)[:120])
check(all(len(I._der_strict_node(b, 8, len(b), 0).children) == 2 for _n, _h, b in real.values()), "every real Apple blob has exactly two elements in its root")
prim = I._der_strict_node(tlv(2, b"\x05\x05"), 0, 4, 0)
check(prim.children == [] and prim.value == b"\x05\x05", "a primitive element has no children, whatever its content looks like")

# ---- BOOLEAN: exactly one octet, 00 or ff
check(accepts(top(entry(b"a", TRUE)), {"a": True}) and accepts(top(entry(b"a", FALSE)), {"a": False}), "BOOLEAN ff is TRUE and 00 is FALSE (accepted)")
for what, c in (("01", b"\x01"), ("02", b"\x02"), ("80", b"\x80"), ("fe", b"\xfe"), ("empty", b""), ("ff ff", b"\xff\xff"), ("00 00", b"\x00\x00"), ("00 ff", b"\x00\xff")):
    check(refuses(top(entry(b"a", tlv(1, c))), "BOOLEAN is not exactly 00 or ff"), "a BOOLEAN with the content %s is refused" % what)
bb = real["booleans"][2]
at = bb.find(b"\x01\x01\x00")
check(at > 8 and refuses(bb[:at] + b"\x01\x01\x01" + bb[at + 3:], "BOOLEAN is not exactly 00 or ff"), "the real `booleans` blob with ONE BOOLEAN changed from 00 to 01 is refused")
at = bb.find(b"\x01\x01\xff")
check(at > 8 and refuses(bb[:at] + b"\x01\x01\xfe" + bb[at + 3:], "BOOLEAN is not exactly 00 or ff"), "the real `booleans` blob with ONE BOOLEAN changed from ff to fe is refused")

# ---- INTEGER: not empty, shortest two's complement (valid: both signs, every width, and the boundaries)
GOOD_INTS = ((b"\x00", 0), (b"\x01", 1), (b"\x7f", 127), (b"\x00\x80", 128), (b"\x00\xff", 255), (b"\x01\x00", 256), (b"\x80", -128), (b"\xff", -1),
             (b"\xff\x7f", -129), (b"\xff\x00", -256), (b"\x7f\xff\xff\xff", 2147483647), (b"\x80\x00\x00\x00", -2147483648),
             (b"\x00\xff\xff\xff\xff", 4294967295), (b"\x7f" + b"\xff" * 7, 2 ** 63 - 1), (b"\x80" + b"\x00" * 7, -2 ** 63))
for c, v in GOOD_INTS:
    check(v == int.from_bytes(c, "big", signed=True) and accepts(top(entry(b"i", tlv(2, c))), {"i": v}), "INTEGER %s is accepted and means %d" % (c.hex(), v))
for what, c in (("empty", b""), ("00 00", b"\x00\x00"), ("00 01", b"\x00\x01"), ("00 7f", b"\x00\x7f"), ("00 00 80", b"\x00\x00\x80"), ("ff ff", b"\xff\xff"),
                ("ff 80", b"\xff\x80"), ("ff ff 80", b"\xff\xff\x80")):
    check(refuses(top(entry(b"i", tlv(2, c))), "INTEGER"), "INTEGER %s (empty or not shortest) is refused" % what)

# ---- lengths: definite, and as short as possible
check(refuses(blob(bytes([0x70, 0x80]) + VER + dic(entry(b"a", TRUE)) + b"\0\0"), "indefinite length"), "an indefinite length on the root is refused")
check(refuses(blob(tlv(0x70, VER + bytes([0xB0, 0x80]) + entry(b"a", TRUE) + b"\0\0")), "indefinite length"), "an indefinite length on the dictionary is refused")
check(refuses(top(bytes([0x30, 0x80]) + KEY + TRUE + b"\0\0"), "indefinite length"), "an indefinite length on an entry is refused")
check(refuses(top(entry(b"a", bytes([0x30, 0x80]) + TRUE + b"\0\0")), "indefinite length"), "an indefinite length on an array is refused")
check(refuses(top(tlv(0x30, bytes([0x0C, 0x80]) + b"a" + TRUE)), "indefinite length"), "an indefinite length on a primitive is refused")
body = VER + dic(entry(b"a", TRUE))
check(refuses(blob(tlv(0x70, body, bytes([0x81, len(body)]))), "long form"), "a length in the long form that fits the short form (81 xx with xx < 80) is refused")
check(refuses(top(tlv(0x30, KEY + TRUE, bytes([0x81, len(KEY + TRUE)]))), "long form"), "a padded entry length (81 06) is refused")
check(refuses(top(tlv(0x30, KEY + TRUE, bytes([0x82, 0x00, len(KEY + TRUE)]))), "leading zero"), "a length with a leading zero octet (82 00 xx) is refused")
check(refuses(top(tlv(0x30, KEY + TRUE, bytes([0x84, 0, 0, 0, len(KEY + TRUE)]))), "leading zero"), "a length with three leading zero octets (84 00 00 00 xx) is refused")
check(refuses(top(entry(b"a", tlv(0x0C, b"x" * 200, bytes([0x82, 0x00, 200])))), "leading zero"), "a padded length on a 200-byte string (82 00 c8) is refused")
check(refuses(top(tlv(0x30, KEY + TRUE, bytes([0x85, 0, 0, 0, 0, len(KEY + TRUE)]))), "oversized length"), "a length of more than four octets is refused")
for n in (128, 200, 255, 256, 300, 70000):  # the long forms that ARE minimal, as Apple writes them (81 in runner and arrays, 82 in integers and many)
    check(accepts(top(entry(b"s", tlv(0x0C, b"x" * n))), {"s": "x" * n}), "a %d-byte string with its minimal long-form length is accepted" % n)

# ---- tags: the single-octet form below 31; a high-tag form only for 31 and above, and then without a leading zero
dic_a = entry(b"a", TRUE)
for what, b in (("the dictionary as bf 10 (tag 16 in the high form)", blob(tlv(0x70, VER + bytes([0xBF, 0x10]) + lenb(len(dic_a)) + dic_a))),
                ("a key as 1f 0c", top(tlv(0x30, bytes([0x1F, 0x0C]) + lenb(1) + b"a" + TRUE))),
                ("a BOOLEAN as 1f 01", top(tlv(0x30, KEY + bytes([0x1F, 0x01]) + lenb(1) + b"\xff"))),
                ("an INTEGER as 1f 02", top(tlv(0x30, KEY + bytes([0x1F, 0x02]) + lenb(1) + b"\x01"))),
                ("the root as 7f 10", blob(bytes([0x7F, 0x10]) + lenb(len(body)) + body)),
                ("an array as 3f 10", top(entry(b"a", bytes([0x3F, 0x10]) + lenb(0))))):
    check(refuses(b, "high-tag-number form"), "%s is refused" % what)
check(refuses(top(entry(b"a", bytes([0x9F, 0x80, 0x1F]) + lenb(0))), "leading zero"), "a high-tag number with a leading zero octet (9f 80 1f) is refused")
check(refuses(top(entry(b"a", bytes([0x9F, 0x81, 0x81, 0x81, 0x81, 0x01]) + lenb(0))), "overlong"), "a tag number of more than four octets is refused")
check(refuses(top(entry(b"a", bytes([0x9F, 0x1F]) + lenb(0))), "unsupported value"), "a CANONICAL high tag (tag 31, 9f 1f) is read, and refused as a value this layout does not have (not as non-canonical)")

# ---- the root: exactly two elements
# (an application rule, not a DER one) the message gives the offset where the surplus starts, worked out here from the bytes written above
for what, extra in (("a BOOLEAN", TRUE), ("a NULL", tlv(5, b"")), ("an empty SEQUENCE", tlv(0x30, b"")), ("a second dictionary (a hidden entitlement)", dic(entry(b"x", TRUE)))):
    inner = VER + dic(entry(b"a", TRUE))
    surplus_at = 8 + 1 + len(lenb(len(inner + extra))) + len(inner)  # blob header, root tag, root length, then version and dictionary
    check(refuses(top(entry(b"a", TRUE), extra=extra), "exactly 2 are required") and refuses(top(entry(b"a", TRUE), extra=extra), "the first surplus element starts at byte %d" % surplus_at)
          and refuses(top(entry(b"a", TRUE), extra=extra), "root holds 3 element(s)"), "a third element in the root, %s, is refused, naming the offset where it starts (byte %d)" % (what, surplus_at))
one, none = blob(tlv(0x70, VER)), blob(tlv(0x70, b""))
check(refuses(one, "exactly 2 are required") and refuses(none, "exactly 2 are required"),
      "a root with one element, or none, is refused as an Asn1Error with a message (not an IndexError)")
check(refuses(one, "root holds 1 element(s)") and refuses(one, "its content ends at byte %d" % len(one)) and refuses(none, "root holds 0 element(s)")
      and refuses(none, "its content ends at byte %d" % len(none)), "...and the message gives the offset where the root's content ends (byte %d, %d)" % (len(one), len(none)))

# ---- nesting depth: a documented limit, refused with a message and NEVER a RecursionError
MAX = I.MAX_DER_ENTITLEMENTS_DEPTH
def nest_dict(k):
    v = TRUE
    for _ in range(k): v = dic(entry(b"a", v))
    return top(entry(b"k", v))
def nest_arr(k):
    v = TRUE
    for _ in range(k): v = tlv(0x30, v)
    return top(entry(b"k", v))
kd, ka = (MAX - 3) // 2, MAX - 3  # the deepest element sits at level 3 + 2k for k nested dictionaries, 3 + k for k nested arrays (root = level 0)
check(parse(nest_dict(kd))[0] == "ok" and refuses(nest_dict(kd + 1), "nested deeper than %d levels" % MAX), "dictionaries nested up to the limit (%d levels) are accepted, one more is refused" % MAX)
check(parse(nest_arr(ka))[0] == "ok" and refuses(nest_arr(ka + 1), "nested deeper than %d levels" % MAX), "arrays nested up to the limit are accepted, one more is refused")
check(all(refuses(nest_dict(k), "nested deeper") for k in (100, 1000, 20000)) and all(refuses(nest_arr(k), "nested deeper") for k in (100, 1000, 20000)),
      "blobs of 100, 1000 and 20000 levels are refused with the limit's message, never a RecursionError")
check(MAX >= 4 * 7, "the limit (%d) is more than four times the deepest Apple blob (7 levels)" % MAX)
def frames_needed(b):
    base = len(inspect.stack())
    try:
        for extra in range(5, 300):
            sys.setrecursionlimit(base + extra)
            try:
                I.parse_der_entitlements(b)
                return extra
            except RecursionError:
                continue
    finally:
        sys.setrecursionlimit(1000)
need = max(frames_needed(nest_dict(kd)), frames_needed(nest_arr(ka)))
check(need is not None and need <= 3 * MAX + 10, "a blob at the limit needs only %s Python frames: the reader cannot exhaust the stack on its own" % need)

# ---- a failure of the reader is a RECORDED problem in read_signature, a RecursionError included: the other fields are still read
work = tempfile.mkdtemp()
def signed_file(name, der_blob):
    import ipa_fixture as fx
    path = os.path.join(work, name)
    with open(path, "wb") as f: f.write(fx.make_macho("p6c" + name))
    keep = fx.der_entitlements_blob
    fx.der_entitlements_blob = lambda ents, version=b"\x01": der_blob
    try:
        fx.MUT.clear()
        fx.sign_macho_file(path, "org.example.p6c", "SYNTH12345", {}, plistlib.dumps({"get-task-allow": False}, fmt=plistlib.FMT_XML), False, True, None, True)
    finally:
        fx.der_entitlements_blob = keep
    return path
good = top(entry(b"get-task-allow", FALSE))
p0 = I.read_signature(signed_file("good", good))["slices"][0]
check(p0["problems"] == [] and p0["der_entitlements"] == {"get-task-allow": False} and p0["cds"], "(control) a well-formed blob is read and nothing is recorded")
for what, b in (("a BOOLEAN 01", top(entry(b"get-task-allow", tlv(1, b"\x01")))), ("an indefinite length", blob(bytes([0x70, 0x80]) + VER + dic(entry(b"a", TRUE)) + b"\0\0")),
                ("a third root element", top(entry(b"a", TRUE), extra=TRUE)), ("nesting of 1000 levels", nest_dict(1000))):
    sl = I.read_signature(signed_file("bad", b))["slices"][0]
    check(any("DER entitlements are unreadable" in p for p in sl["problems"]) and sl["der_entitlements"] is None and sl["cds"] and sl["entitlements"] == {"get-task-allow": False},
          "read_signature records %s as a problem and still reads the CodeDirectory and the XML entitlements" % what, str(sl["problems"])[:160])
real_parse = I.parse_der_entitlements
def boom(_b): raise RecursionError("maximum recursion depth exceeded")
I.parse_der_entitlements = boom
try:
    sl = I.read_signature(signed_file("rec", good))["slices"][0]
finally:
    I.parse_der_entitlements = real_parse
check(any("DER entitlements are unreadable" in p for p in sl["problems"]) and sl["cds"] and sl["entitlements"] == {"get-task-allow": False},
      "a RecursionError from the reader is a recorded problem (nothing aborts), and the other fields are still read", str(sl["problems"])[:160])
# and a REAL stack exhaustion inside the reader: a blob WITHIN the limit, read with so little stack that the interpreter itself gives out
path = signed_file("rec2", nest_dict(kd))
base, found = len(inspect.stack()), None
try:
    for limit in range(base + 70, base + 20, -1):
        sys.setrecursionlimit(limit)
        try:
            sl = I.read_signature(path)["slices"][0]
        except RecursionError:
            continue  # not even enough stack to reach the reader
        if any("nested too deeply" in p for p in sl["problems"]):
            found = (limit - base, sl)
            break
finally:
    sys.setrecursionlimit(1000)
check(found is not None and any("DER entitlements are unreadable" in p for p in found[1]["problems"]) and found[1]["cds"],
      "when the interpreter's stack really runs out inside the reader (with %s frames to spare), read_signature records it as a problem" % (found[0] if found else "?"))

# ---- the BER reader that CMS needs is NOT changed: it still reads what the strict reader refuses
ind = bytes([0x30, 0x80, 0x02, 0x01, 0x05, 0x00, 0x00])
check(I.parse_der(ind).constructed and I.parse_der(ind).children[0].value == b"\x05", "parse_der (the CMS reader) still reads an indefinite length")
check(I.parse_der(bytes([0x30, 0x81, 0x03, 0x02, 0x01, 0x05])).children[0].value == b"\x05", "parse_der still reads a padded length")
check(I.parse_der(bytes([0xBF, 0x10, 0x00])).tag == 16, "parse_der still reads a tag in the high form")
indef_root = bytes([0x70, 0x80]) + VER + dic(entry(b"a", TRUE)) + b"\0\0"
check(refuses(blob(indef_root), "indefinite") and I.parse_der(indef_root).constructed, "...while the same bytes are refused by parse_der_entitlements")
PY

# the same, end to end through the verifier: a refusal by the strict reader is a FAILED verification, in ONE respect only, and the other checks run
derchk() { # NAME MUTATION REASON: a failed, recorded verification; nothing else fails; the independent checks still ran; no abort
  local name=$1 mut=$2 reason=$3 nfail
  mk "$name" staging "$mut"
  run staging "$tmp/$name.ipa" "${common[@]}" --expect-cert-sha256 "$PIN" --evidence "$tmp/$name.ev"
  nfail="$(grep -c 'FAIL  ' <<<"$out")"
  if [ "$rc" -eq 1 ] && grep -F "FAIL" <<<"$out" | grep -F "DER entitlements are unreadable" | grep -F "$reason" >/dev/null && [ "$nfail" -eq 1 ] \
     && ! grep -F "internal error" <<<"$out" >/dev/null && grep -F "PASS  Frameworks/Flut.framework/Flut: signature intact" <<<"$out" >/dev/null && [ -s "$tmp/$name.ev" ]; then
    ok "an IPA whose DER entitlements are $reason: refused as a recorded problem, the only failure, the other checks ran and the evidence was written"
  else
    bad "an IPA whose DER entitlements are $reason is a recorded failure and the other checks ran" "exit $rc, FAIL lines $nfail: $(echo "$out" | grep -E 'FAIL|internal' | head -3 | tr '\n' '|')"
  fi
}
derchk derbool der-bool01 "BOOLEAN is not exactly 00 or ff"
derchk derindef der-indefinite "indefinite length"
derchk derextra der-root-extra "exactly 2 are required"
derchk derdeep der-deep "nested deeper than"

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
