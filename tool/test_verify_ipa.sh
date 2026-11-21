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
# Not covered here, because no genuine evidence exists yet: the DER entitlements layout and the V8 Info.plist comparison.
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
# difference and the real DER layout are is NOT known (no genuine evidence kept); nothing here claims to know.

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
# the parser's acceptance did not change: a blob of the layout it assumes still decodes, others still fail
import ipa_fixture as F
gb = F.der_entitlements_blob({"a": True, "b": ["x", 3]})
check(I.parse_der_entitlements(gb) == {"a": True, "b": ["x", 3]}, "parse_der_entitlements: acceptance is unchanged in Phase 2 (the layout the parser assumes still decodes)")
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
