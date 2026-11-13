#!/usr/bin/env bash
# Tests the offline re-signing of a retained Android AAB (tool/resign_android_aab.py, Stage 3B of issue #54;
# docs/RETAINED_ARTIFACTS.md section 6) with DISPOSABLE credentials only. No real key, keystore or secret is
# read or needed, and nothing is uploaded.
#
#   tool/test_resign_android_aab.sh
#
# Part 1 (always, needs only python3 and a JDK's keytool and jarsigner): the signing core on a synthetic
#   bundle: removing exactly the signature entries, signing, the credential rules of android/app/build.gradle.kts
#   (outside the repository, nothing printed, no debug fallback), the expected-fingerprint gate, and the refusals
#   of `sign` for a retained bundle that is missing, tampered, of another variant or without its evidence.
# Part 2 (with a REAL retained production AAB; needs ANDROID_HOME, BUNDLETOOL_JAR and JDK 17 like
#   tool/test_android_release.sh): the whole procedure and its rejections:
#       REAL_RETAINED_DIR=<retained_android-production-aab_aN>  RETAINED_IDENTITY=<age identity file>
#       RETAINED_AGE=<age or an age-compatible decryptor>  ANDROID_HOME=... BUNDLETOOL_JAR=... JAVA_HOME=<jdk17> \
#         tool/test_resign_android_aab.sh
#   The disposable keys are created in a private temporary directory and deleted on exit.
# Exit 0 only if every check passes.
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RS="$root/tool/resign_android_aab.py"
RA="$root/tool/retain_artifact.py"
pass=0; failed=0; skipped=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
skip() { skipped=$((skipped + 1)); echo "skip $1"; }
tmp="$(mktemp -d)"; chmod 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT

t() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
# expect_rc NAME RC FRAGMENT COMMAND... : exit status RC and FRAGMENT in the output (stdout and stderr)
expect_rc() {
  local name="$1" want="$2" frag="$3" out rc
  shift 3
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then bad "$name" "exit $rc (wanted $want): $(printf '%s' "$out" | tail -n 6)"; return; fi
  if [ -n "$frag" ] && ! grep -qF -- "$frag" <<<"$out"; then bad "$name" "output lacks '$frag': $(printf '%s' "$out" | tail -n 6)"; return; fi
  ok "$name"
}
lacks_text() { ! grep -qF -- "$2" <<<"$1"; }

if ! command -v keytool >/dev/null 2>&1 || ! command -v jarsigner >/dev/null 2>&1; then
  skip "everything: keytool and jarsigner (a JDK) are needed"
  echo; echo "$pass passed, $failed failed, $skipped skipped"; exit 0
fi

# ---- disposable keys ---------------------------------------------------------------------------------
PW="$(openssl rand -hex 12)"
PW_WRONG="$(openssl rand -hex 12)"
mkkey() { # NAME DN : prints the SHA-256 fingerprint of the new certificate
  keytool -genkeypair -alias "$1" -keyalg RSA -keysize 2048 -validity 10000 -keystore "$tmp/$1.p12" -storetype PKCS12 \
    -dname "$2" -storepass "$PW" -keypass "$PW" >/dev/null 2>&1
  keytool -list -keystore "$tmp/$1.p12" -storepass "$PW" 2>/dev/null | sed -n 's/.*SHA-256): //p' | head -n1
}
FP_UP="$(mkkey up "CN=DISPOSABLE TEST UPLOAD KEY, O=Test")"
FP_OTHER="$(mkkey other "CN=DISPOSABLE OTHER KEY, O=Test")"
FP_DEBUG="$(mkkey dbg "C=US, O=Android, CN=Android Debug")"
t "keys: three disposable keys were created" test -n "$FP_UP" -a -n "$FP_OTHER" -a -n "$FP_DEBUG"
# the credentials, as Gradle takes them: environment variables
creds() { # KEY [PASSWORD] : exports for the next command via env(1)
  echo "CADENA_KEYSTORE_FILE=$tmp/$1.p12 CADENA_KEY_ALIAS=$1 CADENA_KEYSTORE_PASSWORD=${2:-$PW} CADENA_KEY_PASSWORD=${2:-$PW}"
}
RSx() { python3 -I "$RS" "$@"; }

# ---- 1a. the signing core on a synthetic AAB-like zip -------------------------------------------------------
python3 -I - "$root" "$tmp" <<'PY'
import sys, zipfile
root, tmp = sys.argv[1:3]
with zipfile.ZipFile(tmp + "/ci.aab", "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("BundleConfig.pb", b"config")
    z.writestr("BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb", b"deps")
    z.writestr("base/manifest/AndroidManifest.xml", b"<manifest/>")
    z.writestr("base/lib/arm64-v8a/libapp.so", b"\x7fELF" + b"A" * 5000)
    z.writestr("META-INF/services/keep.me", b"not a signature entry; must survive")
PY
cp "$tmp/ci.aab" "$tmp/ci-signed.aab"
jarsigner -keystore "$tmp/dbg.p12" -storepass "$PW" -keypass "$PW" -sigalg SHA256withRSA -digestalg SHA-256 "$tmp/ci-signed.aab" dbg >/dev/null 2>&1
t "core: the synthetic CI AAB carries a (debug) jar signature" bash -c "unzip -l '$tmp/ci-signed.aab' | grep -q 'META-INF/DBG.SF'"

t "core: only the signature entries are removed; every other entry keeps its bytes and its order" python3 -I -c "
import sys, zipfile, os
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import resign_android_aab as r, retain_artifact as ra
removed = r.strip_signature_entries('$tmp/ci-signed.aab', '$tmp/stripped.aab')
assert sorted(removed)==['META-INF/DBG.RSA','META-INF/DBG.SF','META-INF/MANIFEST.MF'], removed
a=zipfile.ZipFile('$tmp/ci-signed.aab'); b=zipfile.ZipFile('$tmp/stripped.aab')
keep=[i.filename for i in a.infolist() if not ra.is_signature_entry(i.filename)]
assert [i.filename for i in b.infolist()]==keep, 'order or set differs'
assert all(a.read(n)==b.read(n) for n in keep)
assert 'META-INF/services/keep.me' in keep
assert ra.zip_content_digest('$tmp/ci-signed.aab')==ra.zip_content_digest('$tmp/stripped.aab')
"

t "core: the keystore fingerprint of an alias equals keytool's and needs the right password" python3 -I -c "
import sys, os
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import resign_android_aab as r
c={'storeFile':'$tmp/up.p12','keyAlias':'up','storePassword':'$PW','keyPassword':'$PW'}
assert r.colon(r.keystore_cert_fingerprint(c))=='$FP_UP', 'fingerprint'
for bad in ({'keyAlias':'nope'},{'storePassword':'$PW_WRONG'}):
    try: r.keystore_cert_fingerprint(dict(c,**bad)); raise SystemExit('accepted '+str(sorted(bad)))
    except r.Fail as e: assert '$PW_WRONG' not in str(e) and '$PW' not in str(e)
"

t "core: signing keeps the content digest, one signer, and jarsigner verifies" python3 -I -c "
import sys
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import resign_android_aab as r, retain_artifact as ra
c={'storeFile':'$tmp/up.p12','keyAlias':'up','storePassword':'$PW','keyPassword':'$PW'}
r.jarsigner_sign('$tmp/stripped.aab','$tmp/core-signed.aab',c,r.DEFAULT_SIGALG)
ok,_=r.jarsigner_verify('$tmp/core-signed.aab'); assert ok
sha,owner,n,_=r.signer_of('$tmp/core-signed.aab'); assert n==1 and r.colon(sha)=='$FP_UP', (sha,n)
assert ra.zip_content_digest('$tmp/core-signed.aab')==ra.zip_content_digest('$tmp/ci.aab')
assert r.jarsigner_verify('$tmp/stripped.aab')[0] is False
"
t "core: a wrong KEY password makes jarsigner refuse, and no signed file is left behind" python3 -I -c "
import sys, os
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import resign_android_aab as r
c={'storeFile':'$tmp/up.p12','keyAlias':'up','storePassword':'$PW','keyPassword':'$PW_WRONG'}
try: r.jarsigner_sign('$tmp/stripped.aab','$tmp/never.aab',c,r.DEFAULT_SIGALG); raise SystemExit('signed')
except r.Fail as e: assert '$PW_WRONG' not in str(e)
assert not os.path.exists('$tmp/never.aab')
"

t "core: the certificate's end of validity is recorded as an ISO date (about 10000 days for the disposable key)" python3 -I -c "
import sys, datetime
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import resign_android_aab as r
sha,owner,n,until=r.signer_of('$tmp/core-signed.aab')
d=datetime.date.fromisoformat(r.iso_date(until))
days=(d-datetime.date.today()).days
assert 9990<=days<=10010, (until, d, days)
assert r.iso_date('') is None and r.iso_date('not a date') is None
"

t "env: children that need no credential never receive the signing variables; the keystore children receive only the child passwords" python3 -I -c "
import os, sys
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import resign_android_aab as r
os.environ.update(CADENA_KEYSTORE_PASSWORD='$PW', CADENA_KEY_PASSWORD='$PW', CADENA_KEY_ALIAS='up', CADENA_KEYSTORE_FILE='$tmp/up.p12', CADENA_SIGNING_PROPERTIES='/x')
e=r.clean_env()
assert not any(k.startswith('CADENA_') and k in ('CADENA_KEYSTORE_PASSWORD','CADENA_KEY_PASSWORD','CADENA_KEY_ALIAS','CADENA_KEYSTORE_FILE','CADENA_SIGNING_PROPERTIES') for k in e), sorted(k for k in e if k.startswith('CADENA'))
out=r.run(['env'],'env').stdout.decode()
assert '$PW' not in out
c={'storeFile':'$tmp/up.p12','keyAlias':'up','storePassword':'$PW','keyPassword':'$PW'}
ce=r.child_env(c)
assert ce[r.CHILD_STORE]=='$PW' and ce[r.CHILD_KEY]=='$PW' and 'CADENA_KEYSTORE_PASSWORD' not in ce and 'CADENA_KEY_PASSWORD' not in ce
"

# credentials: the rules of android/app/build.gradle.kts
mkdir -p "$tmp/fakerepo"
t "creds: a missing credential is named, never a value, and there is no fallback" python3 -I -c "
import sys, os
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import resign_android_aab as r
for k in ('CADENA_KEYSTORE_FILE','CADENA_KEY_ALIAS','CADENA_KEYSTORE_PASSWORD','CADENA_KEY_PASSWORD','CADENA_SIGNING_PROPERTIES'): os.environ.pop(k,None)
os.environ['CADENA_KEYSTORE_PASSWORD']='$PW'
try: r.load_credentials(None,'$tmp/fakerepo'); raise SystemExit('accepted')
except r.Fail as e:
    m=str(e); assert 'storeFile' in m and 'keyAlias' in m and 'keyPassword' in m and 'no fallback' in m and '$PW' not in m, m
"
t "creds: a keystore inside the repository is refused" python3 -I -c "
import sys, os, shutil
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import resign_android_aab as r
shutil.copy('$tmp/up.p12','$tmp/fakerepo/in-repo.p12')
os.environ.update(CADENA_KEYSTORE_FILE='$tmp/fakerepo/in-repo.p12',CADENA_KEY_ALIAS='up',CADENA_KEYSTORE_PASSWORD='$PW',CADENA_KEY_PASSWORD='$PW')
try: r.load_credentials(None,'$tmp/fakerepo'); raise SystemExit('accepted')
except r.Fail as e: assert 'outside the repository' in str(e)
"
t "creds: a properties file inside the repository is refused; one outside works, and the environment wins over it" python3 -I -c "
import sys, os
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import resign_android_aab as r
for k in ('CADENA_KEYSTORE_FILE','CADENA_KEY_ALIAS','CADENA_KEYSTORE_PASSWORD','CADENA_KEY_PASSWORD','CADENA_SIGNING_PROPERTIES'): os.environ.pop(k,None)
open('$tmp/fakerepo/p.properties','w').write('storeFile=$tmp/up.p12\nkeyAlias=up\nstorePassword=$PW\nkeyPassword=$PW\n')
try: r.load_credentials('$tmp/fakerepo/p.properties','$tmp/fakerepo'); raise SystemExit('accepted')
except r.Fail as e: assert 'outside the repository' in str(e)
open('$tmp/p.properties','w').write('storeFile=$tmp/up.p12\nkeyAlias=up\nstorePassword=$PW\nkeyPassword=$PW\n')
c=r.load_credentials('$tmp/p.properties','$tmp/fakerepo'); assert c['keyAlias']=='up'
os.environ['CADENA_KEY_ALIAS']='other'
assert r.load_credentials('$tmp/p.properties','$tmp/fakerepo')['keyAlias']=='other'
"

# ---- 1b. `sign` refusals with retained bundles ------------------------------------------------------------------
# age (the real one, or a labelled stub) for the bundles of the synthetic fixtures
source "$root/tool/test_age_setup.sh"
CUST_KEY="$tmp/custodian.key"; "$AGE_KEYGEN" -o "$CUST_KEY" >/dev/null 2>&1
CUST_PUB="$(sed -n 's/^# public key: //p' "$CUST_KEY")"
printf '%s\n' "$CUST_PUB" >"$tmp/recipients.txt"
fx="$tmp/fx"
if python3 -I "$root/tool/retained_fixtures.py" "$root" "$fx" >"$tmp/fix.log" 2>&1; then ok "fixtures: synthetic builds with real build manifests"; else bad "fixtures" "$(tail -n 5 "$tmp/fix.log")"; fi
pack() { # VARIANT KIND ARTIFACT OUT
  python3 -I "$RA" pack --variant "$1" --kind "$2" --artifact "$3" --evidence "$fx/$1/$1.txt" --manifest "$fx/$1/$1.manifest.json" \
    --recipients "$tmp/recipients.txt" --out "$4" --age "$AGE_BIN" --age-keygen "$AGE_KEYGEN" >/dev/null 2>&1
}
pack android-production-aab aab "$fx/android-production-aab/app-production-release.aab" "$tmp/ret-aab" && ok "bundle: a retained synthetic production AAB" || bad "bundle: pack the synthetic AAB"
pack android-production-apk apk "$fx/android-production-apk/app-production-release.apk" "$tmp/ret-apk" && ok "bundle: a retained synthetic production APK" || bad "bundle: pack the synthetic APK"
pack android-staging-apk apk "$fx/android-staging-apk/app-staging-release.apk" "$tmp/ret-stg" && ok "bundle: a retained synthetic staging APK" || bad "bundle: pack the staging APK"
REPOCOPY="$tmp/repocopy"
mkdir -p "$REPOCOPY" && cp -R "$root/tool" "$root/config" "$root/pubspec.yaml" "$REPOCOPY/" && rm -rf "$REPOCOPY/tool/__pycache__"
python3 -I -c '
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["upload"]["active_sha256"]=None; json.dump(d,open(p,"w"),indent=2)' "$REPOCOPY/config/release/android_signing.json"
SIGN() { # BUNDLE OUT KEYNAME FP [env...]  -> runs `sign`
  local bundle="$1" out="$2" key="$3" fp="$4"; shift 4
  env $(creds "$key") "$@" python3 -I "$RS" sign "$bundle" --identity "$CUST_KEY" --expect-cert-sha256 "$fp" --out "$out" --repo "$REPOCOPY" --age "$AGE_BIN"
}

expect_rc "sign: missing credentials are refused (no debug fallback)" 2 "incomplete" \
  env -u CADENA_KEYSTORE_FILE -u CADENA_KEY_ALIAS -u CADENA_KEYSTORE_PASSWORD -u CADENA_KEY_PASSWORD -u CADENA_SIGNING_PROPERTIES \
  python3 -I "$RS" sign "$tmp/ret-aab" --identity "$CUST_KEY" --expect-cert-sha256 "$FP_UP" --out "$tmp/o1" --repo "$REPOCOPY" --age "$AGE_BIN"
expect_rc "sign: an expected fingerprint is required" 2 "required" env $(creds up) python3 -I "$RS" sign "$tmp/ret-aab" --identity "$CUST_KEY" --out "$tmp/o2" --repo "$REPOCOPY" --age "$AGE_BIN"
expect_rc "sign: a malformed expected fingerprint is refused" 2 "SHA-256 fingerprint" SIGN "$tmp/ret-aab" "$tmp/o3" up 12345
expect_rc "sign: a keystore whose certificate is not the expected one is refused before signing" 1 "expected certificate" SIGN "$tmp/ret-aab" "$tmp/o4" up "$FP_OTHER"
t "sign: ... and nothing was written" test ! -e "$tmp/o4"
expect_rc "sign: a wrong keystore password is refused" 2 "could not be opened" SIGN "$tmp/ret-aab" "$tmp/o5" up "$FP_UP" "CADENA_KEYSTORE_PASSWORD=$PW_WRONG"
mkdir -p "$tmp/o6" && : >"$tmp/o6/leftover"
expect_rc "sign: a non-empty output directory is refused" 2 "not empty" SIGN "$tmp/ret-aab" "$tmp/o6" up "$FP_UP"
expect_rc "sign: a missing retained bundle is refused" 1 "does not verify" SIGN "$tmp/nope" "$tmp/o7" up "$FP_UP"
expect_rc "sign: a production APK bundle is not an AAB" 1 "only the production AAB" SIGN "$tmp/ret-apk" "$tmp/o8" up "$FP_UP"
expect_rc "sign: a staging bundle is refused" 1 "only the production AAB" SIGN "$tmp/ret-stg" "$tmp/o9" up "$FP_UP"
rm -rf "$tmp/ret-bad1"; cp -R "$tmp/ret-aab" "$tmp/ret-bad1"; printf 'tampered' >>"$tmp/ret-bad1/"*.age
expect_rc "sign: a tampered ciphertext is refused" 1 "does not verify" SIGN "$tmp/ret-bad1" "$tmp/o10" up "$FP_UP"
rm -rf "$tmp/ret-bad2"; cp -R "$tmp/ret-aab" "$tmp/ret-bad2"; rm "$tmp/ret-bad2/android-production-aab.txt"
expect_rc "sign: a bundle without its evidence is refused" 1 "does not verify" SIGN "$tmp/ret-bad2" "$tmp/o11" up "$FP_UP"
rm -rf "$tmp/ret-bad3"; cp -R "$tmp/ret-aab" "$tmp/ret-bad3"; rm "$tmp/ret-bad3/android-production-aab.manifest.json"
expect_rc "sign: a bundle without its build manifest is refused" 1 "does not verify" SIGN "$tmp/ret-bad3" "$tmp/o12" up "$FP_UP"
rm -rf "$tmp/ret-bad4"; cp -R "$tmp/ret-aab" "$tmp/ret-bad4"
python3 -I -c "
import json,glob
p=glob.glob('$tmp/ret-bad4/*.retained.json')[0]; r=json.load(open(p)); r['source']['commit']='0'*40; json.dump(r,open(p,'w'),indent=2)"
expect_rc "sign: a retained manifest that disagrees with the build manifest is refused" 1 "does not verify" SIGN "$tmp/ret-bad4" "$tmp/o13" up "$FP_UP"
# a valid synthetic bundle goes as far as the release verifier, which cannot accept a zip that is not a real bundle
expect_rc "sign: a synthetic (not real) AAB is rejected by the release verifier, fail closed" 1 "verify_android_release" SIGN "$tmp/ret-aab" "$tmp/o14" up "$FP_UP"
t "sign: ... and no output directory remains" test ! -e "$tmp/o14"
# a jarsigner that changes one entry of its input before it signs (a VALID signature over CHANGED content):
# only the content-digest check after signing can catch it, so this exercises that check and no other
mkdir -p "$tmp/shim"
REALJ="$(command -v jarsigner)"
cat >"$tmp/shim/jarsigner" <<EOF
#!/usr/bin/env bash
# TEST SHIM: tamper with the unsigned input of a -signedjar call, then run the real jarsigner
args=("\$@")
for ((i = 0; i < \${#args[@]}; i++)); do
  if [ "\${args[i]}" = -signedjar ]; then
    python3 -I - "\${args[i+2]}" <<'PYEOF'
import sys, zipfile
p = sys.argv[1]
with zipfile.ZipFile(p) as z:
    items = [(i, z.read(i)) for i in z.infolist()]
with zipfile.ZipFile(p, "w") as z:
    for info, data in items:
        z.writestr(info, data + (b"!" if info.filename == "classes.dex" else b""), compress_type=info.compress_type)
PYEOF
  fi
done
exec "$REALJ" "\$@"
EOF
chmod +x "$tmp/shim/jarsigner"
expect_rc "sign: a validly signed but ALTERED bundle is caught by the content-digest check after signing" 1 "differs from the verified" \
  env "PATH=$tmp/shim:$PATH" bash -c "$(declare -f SIGN creds); PW='$PW'; tmp='$tmp'; RS='$RS'; CUST_KEY='$CUST_KEY'; AGE_BIN='$AGE_BIN'; REPOCOPY='$REPOCOPY'; SIGN '$tmp/ret-aab' '$tmp/o16' up '$FP_UP'"
t "sign: ... and nothing was written" test ! -e "$tmp/o16"
treesum() { ( cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1 ); }
BEFORE="$(treesum "$tmp/ret-aab")"
SIGN "$tmp/ret-aab" "$tmp/o15" up "$FP_UP" >/dev/null 2>&1
t "sign: the retained directory is not modified, not even by a run that fails late" test "$BEFORE" = "$(treesum "$tmp/ret-aab")"
t "sign: no temporary working directory is left behind after a failure" bash -c "[ -z \"\$(ls -d \"\${TMPDIR:-/tmp}\"/resign-* 2>/dev/null)\" ]"
t "no disposable password appears in any output, log, record or manifest the tests produced" bash -c "[ -z \"\$(find '$tmp' -type f \\( -name '*.log' -o -name '*.txt' -o -name '*.json' \\) -exec grep -lF -- '$PW' {} + 2>/dev/null)\" ]"

# ---- 2. the whole procedure on a REAL retained AAB -------------------------------------------------------------------
if [ -z "${REAL_RETAINED_DIR:-}" ] || [ -z "${RETAINED_IDENTITY:-}" ] || [ -z "${ANDROID_HOME:-}" ] || [ -z "${BUNDLETOOL_JAR:-}" ]; then
  skip "real artifact: set REAL_RETAINED_DIR, RETAINED_IDENTITY, RETAINED_AGE, ANDROID_HOME, BUNDLETOOL_JAR (and JAVA_HOME=JDK 17) to run the whole procedure"
else
  RAGE="${RETAINED_AGE:-age}"
  REAL="$REAL_RETAINED_DIR"
  SIGNR() { # OUT KEYNAME FP [env...]
    local out="$1" key="$2" fp="$3"; shift 3
    env $(creds "$key") "$@" python3 -I "$RS" sign "$REAL" --identity "$RETAINED_IDENTITY" --expect-cert-sha256 "$fp" --out "$out" --repo "$REPOCOPY" --age "$RAGE"
  }
  VER() { python3 -I "$RS" verify "$1" --expect-cert-sha256 "$2" --repo "$REPOCOPY"; }
  REAL_BEFORE="$(treesum "$REAL")"
  expect_rc "real: the retained AAB is re-signed with the disposable upload key" 0 "RESULT: OK" SIGNR "$tmp/real-out" up "$FP_UP"
  OUT="$tmp/real-out"
  t "real: the output holds exactly the signed AAB, the record, the verification text, the three provenance files and SHA256SUMS" bash -c "[ \"\$(ls '$OUT' | wc -l | tr -d ' ')\" = 7 ] && ls '$OUT' | grep -q '\.upload-signed\.aab\$' && [ -f '$OUT/signing-record.json' ] && [ -f '$OUT/verify_android_release.txt' ] && [ -f '$OUT/SHA256SUMS' ]"
  t "real: the record ties the signed AAB to the original: commit, run, digests, certificate, verification" python3 -I -c "
import json,glob
r=json.load(open('$OUT/signing-record.json'))
o,s=r['original'],r['signed']
assert o['content_sha256']==s['content_sha256'], 'content'
assert s['sha256']!=o['plaintext']['sha256'], 'a signature must change the file digest'
assert s['certificate_sha256']=='$FP_UP' and len(o['source']['commit'])==40 and o['signing']=='debug'
assert r['verification']['content_unchanged'] is True and r['distributable'] is False
assert 'META-INF/MANIFEST.MF' in s['signature_entries_removed'] and 'META-INF/MANIFEST.MF' in s['signature_entries_added']
print('ok')" >/dev/null
  t "real: the release verifier output says OK with the expected certificate" bash -c "grep -q 'RESULT: OK' '$OUT/verify_android_release.txt' && grep -q 'locally signed with the expected upload identity' '$OUT/verify_android_release.txt'"
  expect_rc "real: verify re-checks the signed directory" 0 "content unchanged" VER "$OUT" "$FP_UP"
  t "real: the record's certificate end of validity is an ISO date beyond Google's 2033-10-22 requirement" python3 -I -c "
import json, datetime
r=json.load(open('$OUT/signing-record.json'))['signed']
d=datetime.date.fromisoformat(r['certificate_valid_until_date']); assert d>datetime.date(2033,10,22), d
assert r['certificate_valid_until']"

  t "real: the retained directory is byte-for-byte unchanged by a successful signing" test "$REAL_BEFORE" = "$(treesum "$REAL")"
  # independent evidence that the application content is unchanged: entry by entry against the recovered original
  python3 -I "$RA" unpack "$REAL" --identity "$RETAINED_IDENTITY" --out "$tmp/orig" --age "$RAGE" >/dev/null 2>&1
  t "real: every non-signature entry of the signed AAB is byte-identical to the verified original, in the same order" python3 -I -c "
import glob, sys, zipfile
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import retain_artifact as ra
o=zipfile.ZipFile(glob.glob('$tmp/orig/*.aab')[0]); s=zipfile.ZipFile(glob.glob('$OUT/*.aab')[0])
on=[i.filename for i in o.infolist() if not ra.is_signature_entry(i.filename)]
sn=[i.filename for i in s.infolist() if not ra.is_signature_entry(i.filename)]
assert on==sn, 'entry names or order differ'
bad=[n for n in on if o.read(n)!=s.read(n)]
assert not bad, bad[:5]
print(len(on),'entries identical')"
  t "real: bundletool validates the signed bundle" bash -c "java -jar '$BUNDLETOOL_JAR' validate --bundle=\"\$(ls '$OUT'/*.aab)\" >/dev/null 2>&1"
  t "real: the original is debug-signed and the signed one is not" bash -c "keytool -printcert -jarfile \"\$(ls '$tmp'/orig/*.aab)\" | grep -q 'Android Debug' && ! keytool -printcert -jarfile \"\$(ls '$OUT'/*.aab)\" | grep -q 'Android Debug'"

  # rejections
  expect_rc "real: another expected certificate is refused before signing" 1 "expected certificate" SIGNR "$tmp/real-o2" up "$FP_OTHER"
  t "real: ... and nothing was written" test ! -e "$tmp/real-o2"
  expect_rc "real: a keystore with the wrong password is refused" 2 "could not be opened" SIGNR "$tmp/real-o3" up "$FP_UP" "CADENA_KEYSTORE_PASSWORD=$PW_WRONG"
  expect_rc "real: a debug certificate is refused by the release verifier and leaves nothing" 1 "DEBUG certificate" SIGNR "$tmp/real-o4" dbg "$FP_DEBUG"
  t "real: ... no output remains" test ! -e "$tmp/real-o4"
  t "real: a ledger-forbidden identity is refused" bash -c "
    d='$tmp/repo-forbid'; rm -rf \"\$d\"; cp -R '$REPOCOPY' \"\$d\"
    python3 -I -c \"
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['upload']['do_not_use'].append({'sha256':'$FP_UP','reason':'disposable test'}); json.dump(d,open(p,'w'))\" \"\$d/config/release/android_signing.json\"
    out=\$(env $(creds up) python3 -I '$RS' sign '$REAL' --identity '$RETAINED_IDENTITY' --expect-cert-sha256 '$FP_UP' --out '$tmp/real-o5' --repo \"\$d\" --age '$RAGE' 2>&1); rc=\$?
    [ \$rc -eq 1 ] && grep -q 'forbids' <<<\"\$out\" && [ ! -e '$tmp/real-o5' ]"

  # modified application content that is validly re-signed: verify must catch it by the content digest
  SIGNED_AAB="$(ls "$OUT"/*.aab)"
  rm -rf "$tmp/mod"; cp -R "$OUT" "$tmp/mod"
  python3 -I - "$root" "$tmp" "$PW" <<'PY'
import glob, hashlib, json, os, subprocess, sys, zipfile
root, tmp, pw = sys.argv[1:4]
sys.dont_write_bytecode = True
sys.path.insert(0, root + "/tool"); import resign_android_aab as r, retain_artifact as ra
d = tmp + "/mod"
signed = glob.glob(d + "/*.aab")[0]
# one byte of an application entry is changed, the signature is removed and a VALID signature is made again
tmpzip = tmp + "/mod-unsigned.aab"
with zipfile.ZipFile(signed) as zin, zipfile.ZipFile(tmpzip, "w") as zout:
    for info in zin.infolist():
        if ra.is_signature_entry(info.filename): continue
        data = zin.read(info)
        if info.filename == "BundleConfig.pb": data = data + b"\x00"
        zout.writestr(info, data, compress_type=info.compress_type)
os.environ["CADENA_RESIGN_CHILD_STOREPASS"] = pw; os.environ["CADENA_RESIGN_CHILD_KEYPASS"] = pw
c = {"storeFile": tmp + "/up.p12", "keyAlias": "up", "storePassword": pw, "keyPassword": pw}
os.remove(signed)
r.jarsigner_sign(tmpzip, signed, c, r.DEFAULT_SIGALG)
# an attacker who also repairs the record's file digest and SHA256SUMS
rec = json.load(open(d + "/signing-record.json"))
rec["signed"]["sha256"] = ra.sha256_file(signed); rec["signed"]["size"] = os.path.getsize(signed)
ra.write_json(d + "/signing-record.json", rec); ra.write_sums(d)
PY
  expect_rc "real: validly re-signed but MODIFIED application content is rejected (content digest)" 1 "content changed" VER "$tmp/mod" "$FP_UP"

  rm -rf "$tmp/m2"; cp -R "$OUT" "$tmp/m2"; rm "$tmp/m2/"*.txt 2>/dev/null; rm "$tmp/m2/verify_android_release.txt" 2>/dev/null
  expect_rc "real: a signed directory without its evidence is rejected" 1 "expected exactly" VER "$tmp/m2" "$FP_UP"
  rm -rf "$tmp/m3"; cp -R "$OUT" "$tmp/m3"
  python3 -I -c "
import json,glob,sys
sys.path.insert(0,'$root/tool'); sys.dont_write_bytecode=True
import retain_artifact as ra
p='$tmp/m3/signing-record.json'; r=json.load(open(p)); r['original']['content_sha256']='0'*64; ra.write_json(p,r); ra.write_sums('$tmp/m3')"
  expect_rc "real: a record whose original content digest was altered is rejected" 1 "content digest" VER "$tmp/m3" "$FP_UP"
  rm -rf "$tmp/m4"; cp -R "$OUT" "$tmp/m4"
  python3 -I -c "
import json,sys
sys.path.insert(0,'$root/tool'); sys.dont_write_bytecode=True
import retain_artifact as ra
p='$tmp/m4/android-production-aab.manifest.json'; m=json.load(open(p)); m['version']['name']='9.9.9'; json.dump(m,open(p,'w'),indent=2)
r='$tmp/m4/signing-record.json'; j=json.load(open(r)); j['original']['build_manifest']['sha256']=ra.sha256_file(p); ra.write_json(r,j); ra.write_sums('$tmp/m4')"
  expect_rc "real: a doctored build manifest (consistent checksums) is rejected" 1 "build manifest" VER "$tmp/m4" "$FP_UP"
  expect_rc "real: verify with another expected certificate is rejected" 1 "expected certificate" VER "$OUT" "$FP_OTHER"
  rm -rf "$tmp/m5"; cp -R "$OUT" "$tmp/m5"; printf 'x' >>"$tmp/m5/"*.aab
  expect_rc "real: a modified signed file (not re-signed) is rejected" 1 "differs from SHA256SUMS" VER "$tmp/m5" "$FP_UP"
fi

echo
echo "$pass passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
