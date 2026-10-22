#!/usr/bin/env bash
# Verifies a BUILT artifact against the application-identity matrix, pubspec.yaml and
# the build configuration, and prints independently checkable evidence.
#
#   tool/verify_artifact.sh apk ENV FILE.apk [--signing debug|unsigned] [--debug-build] [--evidence OUT]
#   tool/verify_artifact.sh aab ENV FILE.aab [--signing debug|unsigned] [--evidence OUT]
#   tool/verify_artifact.sh ios ENV Runner.app             [--min-sdk N] [--evidence OUT]
#   tool/verify_artifact.sh selftest apk|aab|ios ENV FILE [--signing ...] [--debug-build] [--min-sdk N]
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
# iOS additionally reads the toolchain that built the app FROM the app: the SDK recorded in
# Info.plist (DTSDKName, DTXcode) and in the executable's Mach-O build version, the declared
# MinimumOSVersion against the executable's minimum OS, and the minimum OS of every embedded
# framework. --min-sdk N fails the check unless the app was built with an iOS SDK >= N
# (Apple requires 26 for App Store Connect uploads); without it the SDK is only recorded.
# A framework that needs a newer OS than the app declares is reported as a WARNING and in the
# evidence (deployment_target_conflicts), not as a failure: it is a recorded inconsistency.
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
CALLER_PWD=$PWD
cd "$(dirname "$0")/.."
# The artifact path is given relative to the caller; the checks below change directory.
abspath() { case "$1" in /*) echo "$1" ;; *) echo "$CALLER_PWD/$1" ;; esac; }

# The identity matrix. The Android application ID is the package published on Google Play
# (config/release/published_versions.json, Issue #72); the iOS bundle ID is a separate identifier
# (ios/Flutter/Flavor-<flavor>.xcconfig) that is not the Android one. The display names are shared.
ANDROID_STAGING_ID=com.cadenabitcoin.mobile.signer.staging
ANDROID_PRODUCTION_ID=com.cadenabitcoin.mobile.signer
IOS_STAGING_ID=com.app.cadenabitcoin.staging
IOS_PRODUCTION_ID=com.app.cadenabitcoin
STAGING_NAME="Cadena Signer STAGING"
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

expected_id() { # ENV PLATFORM(android|ios)
  case "$2:$1" in
    android:staging) echo "$ANDROID_STAGING_ID" ;;
    android:production) echo "$ANDROID_PRODUCTION_ID" ;;
    ios:staging) echo "$IOS_STAGING_ID" ;;
    ios:production) echo "$IOS_PRODUCTION_ID" ;;
    *) die "ENV must be staging or production (platform ${2:-none})" ;;
  esac
}
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

  [ "$id" = "$(expected_id "$env" android)" ] && pass "application ID is $id" || fail "application ID is '$id', expected $(expected_id "$env" android)"
  [ "$label" = "$(expected_name "$env")" ] && pass "display name is '$label'" || fail "display name is '$label', expected '$(expected_name "$env")'"
  [ "$name" = "$EXPECT_NAME" ] && pass "versionName $name matches pubspec.yaml" || fail "versionName '$name' != pubspec $EXPECT_NAME"
  [ "$code" = "$EXPECT_BUILD" ] && pass "versionCode $code matches pubspec.yaml" || fail "versionCode '$code' != pubspec $EXPECT_BUILD"
  if [ "$DEBUG_BUILD" -eq 1 ]; then
    if grep -q '^application-debuggable' <<<"$badging"; then pass "debug build: the application is debuggable, as declared"; else fail "--debug-build was given but the application is not debuggable"; fi
  elif grep -q '^application-debuggable' <<<"$badging"; then fail "the application is marked debuggable"; else pass "the application is not debuggable"; fi

  kind=unsigned; dn=""; digest=""
  if sign_out=$("$apksigner" verify --print-certs "$file" 2>&1); then
    # The label before "certificate DN:" differs between apksigner versions ("Signer #1 ..."
    # up to build-tools 36, "V2 Signer: ..." in 37), so match on the part that does not.
    # Every signer must be the debug key; a signature that cannot be read is not "debug".
    dns=$(sed -n 's/^.*certificate DN: //p' <<<"$sign_out")
    dn=$(sed -n '1p' <<<"$dns")
    digest=$(sed -n 's/^.*certificate SHA-256 digest: //p' <<<"$sign_out" | sed -n '1p')
    if [ -z "$dns" ]; then kind="signed-unidentified"
    elif grep -qv 'CN=Android Debug' <<<"$dns"; then kind="signed-by-other-key"
    else kind=debug; fi
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

  [ "$id" = "$(expected_id "$env" android)" ] && pass "application ID is $id" || fail "application ID is '$id', expected $(expected_id "$env" android)"
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

# Dotted version -> comparable integer (X[.Y[.Z]], digits only).
ver_num() {
  local a="" b="" c=""
  case "$1" in ''|*[!0-9.]*) echo 0; return 0 ;; esac
  IFS=. read -r a b c <<<"$1"
  echo $(( ${a:-0} * 1000000 + ${b:-0} * 1000 + ${c:-0} ))
}
ver_major() { echo "${1%%.*}"; }
MACHO_INFO=tool/macho_info.py
APPLE_MIN_DEPLOYMENT=13.0   # App Store Connect: iOS apps must target iOS 13 or later (from 2026-09-09)
MIN_SDK=""
warn() { echo "  WARN  $1"; }

# Everything the built app says about the toolchain and the OS versions it needs.
# Sets the evidence; counts failures through pass/fail.
verify_ios_toolchain() { # APP_DIR PLIST EXECUTABLE_NAME
  local app=$1 plist=$2 exe=$3
  local plat sdkname sdkver xcode xcodebuild sdkbuild declared sdk_from_name
  local lines line kv arch plat_m minos_m sdk_m exe_min="" exe_sdk="" exe_platform="" exe_arch=""
  plat=$(plist_get "$plist" DTPlatformName); sdkname=$(plist_get "$plist" DTSDKName)
  sdkver=$(plist_get "$plist" DTPlatformVersion); xcode=$(plist_get "$plist" DTXcode)
  xcodebuild=$(plist_get "$plist" DTXcodeBuild); sdkbuild=$(plist_get "$plist" DTSDKBuild)
  declared=$(plist_get "$plist" MinimumOSVersion)
  ev built_platform "$plat"; ev built_sdk_name "$sdkname"; ev built_platform_version "$sdkver"
  ev built_xcode "$xcode"; ev built_xcode_build "$xcodebuild"; ev built_sdk_build "$sdkbuild"
  ev minimum_os_version "$declared"

  [ "$plat" = "iphoneos" ] && pass "Info.plist DTPlatformName is iphoneos (a device build)" \
    || fail "Info.plist DTPlatformName is '$plat', expected iphoneos"
  sdk_from_name=""
  case "$sdkname" in
    iphoneos[0-9]*) sdk_from_name=${sdkname#iphoneos} ;;
  esac
  case "$sdk_from_name" in ''|*[!0-9.]*) sdk_from_name="" ;; esac
  if [ -z "$sdk_from_name" ]; then
    fail "Info.plist DTSDKName '$sdkname' does not name an iPhoneOS SDK version"
  elif [ -n "$MIN_SDK" ]; then
    if [ "$(ver_major "$sdk_from_name")" -ge "$MIN_SDK" ]; then pass "Info.plist records the iOS $sdk_from_name SDK (SDK $MIN_SDK or later required)"
    else fail "Info.plist records the iOS $sdk_from_name SDK; SDK $MIN_SDK or later is required"; fi
  else
    pass "Info.plist records the iOS $sdk_from_name SDK (no minimum required here)"
  fi

  if [ ! -f "$app/$exe" ]; then
    fail "executable $exe not found in the app"; ev executable_macho "missing"; return 0
  fi
  if ! lines=$(python3 -I "$MACHO_INFO" "$app/$exe" 2>&1); then
    fail "the executable is not a readable Mach-O binary: $lines"; ev executable_macho "unreadable"; return 0
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    arch=""; plat_m=""; minos_m=""; sdk_m=""
    for kv in $line; do
      case "$kv" in arch=*) arch=${kv#arch=} ;; platform=*) plat_m=${kv#platform=} ;; minos=*) minos_m=${kv#minos=} ;; sdk=*) sdk_m=${kv#sdk=} ;; esac
    done
    [ "$plat_m" = "ios" ] && pass "executable slice $arch is built for iOS devices" \
      || fail "executable slice $arch is built for '$plat_m', not iOS devices"
    if [ -n "$MIN_SDK" ]; then
      case "$sdk_m" in
        ''|n/a) fail "executable slice $arch records no SDK version" ;;
        *) if [ "$(ver_major "$sdk_m")" -ge "$MIN_SDK" ]; then pass "executable slice $arch was linked against the iOS $sdk_m SDK"
           else fail "executable slice $arch was linked against the iOS $sdk_m SDK; SDK $MIN_SDK or later is required"; fi ;;
      esac
    fi
    if [ -n "$declared" ] && [ "$(ver_num "$minos_m")" -eq "$(ver_num "$declared")" ] && [ "$declared" != "0" ]; then :; else
      fail "executable slice $arch needs iOS $minos_m but Info.plist MinimumOSVersion is '$declared'"
    fi
    exe_arch=$arch; exe_platform=$plat_m; exe_min=$minos_m; exe_sdk=$sdk_m
  done <<<"$lines"
  ev executable_platform "$exe_platform"; ev executable_minos "$exe_min"; ev executable_sdk "$exe_sdk"
  ev executable_macho_arch "$exe_arch"

  if [ -z "$declared" ]; then
    fail "Info.plist has no MinimumOSVersion"
  elif [ "$(ver_num "$declared")" -ge "$(ver_num "$APPLE_MIN_DEPLOYMENT")" ]; then
    pass "the app declares iOS $declared as its minimum (App Store Connect needs $APPLE_MIN_DEPLOYMENT or later)"
  else
    fail "the app declares iOS $declared as its minimum; App Store Connect needs $APPLE_MIN_DEPLOYMENT or later"
  fi

  # Every embedded framework: record its platform and minimum OS; a device app must not embed a
  # simulator build, and a framework needing a newer OS than the app declares is a conflict.
  local fw fwexe fwlines fwline conflicts=0 listed="" fwname fp fm fs
  for fw in "$app"/Frameworks/*.framework; do
    [ -d "$fw" ] || continue
    fwname=$(basename "$fw")
    fwexe=""
    [ -f "$fw/Info.plist" ] && fwexe=$(plist_get "$fw/Info.plist" CFBundleExecutable)
    [ -n "$fwexe" ] && [ -f "$fw/$fwexe" ] || { ev "framework.$fwname" "no executable"; continue; }
    if ! fwlines=$(python3 -I "$MACHO_INFO" "$fw/$fwexe" 2>/dev/null); then ev "framework.$fwname" "not a Mach-O binary"; continue; fi
    listed=""
    while IFS= read -r fwline; do
      [ -n "$fwline" ] || continue
      fp=""; fm=""; fs=""
      for kv in $fwline; do
        case "$kv" in platform=*) fp=${kv#platform=} ;; minos=*) fm=${kv#minos=} ;; sdk=*) fs=${kv#sdk=} ;; esac
      done
      listed="${listed}${listed:+; }$fp minos=$fm sdk=$fs"
      if [ "$fp" != "ios" ]; then fail "framework $fwname is built for '$fp', not iOS devices"; fi
      if [ -n "$declared" ] && [ "$(ver_num "$fm")" -gt "$(ver_num "$declared")" ]; then
        conflicts=$((conflicts + 1))
        warn "framework $fwname needs iOS $fm but the app declares iOS $declared as its minimum"
      fi
    done <<<"$fwlines"
    ev "framework.$fwname" "$listed"
  done
  ev deployment_target_conflicts "$conflicts"
}

verify_ios() { # ENV APP_DIR
  local env=$1 app=$2 plist id name short build status="unsigned" exe archs="" cs_out out
  load_version
  plist="$app/Info.plist"
  [ -f "$plist" ] || die "$plist not found (pass the Runner.app directory)"
  id=$(plist_get "$plist" CFBundleIdentifier); name=$(plist_get "$plist" CFBundleDisplayName)
  short=$(plist_get "$plist" CFBundleShortVersionString); build=$(plist_get "$plist" CFBundleVersion)

  [ "$id" = "$(expected_id "$env" ios)" ] && pass "bundle identifier is $id" || fail "bundle identifier is '$id', expected $(expected_id "$env" ios)"
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
  verify_ios_toolchain "$app" "$plist" "$exe"
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
# The output and the exit status stay available in QUIET_OUT / QUIET_RC for diagnosis.
QUIET_OUT=""
QUIET_RC=0
quiet_run() {
  QUIET_RC=0
  QUIET_OUT=$( { run_kind "$@"; [ "$failures" -eq 0 ]; } 2>&1 ) || QUIET_RC=$?
  return "$QUIET_RC"
}
# When the verifier unexpectedly rejects the artifact, show why (diagnosis only).
show_quiet_failure() {
  echo "        verifier exit status $QUIET_RC; its output was:"
  printf '%s\n' "$QUIET_OUT" | sed 's/^/        | /'
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
    kind=$cmd; env=$2; file=$(abspath "$3"); shift 3
    signing=debug; evidence_out=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --signing) signing=${2:-}; case "$signing" in debug|unsigned) ;; *) die "--signing must be debug or unsigned" ;; esac; shift 2 ;;
        --evidence) evidence_out=${2:-}; [ -n "$evidence_out" ] || die "--evidence needs a path"; shift 2 ;;
        --debug-build) [ "$kind" = "apk" ] || die "--debug-build is only for apk"; DEBUG_BUILD=1; shift ;;
        --min-sdk) [ "$kind" = "ios" ] || die "--min-sdk is only for ios"; MIN_SDK=${2:-}; case "$MIN_SDK" in ''|*[!0-9]*) die "--min-sdk needs a whole number" ;; esac; shift 2 ;;
        *) die "unknown option '$1'" ;;
      esac
    done
    expected_id "$env" android >/dev/null
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
    kind=$2; env=$3; file=$(abspath "$4"); shift 4
    signing=debug
    while [ $# -gt 0 ]; do
      case "$1" in
        --signing) signing=${2:-debug}; shift 2 ;;
        --debug-build) [ "$kind" = "apk" ] || die "--debug-build is only for apk"; DEBUG_BUILD=1; shift ;;
        --min-sdk) [ "$kind" = "ios" ] || die "--min-sdk is only for ios"; MIN_SDK=${2:-}; case "$MIN_SDK" in ''|*[!0-9]*) die "--min-sdk needs a whole number" ;; esac; shift 2 ;;
        *) die "unknown option '$1'" ;;
      esac
    done
    case "$env" in staging) other=production ;; production) other=staging ;; *) die "ENV must be staging or production" ;; esac
    [ -e "$file" ] || die "$file not found"
    echo "Self-test of the $kind verifier on $file"
    if quiet_run "$kind" "$env" "$file" "$signing"; then pass "accepts the artifact as $env"; else fail "does not accept the artifact as $env"; show_quiet_failure; fi
    if quiet_run "$kind" "$other" "$file" "$signing"; then fail "ACCEPTED the $env artifact as $other (must be rejected)"; else pass "rejects the $env artifact when claimed as $other"; fi
    if [ "$kind" = "ios" ] && [ -n "$MIN_SDK" ]; then
      want_sdk=$MIN_SDK; MIN_SDK=$((MIN_SDK + 1000))
      if quiet_run "$kind" "$env" "$file" "$signing"; then fail "ACCEPTED an app built with an older SDK than the required minimum (must be rejected)"; else pass "rejects the app when a newer SDK than it was built with is required"; fi
      MIN_SDK=$want_sdk
    fi
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
    echo "android  staging     $ANDROID_STAGING_ID  '$STAGING_NAME'"
    echo "android  production  $ANDROID_PRODUCTION_ID  '$PRODUCTION_NAME'"
    echo "ios      staging     $IOS_STAGING_ID  '$STAGING_NAME'"
    echo "ios      production  $IOS_PRODUCTION_ID  '$PRODUCTION_NAME'"
    load_version
    echo "version     $EXPECT_NAME (build $EXPECT_BUILD), from pubspec.yaml"
    ;;
  *)
    sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
