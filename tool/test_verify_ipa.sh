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
