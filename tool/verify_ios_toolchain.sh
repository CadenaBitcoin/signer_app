#!/usr/bin/env bash
# Static check of the iOS toolchain pins and of the iOS deployment targets. Read-only; it needs
# no Flutter, Xcode or macOS and runs on Linux and with the system bash 3.2 of macOS.
#
#   tool/verify_ios_toolchain.sh [REPO_ROOT]
#
# 1. The two iOS build workflows (.github/workflows/ios-ci-validation.yml and the `ios` job of
#    build-variants.yml) must pin the SAME runner image, Xcode, minimum SDK, CocoaPods, Flutter,
#    Dart and Rust library, in a consistent form: the Xcode path names the Xcode version, the
#    minimum SDK is at least Apple's App Store Connect floor (26) and not newer than that Xcode,
#    the runner is a fixed image (not `latest`), and every artifact verification passes
#    --min-sdk. A toolchain edited in one workflow only is rejected here.
#    Podfile.lock drift must fail the build in both workflows, and the committed lock must
#    name the pinned CocoaPods version.
# 2. The deployment targets (Xcode project, Podfile, AppFrameworkInfo.plist, the dlc_wallet
#    podspec) are listed with what each one governs. A value below Apple's floor (iOS 13) or a
#    podspec that needs a newer iOS than the Podfile allows is a failure; a Podfile target above
#    the project's target is a WARNING (the compiled app is checked by tool/verify_artifact.sh).
#
# Exit 0 only if no check failed.
# Note: no `grep -q` at the end of a pipeline under pipefail (an early-closed pipe gives SIGPIPE
# and a spurious failure); here-strings are used instead.
set -euo pipefail
ROOT=$(cd "${1:-$(dirname "$0")/..}" && pwd)
APPLE_MIN_SDK=26          # App Store Connect uploads: Xcode 26 / iOS 26 SDK or later (2026-04-28)
APPLE_MIN_DEPLOYMENT=13   # iOS apps uploaded to App Store Connect must target iOS 13 or later

failures=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; failures=$((failures + 1)); }
warn() { echo "  WARN  $1"; }

ver_num() {
  local a="" b="" c=""
  case "$1" in ''|*[!0-9.]*) echo 0; return 0 ;; esac
  IFS=. read -r a b c <<<"$1"
  echo $(( ${a:-0} * 1000000 + ${b:-0} * 1000 + ${c:-0} ))
}

VALIDATION=$ROOT/.github/workflows/ios-ci-validation.yml
VARIANTS=$ROOT/.github/workflows/build-variants.yml
for f in "$VALIDATION" "$VARIANTS"; do
  [ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 2; }
done

# The text of the iOS part of each workflow: all of the validation workflow, and the `ios:` job.
ios_text() {
  case "$1" in
    "$VARIANTS") awk '/^  ios:[[:space:]]*$/ {f=1; next} f && /^  [A-Za-z_-]+:[[:space:]]*$/ {f=0} f' "$1" ;;
    *) cat "$1" ;;
  esac
}
# value of a KEY: in the text on stdin (first occurrence; quotes and trailing comment removed)
yaml_value() {
  sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" | sed -n '1p' | sed 's/[[:space:]]*#.*$//; s/^"//; s/"$//; s/[[:space:]]*$//'
}

echo "iOS toolchain pins"
V_TEXT=$(ios_text "$VALIDATION"); B_TEXT=$(ios_text "$VARIANTS")
for key in runs-on XCODE_APP EXPECTED_XCODE EXPECTED_MIN_SDK_MAJOR EXPECTED_COCOAPODS EXPECTED_FLUTTER \
           EXPECTED_FLUTTER_REVISION EXPECTED_DART RUST_LIB EXPECTED_RUST_LIB_SHA256; do
  a=$(printf '%s\n' "$V_TEXT" | yaml_value "$key"); b=$(printf '%s\n' "$B_TEXT" | yaml_value "$key")
  if [ -z "$a" ] || [ -z "$b" ]; then fail "$key is missing (validation: '${a:-}', build-variants: '${b:-}')"
  elif [ "$a" = "$b" ]; then pass "$key is $a in both workflows"
  else fail "$key differs: ios-ci-validation.yml '$a' vs build-variants.yml '$b'"; fi
done

xcode=$(printf '%s\n' "$V_TEXT" | yaml_value EXPECTED_XCODE)
xcode_app=$(printf '%s\n' "$V_TEXT" | yaml_value XCODE_APP)
min_sdk=$(printf '%s\n' "$V_TEXT" | yaml_value EXPECTED_MIN_SDK_MAJOR)
runner=$(printf '%s\n' "$V_TEXT" | yaml_value runs-on)
cocoapods=$(printf '%s\n' "$V_TEXT" | yaml_value EXPECTED_COCOAPODS)

[ "$xcode_app" = "/Applications/Xcode_${xcode}.app" ] \
  && pass "XCODE_APP names the pinned Xcode ($xcode_app)" || fail "XCODE_APP '$xcode_app' is not /Applications/Xcode_${xcode}.app"
case "$min_sdk" in
  ''|*[!0-9]*) fail "EXPECTED_MIN_SDK_MAJOR '$min_sdk' is not a whole number" ;;
  *) if [ "$min_sdk" -ge "$APPLE_MIN_SDK" ]; then pass "minimum SDK $min_sdk is at least Apple's floor ($APPLE_MIN_SDK)"
     else fail "minimum SDK $min_sdk is below Apple's App Store Connect floor ($APPLE_MIN_SDK)"; fi
     xmajor=${xcode%%.*}
     case "$xmajor" in ''|*[!0-9]*) fail "EXPECTED_XCODE '$xcode' is not a version" ;;
       *) if [ "$xmajor" -ge "$min_sdk" ]; then pass "Xcode $xcode can provide the iOS $min_sdk SDK"
          else fail "Xcode $xcode is older than the iOS $min_sdk SDK it must provide"; fi ;;
     esac ;;
esac
case "$runner" in
  macos-*latest*|"") fail "runs-on '$runner' is not a fixed macOS image" ;;
  macos-*) pass "runs-on is the fixed image $runner" ;;
  *) fail "runs-on '$runner' is not a macOS image" ;;
esac
case "$cocoapods" in
  [0-9]*.[0-9]*.[0-9]*) pass "CocoaPods is pinned to $cocoapods" ;;
  *) fail "EXPECTED_COCOAPODS '$cocoapods' is not a version" ;;
esac

for pair in "$VALIDATION:ios-ci-validation.yml" "$VARIANTS:build-variants.yml"; do
  f=${pair%%:*}; name=${pair#*:}; text=$(ios_text "$f")
  grep -qF "name: Select Xcode ${xcode}" <<<"$text" \
    && pass "$name: the Xcode step is named for $xcode" || fail "$name: no step 'Select Xcode ${xcode}'"
  grep -q 'EXPECTED_XCODE' <<<"$text" \
    && grep -qF 'xcode-select -s "$XCODE_APP/Contents/Developer"' <<<"$text" \
    && pass "$name: selects Xcode explicitly and compares the result" || fail "$name: does not select and verify Xcode explicitly"
  grep -qF 'Expected an iPhoneOS SDK' <<<"$text" \
    && pass "$name: asserts the runner's iPhoneOS SDK" || fail "$name: does not assert the iPhoneOS SDK"
  grep -qF '$EXPECTED_COCOAPODS' <<<"$text" \
    && pass "$name: asserts the CocoaPods version" || fail "$name: does not assert the CocoaPods version"
  calls=$(printf '%s\n' "$text" | grep -c 'verify_artifact.sh \(selftest \)\{0,1\}ios' || true)
  bare=$(printf '%s\n' "$text" | grep 'verify_artifact.sh \(selftest \)\{0,1\}ios' | grep -vc -- '--min-sdk "\$EXPECTED_MIN_SDK_MAJOR"' || true)
  if [ "$calls" -gt 0 ] && [ "$bare" -eq 0 ]; then pass "$name: all $calls artifact verification(s) require the minimum SDK"
  else fail "$name: $bare of $calls artifact verification(s) do not pass --min-sdk \"\$EXPECTED_MIN_SDK_MAJOR\""; fi
done

# Podfile.lock drift must FAIL the build (tool/check_build_drift.sh), in both workflows: the step
# exists, runs after the build, is not allowed to fail silently, and no warning-only handling
# of the drift is left.
for pair in "$VALIDATION:ios-ci-validation.yml" "$VARIANTS:build-variants.yml"; do
  f=${pair%%:*}; name=${pair#*:}; text=$(ios_text "$f")
  build_line=$(printf '%s\n' "$text" | grep -n 'flutter build ios --release --no-codesign --flavor "\$BUILD_' | sed -n '1p' | sed 's/:.*//' || true)
  drift_line=$(printf '%s\n' "$text" | grep -n 'run: /bin/bash tool/check_build_drift.sh$' | sed -n '1p' | sed 's/:.*//' || true)
  if [ -z "$drift_line" ]; then fail "$name: does not run tool/check_build_drift.sh (Podfile.lock drift would not fail the build)"
  elif [ -z "$build_line" ] || [ "$drift_line" -le "$build_line" ]; then fail "$name: tool/check_build_drift.sh does not run after the build"
  else pass "$name: Podfile.lock drift fails the job (tool/check_build_drift.sh runs after the build)"; fi
  if grep -qF 'continue-on-error' <<<"$text"; then fail "$name: a step may fail silently (continue-on-error in the iOS part)"
  else pass "$name: no iOS step may fail silently (no continue-on-error)"; fi
  if grep -qF '::warning title=ios/Podfile.lock drift' <<<"$text"; then fail "$name: still reports Podfile.lock drift as a warning"
  else pass "$name: Podfile.lock drift is not reported as a mere warning"; fi
done

# The committed lock must be the one the pinned CocoaPods writes.
lock=$ROOT/ios/Podfile.lock
lock_pods=$(sed -n 's/^COCOAPODS: //p' "$lock" 2>/dev/null | sed -n '1p')
if [ -z "$lock_pods" ]; then fail "ios/Podfile.lock records no CocoaPods version"
elif [ "$lock_pods" = "$cocoapods" ]; then pass "ios/Podfile.lock was generated by the pinned CocoaPods ($lock_pods)"
else fail "ios/Podfile.lock was generated by CocoaPods $lock_pods but the workflows pin $cocoapods"; fi

echo
echo "iOS deployment targets"
pbx=$ROOT/ios/Runner.xcodeproj/project.pbxproj
targets=$(sed -n 's/^[[:space:]]*IPHONEOS_DEPLOYMENT_TARGET = \([0-9.]*\);.*/\1/p' "$pbx" | sort -u)
ntargets=$(printf '%s\n' "$targets" | grep -c . || true)
project_target=""
if [ "$ntargets" -eq 1 ]; then
  project_target=$targets
  pass "Xcode project: one IPHONEOS_DEPLOYMENT_TARGET ($project_target) in every configuration; it governs the Runner app (MinimumOSVersion)"
else
  fail "Xcode project: $ntargets different IPHONEOS_DEPLOYMENT_TARGET values ($(printf '%s' "$targets" | tr '\n' ' ')); the app's minimum is ambiguous"
fi
podfile_target=$(sed -n "s/^platform :ios, '\([0-9.]*\)'.*/\1/p" "$ROOT/ios/Podfile" | sed -n '1p')
framework_target=$(sed -n '/<key>MinimumOSVersion<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$ROOT/ios/Flutter/AppFrameworkInfo.plist" | sed -n '1p')
podspec=$ROOT/flutter_plugin/flutter_plugin/ios/dlc_wallet.podspec
podspec_target=$(sed -n "s/.*s\.platform[[:space:]]*=[[:space:]]*:ios,[[:space:]]*'\([0-9.]*\)'.*/\1/p" "$podspec" | sed -n '1p')
echo "         Podfile platform (Pods project; inherited by pods declaring < 13): ${podfile_target:-?}"
echo "         AppFrameworkInfo.plist MinimumOSVersion (App.framework): ${framework_target:-?}"
echo "         dlc_wallet podspec platform (lowest it supports)   : ${podspec_target:-?}"

for pair in "Xcode project:$project_target" "Podfile:$podfile_target" "AppFrameworkInfo.plist:$framework_target" "dlc_wallet podspec:$podspec_target"; do
  what=${pair%%:*}; val=${pair#*:}
  if [ -z "$val" ]; then fail "$what: no deployment target found"
  elif [ "$(ver_num "$val")" -ge "$(ver_num "$APPLE_MIN_DEPLOYMENT")" ] || [ "$what" = "dlc_wallet podspec" ]; then pass "$what: iOS $val (App Store Connect needs $APPLE_MIN_DEPLOYMENT or later for the app)"
  else fail "$what: iOS $val is below Apple's floor ($APPLE_MIN_DEPLOYMENT)"; fi
done
if [ -n "$podspec_target" ] && [ -n "$podfile_target" ]; then
  if [ "$(ver_num "$podspec_target")" -le "$(ver_num "$podfile_target")" ]; then pass "the dlc_wallet podspec (iOS $podspec_target) can be installed under the Podfile platform (iOS $podfile_target)"
  else fail "the dlc_wallet podspec needs iOS $podspec_target but the Podfile platform is iOS $podfile_target"; fi
fi
if [ -n "$project_target" ] && [ -n "$podfile_target" ]; then
  if [ "$(ver_num "$podfile_target")" -gt "$(ver_num "$project_target")" ]; then
    warn "pods whose podspec declares a minimum below iOS 13 are built for the Podfile platform (iOS $podfile_target) but the app declares iOS $project_target; the effective floor of the installed app is the higher value. The built app is checked by tool/verify_artifact.sh (deployment_target_conflicts); nothing is changed here."
  else
    pass "the app's declared minimum (iOS $project_target) is not below the pods' target (iOS $podfile_target)"
  fi
fi

echo
if [ "$failures" -ne 0 ]; then echo "RESULT: FAILED ($failures check(s))"; exit 1; fi
echo "RESULT: OK"
