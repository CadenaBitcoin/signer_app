#!/usr/bin/env bash
# Tests for the Android release-signing configuration and the release verification (Issue #72).
#
#   tool/test_android_release.sh
#
# Always runs (no Android SDK needed): the static checks of android/app/build.gradle.kts, the ledgers,
# the ELF reader, the fingerprint rules, the release driver's refusals and the credential-free state of
# the CI workflows.
#
# Runs when real artifacts are supplied (any APK and AAB built from this repository, in any signing):
#   REAL_APK=/path/app.apk REAL_AAB=/path/app.aab ANDROID_HOME=... BUNDLETOOL_JAR=... JAVA_HOME=<jdk17> \
#     tool/test_android_release.sh
# The artifacts are re-signed with DISPOSABLE keys created here, so the verifier is exercised on the real
# structure of a release (signatures, ABIs, native libraries, alignment) without any real credential.
#
# Runs the whole release procedure (two real Flutter builds, minutes) when ANDROID_RELEASE_E2E=1.
#
# No real key, keystore or password is read, created or needed. Disposable keys live in a temporary
# directory that is deleted at the end.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cadena-android-release-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0
failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
t() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
has() { grep -qF -- "$2" <<<"$1"; }
hasnt() { ! grep -qF -- "$2" <<<"$1"; }
eq() { [ "$1" = "$2" ]; }
VAR="$root/tool/verify_android_release.py"
V() { python3 -I "$VAR" "$@"; }
# expect_rc NAME RC FRAGMENT CMD...: the command exits with RC and its output contains FRAGMENT
expect_rc() {
  local name="$1" rc="$2" frag="$3" out status; shift 3
  out="$("$@" 2>&1)"; status=$?
  if [ "$status" -eq "$rc" ] && grep -qF -- "$frag" <<<"$out"; then ok "$name"; else bad "$name" "exit $status (wanted $rc); wanted '$frag' in: $(printf '%s' "$out" | tail -n 4 | cut -c1-240 | tr '\n' '|')"; fi
}

# ---------------------------------------------------------------------------------------------
# 1. build.gradle.kts: release signing is explicit, external and fail-closed (static)
# ---------------------------------------------------------------------------------------------
G="$root/android/app/build.gradle.kts"
gradle_text="$(cat "$G")"
t "gradle: the signing mode comes from CADENA_SIGNING" has "$gradle_text" 'System.getenv("CADENA_SIGNING")'
t "gradle: an unknown signing mode fails the build" has "$gradle_text" "refusing to guess a signing mode"
t "gradle: incomplete release credentials fail the build and name the missing items" has "$gradle_text" "signing credentials are incomplete"
t "gradle: the failure says there is no fallback to the debug key" has "$gradle_text" "does not fall back to the debug key"
t "gradle: the expected certificate fingerprint is required" has "$gradle_text" "CADENA_EXPECTED_CERT_SHA256"
t "gradle: the keystore certificate is compared with the expected one before signing" has "$gradle_text" "does not match the expected one. Expected SHA-256"
t "gradle: keystore and properties must be outside the repository" has "$gradle_text" "must be outside the repository directory"
t "gradle: the debug key is referenced exactly once (the validation branch)" eq "$(grep -c 'signingConfigs.getByName("debug")' "$G")" 1
t "gradle: that reference is in the validation branch of one conditional" has "$gradle_text" 'if (cadenaSigningMode == "release") signingConfigs.getByName("cadenaRelease") else signingConfigs.getByName("debug")'
t "gradle: the release config enables APK Signature Schemes v2 and v3" eq "$(grep -cE 'enableV(2|3)Signing = true' "$G")" 2
t "gradle: no password or key literal is written in the file" eq "$(grep -ciE '(storePassword|keyPassword)[[:space:]]*=[[:space:]]*"' "$G")" 0
t "gradle: no credential value is printed" eq "$(grep -cE 'println|logger\.(lifecycle|info|quiet|warn)' "$G")" 0
t "gradle: a release-mode task graph check exists (the production signing identity signs production only)" has "$gradle_text" "gradle.taskGraph.whenReady"
t "gradle: the check reads the flavors other than production from the declarations" has "$gradle_text" 'filter { it != "production" }'
t "gradle: the check refuses a release variant of another flavor and says nothing was signed" has "$gradle_text" "signs the production application only"
t "gradle: the production-only check is active in release mode only" eq "$(grep -c '^if (cadenaSigningMode == "release") {$' "$G")" 1
t "gradle: the real-Gradle regression test exists and is executable" test -x "$root/tool/test_android_gradle_signing.sh"
t "gradle: the debug key is not given to any flavor in release mode (no flavor-level signing config)" eq "$(grep -cE '^[[:space:]]*signingConfig[[:space:]]*=' "$G")" 1
t "gradle: the keystore patterns stay ignored by Git" eq "$(grep -cE '^(key\.properties|\*\*/\*\.keystore|\*\*/\*\.jks)$' "$root/android/.gitignore")" 3

# Git ignore rules (Issue #85): new Android sources stay visible, build output and credentials stay out.
# "Ignored" means ignored by a .gitignore of the repository (not by a local or global exclude).
ignored_by_repo() { git -C "$root" check-ignore -v -- "$1" 2>/dev/null | grep -qE '^([^:]*/)?\.gitignore:'; }
visible() { ! git -C "$root" check-ignore -q -- "$1"; }
for f in android/app/src/main/kotlin/com/example/New.kt android/app/proguard-rules.pro android/app/src/main/res/xml/network_security_config.xml \
  android/app/new.gradle.kts android/app/src/main/AndroidManifest.xml config/build/new.json .env.example; do
  t "gitignore: $f is visible to Git" visible "$f"
done
for f in build/app/outputs/x android/app/build/x android/app/key.properties android/app/upload.jks android/app/upload.keystore .flutter-plugins-dependencies \
  .claude/settings.local.json ios/AuthKey_X.p8 cert.p12 key.pem x.mobileprovision .env .env.production android/app/google-services.json ios/Runner/GoogleService-Info.plist; do
  t "gitignore: $f is ignored by the repository" ignored_by_repo "$f"
done
t "gitignore: no tracked file matches an ignore rule" eq "$(git -C "$root" ls-files -ci --exclude-standard | wc -l | tr -d ' ')" 0

# CI stays credential-free: no workflow selects release signing or names a secret
wf_hits="$(grep -rlE 'CADENA_SIGNING|CADENA_KEYSTORE|CADENA_KEY_|CADENA_EXPECTED_CERT|secrets\.' "$root/.github/workflows" 2>/dev/null | grep -v 'ios-signing-feasibility' | tr '\n' ' ')"
t "ci: no workflow enables release signing or reads a secret (${wf_hits:-none})" test -z "$wf_hits"
t "ci: no workflow runs the local release procedure" eq "$(grep -rlE 'release_android\.sh' "$root/.github/workflows" 2>/dev/null | wc -l | tr -d ' ')" 0
t "ci: the plan job of build-variants runs this credential-free test" eq "$(grep -cE '^        run: tool/test_android_release\.sh$' "$root/.github/workflows/build-variants.yml")" 1
t "ci: no workflow publishes to Google Play or uploads a release" eq "$(grep -rliE 'upload-google-play|r0adkll|play-publisher|fastlane supply|androidpublisher' "$root/.github/workflows" 2>/dev/null | wc -l | tr -d ' ')" 0

# The workflow that runs these tests on pull requests (Issue #72): tests only, no credential, no artifact.
PRWF="$root/.github/workflows/android-release-tests.yml"
prwf_code="$(grep -v '^[[:space:]]*#' "$PRWF" 2>/dev/null)"
t "ci: the pull-request workflow exists" test -f "$PRWF"
t "ci: it triggers on pull_request (integration and release branches) and manual runs only" eq "$(sed -n '/^on:/,/^[a-z]/p' <<<"$prwf_code" | grep -E '^  [a-z_]+:' | tr -d ' \n')" "pull_request:workflow_dispatch:"
t "ci: it targets development, staging and production" has "$prwf_code" "branches: [development, staging, production]"
t "ci: it never uses pull_request_target" hasnt "$prwf_code" "pull_request_target"
t "ci: its permissions are exactly contents: read" eq "$(sed -n '/^permissions:/,/^[a-z]/p' <<<"$prwf_code" | grep -v '^[a-z]' | tr -d ' \n')" "contents:read"
t "ci: it uses no environment, secret, token, artifact upload, OIDC or cache write of signing material" eq "$(grep -cE 'environment:|secrets\.|GITHUB_TOKEN|upload-artifact|download-artifact|id-token|attestations' <<<"$prwf_code")" 0
t "ci: it does not publish, sign or build an application" eq "$(grep -cE 'flutter build|release_android|bundletool|apksigner|jarsigner|gh release|gh pr|git push' <<<"$prwf_code")" 0
t "ci: every action is pinned by commit SHA" eq "$(grep -E '^[[:space:]]+uses:' <<<"$prwf_code" | grep -vcE '@[0-9a-f]{40}')" 0
t "ci: it runs the hermetic release test and the real-Gradle signing test" eq "$(grep -cE '^        run: tool/(test_android_release|test_android_gradle_signing)\.sh$' <<<"$prwf_code")" 2
t "ci: build-variants still has no pull_request trigger (the release trigger policy)" eq "$(grep -v '^[[:space:]]*#' "$root/.github/workflows/build-variants.yml" | grep -c 'pull_request')" 0

# ---------------------------------------------------------------------------------------------
# 2. The ledgers hold public facts only
# ---------------------------------------------------------------------------------------------
SIGNING_JSON="$root/config/release/android_signing.json"
NATIVE_JSON="$root/config/release/native_libs.json"
jq_py() { python3 -I -c "$1" "${@:2}"; }
t "ledger: android_signing.json has the expected schema" eq "$(jq_py 'import json,sys; print(json.load(open(sys.argv[1]))["schema"])' "$SIGNING_JSON")" "cadena-android-signing/1"
t "ledger: every recorded fingerprint is a SHA-256" eq "$(jq_py '
import json,re,sys
d=json.load(open(sys.argv[1]))
fps=[d["play_app_signing"]["sha256"]]+[x["sha256"] for x in d["upload"]["do_not_use"]]
print(all(re.fullmatch(r"[0-9a-f]{64}", f.replace(":","").lower()) for f in fps))' "$SIGNING_JSON")" True
t "ledger: the Google Play app-signing certificate is recorded and differs from the forbidden upload key" eq "$(jq_py '
import json,sys
d=json.load(open(sys.argv[1])); n=lambda s:s.replace(":","").lower()
print(n(d["play_app_signing"]["sha256"]) not in [n(x["sha256"]) for x in d["upload"]["do_not_use"]])' "$SIGNING_JSON")" True
t "ledger: no secret-looking content in the ledgers" eq "$(grep -ciE 'BEGIN [A-Z ]*PRIVATE|\.jks|\.p12|storePassword|keyPassword|api[_-]?key' "$SIGNING_JSON" "$NATIVE_JSON" | awk -F: '{s+=$2} END {print s+0}')" 0
t "ledger: native_libs.json lists, per ABI, files that exist in the plugin's jniLibs" eq "$(jq_py '
import json,os,sys
d=json.load(open(sys.argv[1])); base=sys.argv[2]
print(all(os.path.isfile(os.path.join(base,abi,name)) for abi,libs in d["abis"].items() for name in libs))' "$NATIVE_JSON" "$root/flutter_plugin/flutter_plugin/android/src/main/jniLibs")" True
t "ledger: every ABI lists the Rust library and the secp256k1 library" eq "$(jq_py '
import json,sys
d=json.load(open(sys.argv[1]))
print(sorted(d["abis"])==["arm64-v8a","armeabi-v7a","x86_64"] and all(len(v)==2 and "libdlcplazacryptlib.so" in v for v in d["abis"].values()))' "$NATIVE_JSON")" True

# ---------------------------------------------------------------------------------------------
# 3. Unit tests of the verifier's building blocks
# ---------------------------------------------------------------------------------------------
unit="$(python3 -I - "$VAR" <<'EOF'
import runpy, struct, sys
M = runpy.run_path(sys.argv[1], run_name="not_main")
def elf64(align, endian="<"):
    ident = b"\x7fELF" + bytes([2, 1 if endian == "<" else 2, 1]) + b"\0" * 9
    hdr = ident + struct.pack(endian + "HHIQQQIHHHHHH", 3, 183, 1, 0, 64, 0, 0, 64, 56, 2, 0, 0, 0)
    ph = struct.pack(endian + "IIQQQQQQ", 1, 5, 0, 0, 0, 100, 100, align) + struct.pack(endian + "IIQQQQQQ", 1, 6, 0, 0, 0, 100, 100, align * 4)
    return hdr + ph
def elf32(align):
    ident = b"\x7fELF" + bytes([1, 1, 1]) + b"\0" * 9
    hdr = ident + struct.pack("<HHIIIIIHHHHHH", 3, 40, 1, 0, 52, 0, 0, 52, 32, 1, 0, 0, 0)
    ph = struct.pack("<IIIIIIII", 1, 0, 0, 0, 100, 100, 5, align)
    return hdr + ph
r = []
def t(name, cond): r.append((name, bool(cond)))
t("elf: 16 KB alignment is read from the segments", M["elf_info"](elf64(16384)) == (64, 16384))
t("elf: 64 KB alignment", M["elf_info"](elf64(65536)) == (64, 65536))
t("elf: the smallest segment alignment decides (4 KB)", M["elf_info"](elf64(4096)) == (64, 4096))
t("elf: big-endian is read too", M["elf_info"](elf64(16384, ">")) == (64, 16384))
t("elf: a 32-bit ELF is read", M["elf_info"](elf32(4096)) == (32, 4096))
t("elf: garbage is not an ELF", M["elf_info"](b"not an elf at all" * 10) is None)
t("elf: a truncated program header table is not an ELF", M["elf_info"](elf64(16384)[:70]) is None)
t("elf: an empty file is not an ELF", M["elf_info"](b"") is None)
fp = "ab" * 32
t("fingerprint: plain hex", M["norm_fp"](fp) == fp)
t("fingerprint: colons and upper case", M["norm_fp"](":".join(fp[i:i+2] for i in range(0, 64, 2)).upper()) == fp)
t("fingerprint: 63 digits are refused", M["norm_fp"](fp[:-1]) is None)
t("fingerprint: non-hex is refused", M["norm_fp"]("zz" * 32) is None)
t("fingerprint: None is refused", M["norm_fp"](None) is None)
ledger = {"play_app_signing": {"sha256": "13:52:D9:EE:63:8B:89:6B:53:2E:C6:F3:79:30:DA:42:5D:84:F3:55:0A:64:66:58:F3:9B:2E:22:22:AC:9F:CB"}}
play = M["norm_fp"](ledger["play_app_signing"]["sha256"])
t("class: the expected local identity", M["classify"](fp, ledger, fp, "CN=x") == "release-local")
t("class: the Play app-signing certificate", M["classify"](play, ledger, fp, "CN=x") == "play-signed")
t("class: a debug certificate, whatever else", M["classify"](fp, ledger, fp, "C=US, O=Android, CN=Android Debug") == "debug")
t("class: anything else is unknown", M["classify"]("cd" * 32, ledger, fp, "CN=x") == "unknown")
t("date: the validity end of a keytool certificate is read", str(M["until_date"]("Tue Mar 09 20:38:00 CET 2054")) == "2054-03-09")
t("date: text that is not a date gives no date", M["until_date"]("never") is None)
t("badging: the fields are read", M["parse_badging"]("package: name='a.b' versionCode='7' versionName='1.2'\nsdkVersion:'24'\ntargetSdkVersion:'36'\napplication-label:'X'\n")["code"] == "7")
for name, ok in r:
    print(("ok   " if ok else "FAIL ") + name)
EOF
)"
while IFS= read -r line; do case "$line" in ok*) pass=$((pass + 1)); echo "$line" ;; FAIL*) failed=$((failed + 1)); echo "$line" ;; esac; done <<<"$unit"

# ---------------------------------------------------------------------------------------------
# 4. The release driver refuses before it builds (a fake flutter proves nothing is started)
# ---------------------------------------------------------------------------------------------
fakebin="$tmp/fakebin"; mkdir -p "$fakebin"
printf '#!/bin/sh\necho "FLUTTER-WAS-CALLED" >> "%s/flutter-called"\nexit 99\n' "$tmp" >"$fakebin/flutter"; chmod +x "$fakebin/flutter"
D() { PATH="$fakebin:$PATH" "$root/tool/release_android.sh" "$@"; }
printf 'storeFile=/nonexistent/ks.p12\nkeyAlias=a\nstorePassword=x\nkeyPassword=x\n' >"$tmp/props.properties"
GOODFP="$(printf '%064d' 0 | tr 0 a)"
expect_rc "driver: no arguments are refused" 2 "are all required" D
expect_rc "driver: a missing properties file is refused" 2 "does not exist" D --signing-properties "$tmp/nope" --expect-cert-sha256 "$GOODFP" --identity-label x --out "$tmp/o1"
expect_rc "driver: properties inside the repository are refused" 2 "outside the repository" D --signing-properties "$root/pubspec.yaml" --expect-cert-sha256 "$GOODFP" --identity-label x --out "$tmp/o1"
expect_rc "driver: a malformed fingerprint is refused" 2 "not a SHA-256 fingerprint" D --signing-properties "$tmp/props.properties" --expect-cert-sha256 abc --identity-label x --out "$tmp/o1"
mkdir -p "$tmp/o2"; touch "$tmp/o2/old"
expect_rc "driver: an output directory that is not empty is refused" 2 "never overwritten" D --signing-properties "$tmp/props.properties" --expect-cert-sha256 "$GOODFP" --identity-label x --out "$tmp/o2"
expect_rc "driver: an unknown option is refused" 2 "unknown option" D --bogus
if [ -n "${BUNDLETOOL_JAR:-}" ] && [ -n "${ANDROID_HOME:-}" ] && java -version 2>&1 | head -n1 | grep -q '"17\.'; then
  expect_rc "driver: the production gate stops the release at the published version (nothing is built)" 2 "release gate fails" D --signing-properties "$tmp/props.properties" --expect-cert-sha256 "$GOODFP" --identity-label x --out "$tmp/o3" --allow-dirty
else
  echo "skip driver: the gate refusal (needs JDK 17, ANDROID_HOME and BUNDLETOOL_JAR)"
fi
t "driver: flutter was never started by any refusal" test ! -e "$tmp/flutter-called"

# ---------------------------------------------------------------------------------------------
# 5. Real artifacts re-signed with disposable keys
# ---------------------------------------------------------------------------------------------
if [ -z "${REAL_APK:-}" ] || [ -z "${REAL_AAB:-}" ]; then
  echo "skip artifacts: set REAL_APK and REAL_AAB (and ANDROID_HOME, BUNDLETOOL_JAR, JAVA_HOME=JDK 17) to verify real artifacts"
else
  ABT="$(ls -d "$ANDROID_HOME"/build-tools/*/ 2>/dev/null | sort -V | tail -n1)"
  APKSIGNER="${ABT}apksigner"
  PW="$(openssl rand -hex 12)"
  mkkey() { # NAME DN
    keytool -genkeypair -alias "$1" -keyalg RSA -keysize 2048 -validity 10000 -keystore "$tmp/$1.p12" -storetype PKCS12 \
      -dname "$2" -storepass "$PW" -keypass "$PW" >/dev/null 2>&1
    keytool -list -keystore "$tmp/$1.p12" -storepass "$PW" 2>/dev/null | sed -n 's/.*SHA-256): //p' | head -n1
  }
  FP_UP="$(mkkey up "CN=DISPOSABLE TEST UPLOAD KEY, O=Test")"
  FP_OTHER="$(mkkey other "CN=DISPOSABLE OTHER KEY, O=Test")"
  FP_DEBUG="$(mkkey dbg "C=US, O=Android, CN=Android Debug")"
  t "keys: three disposable keys were created" test -n "$FP_UP" -a -n "$FP_OTHER" -a -n "$FP_DEBUG"
  sign_apk() { # IN OUT KEY
    cp "$1" "$2"; "$APKSIGNER" sign --ks "$tmp/$3.p12" --ks-key-alias "$3" --ks-pass "pass:$PW" --key-pass "pass:$PW" \
      --v2-signing-enabled true --v3-signing-enabled true "$2" >/dev/null 2>&1
  }
  sign_aab() { # IN OUT KEY
    cp "$1" "$2"; zip -q -d "$2" 'META-INF/*' >/dev/null 2>&1 || true
    jarsigner -keystore "$tmp/$3.p12" -storepass "$PW" -keypass "$PW" -sigalg SHA256withRSA -digestalg SHA-256 "$2" "$3" >/dev/null 2>&1
  }
  sign_apk "$REAL_APK" "$tmp/up.apk" up; sign_aab "$REAL_AAB" "$tmp/up.aab" up
  sign_apk "$REAL_APK" "$tmp/other.apk" other; sign_apk "$REAL_APK" "$tmp/dbg.apk" dbg; sign_aab "$REAL_AAB" "$tmp/dbg.aab" dbg
  t "artifacts: the disposable-signed APK and AAB exist" test -s "$tmp/up.apk" -a -s "$tmp/up.aab"

  # a copy of the repository that the verifier can use as its reference (ledgers, pubspec, tools)
  mkrepo() { # DEST
    mkdir -p "$1"; cp -R "$root/tool" "$root/config" "$root/pubspec.yaml" "$1/"; mkdir -p "$1/android/gradle/wrapper"
    cp "$root/android/settings.gradle.kts" "$1/android/"; cp "$root/android/gradle/wrapper/gradle-wrapper.properties" "$1/android/gradle/wrapper/"
    rm -rf "$1/tool/__pycache__"
  }
  mkrepo "$tmp/fx"
  # VX REPO SUBCOMMAND ARGS...: the verifier copy of that repository copy, with that repository as the reference
  VX() { local r="$1" sub="$2"; shift 2; python3 -I "$r/tool/verify_android_release.py" "$sub" "$@" --repo "$r"; }
  VF() { local sub="$1"; shift; VX "$tmp/fx" "$sub" "$@"; }

  expect_rc "apk: a correctly signed production APK passes" 0 "RESULT: OK" VF apk production "$tmp/up.apk" --expect-cert-sha256 "$FP_UP"
  expect_rc "apk: the signer is classified as the local release identity" 0 "evidence signing_class=release-local" VF apk production "$tmp/up.apk" --expect-cert-sha256 "$FP_UP"
  expect_rc "apk: both signature schemes are reported" 0 "v2=True v3=True" VF apk production "$tmp/up.apk" --expect-cert-sha256 "$FP_UP"
  expect_rc "apk: a lower-case fingerprint without colons is accepted" 0 "RESULT: OK" VF apk production "$tmp/up.apk" --expect-cert-sha256 "$(printf '%s' "$FP_UP" | tr -d ':' | tr 'A-F' 'a-f')"
  expect_rc "apk: another expected certificate is refused" 1 "the expected certificate is" VF apk production "$tmp/up.apk" --expect-cert-sha256 "$FP_OTHER"
  expect_rc "apk: a signature by another key is refused" 1 "the signer is" VF apk production "$tmp/other.apk" --expect-cert-sha256 "$FP_UP"
  expect_rc "apk: a debug certificate is refused as a release" 1 "DEBUG certificate" VF apk production "$tmp/dbg.apk" --expect-cert-sha256 "$FP_DEBUG"
  expect_rc "apk: no expected fingerprint is a usage error, not a pass" 2 "needs --expect-cert-sha256" VF apk production "$tmp/up.apk"
  expect_rc "apk: a malformed expected fingerprint is a usage error" 2 "must be a SHA-256 fingerprint" VF apk production "$tmp/up.apk" --expect-cert-sha256 12345
  expect_rc "apk: a locally signed APK is NOT a Google Play-signed APK" 1 "NOT Google Play-signed" VF apk production "$tmp/up.apk" --signing play
  expect_rc "apk: the staging flavor identity is refused for a production APK" 1 "the staging ID is com.cadenabitcoin.mobile.signer.staging" VF apk staging "$tmp/up.apk" --expect-cert-sha256 "$FP_UP"
  expect_rc "apk: the local-signing note explains the missing update compatibility" 0 "cannot update an installation that came from Google Play" VF apk production "$tmp/up.apk" --expect-cert-sha256 "$FP_UP"

  # a ledger that records the disposable key as the Play app-signing certificate: a Play-signed APK passes in play mode
  mkrepo "$tmp/fxplay"
  python3 -I -c '
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["play_app_signing"]["sha256"]=sys.argv[2]; json.dump(d,open(p,"w"),indent=2)' "$tmp/fxplay/config/release/android_signing.json" "$FP_UP"
  expect_rc "apk: an APK signed with the ledger's Play app-signing certificate is classified play-signed" 0 "evidence signing_class=play-signed" VX "$tmp/fxplay" apk production "$tmp/up.apk" --signing play
  expect_rc "apk: a local release may not claim the Play app-signing key" 1 "no local build can hold" VX "$tmp/fxplay" apk production "$tmp/up.apk" --expect-cert-sha256 "$FP_UP"
  # a ledger that forbids the disposable key
  mkrepo "$tmp/fxban"
  python3 -I -c '
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["upload"]["do_not_use"].append({"sha256":sys.argv[2],"reason":"test"}); json.dump(d,open(p,"w"),indent=2)' "$tmp/fxban/config/release/android_signing.json" "$FP_UP"
  expect_rc "apk: an identity the ledger forbids is refused even when it is the expected one" 1 "forbids" VX "$tmp/fxban" apk production "$tmp/up.apk" --expect-cert-sha256 "$FP_UP"
  # a ledger with an active upload fingerprint: a different expected value is refused
  mkrepo "$tmp/fxact"
  python3 -I -c '
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["upload"]["active_sha256"]=sys.argv[2]; json.dump(d,open(p,"w"),indent=2)' "$tmp/fxact/config/release/android_signing.json" "$FP_OTHER"
  expect_rc "apk: an expected fingerprint that differs from the recorded active upload key is refused" 2 "differs from the active upload fingerprint" VX "$tmp/fxact" apk production "$tmp/up.apk" --expect-cert-sha256 "$FP_UP"
  # a wrong version in the repository
  mkrepo "$tmp/fxver"
  sed -i.bak 's/^version: .*/version: 1.0.3+1000099/' "$tmp/fxver/pubspec.yaml"; rm -f "$tmp/fxver/pubspec.yaml.bak"
  expect_rc "apk: a versionCode that differs from pubspec.yaml is refused" 1 "versionCode '1000034' != pubspec 1000099" VX "$tmp/fxver" apk production "$tmp/up.apk" --expect-cert-sha256 "$FP_UP"

  # native libraries: altered, missing ABI, mis-aligned
  mutate_zip() { # IN OUT PYTHON_BODY (variables: zin, zout, names)
    python3 -I - "$1" "$2" "$3" <<'EOF'
import sys, zipfile
src, dst, mode = sys.argv[1:4]
zin = zipfile.ZipFile(src)
zout = zipfile.ZipFile(dst, "w", zipfile.ZIP_STORED)
for info in zin.infolist():
    data = zin.read(info)
    n = info.filename
    if mode == "alter-cryptlib" and n.endswith("arm64-v8a/libdlcplazacryptlib.so"):
        data = data[:-1] + bytes([data[-1] ^ 1])
    if mode == "drop-abi" and "/x86_64/" in n:
        continue
    if mode == "misaligned" and n.endswith("arm64-v8a/libapp.so"):
        import struct
        # a 64-bit ELF whose only segments are aligned to 4 KB
        ident = b"\x7fELF" + bytes([2, 1, 1]) + b"\0" * 9
        hdr = ident + struct.pack("<HHIQQQIHHHHHH", 3, 183, 1, 0, 64, 0, 0, 64, 56, 1, 0, 0, 0)
        data = hdr + struct.pack("<IIQQQQQQ", 1, 5, 0, 0, 0, 100, 100, 4096)
    zout.writestr(info.filename, data)
zout.close()
EOF
  }
  mutate_zip "$REAL_APK" "$tmp/m1.apk" alter-cryptlib; sign_apk "$tmp/m1.apk" "$tmp/m1s.apk" up
  expect_rc "native: an altered Rust library is refused" 1 "differs from config/release/native_libs.json" VF apk production "$tmp/m1s.apk" --expect-cert-sha256 "$FP_UP"
  mutate_zip "$REAL_APK" "$tmp/m2.apk" drop-abi; sign_apk "$tmp/m2.apk" "$tmp/m2s.apk" up
  expect_rc "native: a missing ABI is refused" 1 "ships the ABIs" VF apk production "$tmp/m2s.apk" --expect-cert-sha256 "$FP_UP"
  mutate_zip "$REAL_APK" "$tmp/m3.apk" misaligned; sign_apk "$tmp/m3.apk" "$tmp/m3s.apk" up
  expect_rc "native: a 4 KB-aligned 64-bit library is refused" 1 "NOT 16 KB aligned" VF apk production "$tmp/m3s.apk" --expect-cert-sha256 "$FP_UP"

  # unsigned (signature removed): never a pass
  mutate_zip "$REAL_APK" "$tmp/plain.apk" none
  expect_rc "apk: an APK with no valid signature is refused" 1 "apksigner REJECTS" VF apk production "$tmp/plain.apk" --expect-cert-sha256 "$FP_UP"
  expect_rc "apk: a file that is not an APK is a usage error, never a pass" 2 "" VF apk production "$tmp/props.properties" --expect-cert-sha256 "$FP_UP"

  # AAB
  expect_rc "aab: a correctly signed production AAB passes" 0 "RESULT: OK" VF aab production "$tmp/up.aab" --expect-cert-sha256 "$FP_UP"
  expect_rc "aab: another expected certificate is refused" 1 "the expected certificate is" VF aab production "$tmp/up.aab" --expect-cert-sha256 "$FP_OTHER"
  expect_rc "aab: a debug certificate is refused as a release" 1 "DEBUG certificate" VF aab production "$tmp/dbg.aab" --expect-cert-sha256 "$FP_DEBUG"
  cp "$tmp/up.aab" "$tmp/tampered.aab"; printf 'x' >"$tmp/extra.txt"; (cd "$tmp" && zip -q tampered.aab extra.txt)
  expect_rc "aab: an entry added after signing is refused" 1 "unsigned entries" VF aab production "$tmp/tampered.aab" --expect-cert-sha256 "$FP_UP"
  cp "$tmp/up.aab" "$tmp/nosig.aab"; zip -q -d "$tmp/nosig.aab" 'META-INF/*' >/dev/null 2>&1
  expect_rc "aab: a bundle with its signature removed is refused" 1 "jarsigner REJECTS" VF aab production "$tmp/nosig.aab" --expect-cert-sha256 "$FP_UP"

  # pair
  expect_rc "pair: APK and AAB of one release, one signer, pass" 0 "RESULT: OK" VF pair production "$tmp/up.apk" "$tmp/up.aab" --expect-cert-sha256 "$FP_UP"
  expect_rc "pair: the version and the Rust libraries are compared" 0 "are byte-identical in both artifacts" VF pair production "$tmp/up.apk" "$tmp/up.aab" --expect-cert-sha256 "$FP_UP"
  expect_rc "pair: an APK and an AAB with different signers fail" 1 "signing certificate differs" VF pair production "$tmp/other.apk" "$tmp/up.aab" --expect-cert-sha256 "$FP_UP"

  # release report on a committed copy of the repository whose ledger puts the published floor one below this build
  mkrepo "$tmp/rel"
  python3 -I -c '
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["entries"][0]["version_code"]=1000033; json.dump(d,open(p,"w"),indent=2)' "$tmp/rel/config/release/published_versions.json"
  git -C "$tmp/rel" init -q && git -C "$tmp/rel" add -A >/dev/null 2>&1 && git -C "$tmp/rel" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m fixture
  VR() { local sub="$1"; shift; VX "$tmp/rel" "$sub" "$@"; }
  expect_rc "release: verified artifacts of a clean commit above the floor are release-ready (not published)" 0 "RESULT: OK (release ready, verified, not published)" \
    VR release production --apk "$tmp/up.apk" --aab "$tmp/up.aab" --expect-cert-sha256 "$FP_UP" --identity-label "disposable test key" --out "$tmp/report1"
  R="$tmp/report1/release-report.json"
  t "release: the report is JSON with the schema and release_ready true" eq "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["schema"], d["release_ready"])' "$R")" "cadena-android-release-report/1 True"
  t "release: the report never says distributable" eq "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["distributable"])' "$R")" False
  t "release: the recorded artifact SHA-256 values are those of the files" eq "$(python3 -I -c '
import json,sys,hashlib
d=json.load(open(sys.argv[1]))
print(all(a["sha256"]==hashlib.sha256(open(sys.argv[2+i],"rb").read()).hexdigest() for i,a in enumerate(d["artifacts"])))' "$R" "$tmp/up.apk" "$tmp/up.aab")" True
  t "release: the report records the commit, the tools and the ledgers" eq "$(python3 -I -c '
import json,sys,re
p=json.load(open(sys.argv[1]))["provenance"]
print(bool(re.fullmatch(r"[0-9a-f]{40}", p["commit"])) and p["tracked_tree_clean"] and "published_versions.json" in p["ledgers"] and p["toolchain"]["gradle"]!="")' "$R")" True
  t "release: SHA256SUMS verifies the artifacts" eq "$(cd "$tmp" && sha256sum -c report1/SHA256SUMS 2>&1 | grep -c ': OK')" 2
  t "release: the Markdown report states that verification is not authorization to publish" has "$(cat "$tmp/report1/release-report.md")" "Verification is not authorization to publish"
  t "release: no password or key material is in any report file" eq "$(grep -rlF -e "$PW" -e "PRIVATE KEY" "$tmp/report1" | wc -l | tr -d ' ')" 0
  # not ready: a dirty tracked tree
  echo "# changed" >>"$tmp/rel/pubspec.yaml"
  expect_rc "release: a dirty tracked tree makes the release NOT READY" 1 "tracked working tree is not clean" \
    VR release production --apk "$tmp/up.apk" --aab "$tmp/up.aab" --expect-cert-sha256 "$FP_UP" --identity-label x --out "$tmp/report2"
  git -C "$tmp/rel" checkout -q -- pubspec.yaml
  # not ready: the real ledger (floor 1000034 = this build) fails the production gate
  mkrepo "$tmp/rel2"; git -C "$tmp/rel2" init -q && git -C "$tmp/rel2" add -A >/dev/null 2>&1 && git -C "$tmp/rel2" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m fixture
  expect_rc "release: a build number that is not above the published one makes the release NOT READY" 1 "release gate fails" \
    VX "$tmp/rel2" release production --apk "$tmp/up.apk" --aab "$tmp/up.aab" --expect-cert-sha256 "$FP_UP" --identity-label x --out "$tmp/report3"
  t "release: a NOT READY report is still written for the audit" eq "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["release_ready"], d["distributable"])' "$tmp/report3/release-report.json")" "False False"
  expect_rc "release: staging has no release command yet" 2 "does not exist yet" VR release staging --apk "$tmp/up.apk" --aab "$tmp/up.aab" --expect-cert-sha256 "$FP_UP" --identity-label x --out "$tmp/report4"
  unset PW
fi

# ---------------------------------------------------------------------------------------------
# 6. The whole procedure with real builds (opt-in)
# ---------------------------------------------------------------------------------------------
if [ "${ANDROID_RELEASE_E2E:-0}" = 1 ]; then
  e2e="$tmp/e2e"; git clone -q "$root" "$e2e"
  sed -i.bak 's/^version: .*/version: 1.0.3+1000035/' "$e2e/pubspec.yaml"; rm -f "$e2e/pubspec.yaml.bak"
  git -C "$e2e" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -am "e2e: raise the build number"
  PW2="$(openssl rand -hex 12)"
  keytool -genkeypair -alias e2e -keyalg RSA -keysize 2048 -validity 10000 -keystore "$tmp/e2e.p12" -storetype PKCS12 \
    -dname "CN=DISPOSABLE E2E KEY, O=Test" -storepass "$PW2" -keypass "$PW2" >/dev/null 2>&1
  FPE="$(keytool -list -keystore "$tmp/e2e.p12" -storepass "$PW2" 2>/dev/null | sed -n 's/.*SHA-256): //p' | head -n1)"
  printf 'storeFile=%s\nkeyAlias=e2e\n' "$tmp/e2e.p12" >"$tmp/e2e.properties"
  e2e_out="$( cd "$e2e" && CADENA_KEYSTORE_PASSWORD="$PW2" CADENA_KEY_PASSWORD="$PW2" tool/release_android.sh \
      --signing-properties "$tmp/e2e.properties" --expect-cert-sha256 "$FPE" --identity-label "disposable e2e key" --out "$tmp/e2e-out" 2>&1 )"; e2e_rc=$?
  t "e2e: the whole procedure exits 0" eq "$e2e_rc" 0
  t "e2e: it ends with a verified, unpublished release" has "$e2e_out" "RESULT: OK (release ready, verified, not published)"
  t "e2e: the report and the artifacts exist" test -s "$tmp/e2e-out/release-report.json" -a -s "$tmp/e2e-out/SHA256SUMS"
  t "e2e: no password appears in the output or the report" eq "$( (printf '%s' "$e2e_out"; cat "$tmp/e2e-out"/release-report.*) | grep -cF "$PW2")" 0
  # missing credentials: the driver refuses, nothing is built
  rm -rf "$tmp/e2e-out2"
  e2e2="$( cd "$e2e" && tool/release_android.sh --signing-properties "$tmp/e2e.properties" --expect-cert-sha256 "$FPE" --identity-label x --out "$tmp/e2e-out2" 2>&1 )"; e2e2_rc=$?
  t "e2e: without the passwords the procedure refuses before building" eq "$e2e2_rc" 2
  t "e2e: and says which passwords are missing" has "$e2e2" "no keystore password"
fi

echo
echo "test_android_release: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
