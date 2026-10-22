#!/usr/bin/env bash
# Read-only check of the product version and its Android/iOS wiring.
# Policy: docs/RELEASE_POLICY.md (section 4).
# Usage:  tool/verify_version.sh [--channel staging|production]
#                                [--release-id vMAJOR.MINOR.PATCH[-rc.N]] [repo-root]
#
# It never modifies anything and needs no Flutter, Gradle or Xcode. It checks that
#   1. pubspec.yaml `version:` is MAJOR.MINOR.PATCH+BUILD (no suffix, no leading zeros);
#   2. the Android versionCode/versionName and iOS CFBundleVersion/CFBundleShortVersionString
#      are derived only from it, and both platforms read it identically;
#   3. nothing in the repository overrides the version (build flags, literals, ABI splits);
#   4. with --release-id, the release identifier (e.g. v1.0.4-rc.1) is well formed and its
#      numeric part equals the product version in pubspec.yaml. The identifier is a label
#      for a Git revision; its -rc.N form is never written to pubspec.yaml or to Apple's
#      numeric version fields;
#   5. with --channel, the identifier kind matches the release branch: `staging` needs a
#      vX.Y.Z-rc.N identifier, `production` needs a plain vX.Y.Z (no staging identifier).
#
# This describes the CURRENT wiring: one version for both platforms and no overrides, plus
# exactly two flavors (production, staging) that change only the application identity
# (application ID / bundle ID and display name) and never the version. When the Android
# staging versionName (X.Y.Z-rc.N) is introduced, the same pull request must teach this
# script to expect exactly that wiring; it is not to be loosened ahead of time.
#   6. Android and iOS declare exactly the two flavors with the identities of
#      docs/BUILD_CONFIGURATION.md (Android production is the published Google Play package
#      com.cadenabitcoin.mobile.signer; the iOS bundle ID com.app.cadenabitcoin is separate;
#      the Kotlin namespace com.app.cadenabitcoin is a source package and is not an identity).
#
# Build numbers: today both platforms take the build number from pubspec.yaml, and check 3
# flags anything else as unintended. The policy does NOT forbid different Android/iOS build
# numbers in future (RELEASE_POLICY.md 4.3); adding such a mechanism needs an explicit,
# reviewed change to this script. The product version is never allowed to differ.
# Works with bash 3.2 (macOS) and GNU tools.
set -u

release_id=""
channel=""
root="."
while [ $# -gt 0 ]; do
  case "$1" in
    --release-id) release_id="${2:-}"; [ -n "$release_id" ] || { echo "FAIL --release-id needs a value"; exit 2; }; shift 2 ;;
    --channel) channel="${2:-}"; case "$channel" in staging|production) ;; *) echo "FAIL --channel must be 'staging' or 'production'"; exit 2 ;; esac; shift 2 ;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "FAIL unknown option '$1'"; exit 2 ;;
    *) root="$1"; shift ;;
  esac
done
cd "$root" || { echo "FAIL cannot enter '$root'"; exit 2; }

fails=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

# ---- 1. pubspec.yaml ---------------------------------------------------------------
[ -f pubspec.yaml ] || { echo "FAIL pubspec.yaml not found in $(pwd)"; exit 2; }

count="$(grep -c '^version:' pubspec.yaml)"
if [ "$count" -ne 1 ]; then
  fail "pubspec.yaml must contain exactly one top-level 'version:' line (found $count)"
  echo "RESULT: FAILED ($fails)"; exit 1
fi
raw="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//')"

# Component without leading zeros: 0 or [1-9][0-9]*
num='(0|[1-9][0-9]*)'
if printf '%s' "$raw" | grep -Eq "^${num}\.${num}\.${num}\+[1-9][0-9]*$"; then
  pass "pubspec version '$raw' is MAJOR.MINOR.PATCH+BUILD"
else
  fail "pubspec version '$raw' is not MAJOR.MINOR.PATCH+BUILD (numeric, no leading zeros, no -prerelease, build number >= 1)"
  echo "RESULT: FAILED ($fails)"; exit 1
fi
name="${raw%%+*}"
build="${raw##*+}"

# Release identifier (label of a Git revision): vMAJOR.MINOR.PATCH for production,
# vMAJOR.MINOR.PATCH-rc.N for a staging candidate. Its numeric part must be the product version.
if [ -n "$release_id" ]; then
  if printf '%s' "$release_id" | grep -Eq "^v${num}\.${num}\.${num}(-rc\.[1-9][0-9]*)?$"; then
    id_version="${release_id#v}"; id_version="${id_version%%-*}"
    if [ "$id_version" = "$name" ]; then
      pass "release identifier '$release_id' matches product version $name"
    else
      fail "release identifier '$release_id' is for $id_version but pubspec.yaml is $name"
    fi
  else
    fail "release identifier '$release_id' is not vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-rc.N"
  fi
fi

# Channel / identifier coherence (staging: rc identifier required; production: none).
if [ -n "$channel" ]; then
  case "$channel" in
    staging)
      if [ -z "$release_id" ]; then fail "channel staging requires --release-id vX.Y.Z-rc.N"
      elif printf '%s' "$release_id" | grep -Eq -- '-rc\.[1-9][0-9]*$'; then pass "channel staging: identifier '$release_id' is a candidate (-rc.N)"
      else fail "channel staging needs a -rc.N identifier, got '$release_id'"; fi ;;
    production)
      if [ -z "$release_id" ]; then fail "channel production requires --release-id vX.Y.Z"
      elif printf '%s' "$release_id" | grep -Eq -- '-'; then fail "channel production must not carry a staging identifier, got '$release_id'"
      else pass "channel production: identifier '$release_id' has no staging suffix"; fi ;;
  esac
fi

# Google Play versionCode ceiling (2,100,000,000); an Apple build number is just a counter here.
if [ "${#build}" -le 9 ] || { [ "${#build}" -eq 10 ] && [ "$build" -le 2100000000 ]; }; then
  pass "build number $build is within the Android versionCode range"
else
  fail "build number $build exceeds the Android versionCode limit 2100000000"
fi

# Same interpretation on both platforms. Flutter silently rewrites invalid values
# (iOS: strips every character except digits and dots); show that nothing is rewritten.
ios_name="$(printf '%s' "$name" | sed 's/[^0-9.]//g')"
ios_build="$(printf '%s' "$build" | sed 's/[^0-9.]//g')"
if [ "$ios_name" = "$name" ] && [ "$ios_build" = "$build" ]; then
  pass "Android and iOS read the same name '$name' and build '$build' (no coercion)"
else
  fail "a platform would rewrite the version (iOS would use '$ios_name' / '$ios_build')"
fi

# ---- 2. Android --------------------------------------------------------------------
gradle=android/app/build.gradle.kts
if [ ! -f "$gradle" ]; then
  fail "$gradle not found"
else
  grep -Eq '^[[:space:]]*versionCode[[:space:]]*=[[:space:]]*flutter\.versionCode[[:space:]]*$' "$gradle" \
    && pass "Android versionCode = flutter.versionCode" \
    || fail "$gradle: versionCode must be exactly 'flutter.versionCode'"
  grep -Eq '^[[:space:]]*versionName[[:space:]]*=[[:space:]]*flutter\.versionName[[:space:]]*$' "$gradle" \
    && pass "Android versionName = flutter.versionName" \
    || fail "$gradle: versionName must be exactly 'flutter.versionName'"
fi

# Any other place that could change a version or split it per ABI/flavor.
android_hits="$(grep -rnE 'versionCode|versionName|versionNameSuffix|versionCodeOverride|splits[[:space:]]*\{|flutter\.version' \
  android --include='*.gradle' --include='*.kts' --include='gradle.properties' 2>/dev/null \
  | grep -vE '^android/app/build.gradle.kts:[0-9]+:[[:space:]]*version(Code|Name)[[:space:]]*=[[:space:]]*flutter\.version(Code|Name)[[:space:]]*$' || true)"
if [ -z "$android_hits" ]; then
  pass "no other Android version, suffix or ABI-split configuration"
else
  fail "unexpected Android version-related configuration:"; echo "$android_hits" | sed 's/^/        /'
fi
[ -f android/app/build.gradle ] && fail "legacy android/app/build.gradle exists next to build.gradle.kts"

# Flavors: exactly production (the existing application ID) and staging (".staging"
# suffix); the flavor changes the identity only (no version, no signing).
if [ -f "$gradle" ]; then
  flavor_block() { # body of create("$1") { ... } in the productFlavors block
    sed -n "/^        create(\"$1\") {\$/,/^        }\$/p" "$gradle" | sed '1d;$d'
  }
  n_create="$(grep -cE '^        create\("[a-z]+"\) \{$' "$gradle")"
  n_any_create="$(grep -c 'create(' "$gradle")"
  [ "$n_create" -eq 2 ] && [ "$n_any_create" -eq 2 ] && [ "$(grep -cE '^    productFlavors \{$' "$gradle")" -eq 1 ] \
    && [ -n "$(flavor_block production)" ] && [ -n "$(flavor_block staging)" ] \
    && pass "Android declares exactly the flavors production and staging" \
    || fail "$gradle: expected exactly the flavors production and staging (found $n_create flavor blocks, $n_any_create create() calls)"
  [ "$(grep -cE '^    flavorDimensions \+= "environment"$' "$gradle")" -eq 1 ] \
    && pass "Android has the single flavor dimension 'environment'" \
    || fail "$gradle: expected exactly one flavorDimensions += \"environment\""
  [ "$(grep -cE '^        applicationId = "com\.cadenabitcoin\.mobile\.signer"$' "$gradle")" -eq 1 ] \
    && [ "$(grep -cE '^[[:space:]]*applicationId[[:space:]]*=' "$gradle")" -eq 1 ] \
    && pass "Android applicationId com.cadenabitcoin.mobile.signer is set once, in defaultConfig (the production identity, the published Google Play package)" \
    || fail "$gradle: applicationId must be set exactly once, to com.cadenabitcoin.mobile.signer, in defaultConfig"
  [ "$(grep -cE '^    namespace = "com\.app\.cadenabitcoin"$' "$gradle")" -eq 1 ] \
    && pass "Android namespace com.app.cadenabitcoin unchanged (a source package, not the application ID)" \
    || fail "$gradle: namespace must stay com.app.cadenabitcoin"
  [ "$(grep -cE '^[[:space:]]*applicationIdSuffix[[:space:]]*=' "$gradle")" -eq 1 ] \
    && flavor_block staging | grep -qE '^            applicationIdSuffix = "\.staging"$' \
    && pass "Android staging application ID = com.cadenabitcoin.mobile.signer.staging (suffix only in the staging flavor)" \
    || fail "$gradle: applicationIdSuffix \".staging\" must appear once, in the staging flavor only"
  flavor_block staging | grep -qE '^            manifestPlaceholders\["appLabel"\] = "Cadena Signer STAGING"$' \
    && flavor_block production | grep -qE '^            manifestPlaceholders\["appLabel"\] = "Cadena Bitcoin"$' \
    && pass "Android launcher labels: production 'Cadena Bitcoin', staging 'Cadena Signer STAGING'" \
    || fail "$gradle: flavor labels must be 'Cadena Bitcoin' (production) and 'Cadena Signer STAGING' (staging)"
  grep -q 'android:label="${appLabel}"' android/app/src/main/AndroidManifest.xml \
    && pass "Android manifest label comes from the flavor (\${appLabel})" \
    || fail "android/app/src/main/AndroidManifest.xml: android:label must be \"\${appLabel}\""
fi

# ---- 3. iOS ------------------------------------------------------------------------
plist=ios/Runner/Info.plist
plist_value() { # value of the <string> that follows <key>$1</key>
  awk -v k="$1" '$0 ~ "<key>" k "</key>" {f=1; next} f && /<string>/ {gsub(/.*<string>|<\/string>.*/, ""); print; exit}' "$plist"
}
if [ ! -f "$plist" ]; then
  fail "$plist not found"
else
  [ "$(plist_value CFBundleShortVersionString)" = '$(FLUTTER_BUILD_NAME)' ] \
    && pass "iOS CFBundleShortVersionString = \$(FLUTTER_BUILD_NAME)" \
    || fail "$plist: CFBundleShortVersionString must be '\$(FLUTTER_BUILD_NAME)'"
  [ "$(plist_value CFBundleVersion)" = '$(FLUTTER_BUILD_NUMBER)' ] \
    && pass "iOS CFBundleVersion = \$(FLUTTER_BUILD_NUMBER)" \
    || fail "$plist: CFBundleVersion must be '\$(FLUTTER_BUILD_NUMBER)'"
fi

# Build settings of the app target (the blocks that set Runner/Info.plist; the RunnerTests
# target is not shipped and is ignored). Six configurations: Debug|Release|Profile for each
# of the two flavors. The app target must take its build number from Flutter, must not define
# a MARKETING_VERSION, and must not set a bundle identifier itself: the identity of each flavor
# comes from ios/Flutter/Flavor-<flavor>.xcconfig (checked below).
pbx=ios/Runner.xcodeproj/project.pbxproj
if [ ! -f "$pbx" ]; then
  fail "$pbx not found"
else
  app_blocks="$(awk '
    /buildSettings = \{/ {inb=1; blk=""; next}
    inb && /^[[:space:]]*\};/ {
      if (blk ~ /INFOPLIST_FILE = Runner\/Info\.plist;/) {n++; print blk "\n----"}
      inb=0; next }
    inb {blk = blk $0 "\n"}
  ' "$pbx")"
  n_blocks="$(printf '%s\n' "$app_blocks" | grep -c '^----$')"
  n_good="$(printf '%s\n' "$app_blocks" | grep -c 'CURRENT_PROJECT_VERSION = "\$(FLUTTER_BUILD_NUMBER)";')"
  if [ "$n_blocks" -eq 6 ] && [ "$n_blocks" -eq "$n_good" ]; then
    pass "iOS app target: CURRENT_PROJECT_VERSION = \$(FLUTTER_BUILD_NUMBER) in all $n_blocks configurations"
  else
    fail "iOS app target: $n_good of $n_blocks (expected 6) configurations use \$(FLUTTER_BUILD_NUMBER) for CURRENT_PROJECT_VERSION"
  fi
  if printf '%s\n' "$app_blocks" | grep -q 'PRODUCT_BUNDLE_IDENTIFIER'; then
    fail "iOS app target sets PRODUCT_BUNDLE_IDENTIFIER in the project; it must come from Flavor-<flavor>.xcconfig"
  else
    pass "iOS app target takes its bundle identifier only from the flavor xcconfig"
  fi
  for cfg_name in Debug-production Release-production Profile-production Debug-staging Release-staging Profile-staging; do
    grep -q "name = \"$cfg_name\";" "$pbx" || fail "$pbx: build configuration $cfg_name is missing"
  done
  if grep -qE 'name = (Debug|Release|Profile);' "$pbx"; then
    fail "$pbx: an unflavored Debug/Release/Profile configuration exists"
  else
    pass "iOS has the six flavored configurations and no unflavored one"
  fi
  if printf '%s\n' "$app_blocks" | grep -q 'MARKETING_VERSION'; then
    fail "iOS app target defines MARKETING_VERSION (would bypass pubspec.yaml)"
  else
    pass "iOS app target defines no MARKETING_VERSION"
  fi
fi

# Flavors: identity lives in one small file per flavor.
xcflavor_value() { # xcflavor_value FLAVOR KEY: value of KEY in ios/Flutter/Flavor-FLAVOR.xcconfig
  sed -n "s/^$2 = //p" "ios/Flutter/Flavor-$1.xcconfig" 2>/dev/null
}
if [ "$(xcflavor_value production PRODUCT_BUNDLE_IDENTIFIER)" = "com.app.cadenabitcoin" ] \
  && [ "$(xcflavor_value production APP_DISPLAY_NAME)" = "Cadena Bitcoin" ] \
  && [ "$(xcflavor_value staging PRODUCT_BUNDLE_IDENTIFIER)" = "com.app.cadenabitcoin.staging" ] \
  && [ "$(xcflavor_value staging APP_DISPLAY_NAME)" = "Cadena Signer STAGING" ]; then
  pass "iOS identities: production com.app.cadenabitcoin 'Cadena Bitcoin'; staging com.app.cadenabitcoin.staging 'Cadena Signer STAGING'"
else
  fail "ios/Flutter/Flavor-<flavor>.xcconfig: expected production com.app.cadenabitcoin/'Cadena Bitcoin' and staging com.app.cadenabitcoin.staging/'Cadena Signer STAGING'"
fi
[ "$(plist_value CFBundleDisplayName)" = '$(APP_DISPLAY_NAME)' ] \
  && pass "iOS CFBundleDisplayName = \$(APP_DISPLAY_NAME)" \
  || fail "$plist: CFBundleDisplayName must be '\$(APP_DISPLAY_NAME)'"
schemes_dir=ios/Runner.xcodeproj/xcshareddata/xcschemes
scheme_ok=1
for fl in production staging; do
  [ -f "$schemes_dir/$fl.xcscheme" ] || { scheme_ok=0; continue; }
  cfgs="$(sed -n 's/.*buildConfiguration = "\([^"]*\)".*/\1/p' "$schemes_dir/$fl.xcscheme" | sort -u | tr '\n' ' ')"
  [ "$cfgs" = "Debug-$fl Profile-$fl Release-$fl " ] || scheme_ok=0
done
if [ "$scheme_ok" -eq 1 ] && [ "$(ls "$schemes_dir" | wc -l | tr -d ' ')" -eq 2 ]; then
  pass "iOS schemes: exactly production and staging, each using only its own configurations"
else
  fail "$schemes_dir: expected exactly the schemes production and staging using Debug|Profile|Release-<flavor>"
fi
pods_ok=1
for n in Debug-production Profile-production Release-production Debug-staging Profile-staging Release-staging; do
  grep -q "'$n' =>" ios/Podfile || pods_ok=0
done
if [ "$pods_ok" -eq 1 ] && ! grep -qE "'(Debug|Profile|Release)' =>" ios/Podfile; then
  pass "iOS Podfile maps the six flavored configurations"
else
  fail "ios/Podfile: expected a mapping for the six flavored configurations and none for the unflavored ones"
fi
podfile_sum="$(sed -n 's/^PODFILE CHECKSUM: //p' ios/Podfile.lock)"
if command -v sha1sum >/dev/null 2>&1; then actual_sum="$(sha1sum ios/Podfile | cut -d' ' -f1)"; else actual_sum="$(shasum -a 1 ios/Podfile | cut -d' ' -f1)"; fi
[ "$podfile_sum" = "$actual_sum" ] \
  && pass "ios/Podfile.lock records the checksum of the current ios/Podfile" \
  || fail "ios/Podfile.lock PODFILE CHECKSUM ($podfile_sum) does not match ios/Podfile ($actual_sum)"

xc_hits="$(grep -nE 'FLUTTER_BUILD_NAME|FLUTTER_BUILD_NUMBER|MARKETING_VERSION|CURRENT_PROJECT_VERSION' ios/Flutter/*.xcconfig ios/*.xcconfig 2>/dev/null | grep -v '/Generated\.xcconfig:' || true)"
if [ -z "$xc_hits" ]; then
  pass "no version override in tracked iOS xcconfig files"
else
  fail "version override in iOS xcconfig:"; echo "$xc_hits" | sed 's/^/        /'
fi

# ---- 4. Unintended overrides in automation -------------------------------------------
if [ -d .github ]; then
  gh_hits="$(grep -rnE -- '--build-name|--build-number|FLUTTER_BUILD_NAME|FLUTTER_BUILD_NUMBER' .github 2>/dev/null || true)"
  if [ -z "$gh_hits" ]; then
    pass "no workflow overrides the version (--build-name/--build-number)"
  else
    fail "a workflow overrides the version (allowed only for an approved release workflow):"; echo "$gh_hits" | sed 's/^/        /'
  fi
fi

echo
echo "Product version : $name"
echo "Build number    : $build"
echo "Android         : versionName=$name versionCode=$build"
echo "iOS             : CFBundleShortVersionString=$name CFBundleVersion=$build"
if [ -n "$release_id" ]; then
  echo "Release id      : $release_id${channel:+ (channel: $channel)}"
  case "$release_id" in
    *-rc.*) echo "Policy embeds  : Android versionName=${release_id#v}, iOS CFBundleShortVersionString=$name (numeric); identifier shown in the app" ;;
    *)      echo "Policy embeds  : Android versionName=$name, iOS CFBundleShortVersionString=$name; no staging identifier" ;;
  esac
fi
if [ "$fails" -eq 0 ]; then echo "RESULT: OK"; exit 0; fi
echo "RESULT: FAILED ($fails check(s))"; exit 1
