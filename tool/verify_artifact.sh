#!/usr/bin/env bash
# Verifies a BUILT artifact against the application-identity matrix, pubspec.yaml and
# the build configuration, and prints independently checkable evidence.
#
#   tool/verify_artifact.sh apk ENV FILE.apk [--signing debug|unsigned] [--debug-build] [--evidence OUT]
#   tool/verify_artifact.sh aab ENV FILE.aab [--signing debug|unsigned] [--evidence OUT]
#   tool/verify_artifact.sh ios ENV Runner.app                          [--evidence OUT]
#   tool/verify_artifact.sh selftest apk|aab|ios ENV FILE [--signing ...] [--debug-build]
#   tool/verify_artifact.sh consistent EVIDENCE_A EVIDENCE_B     # e.g. production APK vs AAB
#   tool/verify_artifact.sh matrix                               # print the expected identities
#
# ENV is staging or production. For every artifact it checks what the artifact ITSELF says
# (read with aapt2 / bundletool / the Info.plist), not what the build command was:
#   - application ID / bundle identifier and display name for ENV (the matrix below);
#   - version name/number against the pubspec.yaml `version:` (X.Y.Z+BUILD);
#   - signing status: Android `debug` (the existing temporary debug signing, NOT
#     distributable) or `unsigned`; iOS must be unsigned (no profile, no signature);
#   - the environment: the Dart AOT snapshot contains ENV's backend URL and not the
#     other environment's (tool/verify_build_config.sh check-binary). Supporting evidence
#     only: it does not prove runtime behavior or network isolation. Debug builds are
#     rejected because they embed both URLs.
# --debug-build (apk only) is for the CI validation APK: it expects a debuggable build and
# records that the environment check was skipped (a debug build embeds both URLs).
# `selftest` additionally proves the checks can fail: the same artifact claimed for the
# other environment, and a debug-signed artifact claimed unsigned, must be rejected.
#
# Needs python3. APK: aapt2 and apksigner (PATH, ANDROID_HOME/ANDROID_SDK_ROOT or the
# sdk.dir of android/local.properties). AAB: BUNDLETOOL_JAR=/path/bundletool.jar (a pinned
# release, see docs/BUILD_CONFIGURATION.md), java and keytool. iOS: nothing beyond python3
# (codesign is used when present).
#
# Portability: bash 3.2 (macOS) compatible; no arrays, no mapfile. Prints PASS/FAIL lines,
# then an `evidence` block of key=value lines; exits 1 if any check failed.
set -euo pipefail
cd "$(dirname "$0")/.."

STAGING_ID=com.app.cadenabitcoin.staging
STAGING_NAME="Cadena Signer STAGING"
PRODUCTION_ID=com.app.cadenabitcoin
PRODUCTION_NAME="Cadena Bitcoin"

failures=0
DEBUG_BUILD=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; failures=$((failures + 1)); }
die() { echo "ERROR: $1" >&2; exit 2; }

TMP=""
cleanup() { if [ -n "$TMP" ]; then rm -rf "$TMP"; fi; }
trap cleanup EXIT
tmpdir() { if [ -z "$TMP" ]; then TMP=$(mktemp -d "${TMPDIR:-/tmp}/cadena-artifact.XXXXXX"); fi; }

EVIDENCE=""
ev() { EVIDENCE="${EVIDENCE}$1=$2
"; }

expected_id() { case "$1" in staging) echo "$STAGING_ID" ;; production) echo "$PRODUCTION_ID" ;; *) die "ENV must be staging or production" ;; esac; }
expected_name() { case "$1" in staging) echo "$STAGING_NAME" ;; production) echo "$PRODUCTION_NAME" ;; *) die "ENV must be staging or production" ;; esac; }

# ---- the expected version, from pubspec.yaml only ----------------------------------
EXPECT_NAME=""
EXPECT_BUILD=""
load_version() {
  local raw
  raw=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | sed -n '1p' | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//')
  case "$raw" in
    *+*) EXPECT_NAME=${raw%%+*}; EXPECT_BUILD=${raw##*+} ;;
    *) die "pubspec.yaml version '$raw' is not X.Y.Z+BUILD" ;;
  esac
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | awk '{print $1}'; fi
}
# Digest of a directory tree: the SHA-256 of the sorted "<sha256>  <relative path>" manifest of
# every regular file. Reproduces from the same app bundle; symlinks are not followed.
tree_sha256() {
  ( cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(sha256_of "$f")" "$f"
    done ) | sha256_stdin
}
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# ---- Android SDK tools ----------------------------------------------------------------
sdk_root() {
  local d
  for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$(sed -n 's/^sdk\.dir=//p' android/local.properties 2>/dev/null || true)"; do
    if [ -n "$d" ] && [ -d "$d" ]; then echo "$d"; return 0; fi
  done
  return 1
}
find_sdk_tool() { # NAME: PATH first, then the newest build-tools directory that has it
  local root v found=""
  if command -v "$1" >/dev/null 2>&1; then command -v "$1"; return 0; fi
  root=$(sdk_root) || return 1
  for v in $(ls -1 "$root/build-tools" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n); do
    if [ -x "$root/build-tools/$v/$1" ]; then found="$root/build-tools/$v/$1"; fi
  done
  if [ -n "$found" ]; then echo "$found"; return 0; fi
  return 1
}

# ---- environment evidence from the AOT snapshots ---------------------------------------
# check_snapshots ENV DIR: every libapp.so (Android) found under DIR must pass check-binary.
check_snapshots() {
  local env=$1 dir=$2 f n=0 bad=0 out
  for f in $(find "$dir" -name libapp.so | sort); do
    n=$((n + 1))
    if out=$(tool/verify_build_config.sh check-binary "$env" "$f" 2>&1); then
      pass "$(basename "$(dirname "$f")")/libapp.so: contains the $env backend URL and not the other environment's"
    else
      bad=$((bad + 1)); fail "$(basename "$(dirname "$f")")/libapp.so failed the $env check: $(echo "$out" | tr '\n' ' ')"
    fi
  done
  if [ "$n" -eq 0 ]; then
    fail "no libapp.so in the artifact: not a release/AOT build (a debug build embeds both URLs, so the check would be inconclusive)"
  fi
  ev "environment_check_snapshots" "$n"
  ev "environment_check" "$([ "$n" -gt 0 ] && [ "$bad" -eq 0 ] && echo "$env-url-present-other-absent" || echo failed)"
}

record_native_libs() { # DIR: sha256 of the committed prebuilt Rust library, for provenance
  local f
  for f in $(find "$1" -name libdlcplazacryptlib.so | sort); do
    ev "native_lib_sha256.$(basename "$(dirname "$f")")" "$(sha256_of "$f")"
  done
}

# ---- Android signing --------------------------------------------------------------------
check_signing_expectation() { # WANT ACTUAL_KIND: debug|unsigned vs what was found
  if [ "$2" = "$1" ]; then pass "signing status is '$2' as expected"; else fail "signing status is '$2', expected '$1'"; fi
}

verify_apk() { # ENV FILE SIGNING
  local env=$1 file=$2 signing=$3 aapt2 apksigner badging id code name label sign_out kind dn digest
  aapt2=$(find_sdk_tool aapt2) || die "aapt2 not found (set ANDROID_HOME)"
  apksigner=$(find_sdk_tool apksigner) || die "apksigner not found (set ANDROID_HOME)"
  load_version
  badging=$("$aapt2" dump badging "$file" 2>/dev/null) || die "aapt2 cannot read $file"
  id=$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<<"$badging" | sed -n '1p')
  code=$(sed -n "s/^package:.* versionCode='\([^']*\)'.*/\1/p" <<<"$badging" | sed -n '1p')
  name=$(sed -n "s/^package:.* versionName='\([^']*\)'.*/\1/p" <<<"$badging" | sed -n '1p')
  label=$(sed -n "s/^application-label:'\(.*\)'$/\1/p" <<<"$badging" | sed -n '1p')

  [ "$id" = "$(expected_id "$env")" ] && pass "application ID is $id" || fail "application ID is '$id', expected $(expected_id "$env")"
  [ "$label" = "$(expected_name "$env")" ] && pass "display name is '$label'" || fail "display name is '$label', expected '$(expected_name "$env")'"
  [ "$name" = "$EXPECT_NAME" ] && pass "versionName $name matches pubspec.yaml" || fail "versionName '$name' != pubspec $EXPECT_NAME"
  [ "$code" = "$EXPECT_BUILD" ] && pass "versionCode $code matches pubspec.yaml" || fail "versionCode '$code' != pubspec $EXPECT_BUILD"
  if [ "$DEBUG_BUILD" -eq 1 ]; then
    if grep -q '^application-debuggable' <<<"$badging"; then pass "debug build: the application is debuggable, as declared"; else fail "--debug-build was given but the application is not debuggable"; fi
  elif grep -q '^application-debuggable' <<<"$badging"; then fail "the application is marked debuggable"; else pass "the application is not debuggable"; fi

  kind=unsigned; dn=""; digest=""
  if sign_out=$("$apksigner" verify --print-certs "$file" 2>&1); then
    dn=$(sed -n 's/^Signer #1 certificate DN: //p' <<<"$sign_out" | sed -n '1p')
    digest=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' <<<"$sign_out" | sed -n '1p')
    case "$dn" in *"CN=Android Debug"*) kind=debug ;; *) kind="signed-by-other-key" ;; esac
  fi
  check_signing_expectation "$signing" "$kind"

  tmpdir
  rm -rf "$TMP/apk" && mkdir -p "$TMP/apk"
  (cd "$TMP/apk" && unzip -q -o "$file" 'lib/*' 2>/dev/null) || true
  if [ "$DEBUG_BUILD" -eq 1 ]; then
    echo "  NOTE  debug build: it embeds both backend URLs, so no environment check from the binary is possible"
    ev environment_check "skipped-debug-build"
  else
    check_snapshots "$env" "$TMP/apk"
  fi
  record_native_libs "$TMP/apk"

  ev artifact_kind apk; ev artifact_file "$(basename "$file")"; ev artifact_sha256 "$(sha256_of "$file")"
  ev artifact_bytes "$(wc -c <"$file" | tr -d ' ')"
  ev environment "$env"; ev application_id "$id"; ev display_name "$label"
  ev version_name "$name"; ev version_code "$code"
  ev signing "$kind"; ev signer_dn "$dn"; ev signer_cert_sha256 "$digest"
  ev distributable "no"
}

verify_aab() { # ENV FILE SIGNING
  local env=$1 file=$2 signing=$3 manifest parsed id code name label kind owner sha java_cmd keytool
  load_version
  if [ -n "${BUNDLETOOL_JAR:-}" ] && [ -f "${BUNDLETOOL_JAR:-}" ]; then
    java_cmd="java -jar $BUNDLETOOL_JAR"
  elif command -v bundletool >/dev/null 2>&1; then
    java_cmd="bundletool"
  else
    die "bundletool not found (set BUNDLETOOL_JAR to a pinned bundletool jar)"
  fi
  manifest=$($java_cmd dump manifest --bundle="$file" 2>/dev/null) || die "bundletool cannot read $file"
  parsed=$(python3 -I -c '
import sys, xml.etree.ElementTree as ET
A = "{http://schemas.android.com/apk/res/android}"
root = ET.fromstring(sys.stdin.read())
app = root.find("application")
print("package=" + root.get("package", ""))
print("versionCode=" + root.get(A + "versionCode", ""))
print("versionName=" + root.get(A + "versionName", ""))
print("label=" + (app.get(A + "label", "") if app is not None else ""))
print("debuggable=" + (app.get(A + "debuggable", "") if app is not None else ""))
' <<<"$manifest") || die "cannot parse the bundle manifest"
  id=$(sed -n 's/^package=//p' <<<"$parsed"); code=$(sed -n 's/^versionCode=//p' <<<"$parsed")
  name=$(sed -n 's/^versionName=//p' <<<"$parsed"); label=$(sed -n 's/^label=//p' <<<"$parsed")

  [ "$id" = "$(expected_id "$env")" ] && pass "application ID is $id" || fail "application ID is '$id', expected $(expected_id "$env")"
  [ "$label" = "$(expected_name "$env")" ] && pass "display name is '$label'" || fail "display name is '$label', expected '$(expected_name "$env")'"
  [ "$name" = "$EXPECT_NAME" ] && pass "versionName $name matches pubspec.yaml" || fail "versionName '$name' != pubspec $EXPECT_NAME"
  [ "$code" = "$EXPECT_BUILD" ] && pass "versionCode $code matches pubspec.yaml" || fail "versionCode '$code' != pubspec $EXPECT_BUILD"
  if [ "$(sed -n 's/^debuggable=//p' <<<"$parsed")" = "true" ]; then fail "the application is marked debuggable"; else pass "the application is not debuggable"; fi

  kind=unsigned; owner=""; sha=""
  keytool=$(command -v keytool || true)
  [ -n "$keytool" ] || die "keytool not found (needs a JDK)"
  if out=$("$keytool" -printcert -jarfile "$file" 2>&1) && grep -q '^Owner:' <<<"$out"; then
    owner=$(sed -n 's/^Owner: //p' <<<"$out" | sed -n '1p')
    sha=$(sed -n 's/^[[:space:]]*SHA256: //p' <<<"$out" | sed -n '1p' | tr -d ':' | tr 'A-F' 'a-f')
    case "$owner" in *"CN=Android Debug"*) kind=debug ;; *) kind="signed-by-other-key" ;; esac
  fi
  check_signing_expectation "$signing" "$kind"

  tmpdir
  rm -rf "$TMP/aab" && mkdir -p "$TMP/aab"
  (cd "$TMP/aab" && unzip -q -o "$file" 'base/lib/*' 2>/dev/null) || true
  check_snapshots "$env" "$TMP/aab"
  record_native_libs "$TMP/aab"

  ev artifact_kind aab; ev artifact_file "$(basename "$file")"; ev artifact_sha256 "$(sha256_of "$file")"
  ev artifact_bytes "$(wc -c <"$file" | tr -d ' ')"
  ev environment "$env"; ev application_id "$id"; ev display_name "$label"
  ev version_name "$name"; ev version_code "$code"
  ev signing "$kind"; ev signer_dn "$owner"; ev signer_cert_sha256 "$sha"
  ev distributable "no"
}

# ---- iOS ---------------------------------------------------------------------------------
plist_get() { # FILE KEY
  python3 -I -c '
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    print(plistlib.load(f).get(sys.argv[2], ""))
' "$1" "$2"
}

verify_ios() { # ENV APP_DIR
  local env=$1 app=$2 plist id name short build status="unsigned" exe archs="" cs_out out
  load_version
  plist="$app/Info.plist"
  [ -f "$plist" ] || die "$plist not found (pass the Runner.app directory)"
  id=$(plist_get "$plist" CFBundleIdentifier); name=$(plist_get "$plist" CFBundleDisplayName)
  short=$(plist_get "$plist" CFBundleShortVersionString); build=$(plist_get "$plist" CFBundleVersion)

  [ "$id" = "$(expected_id "$env")" ] && pass "bundle identifier is $id" || fail "bundle identifier is '$id', expected $(expected_id "$env")"
  [ "$name" = "$(expected_name "$env")" ] && pass "display name is '$name'" || fail "display name is '$name', expected '$(expected_name "$env")'"
  [ "$short" = "$EXPECT_NAME" ] && pass "CFBundleShortVersionString $short matches pubspec.yaml" || fail "CFBundleShortVersionString '$short' != pubspec $EXPECT_NAME"
  [ "$build" = "$EXPECT_BUILD" ] && pass "CFBundleVersion $build matches pubspec.yaml" || fail "CFBundleVersion '$build' != pubspec $EXPECT_BUILD"

  # Unsigned means: no provisioning profile, no code-signature resources and, where codesign
  # exists, no signing authority. (A linker-applied ad-hoc signature on the executable is not
  # a signing identity.)
  if [ -e "$app/embedded.mobileprovision" ]; then status="has-provisioning-profile"; fi
  if [ -d "$app/_CodeSignature" ]; then status="has-code-signature-resources"; fi
  if command -v codesign >/dev/null 2>&1; then
    cs_out=$(codesign -dvv "$app" 2>&1 || true)
    if grep -q '^Authority=' <<<"$cs_out"; then status="signed-by-an-identity"; fi
  fi
  [ "$status" = "unsigned" ] && pass "unsigned: no provisioning profile, no code signature, no signing authority" || fail "the app is not unsigned: $status"

  tmpdir
  if [ -f "$app/Frameworks/App.framework/App" ]; then
    if out=$(tool/verify_build_config.sh check-binary "$env" "$app/Frameworks/App.framework/App" 2>&1); then
      pass "App.framework/App contains the $env backend URL and not the other environment's"
      ev environment_check "$env-url-present-other-absent"
    else
      fail "App.framework/App failed the $env check: $(echo "$out" | tr '\n' ' ')"; ev environment_check failed
    fi
    ev environment_check_snapshots 1
  else
    fail "Dart AOT snapshot not found at $app/Frameworks/App.framework/App"
    ev environment_check failed; ev environment_check_snapshots 0
  fi
  exe=$(plist_get "$plist" CFBundleExecutable)
  if command -v lipo >/dev/null 2>&1 && [ -f "$app/$exe" ]; then archs=$(lipo -info "$app/$exe" 2>&1 | sed 's/.*: //'); fi

  ev artifact_kind ios-app; ev artifact_file "$(basename "$app")"
  ev artifact_sha256 "$(tree_sha256 "$app")"
  ev artifact_sha256_basis "sha256 of the sorted per-file sha256 manifest of the .app directory"
  ev artifact_bytes "$(du -sk "$app" | cut -f1)KiB"
  if [ -f "$app/Frameworks/App.framework/App" ]; then ev app_snapshot_sha256 "$(sha256_of "$app/Frameworks/App.framework/App")"; fi
  if [ -f "$app/$exe" ]; then ev executable_sha256 "$(sha256_of "$app/$exe")"; fi
  ev executable_archs "$archs"
  ev environment "$env"; ev application_id "$id"; ev display_name "$name"
  ev version_name "$short"; ev version_code "$build"
  ev signing "$status"; ev distributable "no"
}

# ---- driver -------------------------------------------------------------------------------
run_kind() { # KIND ENV FILE SIGNING
  case "$1" in
    apk) verify_apk "$2" "$3" "$4" ;;
    aab) verify_aab "$2" "$3" "$4" ;;
    ios) verify_ios "$2" "$3" ;;
    *) die "unknown kind '$1'" ;;
  esac
}

# One check run, isolated in a subshell so a negative run cannot disturb the counters.
# Prints nothing; returns the verifier's verdict (0 = all checks passed).
quiet_run() {
  ( run_kind "$@" >/dev/null 2>&1; [ "$failures" -eq 0 ] )
}

finish() {
  echo
  echo "evidence:"
  printf '%s' "$EVIDENCE" | sed 's/^/  /'
  if [ "$failures" -ne 0 ]; then
    echo "RESULT: FAILED ($failures check(s))"
    exit 1
  fi
  echo "RESULT: OK"
}

cmd=${1:-}
case "$cmd" in
  apk|aab|ios)
    [ $# -ge 3 ] || die "usage: $0 $cmd ENV FILE [--signing debug|unsigned] [--evidence OUT]"
    kind=$cmd; env=$2; file=$3; shift 3
    signing=debug; evidence_out=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --signing) signing=${2:-}; case "$signing" in debug|unsigned) ;; *) die "--signing must be debug or unsigned" ;; esac; shift 2 ;;
        --evidence) evidence_out=${2:-}; [ -n "$evidence_out" ] || die "--evidence needs a path"; shift 2 ;;
        --debug-build) [ "$kind" = "apk" ] || die "--debug-build is only for apk"; DEBUG_BUILD=1; shift ;;
        *) die "unknown option '$1'" ;;
      esac
    done
    expected_id "$env" >/dev/null
    [ -e "$file" ] || die "$file not found"
    echo "Verifying $kind for the $env environment: $file"
    run_kind "$kind" "$env" "$file" "$signing"
    if [ -n "$evidence_out" ]; then
      printf '%s' "$EVIDENCE" >"$evidence_out"
      echo "  evidence written to $evidence_out"
    fi
    finish
    ;;
  selftest)
    [ $# -ge 4 ] || die "usage: $0 selftest apk|aab|ios ENV FILE [--signing debug|unsigned]"
    kind=$2; env=$3; file=$4; shift 4
    signing=debug
    while [ $# -gt 0 ]; do
      case "$1" in
        --signing) signing=${2:-debug}; shift 2 ;;
        --debug-build) [ "$kind" = "apk" ] || die "--debug-build is only for apk"; DEBUG_BUILD=1; shift ;;
        *) die "unknown option '$1'" ;;
      esac
    done
    case "$env" in staging) other=production ;; production) other=staging ;; *) die "ENV must be staging or production" ;; esac
    [ -e "$file" ] || die "$file not found"
    echo "Self-test of the $kind verifier on $file"
    if quiet_run "$kind" "$env" "$file" "$signing"; then pass "accepts the artifact as $env"; else fail "does not accept the artifact as $env"; fi
    if quiet_run "$kind" "$other" "$file" "$signing"; then fail "ACCEPTED the $env artifact as $other (must be rejected)"; else pass "rejects the $env artifact when claimed as $other"; fi
    if [ "$kind" != "ios" ]; then
      if [ "$signing" = "debug" ]; then wrong=unsigned; else wrong=debug; fi
      if quiet_run "$kind" "$env" "$file" "$wrong"; then fail "ACCEPTED a $signing-signed artifact as $wrong (must be rejected)"; else pass "rejects a $signing-signed artifact claimed as $wrong"; fi
    fi
    if [ "$failures" -ne 0 ]; then echo "RESULT: FAILED ($failures)"; exit 1; fi
    echo "RESULT: OK"
    ;;
  consistent)
    [ $# -eq 3 ] || die "usage: $0 consistent EVIDENCE_A EVIDENCE_B"
    for key in environment application_id display_name version_name version_code signing; do
      a=$(sed -n "s/^$key=//p" "$2" | sed -n '1p'); b=$(sed -n "s/^$key=//p" "$3" | sed -n '1p')
      if [ -n "$a" ] && [ "$a" = "$b" ]; then pass "$key is identical: $a"; else fail "$key differs or is missing: '$a' vs '$b'"; fi
    done
    if [ "$failures" -ne 0 ]; then echo "RESULT: FAILED ($failures)"; exit 1; fi
    echo "RESULT: OK"
    ;;
  matrix)
    echo "staging     $STAGING_ID  '$STAGING_NAME'"
    echo "production  $PRODUCTION_ID  '$PRODUCTION_NAME'"
    load_version
    echo "version     $EXPECT_NAME (build $EXPECT_BUILD), from pubspec.yaml"
    ;;
  *)
    sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
