#!/usr/bin/env bash
# Tests the retained-artifact tool (tool/retain_artifact.py, tool/install_age.sh, the retained mode
# of tool/check_verdict.sh) without any build, credential or network: Stage 2 of the release
# pipeline (docs/RETAINED_ARTIFACTS.md). Run by the `plan` job of build-variants.yml before every
# build, and locally.
#
#   tool/test_retained_artifacts.sh
#
# It uses synthetic APK, AAB and .xcarchive fixtures with real build manifests (tool/build_manifest.py
# create), real zip/tar handling and, when the pinned `age` is on PATH, real encryption. Without
# age, a labelled stub stands in (header + copy; it tests the logic, not the cryptography), unless
# CADENA_REQUIRE_AGE=1, which turns a missing age into a failure (CI sets it).
# What it shows:
#   - which runs retain, and for whom; that a secret key or a malformed key is refused;
#   - that a retained bundle is ciphertext only (no plaintext artifact, no secret), with checksums,
#     the build manifest and the evidence next to it, and that it describes the verified build;
#   - that tampering, a missing or an extra file, another build's evidence, a signed archive and an
#     artifact that is not the verified one are all rejected;
#   - that the key holder can unpack exactly the verified artifact (round trip).
# Exit 0 only if every check passes.
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RA="$root/tool/retain_artifact.py"
BM="$root/tool/build_manifest.py"
verdict="$root/tool/check_verdict.sh"

pass=0
failed=0
skipped=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
skip() { skipped=$((skipped + 1)); echo "skip $1"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---- age: the real one if present, else a labelled stub ---------------------------------------
AGE_BIN="$(command -v age || true)"
AGE_KEYGEN="$(command -v age-keygen || true)"
real_age=false
if [ -n "$AGE_BIN" ] && [ -n "$AGE_KEYGEN" ]; then
  real_age=true
  echo "using the real age: $("$AGE_BIN" --version 2>&1 | head -n1)"
elif [ "${CADENA_REQUIRE_AGE:-}" = 1 ]; then
  bad "age and age-keygen are required (CADENA_REQUIRE_AGE=1) but are not on PATH"
  echo; echo "$pass passed, $failed failed"; exit 1
else
  echo "NOTE: age is not installed; a STUB stands in. This tests the logic, not the cryptography."
  mkdir -p "$tmp/stub"
  cat >"$tmp/stub/age-keygen" <<'EOF'
#!/usr/bin/env bash
# TEST STUB, not cryptography.
[ "$1" = -o ] || exit 2
pub="age1$(head -c 4000 /dev/urandom | LC_ALL=C tr -dc 'qpzry9x8gf2tvdw0s3jn54khce6mua7l' | head -c 58)"
printf '# created: stub\n# public key: %s\nAGE-SECRET-KEY-1STUBSTUBSTUBSTUB\n' "$pub" >"$2"
EOF
  cat >"$tmp/stub/age" <<'EOF'
#!/usr/bin/env bash
# TEST STUB, not cryptography: "encryption" is the age header plus a copy; it records its arguments.
mode=enc; out=""; ident=""; rf=""; r=""
while [ $# -gt 1 ]; do
  case "$1" in
    -d) mode=dec; shift ;;
    -o) out="$2"; shift 2 ;;
    -i) ident="$2"; shift 2 ;;
    -R) rf="$2"; shift 2 ;;
    -r) r="$r $2"; shift 2 ;;
    --version) echo "age stub"; exit 0 ;;
    *) shift ;;
  esac
done
in="$1"
[ -n "${AGE_STUB_LOG:-}" ] && echo "$mode R=$rf r=$r" >>"$AGE_STUB_LOG"
if [ "$mode" = enc ]; then
  { printf 'age-encryption.org/v1\n'; cat "$in"; } >"$out"
else
  [ -f "$ident" ] || exit 1
  head -c 22 "$in" | grep -q '^age-encryption.org/v1' || exit 1
  tail -c +23 "$in" >"$out"
fi
EOF
  chmod +x "$tmp/stub/age" "$tmp/stub/age-keygen"
  AGE_BIN="$tmp/stub/age"; AGE_KEYGEN="$tmp/stub/age-keygen"
  export AGE_STUB_LOG="$tmp/stub.log"
fi

PACK_AGE=(--age "$AGE_BIN" --age-keygen "$AGE_KEYGEN")
RAx() { python3 -I "$RA" "$@"; }

# t NAME COMMAND...  : passes when the command succeeds
t() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
# expect_rc NAME RC FRAGMENT COMMAND... : the command exits with RC and its output contains FRAGMENT
expect_rc() {
  local name="$1" want="$2" frag="$3" out rc
  shift 3
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then bad "$name" "exit $rc (wanted $want): $out"; return; fi
  if [ -n "$frag" ] && ! grep -qF -- "$frag" <<<"$out"; then bad "$name" "output lacks '$frag': $out"; return; fi
  ok "$name"
}
# kv OUTPUT KEY
kv() { sed -n "s/^$2=//p" <<<"$1" | head -n1; }

# ---- keys -------------------------------------------------------------------------------------
mkkey() { "$AGE_KEYGEN" -o "$1" >/dev/null 2>&1; sed -n 's/^# public key: //p' "$1"; }
CUSTODIAN_KEY="$tmp/custodian.key"; CUSTODIAN_PUB="$(mkkey "$CUSTODIAN_KEY")"
OTHER_KEY="$tmp/other.key";         OTHER_PUB="$(mkkey "$OTHER_KEY")"
t "the test keys are age public keys" bash -c "[[ '$CUSTODIAN_PUB' =~ ^age1[02-9ac-hj-np-z]{58}\$ ]] && [[ '$OTHER_PUB' =~ ^age1[02-9ac-hj-np-z]{58}\$ ]]"

# ---- 1. plan: who retains, for whom -----------------------------------------------------------
empty="$tmp/recipients-empty.txt"; printf '# nothing configured\n\n' >"$empty"
one="$tmp/recipients-one.txt"; printf '# custodian\n%s\n' "$CUSTODIAN_PUB" >"$one"
plan() { RAx plan "$@"; }

out="$(plan --event push --recipients-file "$empty" 2>&1)"
t "push, no committed recipient: nothing is retained, and it says why" bash -c "[ '$(kv "$out" retain)' = false ] && [ '$(kv "$out" recipient_count)' = 0 ] && grep -q '^note=' <<<'$out'"
out="$(plan --event push --recipients-file "$one" 2>&1)"
t "push, one committed recipient: retained for that recipient" bash -c "[ '$(kv "$out" retain)' = true ] && [ '$(kv "$out" recipients)' = '$CUSTODIAN_PUB' ] && [ '$(kv "$out" source)' = committed ]"
expect_rc "a push cannot carry a retention input" 2 "cannot carry" plan --event push --retain true --recipients-file "$one"
expect_rc "a push cannot carry a recipient input" 2 "cannot carry" plan --event push --recipient "$OTHER_PUB" --recipients-file "$one"
out="$(plan --event workflow_dispatch --retain false --recipients-file "$one" 2>&1)"
t "manual run without retain: nothing is retained, no recipient is carried" bash -c "[ '$(kv "$out" retain)' = false ] && [ -z '$(kv "$out" recipients)' ]"
out="$(plan --event workflow_dispatch --retain true --recipient "$OTHER_PUB" --recipients-file "$empty" 2>&1)"
t "manual run, retain and a public key given: retained for that key" bash -c "[ '$(kv "$out" retain)' = true ] && [ '$(kv "$out" recipients)' = '$OTHER_PUB' ] && [ '$(kv "$out" source)' = input ]"
out="$(plan --event workflow_dispatch --retain true --recipient "$OTHER_PUB" --recipients-file "$one" 2>&1)"
t "manual run: the committed and the given key are both recipients" bash -c "[ '$(kv "$out" recipient_count)' = 2 ] && [ '$(kv "$out" source)' = committed+input ]"
expect_rc "retain without any recipient is refused (it would be unreadable)" 2 "no recipient" plan --event workflow_dispatch --retain true --recipients-file "$empty"
expect_rc "a recipient without retain is refused" 2 "retention was not requested" plan --event workflow_dispatch --retain false --recipient "$OTHER_PUB" --recipients-file "$one"
expect_rc "a secret key as the recipient input is refused" 2 "SECRET" plan --event workflow_dispatch --retain true --recipient "AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ" --recipients-file "$empty"
expect_rc "a malformed recipient is refused" 2 "not an age X25519 public key" plan --event workflow_dispatch --retain true --recipient "age1short" --recipients-file "$empty"
printf '%s\nAGE-SECRET-KEY-1QQQQ\n' "$CUSTODIAN_PUB" >"$tmp/recipients-secret.txt"
expect_rc "a secret key in the recipients file is refused" 2 "SECRET" plan --event push --recipients-file "$tmp/recipients-secret.txt"
printf 'ssh-ed25519 AAAA\n' >"$tmp/recipients-ssh.txt"
expect_rc "a recipients file with another kind of line is refused" 2 "not an age X25519 public key" plan --event push --recipients-file "$tmp/recipients-ssh.txt"
expect_rc "an unsupported event is refused" 2 "unsupported event" plan --event pull_request --recipients-file "$empty"
expect_rc "a missing recipients file is refused (fail closed)" 2 "cannot read" plan --event push --recipients-file "$tmp/nope.txt"
expect_rc "the committed recipients file parses (empty or public keys only)" 0 "retain=" plan --event push --recipients-file "$root/config/release/artifact_recipients.txt"
t "the committed recipients file holds no secret key" bash -c "! grep -q 'AGE-SECRET-KEY' '$root/config/release/artifact_recipients.txt'"

wr="$tmp/written.txt"
expect_rc "write-recipients writes validated, de-duplicated keys" 0 "1 recipient" RAx write-recipients --list "$CUSTODIAN_PUB,$CUSTODIAN_PUB" --out "$wr"
t "the written recipients file is a plain list of the key" bash -c "[ \"\$(grep -v '^#' '$wr')\" = '$CUSTODIAN_PUB' ]"
expect_rc "write-recipients refuses a bad key" 2 "not an age X25519" RAx write-recipients --list "$CUSTODIAN_PUB,junk" --out "$tmp/w2.txt"

# ---- 2. fixtures: synthetic builds with real manifests --------------------------------------------
fx="$tmp/fx"
cat >"$tmp/mkfix.py" <<'PY'
import hashlib, json, os, plistlib, shutil, subprocess, sys, zipfile
root, out = sys.argv[1], sys.argv[2]
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(root, "tool"))
import build_manifest as bm

COMMIT = "7b63c9791fccc8f9711ed853e2294967899be972"
RUN = "39237471969"
Z = "0" * 64
pubspec, name, build = bm.load_pubspec(root)
cfg_sha = {e: bm.sha256_file(os.path.join(root, "config/build/%s.json" % e)) for e in ("staging", "production")}

def sha(b): return hashlib.sha256(b).hexdigest()

def make_zip(path, entries, signer=b"SIGNER-A"):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, data in entries.items():
            z.writestr(n, data)
        z.writestr("META-INF/MANIFEST.MF", b"Manifest-Version: 1.0\n" + signer)
        z.writestr("META-INF/CERT.SF", b"Signature-Version: 1.0\n" + signer)
        z.writestr("META-INF/CERT.RSA", b"\x30\x82" + signer)

def write_ev(d, variant, lines):
    with open(os.path.join(d, variant + ".txt"), "w") as f:
        f.write("".join("%s=%s\n" % kv for kv in lines))

def common(variant, env, app_id, bname, kind_cmd):
    return [
        ("variant", variant),
        ("build_command", "flutter build %s --release --flavor %s --dart-define-from-file=config/build/%s.json" % (kind_cmd, env, env)),
        ("config_file", "config/build/%s.json" % env),
        ("config_file_sha256", cfg_sha[env]),
        ("commit", COMMIT), ("ref", env),
        ("run", "https://github.com/CadenaBitcoin/signer_app/actions/runs/%s (attempt 1)" % RUN),
    ]

def tail(env, app_id, dname):
    return [("environment", env), ("application_id", app_id), ("display_name", dname),
            ("version_name", name), ("version_code", str(build)), ("distributable", "no"),
            ("environment_check", "%s-url-present-other-absent" % env), ("environment_check_snapshots", "3")]

def create_manifest(d, variant, toolchain):
    with open(os.path.join(d, variant + ".toolchain"), "w") as f:
        f.write(toolchain)
    env = dict(os.environ, GITHUB_RUN_ID=RUN, GITHUB_RUN_ATTEMPT="1", GITHUB_SERVER_URL="https://github.com",
               GITHUB_REPOSITORY="CadenaBitcoin/signer_app", GITHUB_SHA=COMMIT, GITHUB_REF_NAME=("staging" if "staging" in variant else "production"),
               GITHUB_REF_TYPE="branch", GITHUB_EVENT_NAME="push", GITHUB_WORKFLOW="Build variants (compile validation)")
    subprocess.run([sys.executable, "-I", os.path.join(root, "tool", "build_manifest.py"), "create", "--evidence", os.path.join(d, variant + ".txt"),
                    "--toolchain", os.path.join(d, variant + ".toolchain"), "--out", os.path.join(d, variant + ".manifest.json")],
                   check=True, stdout=subprocess.DEVNULL, env=env)

ANDROID_TC = "flutter=Flutter 3.35.3 • channel stable\ndart=3.9.2\njava=openjdk version \"17.0.10\"\nrunner_image=ubuntu24 20260101.1\nandroid_build_tools=36.0.0\n"
IOS_TC = "runner_image=macos15 20260101.1\nrunner_arch=arm64\nxcode=26.3 (17C529)\niphoneos_sdk=26.2\nflutter=3.35.3 (revision a402d9a437)\ndart=3.9.2\ncocoapods=1.17.0\n"

def android(variant, kind, env):
    d = os.path.join(out, variant); os.makedirs(d)
    fname = "app-%s-release.%s" % (env, kind)
    path = os.path.join(d, fname)
    make_zip(path, {"AndroidManifest.xml": b"<manifest/>", "classes.dex": b"dex-" + variant.encode(), "resources.arsc": b"res",
                    "META-INF/services/x": b"service"})
    data = open(path, "rb").read()
    app_id = "com.cadenabitcoin.mobile.signer" + (".staging" if env == "staging" else "")
    lines = common(variant, env, app_id, "", "apk" if kind == "apk" else "appbundle")
    lines += [("artifact_kind", kind), ("artifact_file", fname), ("artifact_sha256", sha(data)), ("artifact_bytes", str(len(data))),
              ("signing", "debug"), ("signer_dn", "C=US, O=Android, CN=Android Debug"), ("signer_cert_sha256", Z),
              ("native_lib_sha256.arm64-v8a", Z)]
    lines += tail(env, app_id, "Cadena Signer STAGING" if env == "staging" else "Cadena Bitcoin")
    write_ev(d, variant, lines)
    create_manifest(d, variant, ANDROID_TC)

def ios_app(app, version, build_no, bundle_id, exe=b"MACHO-EXE", extra=None):
    os.makedirs(os.path.join(app, "Frameworks", "App.framework"))
    with open(os.path.join(app, "Info.plist"), "wb") as f:
        plistlib.dump({"CFBundleIdentifier": bundle_id, "CFBundleShortVersionString": version, "CFBundleVersion": str(build_no)}, f)
    with open(os.path.join(app, "Runner"), "wb") as f: f.write(exe)
    os.chmod(os.path.join(app, "Runner"), 0o755)
    with open(os.path.join(app, "Frameworks", "App.framework", "App"), "wb") as f: f.write(b"AOT-SNAPSHOT" + (extra or b""))

def ios_evidence(app, extra=None):
    snap = sha(open(os.path.join(app, "Frameworks", "App.framework", "App"), "rb").read())
    exe = sha(open(os.path.join(app, "Runner"), "rb").read())
    return [("artifact_sha256", bm.tree_digest(app)), ("app_snapshot_sha256", snap), ("executable_sha256", exe),
            ("minimum_os_version", "14.0"), ("executable_archs", "arm64"), ("signing", "unsigned"),
            ("environment", "production"), ("application_id", "com.app.cadenabitcoin"), ("display_name", "Cadena Bitcoin"),
            ("version_name", name), ("version_code", str(build))]

def ios(variant, env):
    d = os.path.join(out, variant); os.makedirs(d)
    bundle = "com.app.cadenabitcoin" + (".staging" if env == "staging" else "")
    dname = "Cadena Signer STAGING" if env == "staging" else "Cadena Bitcoin"
    # the validated build (flutter build ios): Runner.app
    built = os.path.join(d, "built", "Runner.app")
    ios_app(built, name, build, bundle)
    ev = common(variant, env, bundle, "", "ios")
    ev[1] = ("build_command", "flutter build ios --release --no-codesign --flavor %s --dart-define-from-file=config/build/%s.json" % (env, env))
    ev += [("podfile_lock_drift", "no"), ("rust_lib_sha256", Z), ("artifact_kind", "ios-app"), ("artifact_file", "Runner.app"),
           ("artifact_sha256_basis", "sha256 of the sorted per-file sha256 manifest of the .app directory"), ("artifact_bytes", "12KiB")]
    base = dict(ios_evidence(built))
    ev += [("artifact_sha256", base["artifact_sha256"]), ("app_snapshot_sha256", base["app_snapshot_sha256"]),
           ("executable_sha256", base["executable_sha256"]), ("minimum_os_version", "14.0"), ("executable_archs", "arm64"),
           ("signing", "unsigned")]
    ev += tail(env, bundle, dname)
    write_ev(d, variant, ev)
    create_manifest(d, variant, IOS_TC)
    # the unsigned archive of the same build (flutter build ipa --no-codesign); identical application
    for label, exe in (("same", b"MACHO-EXE"), ("rebuilt", b"MACHO-EXE-REBUILT")):
        arch = os.path.join(d, label, "Runner.xcarchive")
        app = os.path.join(arch, "Products", "Applications", "Runner.app")
        ios_app(app, name, build, bundle, exe=exe)
        os.makedirs(os.path.join(arch, "dSYMs", "Runner.app.dSYM"))
        with open(os.path.join(arch, "dSYMs", "Runner.app.dSYM", "sym"), "wb") as f: f.write(b"dsym")
        with open(os.path.join(arch, "Info.plist"), "wb") as f:
            plistlib.dump({"ApplicationProperties": {"ApplicationPath": "Applications/Runner.app"}}, f)
        with open(os.path.join(d, label + ".archive-evidence.txt"), "w") as f:
            f.write("".join("%s=%s\n" % kv for kv in ios_evidence(app)))

android("android-production-apk", "apk", "production")
android("android-production-aab", "aab", "production")
android("android-staging-apk", "apk", "staging")
ios("ios-production", "production")
print("fixtures ready")
PY
if python3 -I "$tmp/mkfix.py" "$root" "$fx" >"$tmp/mkfix.log" 2>&1; then ok "fixtures: three Android builds and an iOS build, with real build manifests"; else bad "fixtures could not be created" "$(tail -n 8 "$tmp/mkfix.log")"; echo; echo "$pass passed, $failed failed"; exit 1; fi

REC="$tmp/recipients.txt"; printf '%s\n' "$CUSTODIAN_PUB" >"$REC"
# the artifact file name carries the environment: app-production-release.apk / .aab, app-staging-release.apk
pack_apk() { local v="$1" o="$2"; shift 2; RAx pack --variant "$v" --kind apk --artifact "$fx/$v/app-$( [[ $v == *staging* ]] && echo staging || echo production )-release.apk" --evidence "$fx/$v/$v.txt" --manifest "$fx/$v/$v.manifest.json" --recipients "$REC" --out "$o" "${PACK_AGE[@]}" "$@"; }
pack_aab() { local v=android-production-aab o="$1"; shift; RAx pack --variant $v --kind aab --artifact "$fx/$v/app-production-release.aab" --evidence "$fx/$v/$v.txt" --manifest "$fx/$v/$v.manifest.json" --recipients "$REC" --out "$o" "${PACK_AGE[@]}" "$@"; }
pack_ios() { # LABEL(same|rebuilt) OUT [extra]
  local l="$1" o="$2"; shift 2
  RAx pack --variant ios-production --kind ios-xcarchive --artifact "$fx/ios-production/$l/Runner.xcarchive" --archive-evidence "$fx/ios-production/$l.archive-evidence.txt" \
    --evidence "$fx/ios-production/ios-production.txt" --manifest "$fx/ios-production/ios-production.manifest.json" --recipients "$REC" --out "$o" "${PACK_AGE[@]}" "$@"
}

# ---- 3. Android APK and AAB -----------------------------------------------------------------------
apk="$tmp/out-apk"
expect_rc "pack: the production APK is retained" 0 "RESULT: OK" pack_apk android-production-apk "$apk"
t "the APK bundle holds exactly: ciphertext, retained manifest, build manifest, evidence, SHA256SUMS" bash -c "[ \"\$(ls '$apk' | wc -l | tr -d ' ')\" = 5 ] && ls '$apk' | grep -q '\.age\$' && ls '$apk' | grep -q 'retained.json\$' && [ -f '$apk/SHA256SUMS' ]"
plain_sha="$(sha256sum "$fx/android-production-apk/app-production-release.apk" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$fx/android-production-apk/app-production-release.apk" | cut -d' ' -f1)"
t "no file of the bundle is the plaintext APK (checked by SHA-256)" bash -c "for f in '$apk'/*; do s=\$( (sha256sum \"\$f\" 2>/dev/null || shasum -a 256 \"\$f\") | cut -d' ' -f1); [ \"\$s\" != '$plain_sha' ] || exit 1; done"
t "the ciphertext starts with the age header" bash -c "head -c 21 '$apk'/*.age | grep -q 'age-encryption.org/v1'"
t "the ciphertext file name is the labelled canonical name plus .age" bash -c "ls '$apk' | grep -qE '^NON-DISTRIBUTABLE_INTERNAL-EVALUATION_cadena-signer-production-.*-android-apk-7b63c97-run39237471969\.1\.apk\.age\$'"
t "SHA256SUMS verifies with sha256sum/shasum" bash -c "cd '$apk' && (sha256sum -c SHA256SUMS >/dev/null 2>&1 || shasum -a 256 -c SHA256SUMS >/dev/null 2>&1)"
t "the retained manifest records the commit, version, configuration and a verified round trip" python3 -I -c "
import json,glob,sys
r=json.load(open(glob.glob('$apk/*.retained.json')[0]))
assert r['source']['commit']=='7b63c9791fccc8f9711ed853e2294967899be972', r['source']
assert r['version']['build']>0 and r['application']['id']=='com.cadenabitcoin.mobile.signer'
assert len(r['configuration']['sha256'])==64 and r['encryption']['round_trip_verified'] is True
assert r['artifact']['plaintext']['sha256']=='$plain_sha' and r['signing']['distributable'] is False
assert r['artifact']['content']['digest_kind']=='zip-entries-without-signature-files'
"
expect_rc "verify without a key: the bundle is consistent" 0 "RESULT: OK" RAx verify "$apk" --repo "$root" --against "$fx/android-production-apk" --age "$AGE_BIN"
expect_rc "verify with the custodian's key: the plaintext is the verified artifact" 0 "plaintext verified" RAx verify "$apk" --identity "$CUSTODIAN_KEY" --age "$AGE_BIN"
if $real_age; then
  expect_rc "verify with another key: the artifact cannot be read" 1 "FAIL" RAx verify "$apk" --identity "$OTHER_KEY" --age "$AGE_BIN"
else
  skip "verify with another key (needs the real age)"
fi
out_unpack="$tmp/unpacked-apk"
expect_rc "unpack writes the labelled APK" 0 "unpacked:" RAx unpack "$apk" --identity "$CUSTODIAN_KEY" --out "$out_unpack" --age "$AGE_BIN"
t "the unpacked APK is byte-identical to the verified one" bash -c "cmp -s '$fx/android-production-apk/app-production-release.apk' '$out_unpack'/NON-DISTRIBUTABLE_INTERNAL-EVALUATION_*.apk"
aab="$tmp/out-aab"
expect_rc "pack: the production AAB is retained" 0 "RESULT: OK" pack_aab "$aab"
expect_rc "pack: the staging APK is retained" 0 "RESULT: OK" pack_apk android-staging-apk "$tmp/out-stg"
if $real_age; then
  skip "the encryption arguments (recorded by the stub only)"
else
  t "the stub recorded -R (recipients file) and -r (the one-time key) for every encryption" bash -c "[ \"\$(grep -c '^enc R=.* r= age1' '$AGE_STUB_LOG')\" -ge 3 ]"
fi

# the content digest does not change with the signature, and does with the content
t "content digest: the same entries signed differently give the same digest; another content does not" python3 -I -c "
import sys,zipfile,os
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import retain_artifact as r
def mk(p, extra, signer):
    with zipfile.ZipFile(p,'w') as z:
        z.writestr('AndroidManifest.xml', b'm'); z.writestr('classes.dex', b'dex'+extra)
        z.writestr('META-INF/MANIFEST.MF', b'x'+signer); z.writestr('META-INF/UPLOAD.SF', b's'+signer); z.writestr('META-INF/UPLOAD.RSA', b'r'+signer)
        z.writestr('META-INF/services/keep', b'kept')
a=r.zip_content_digest(('$tmp/d1.zip', mk('$tmp/d1.zip', b'', b'debug'))[0])
b=r.zip_content_digest(('$tmp/d2.zip', mk('$tmp/d2.zip', b'', b'upload-key'))[0])
c=r.zip_content_digest(('$tmp/d3.zip', mk('$tmp/d3.zip', b'!', b'debug'))[0])
assert a==b and a!=c, (a,b,c)
"

# ---- 4. iOS archive -----------------------------------------------------------------------------------
ios="$tmp/out-ios"
expect_rc "pack: the unsigned iOS archive is retained" 0 "RESULT: OK" pack_ios same "$ios"
t "the iOS bundle holds exactly five files, the ciphertext is an .xcarchive.tar.gz.age" bash -c "[ \"\$(ls '$ios' | wc -l | tr -d ' ')\" = 5 ] && ls '$ios' | grep -qE 'ios-xcarchive-.*\.xcarchive\.tar\.gz\.age\$'"
t "the retained manifest records an application bit-identical to the validated build" python3 -I -c "
import json,glob
r=json.load(open(glob.glob('$ios/*.retained.json')[0]))
c=r['artifact']['correspondence_to_validated_build']
assert c['identity_and_version_equal'] and c['app_directory_sha256_equal'] and c['executable_sha256_equal'] and c['app_snapshot_sha256_equal'], c
assert r['artifact']['content']['digest_kind']=='directory-manifest' and r['signing']['status']=='unsigned'
"
expect_rc "verify (no key) of the iOS bundle" 0 "RESULT: OK" RAx verify "$ios" --repo "$root" --against "$fx/ios-production" --age "$AGE_BIN"
expect_rc "verify with the key: the archive's application matches the manifest" 0 "plaintext verified" RAx verify "$ios" --identity "$CUSTODIAN_KEY" --age "$AGE_BIN"
out_ios="$tmp/unpacked-ios"
expect_rc "unpack writes Runner.xcarchive" 0 "Runner.xcarchive" RAx unpack "$ios" --identity "$CUSTODIAN_KEY" --out "$out_ios" --age "$AGE_BIN"
t "the unpacked archive has the application and the dSYMs, and the same application digest" python3 -I -c "
import sys,os
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import build_manifest as bm
a=bm.tree_digest('$out_ios/Runner.xcarchive/Products/Applications/Runner.app')
b=bm.tree_digest('$fx/ios-production/same/Runner.xcarchive/Products/Applications/Runner.app')
assert a==b, (a,b)
assert os.path.isfile('$out_ios/Runner.xcarchive/dSYMs/Runner.app.dSYM/sym')
assert os.access('$out_ios/Runner.xcarchive/Products/Applications/Runner.app/Runner', os.X_OK)
"
t "the archive is deterministic: packing the same tree twice gives the same plaintext digest" bash -c "
python3 -I -c \"
import sys
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import retain_artifact as r
r.deterministic_tar_gz('$fx/ios-production/same/Runner.xcarchive','Runner.xcarchive','$tmp/t1.tgz'); r.deterministic_tar_gz('$fx/ios-production/same/Runner.xcarchive','Runner.xcarchive','$tmp/t2.tgz')\" && cmp -s '$tmp/t1.tgz' '$tmp/t2.tgz'"
# a rebuilt application: allowed and recorded as not identical, unless identity is demanded
expect_rc "pack: a rebuilt archive application is recorded as not bit-identical" 0 "RESULT: OK" pack_ios rebuilt "$tmp/out-ios-rebuilt"
t "the correspondence records the difference honestly" python3 -I -c "
import json,glob
c=json.load(open(glob.glob('$tmp/out-ios-rebuilt/*.retained.json')[0]))['artifact']['correspondence_to_validated_build']
assert c['identity_and_version_equal'] is True and c['executable_sha256_equal'] is False, c
"
expect_rc "pack --require-identical refuses a rebuilt application" 2 "not bit-identical" pack_ios rebuilt "$tmp/out-ios-req" --require-identical

# ---- 5. refusals at pack time --------------------------------------------------------------------------
cp "$fx/android-production-apk/app-production-release.apk" "$tmp/other.apk"
printf 'x' >>"$tmp/other.apk"
expect_rc "pack refuses an artifact that is not the one whose evidence was recorded" 2 "not the file whose verification evidence" \
  RAx pack --variant android-production-apk --kind apk --artifact "$tmp/other.apk" --evidence "$fx/android-production-apk/android-production-apk.txt" --manifest "$fx/android-production-apk/android-production-apk.manifest.json" --recipients "$REC" --out "$tmp/o1" "${PACK_AGE[@]}"
expect_rc "pack refuses the wrong kind for a variant" 2 "is retained as" \
  RAx pack --variant android-production-apk --kind aab --artifact "$fx/android-production-apk/app-production-release.apk" --evidence "$fx/android-production-apk/android-production-apk.txt" --manifest "$fx/android-production-apk/android-production-apk.manifest.json" --recipients "$REC" --out "$tmp/o2" "${PACK_AGE[@]}"
: >"$tmp/norecips.txt"
expect_rc "pack refuses to run without a recipient" 2 "no recipient" \
  RAx pack --variant android-production-apk --kind apk --artifact "$fx/android-production-apk/app-production-release.apk" --evidence "$fx/android-production-apk/android-production-apk.txt" --manifest "$fx/android-production-apk/android-production-apk.manifest.json" --recipients "$tmp/norecips.txt" --out "$tmp/o3" "${PACK_AGE[@]}"
mkdir -p "$tmp/o4" && : >"$tmp/o4/leftover"
expect_rc "pack refuses a non-empty output directory" 2 "not empty" pack_apk android-production-apk "$tmp/o4"
expect_rc "pack refuses an iOS archive without its evidence" 2 "--archive-evidence is required" \
  RAx pack --variant ios-production --kind ios-xcarchive --artifact "$fx/ios-production/same/Runner.xcarchive" --evidence "$fx/ios-production/ios-production.txt" --manifest "$fx/ios-production/ios-production.manifest.json" --recipients "$REC" --out "$tmp/o5" "${PACK_AGE[@]}"
sed 's/^version_name=.*/version_name=9.9.9/' "$fx/ios-production/same.archive-evidence.txt" >"$tmp/ios-wrong-version.txt"
expect_rc "pack refuses an archive whose application has another version than the validated build" 2 "version_name differs" \
  RAx pack --variant ios-production --kind ios-xcarchive --artifact "$fx/ios-production/same/Runner.xcarchive" --archive-evidence "$tmp/ios-wrong-version.txt" --evidence "$fx/ios-production/ios-production.txt" --manifest "$fx/ios-production/ios-production.manifest.json" --recipients "$REC" --out "$tmp/o6" "${PACK_AGE[@]}"
cp -R "$fx/ios-production/same/Runner.xcarchive" "$tmp/tampered.xcarchive"
printf 'x' >>"$tmp/tampered.xcarchive/Products/Applications/Runner.app/Runner"
expect_rc "pack refuses an archive whose application is not the one whose evidence was recorded" 2 "not the one whose verification evidence" \
  RAx pack --variant ios-production --kind ios-xcarchive --artifact "$tmp/tampered.xcarchive" --archive-evidence "$fx/ios-production/same.archive-evidence.txt" --evidence "$fx/ios-production/ios-production.txt" --manifest "$fx/ios-production/ios-production.manifest.json" --recipients "$REC" --out "$tmp/o7" "${PACK_AGE[@]}"
cp "$fx/ios-production/ios-production.manifest.json" "$tmp/bad.manifest.json"
python3 -I -c "
import json
m=json.load(open('$tmp/bad.manifest.json')); m['signing']['status']='debug'; json.dump(m,open('$tmp/bad.manifest.json','w'))"
expect_rc "pack refuses a manifest that does not verify" 2 "does not verify" \
  RAx pack --variant ios-production --kind ios-xcarchive --artifact "$fx/ios-production/same/Runner.xcarchive" --archive-evidence "$fx/ios-production/same.archive-evidence.txt" --evidence "$fx/ios-production/ios-production.txt" --manifest "$tmp/bad.manifest.json" --recipients "$REC" --out "$tmp/o8" "${PACK_AGE[@]}"
# a signed archive: the digest evidence matches (it is computed over what is there), but it must not be retained as unsigned
cp -R "$fx/ios-production/same/Runner.xcarchive" "$tmp/signed.xcarchive"
mkdir -p "$tmp/signed.xcarchive/Products/Applications/Runner.app/_CodeSignature" && printf 'sig' >"$tmp/signed.xcarchive/Products/Applications/Runner.app/_CodeSignature/CodeResources"
python3 -I -c "
import sys
sys.dont_write_bytecode=True
sys.path.insert(0,'$root/tool'); import build_manifest as bm
d=bm.tree_digest('$tmp/signed.xcarchive/Products/Applications/Runner.app')
t=open('$fx/ios-production/same.archive-evidence.txt').read().splitlines()
open('$tmp/signed-evidence.txt','w').write(''.join(('artifact_sha256='+d if l.startswith('artifact_sha256=') else l)+'\n' for l in t))"
RAx pack --variant ios-production --kind ios-xcarchive --artifact "$tmp/signed.xcarchive" --archive-evidence "$tmp/signed-evidence.txt" --evidence "$fx/ios-production/ios-production.txt" --manifest "$fx/ios-production/ios-production.manifest.json" --recipients "$REC" --out "$tmp/out-signed" "${PACK_AGE[@]}" >/dev/null 2>&1
expect_rc "a signed archive packs but is rejected when the key holder verifies it" 1 "must be unsigned" RAx verify "$tmp/out-signed" --identity "$CUSTODIAN_KEY" --age "$AGE_BIN"

# ---- 6. tampering with a bundle ---------------------------------------------------------------------------
clone() { rm -rf "$2"; cp -R "$1" "$2"; }
clone "$apk" "$tmp/b1"; printf 'extra' >>"$tmp/b1/"*.age
expect_rc "verify rejects a modified ciphertext" 1 "differs" RAx verify "$tmp/b1" --age "$AGE_BIN"
clone "$apk" "$tmp/b2"; cp "$fx/android-production-apk/app-production-release.apk" "$tmp/b2/plain.apk"
expect_rc "verify rejects a bundle with an extra file (a plaintext APK)" 1 "expected exactly" RAx verify "$tmp/b2" --age "$AGE_BIN"
clone "$apk" "$tmp/b3"; rm "$tmp/b3/SHA256SUMS"
expect_rc "verify rejects a missing SHA256SUMS" 1 "expected exactly" RAx verify "$tmp/b3" --age "$AGE_BIN"
clone "$apk" "$tmp/b4"; sed -i.bak 's/^[0-9a-f]\{4\}/0000/' "$tmp/b4/SHA256SUMS"; rm -f "$tmp/b4/SHA256SUMS.bak"
expect_rc "verify rejects a SHA256SUMS that does not match the files" 1 "differs from SHA256SUMS" RAx verify "$tmp/b4" --age "$AGE_BIN"
clone "$apk" "$tmp/b5"; cp "$fx/android-production-apk/app-production-release.apk" "$tmp/b5/$(ls "$tmp/b5" | grep '\.age$')"
( cd "$tmp/b5" && rm SHA256SUMS && for f in $(ls); do printf '%s  %s\n' "$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | cut -d' ' -f1)" "$f"; done >SHA256SUMS )
expect_rc "verify rejects a plaintext artifact under the .age name (no age header)" 1 "no age header" RAx verify "$tmp/b5" --age "$AGE_BIN"
clone "$apk" "$tmp/b6"; echo "note=AGE-SECRET-KEY-1AAAA" >>"$tmp/b6/android-production-apk.txt"
( cd "$tmp/b6" && rm SHA256SUMS && for f in $(ls); do printf '%s  %s\n' "$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | cut -d' ' -f1)" "$f"; done >SHA256SUMS )
expect_rc "verify rejects a secret key marker anywhere in the bundle" 1 "secret key marker" RAx verify "$tmp/b6" --age "$AGE_BIN"
clone "$apk" "$tmp/b7"
python3 -I -c "
import json,glob
p=glob.glob('$tmp/b7/*.retained.json')[0]; r=json.load(open(p)); r['source']['commit']='0'*40; json.dump(r,open(p,'w'),indent=2)"
( cd "$tmp/b7" && rm SHA256SUMS && for f in $(ls); do printf '%s  %s\n' "$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | cut -d' ' -f1)" "$f"; done >SHA256SUMS )
expect_rc "verify rejects a retained manifest that names another commit than the build manifest" 1 "source.commit" RAx verify "$tmp/b7" --age "$AGE_BIN"
expect_rc "verify rejects evidence that differs from the verified build's evidence" 1 "differs from the verified build evidence" RAx verify "$apk" --against "$fx/android-production-aab" --age "$AGE_BIN"
clone "$apk" "$tmp/b8"
python3 -I -c "
import json,glob
p=glob.glob('$tmp/b8/*.retained.json')[0]; r=json.load(open(p)); r['encryption']['round_trip_verified']=False; json.dump(r,open(p,'w'),indent=2)"
( cd "$tmp/b8" && rm SHA256SUMS && for f in $(ls); do printf '%s  %s\n' "$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | cut -d' ' -f1)" "$f"; done >SHA256SUMS )
expect_rc "verify rejects a bundle without a successful round trip" 1 "round trip" RAx verify "$tmp/b8" --age "$AGE_BIN"
clone "$apk" "$tmp/b9"; mv "$tmp/b9/android-production-apk.retained.json" "$tmp/b9/android-production-aab.retained.json"
expect_rc "verify rejects a manifest filed under another variant's name" 1 "FAIL" RAx verify "$tmp/b9" --age "$AGE_BIN"
if $real_age; then
  clone "$apk" "$tmp/b10"
  python3 -I -c "
import glob
p=glob.glob('$tmp/b10/*.age')[0]; b=bytearray(open(p,'rb').read()); b[-5]^=0xff; open(p,'wb').write(bytes(b))"
  expect_rc "verify without a key rejects a bit flip (checksum)" 1 "differs" RAx verify "$tmp/b10" --age "$AGE_BIN"
  python3 -I -c "
import glob,json,hashlib
d='$tmp/b10/'
c=glob.glob(d+'*.age')[0]
r=glob.glob(d+'*.retained.json')[0]
m=json.load(open(r)); m['encryption']['ciphertext']['sha256']=hashlib.sha256(open(c,'rb').read()).hexdigest(); json.dump(m,open(r,'w'),indent=2)"
  ( cd "$tmp/b10" && rm SHA256SUMS && for f in $(ls); do printf '%s  %s\n' "$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | cut -d' ' -f1)" "$f"; done >SHA256SUMS )
  expect_rc "even with consistent checksums, age's authentication rejects a modified ciphertext" 1 "age decrypt failed" RAx verify "$tmp/b10" --identity "$CUSTODIAN_KEY" --age "$AGE_BIN"
else
  skip "age's authentication of a modified ciphertext (needs the real age)"
fi

# ---- 7. the verdict's retained mode ---------------------------------------------------------------------------
vd="$tmp/vd"; mkdir -p "$vd/retained_android-production-apk_a1" "$vd/retained_ios-production_a1"
: >"$vd/retained_android-production-apk_a1/f"; : >"$vd/retained_ios-production_a1/f"
env_v() { REQUIRED_VARIANTS="android-production-apk ios-production" RUN_ATTEMPT=1 "$verdict" retained "$1"; }
expect_rc "verdict retained: exactly the required bundles pass" 0 "" env_v "$vd"
rm -rf "$tmp/vd2"; cp -R "$vd" "$tmp/vd2"; rm -rf "$tmp/vd2/retained_ios-production_a1"
expect_rc "verdict retained: a missing bundle fails" 1 "Missing retained artifact" env_v "$tmp/vd2"
rm -rf "$tmp/vd3"; cp -R "$vd" "$tmp/vd3"; mkdir "$tmp/vd3/retained_android-staging-apk_a1"
expect_rc "verdict retained: a bundle of a variant that was not required fails" 1 "Unexpected retained entry" env_v "$tmp/vd3"
rm -rf "$tmp/vd4"; cp -R "$vd" "$tmp/vd4"; mkdir "$tmp/vd4/retained_ios-production_a2"
expect_rc "verdict retained: a bundle of another attempt fails" 1 "Unexpected retained entry" env_v "$tmp/vd4"
rm -rf "$tmp/vd5"; cp -R "$vd" "$tmp/vd5"; rm "$tmp/vd5/retained_ios-production_a1/f"
expect_rc "verdict retained: an empty bundle fails" 1 "Missing retained artifact" env_v "$tmp/vd5"

# ---- 8. the pinned installer ---------------------------------------------------------------------------------
pins="$("$root/tool/install_age.sh" --print-pins)"
t "install_age pins a version and two SHA-256 digests" bash -c "grep -q '^AGE_VERSION=[0-9]' <<<'$pins' && [ \"\$(grep -cE '^AGE_SHA256_.*=[0-9a-f]{64}\$' <<<'$pins')\" = 2 ]"
t "install_age downloads only from the project's release URL and compares the digest before use" bash -c "grep -q 'github.com/FiloSottile/age/releases/download/v\${AGE_VERSION}' '$root/tool/install_age.sh' && grep -q 'Refusing to use it' '$root/tool/install_age.sh'"
t "tool/test_retained_artifacts and install_age are valid bash" bash -c "bash -n '$root/tool/install_age.sh' && bash -n '$root/tool/test_retained_artifacts.sh' && bash -n '$verdict'"

echo
echo "$pass passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
