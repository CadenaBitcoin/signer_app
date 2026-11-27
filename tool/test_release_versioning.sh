#!/usr/bin/env bash
# Tests the release-versioning and traceability logic without compiling anything:
#
#   1. tool/verify_version.sh   valid and invalid versions, release identifiers, channel/identifier
#                               combinations, and every way a platform or workflow could override
#                               the single version source (run on throw-away copies of the repository)
#   2. tool/build_manifest.py   create + verify of the manifest of every variant, and a rejection
#                               for each kind of missing, malformed, inconsistent or contradictory
#                               metadata; cross-checks of the manifests of one run; canonical names;
#                               the published-version gate
#   3. the workflow             the manifest steps exist, nothing but evidence is uploaded, nothing
#                               writes or overrides the version
#
#   tool/test_release_versioning.sh
#
# Needs bash, git, python3 and the usual text tools (the runners have them); no Flutter, no Android
# SDK, no Xcode. Exit 0 only if every check passes.
# The workflow lines pinned in part 3 contain literal ${{ ... }} and $VAR text on purpose.
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool="$root/tool/build_manifest.py"
workflow="$root/.github/workflows/build-variants.yml"
BM() { python3 -I "$tool" "$@"; }

pass=0
failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null

# expect_rc NAME RC FRAGMENT COMMAND... : exit status RC and the output contains FRAGMENT
expect_rc() {
  local name="$1" want="$2" frag="$3" out rc
  shift 3
  out="$("$@" 2>&1)"
  rc=$?
  if [ "$rc" -ne "$want" ]; then bad "$name" "exit $rc, expected $want: $(printf '%s' "$out" | tail -n 3 | tr '\n' ' ')"; return; fi
  if [ -n "$frag" ] && ! grep -qF -- "$frag" <<<"$out"; then bad "$name" "output lacks '$frag': $(printf '%s' "$out" | tail -n 3 | tr '\n' ' ')"; return; fi
  ok "$name"
}
accepted() { local n="$1"; shift; expect_rc "$n" 0 "" "$@"; }
rejected() { local n="$1" frag="$2"; shift 2; expect_rc "$n" 1 "$frag" "$@"; }

# edit FILE OLD NEW : replace the first OLD by NEW; fails if OLD is not there (a silent no-op
# would make a rejection test pass for the wrong reason)
edit() {
  python3 -I -c '
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    sys.exit("edit: %r not found in %s" % (old, p))
open(p, "w").write(s.replace(old, new, 1))
' "$1" "$2" "$3"
}

t() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
eq() { [ "$1" = "$2" ]; }
has() { grep -qF -- "$2" <<<"$1"; }

# ---------------------------------------------------------------------------------------------
# 1. verify_version.sh on a throw-away copy of the repository (text files and the launcher icons)
# ---------------------------------------------------------------------------------------------
# Only what the version tools read: pubspec.yaml, the native projects, the workflows, the
# configuration and the tools (build outputs and caches are never copied).
copy_repo() { # DEST
  local f
  mkdir -p "$1"
  (cd "$root" && git ls-files -z --cached --others --exclude-standard -- pubspec.yaml android ios .github config tool assets/branding) | while IFS= read -r -d '' f; do
    case "$f" in
      android/app/src/*/res/mipmap-*/ic_launcher.* | ios/Runner/Assets.xcassets/AppIcon*.appiconset/* | assets/branding/app-icon-*.png) ;; # the launcher icons are read by verify_version.sh (Issue #139)
      *.so | *.a | *.png | *.jpg | *.jpeg | *.ttf | *.otf | *.jar | *.apk | *.aab | *.ipa | *.zip | *.gz | *.webp | *.ico | *.tflite | *.icns | *.pdf | *.DS_Store) continue ;;
      build/* | android/build/* | android/app/build/* | ios/build/* | */.dart_tool/* | */.gradle/*) continue ;;
    esac
    [ -f "$root/$f" ] || continue
    mkdir -p "$1/$(dirname "$f")"
    cp "$root/$f" "$1/$f"
  done
}
base="$tmp/repo"
copy_repo "$base"
fresh() { rm -rf "$tmp/w" && cp -R "$base" "$tmp/w"; } # a pristine copy to mutate
VV() { (cd "$tmp/w" && bash tool/verify_version.sh "$@"); }

fresh
current_version="$(sed -n 's/^version:[[:space:]]*\([^+]*\)+.*$/\1/p' "$root/pubspec.yaml")"
[ -n "$current_version" ] || { echo "Cannot determine current version" >&2; exit 2; }
current_release_id="v${current_version}"
patch="${current_version##*.}"
different_release_id="v${current_version%.*}.$((patch + 1))"

accepted "version: the repository as it is passes" VV
accepted "version: release id ${current_release_id} on channel production" VV --channel production --release-id "$current_release_id"
accepted "version: release id ${current_release_id}-rc.2 on channel staging" VV --channel staging --release-id "${current_release_id}-rc.2"

pubspec_case() { # NAME REPLACEMENT-LINE
  fresh
  edit "$tmp/w/pubspec.yaml" "version: $(sed -n 's/^version: *//p' "$root/pubspec.yaml")" "$2"
  rejected "version: $1" "FAIL" VV
}
pubspec_case "no build number is rejected" "version: 1.0.3"
pubspec_case "a prerelease suffix is rejected (it would be rewritten on iOS)" "version: 1.0.3-rc.1+1000034"
pubspec_case "a leading zero is rejected" "version: 1.0.03+1000034"
pubspec_case "build number 0 is rejected" "version: 1.0.3+0"
pubspec_case "a build number with a leading zero is rejected" "version: 1.0.3+01"
pubspec_case "a four-part version is rejected" "version: 1.0.3.1+1000034"
pubspec_case "a non-numeric build is rejected" "version: 1.0.3+abc"
fresh
printf 'version: %s\n' "$(sed -n 's/^version: *//p' "$root/pubspec.yaml")" >>"$tmp/w/pubspec.yaml"
rejected "version: two version lines are rejected (ambiguous source)" "exactly one" VV

fresh
edit "$tmp/w/android/app/build.gradle.kts" 'versionCode = flutter.versionCode' 'versionCode = 99'
rejected "version: a literal Android versionCode is rejected" "versionCode" VV
fresh
edit "$tmp/w/android/app/build.gradle.kts" 'versionName = flutter.versionName' 'versionName = "9.9.9"'
rejected "version: a literal Android versionName is rejected" "versionName" VV
fresh
edit "$tmp/w/android/app/build.gradle.kts" 'versionName = flutter.versionName' 'versionName = flutter.versionName
        versionNameSuffix = "-x"'
rejected "version: an Android version suffix is rejected" "" VV
fresh
edit "$tmp/w/android/app/build.gradle.kts" 'versionCode = flutter.versionCode' 'versionCode = flutter.versionCode
        versionCodeOverride = 5'
rejected "version: an Android versionCode override is rejected" "" VV
fresh
grep -q 'CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";' "$tmp/w/ios/Runner.xcodeproj/project.pbxproj" \
  && edit "$tmp/w/ios/Runner.xcodeproj/project.pbxproj" 'CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";' 'CURRENT_PROJECT_VERSION = 7;'
rejected "version: a literal iOS build number is rejected" "" VV
fresh
printf 'MARKETING_VERSION = 3.0\n' >>"$tmp/w/ios/Flutter/Flavor-production.xcconfig"
rejected "version: an iOS marketing version in an xcconfig is rejected" "" VV
fresh
edit "$tmp/w/ios/Runner/Info.plist" '$(FLUTTER_BUILD_NAME)' '1.2.3'
rejected "version: a literal CFBundleShortVersionString is rejected" "" VV
fresh
edit "$tmp/w/.github/workflows/build-variants.yml" 'flutter build "$FLUTTER_COMMAND" --release' 'flutter build "$FLUTTER_COMMAND" --build-number 5 --release'
rejected "version: a workflow that passes --build-number is rejected" "overrides the version" VV
fresh
edit "$tmp/w/.github/workflows/build-variants.yml" 'flutter build "$FLUTTER_COMMAND" --release' 'flutter build "$FLUTTER_COMMAND" --build-name 9.9.9 --release'
rejected "version: a workflow that passes --build-name is rejected" "overrides the version" VV

fresh
# malformed identifiers are derived from the current version so each is rejected for its own
# defect, never for naming another version; "$different_release_id" is the mismatch case
for id in "$current_version" "$different_release_id" "${current_release_id}-rc.0" "${current_release_id}-rc." "v0${current_version}" "${current_release_id}-beta.1" "V${current_version}" "v${current_version%.*}"; do
  rejected "version: release id '$id' is rejected" "FAIL" VV --release-id "$id"
done
rejected "version: channel staging with a final identifier is rejected" "needs a -rc.N" VV --channel staging --release-id "$current_release_id"
rejected "version: channel production with a candidate identifier is rejected" "must not carry" VV --channel production --release-id "${current_release_id}-rc.1"
rejected "version: channel staging without an identifier is rejected (missing identity)" "requires --release-id" VV --channel staging
rejected "version: channel production without an identifier is rejected (missing identity)" "requires --release-id" VV --channel production
expect_rc "version: an unknown channel is a usage error" 2 "" VV --channel qa --release-id "$current_release_id"

# Launcher icons (Issue #139): the flavor alone selects the icon, so every way of losing, sharing or
# overriding a flavor's icon is rejected by verify_version.sh. (A built APK/app is checked against the same
# files by tool/verify_artifact.sh.)
A="android/app/src"; I="ios/Runner/Assets.xcassets"
fresh
rm "$tmp/w/$A/staging/res/mipmap-hdpi/ic_launcher.jpg"
rejected "icons: a missing Android staging icon is rejected" "launcher icon is missing" VV
fresh
rm "$tmp/w/$A/production/res/mipmap-xxhdpi/ic_launcher.jpg"
rejected "icons: a missing Android production icon is rejected" "launcher icon is missing" VV
fresh
cp "$tmp/w/$A/production/res/mipmap-hdpi/ic_launcher.jpg" "$tmp/w/$A/staging/res/mipmap-hdpi/ic_launcher.jpg"
rejected "icons: the staging Android icon equal to the production one is rejected" "identical" VV
fresh
cp "$tmp/w/$A/staging/res/mipmap-mdpi/ic_launcher.jpg" "$tmp/w/$A/staging/res/mipmap-xhdpi/ic_launcher.jpg"
rejected "icons: an Android icon of the wrong size is rejected" "must be a 96x96 JPEG" VV
fresh
mkdir -p "$tmp/w/$A/main/res/mipmap-mdpi" && cp "$tmp/w/$A/production/res/mipmap-mdpi/ic_launcher.jpg" "$tmp/w/$A/main/res/mipmap-mdpi/ic_launcher.jpg"
rejected "icons: a shared icon in src/main (a fallback for a flavor without its own) is rejected" "fallback" VV
fresh
edit "$tmp/w/ios/Flutter/Flavor-staging.xcconfig" 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-Staging' 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon'
rejected "icons: the iOS staging flavor selecting the production icon set is rejected" "must be set once, to AppIcon-Staging" VV
fresh
edit "$tmp/w/ios/Flutter/Flavor-production.xcconfig" 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon' 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-Staging'
rejected "icons: the iOS production flavor selecting the staging icon set is rejected" "must be set once, to AppIcon" VV
fresh
sed -i '/^ASSETCATALOG_COMPILER_APPICON_NAME/d' "$tmp/w/ios/Flutter/Flavor-staging.xcconfig"
rejected "icons: an iOS flavor without an icon set selection is rejected" "must be set once" VV
fresh
edit "$tmp/w/ios/Runner.xcodeproj/project.pbxproj" 'PRODUCT_NAME = "$(TARGET_NAME)";' 'PRODUCT_NAME = "$(TARGET_NAME)"; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'
rejected "icons: a project-level icon setting (it would override the flavor) is rejected" "would override" VV
fresh
cp "$tmp/w/$I/AppIcon.appiconset/120.png" "$tmp/w/$I/AppIcon-Staging.appiconset/120.png"
rejected "icons: an iOS staging icon file equal to the production one is rejected" "identical" VV
fresh
rm "$tmp/w/assets/branding/app-icon-staging.png"
rejected "icons: a missing staging icon master is rejected" "icon master is missing" VV
fresh
cp "$tmp/w/$I/AppIcon.appiconset/120.png" "$tmp/w/assets/branding/app-icon-production.png"
rejected "icons: a production icon master that is not 1024x1024 is rejected" "must be a 1024x1024 PNG" VV
fresh
rm "$tmp/w/$I/AppIcon-Staging.appiconset/87.png"
rejected "icons: an iOS icon listed in Contents.json but missing is rejected" "missing" VV
fresh
cp "$tmp/w/$I/AppIcon-Staging.appiconset/29.png" "$tmp/w/$I/AppIcon-Staging.appiconset/58.png"
rejected "icons: an iOS icon of the wrong size is rejected" "expects 58x58" VV

# ---------------------------------------------------------------------------------------------
# 2. build manifests
# ---------------------------------------------------------------------------------------------
Z="$(printf '%064d' 0 | tr 0 a)"
Y="$(printf '%064d' 0 | tr 0 b)"

# The controlled fixture: the real tools, configuration and native projects, but a PINNED application
# version and a PINNED published-versions ledger. Every boundary test below runs on it, so none depends
# on the version the live repository has today, nor on entries that a later release adds to the live
# ledger. What does read the live repository is marked "live" and asserts only what holds at any version.
FLOOR=1000034                           # the pinned Google Play build number
PUBLISHED_ID=com.cadenabitcoin.mobile.signer # the pinned published package: the Android production application ID (#72)
PROD_ID=$PUBLISHED_ID                   # the production Android application ID of the repository
STAGING_ANDROID_ID=com.cadenabitcoin.mobile.signer.staging
OTHER_ID=com.example.other.package      # a package the ledger may publish that is NOT the repository's (rule 2 of the gate)
IOS_PROD_ID=com.app.cadenabitcoin       # iOS bundle IDs are separate identifiers and are not the Android ones
IOS_STAGING_ID=com.app.cadenabitcoin.staging
ledger_json() { # PACKAGE FLOOR
  printf '{"schema":"cadena-published-versions/1","entries":[{"platform":"android","channel":"google-play","package":"%s","version_name":"1.0.3","version_code":%s,"status":"fully-rolled-out","recorded":"2026-10-19","source":"test fixture"}]}\n' "$1" "$2"
}
# mkfix DEST BUILD PACKAGE [FLOOR]: a repository at version 1.0.3+BUILD whose ledger publishes PACKAGE at FLOOR
mkfix() {
  rm -rf "$1" && cp -R "$base" "$1"
  edit "$1/pubspec.yaml" "version: $(sed -n 's/^version: *//p' "$root/pubspec.yaml")" "version: 1.0.3+$2"
  mkdir -p "$1/config/release"
  ledger_json "$3" "${4:-$FLOOR}" >"$1/config/release/published_versions.json"
}
fx="$tmp/fx"
mkfix "$fx" "$FLOOR" "$PUBLISHED_ID"
FIX="$fx"
TOOLPY="$fx/tool/build_manifest.py"     # create() reads the pubspec and ledger of the repository holding the tool
cfg_sha() { sha256sum "$FIX/config/build/$1.json" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$FIX/config/build/$1.json" | cut -d' ' -f1; }
COMMIT=7b63c9791fccc8f9711ed853e2294967899be972
RUN=39237471969

# mkev VARIANT DIR [COMMIT]: synthetic evidence in the format of tool/verify_artifact.sh + the workflow
mkev() {
  local v="$1" d="$2" commit="${3:-$COMMIT}" env kind id name file
  case "$v" in
    ios-staging) env=staging; id=$IOS_STAGING_ID; name="Cadena Signer STAGING" ;;
    ios-*) env=production; id=$IOS_PROD_ID; name="Cadena Bitcoin" ;;
    *staging*) env=staging; id=$STAGING_ANDROID_ID; name="Cadena Signer STAGING" ;;
    *) env=production; id=$PROD_ID; name="Cadena Bitcoin" ;;
  esac
  mkdir -p "$d"
  {
    echo "variant=$v"
    case "$v" in
      ios-*) echo "build_command=flutter build ios --release --no-codesign --flavor $env --dart-define-from-file=config/build/$env.json" ;;
      *-aab) echo "build_command=flutter build appbundle --release --flavor $env --dart-define-from-file=config/build/$env.json" ;;
      *) echo "build_command=flutter build apk --release --flavor $env --dart-define-from-file=config/build/$env.json" ;;
    esac
    echo "config_file=config/build/$env.json"
    echo "config_file_sha256=$(cfg_sha "$env")"
    echo "commit=$commit"
    echo "ref=$env"
    echo "run=https://github.com/CadenaBitcoin/signer_app/actions/runs/$RUN (attempt 1)"
    case "$v" in
      ios-*)
        echo "podfile_lock_drift=yes"
        echo "rust_lib_sha256=$Z"
        echo "artifact_kind=ios-app"; echo "artifact_file=Runner.app"
        case "$v" in *staging*) echo "artifact_sha256=$(printf '%064d' 0 | tr 0 e)" ;; *) echo "artifact_sha256=$(printf '%064d' 0 | tr 0 c)" ;; esac
        echo "artifact_sha256_basis=sha256 of the sorted per-file sha256 manifest of the .app directory"
        echo "artifact_bytes=1234KiB"
        echo "signing=unsigned" ;;
      *)
        case "$v" in *-aab) kind=aab; file=app-$env-release.aab ;; *) kind=apk; file=app-$env-release.apk ;; esac
        echo "artifact_kind=$kind"; echo "artifact_file=$file"
        case "$v" in *staging*) echo "artifact_sha256=$Y" ;; *-aab) echo "artifact_sha256=$(printf '%064d' 0 | tr 0 d)" ;; *) echo "artifact_sha256=$Z" ;; esac
        echo "artifact_bytes=100"
        if [ "${EV_SIGNING:-debug}" = unsigned ]; then
          echo "signing=unsigned"
        else
          echo "signing=debug"
          echo "signer_dn=C=US, O=Android, CN=Android Debug"
          echo "signer_cert_sha256=$Z"
        fi
        echo "native_lib_sha256.arm64-v8a=$Z" ;;
    esac
    echo "environment=$env"; echo "application_id=$id"; echo "display_name=$name"
    echo "version_name=1.0.3"; echo "version_code=$(sed -n 's/^version: *[0-9.]*+//p' "$FIX/pubspec.yaml")"
    echo "distributable=no"
    echo "environment_check=$env-url-present-other-absent"; echo "environment_check_snapshots=3"
  } >"$d/$v.txt"
  case "$v" in
    ios-*) cat >"$d/$v.toolchain" <<EOF
runner_image=macos15 20260101.1
runner_arch=arm64
xcode=26.3 (17C529)
iphoneos_sdk=26.2
flutter=3.35.3 (revision a402d9a437)
dart=3.9.2
cocoapods=1.17.0
EOF
      ;;
    *) cat >"$d/$v.toolchain" <<EOF
flutter=Flutter 3.35.3 • channel stable
dart=3.9.2
java=openjdk version "17.0.10"
runner_image=ubuntu24 20260101.1
android_build_tools=36.0.0
EOF
      ;;
  esac
}
# mkman VARIANT DIR [COMMIT] [EVENT] [REF] [ON_DEVELOPMENT]: evidence + manifest in DIR (a manual run states whether its commit is on development)
mkman() {
  local v="$1" d="$2" commit="${3:-$COMMIT}" event="${4:-workflow_dispatch}" ref="${5:-feature}" ondev="${6:-true}"
  mkev "$v" "$d" "$commit"
  GITHUB_RUN_ID=$RUN GITHUB_RUN_ATTEMPT=1 GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=CadenaBitcoin/signer_app \
    GITHUB_SHA=$commit CADENA_COMMIT_ON_DEVELOPMENT=$([ "$event" = push ] || echo "$ondev") \
    GITHUB_REF_NAME=$ref GITHUB_REF_TYPE=branch GITHUB_EVENT_NAME=$event GITHUB_WORKFLOW="Build variants (compile validation)" \
    python3 -I "$TOOLPY" create --evidence "$d/$v.txt" --toolchain "$d/$v.toolchain" --out "$d/$v.manifest.json" ${RELEASE_ID:+--release-id "$RELEASE_ID"} >/dev/null
}
# mut IN OUT 'python using m'
mut() { python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); exec(sys.argv[3]); json.dump(m, open(sys.argv[2], "w"))' "$1" "$2" "$3"; }

VARS="android-staging-apk ios-staging android-production-apk android-production-aab ios-production"
good="$tmp/good"
for v in $VARS; do
  ev="$tmp/good/$v.txt"
  if mkman "$v" "$good" "$COMMIT" push "$(case "$v" in *staging*) echo staging ;; *) echo production ;; esac)"; then
    accepted "manifest: $v is created and verified against the repository and its evidence" BM verify "$good/$v.manifest.json" --repo "$fx" --evidence "$ev"
    accepted "manifest: $v verifies without --repo" BM verify "$good/$v.manifest.json"
  else
    bad "manifest: $v could not be created"
  fi
done
allrun="$tmp/allrun"
for v in $VARS; do mkman "$v" "$allrun" "$COMMIT" workflow_dispatch issue/69-x; done
# the manifests of one run (staging pair, production triple)
sd="$tmp/stg"; pd="$tmp/prd"
mkdir -p "$sd" "$pd"
for v in android-staging-apk ios-staging; do mkman "$v" "$sd" "$COMMIT" push staging; done
for v in android-production-apk android-production-aab ios-production; do mkman "$v" "$pd" "$COMMIT" push production; done
accepted "manifest: the staging pair is consistent" BM verify-dir "$sd" --variants "android-staging-apk ios-staging" --repo "$fx"
accepted "manifest: the production triple is consistent" BM verify-dir "$pd" --variants "android-production-apk android-production-aab ios-production" --repo "$fx"

M="$good/android-production-apk.manifest.json"
mrej() { # NAME FRAGMENT 'python using m' [extra verify args...]
  local name="$1" frag="$2" code="$3"
  shift 3
  mut "$M" "$tmp/bad.json" "$code" || { bad "manifest: $name (mutation failed)"; return; }
  rejected "manifest: $name" "$frag" BM verify "$tmp/bad.json" "$@"
}
macc() { local name="$1" code="$2"; shift 2; mut "$M" "$tmp/okm.json" "$code" && accepted "manifest: $name" BM verify "$tmp/okm.json" "$@"; }

# structure
mrej "wrong schema" "schema" 'm["schema"]="cadena-build-manifest/3"'
mrej "a missing section" "missing key 'ci'" 'del m["ci"]'
mrej "a missing field" "missing key 'source.commit'" 'del m["source"]["commit"]'
mrej "an unknown top-level key" "unknown key 'extra'" 'm["extra"]=1'
mrej "an unknown field" "unknown key 'artifact.extra'" 'm["artifact"]["extra"]=1'
mrej "an unknown variant" "unknown variant" 'm["variant"]="android-qa-apk"'
mrej "environment contradicts the variant" "environment is 'staging'" 'm["environment"]="staging"'
mrej "platform contradicts the variant" "platform is 'ios'" 'm["platform"]="ios"'
mrej "kind contradicts the variant" "kind is 'aab'" 'm["kind"]="aab"'
# source
mrej "a short commit" "40-character" 'm["source"]["commit"]="7b63c97"'
mrej "an uppercase commit" "40-character" 'm["source"]["commit"]=m["source"]["commit"].upper()'
mrej "a missing ref" "source.ref is missing" 'm["source"]["ref"]=""'
mrej "an unknown ref type" "ref_type" 'm["source"]["ref_type"]="pull"'
mrej "an unsupported event" "source.event" 'm["source"]["event"]="pull_request"'
mrej "a push to staging that built production" "cannot build the production" 'm["source"]["ref"]="staging"'
accepted "manifest: a manual run may build any variant from any branch (real manual manifest, from the issue branch)" BM verify "$allrun/android-production-apk.manifest.json" --repo "$fx" --evidence "$allrun/android-production-apk.txt"
# release identity
macc "no release identifier is allowed for a compile-validation build" 'm["source"]["release_id"]=None'
mrej "a malformed release identifier" "release_id" 'm["source"]["release_id"]="1.0.3"'
mrej "a release identifier for another product version" "does not match the product version" 'm["source"]["release_id"]="v1.0.4"'
mrej "a candidate identifier on a production build" "must not carry -rc.N" 'm["source"]["release_id"]="v1.0.3-rc.1"'
mrej "a final identifier on a staging build" "must be vX.Y.Z-rc.N" 'm["environment"]="staging"; m["variant"]="android-staging-apk"; m["application"]["id"]="com.cadenabitcoin.mobile.signer.staging"; m["application"]["display_name"]="Cadena Signer STAGING"; m["configuration"]["file"]="config/build/staging.json"; m["configuration"]["build_command"]=m["configuration"]["build_command"].replace("production","staging"); m["source"]["ref"]="staging"; m["source"]["release_id"]="v1.0.3"'
# CI build identity
mrej "a non-numeric run id" "ci.run_id" 'm["ci"]["run_id"]="abc"'
mrej "run attempt 0" "run_attempt" 'm["ci"]["run_attempt"]=0'
mrej "a run url for another run" "run_url" 'm["ci"]["run_url"]="https://github.com/CadenaBitcoin/signer_app/actions/runs/1"'
mrej "a build id that is not <run>.<attempt>:<variant>" "build_id" 'm["ci"]["build_id"]="39237471969.2:android-production-apk"'
# version
mrej "a pubspec that is not X.Y.Z+BUILD" "version.pubspec" 'm["version"]["pubspec"]="1.0.3"'
mrej "a version name that differs from the pubspec" "differs from pubspec" 'm["version"]["name"]="1.0.4"; m["version"]["platform_version_name"]="1.0.4"'
mrej "a platform version name that differs from the product version" "differs from the product version" 'm["version"]["platform_version_name"]="1.0.3-rc.1"'
mrej "a build number that differs from the pubspec build" "differs from the pubspec build" 'm["version"]["platform_build_number"]=m["version"]["platform_build_number"]+1'
mrej "a versionCode above Google Play's limit" "limit" 'm["version"]["pubspec"]="1.0.3+2100000001"; m["version"]["pubspec_build"]=2100000001; m["version"]["platform_build_number"]=2100000001'
mkfix "$tmp/w" 1000099 "$PUBLISHED_ID"
rejected "manifest: the repository's pubspec changed since the manifest was written" "the repository says" BM verify "$M" --repo "$tmp/w"
# identity and configuration
mrej "the staging application ID on a production build" "application.id" 'm["application"]["id"]="com.cadenabitcoin.mobile.signer.staging"'
mrej "the previous repository ID on an Android production build" "application.id" 'm["application"]["id"]="com.app.cadenabitcoin"'
mrej "the previous repository staging ID on an Android production build" "application.id" 'm["application"]["id"]="com.app.cadenabitcoin.staging"'
mrej "another display name" "display_name" 'm["application"]["display_name"]="Cadena Signer"'
mrej "the staging configuration on a production build" "configuration.file" 'm["configuration"]["file"]="config/build/staging.json"'
mrej "a configuration digest that is not a SHA-256" "configuration.sha256" 'm["configuration"]["sha256"]="abc"'
mrej "a configuration file that changed" "changed since" 'm["configuration"]["sha256"]="'"$Z"'"' --repo "$fx"
mrej "a build command with another flavor" "flavor and configuration" 'm["configuration"]["build_command"]=m["configuration"]["build_command"].replace("--flavor production","--flavor staging")'
mrej "a build command that overrides the version" "overrides the version" 'm["configuration"]["build_command"]+=" --build-number 7"'
# toolchain and native libraries
mrej "a missing toolchain entry" "toolchain.flutter" 'del m["toolchain"]["flutter"]'
mrej "an unknown toolchain entry" "toolchain.dart" 'm["toolchain"]["dart"]="unknown"'
mrej "an unknown runner image" "toolchain.runner_image" 'm["toolchain"]["runner_image"]="unknown unknown"'
mrej "no native library digest" "native_libs is empty" 'm["native_libs"]={}'
mrej "a native library digest that is not a SHA-256" "native_libs" 'k=list(m["native_libs"])[0]; m["native_libs"][k]="zz"'
# artifact
mrej "an artifact digest that is not a SHA-256" "artifact.sha256" 'm["artifact"]["sha256"]="abc"'
mrej "a directory digest on a file artifact" "digest_kind" 'm["artifact"]["digest_kind"]="directory-manifest"'
mrej "a canonical name of another build" "canonical" 'm["artifact"]["canonical_name"]=m["artifact"]["canonical_name"].replace("run3923","run1111")'
mrej "a missing artifact size" "artifact.size" 'm["artifact"]["size"]=""'
# signing, classification, distribution
mrej "an unknown signing status" "signing.status" 'm["signing"]["status"]="self-signed"'
mrej "debug signing without the debug certificate" "debug certificate" 'm["signing"]["signer_dn"]="CN=Cadena Release"'
mrej "debug signing without a fingerprint" "signer certificate SHA-256" 'm["signing"]["signer_cert_sha256"]=""'
mrej "unsigned but a signer is recorded" "'unsigned' but a signer" 'm["signing"]["status"]="unsigned"'
mrej "release signing without a fingerprint" "release-signed artifact must record" 'm["signing"]["status"]="release"; m["signing"]["signer_dn"]=""; m["signing"]["signer_cert_sha256"]=""'
mrej "release signing without a release identifier" "needs a release identifier" 'm["signing"]["status"]="release"; m["signing"]["signer_dn"]="CN=Cadena"'
mrej "a debug-signed artifact classified as a release" "cannot be classified" 'm["classification"]="release"'
mrej "a debug-signed artifact that claims to be distributable" "distributable must be false" 'm["distribution"]["distributable"]=True'
mrej "a retained binary of a compile-validation build" "retained binary needs" 'm["distribution"]["binary_retained"]=True'
macc "an internal-evaluation classification is representable" 'm["classification"]="internal-evaluation"; m["distribution"]["binary_retained"]=True'
# iOS must stay unsigned
im="$good/ios-production.manifest.json"
mut "$im" "$tmp/bad.json" 'm["signing"]["status"]="debug"; m["signing"]["signer_dn"]="CN=Android Debug"; m["signing"]["signer_cert_sha256"]="'"$Z"'"'
rejected "manifest: an iOS artifact that is not unsigned" "iOS compile-validation artifact must be unsigned" BM verify "$tmp/bad.json"
mut "$im" "$tmp/bad.json" 'm["artifact"]["digest_kind"]="file"'
rejected "manifest: a raw-file digest on an iOS directory artifact" "digest_kind" BM verify "$tmp/bad.json"
# the repository's ledger decides the gate and the known issues; they cannot be dropped or edited
mrej "a dropped known issue" "cannot be dropped" 'm["known_issues"]=[]' --repo "$fx"
mrej "a known issue that is not in the vocabulary" "known_issues" 'm["known_issues"]=["whatever"]'
mrej "a release gate that was opened by hand" "release_gate" 'm["release_gate"]={"status":"above-floor","published_floor":1000034}' --repo "$fx"
mrej "an unknown gate status" "release_gate.status" 'm["release_gate"]["status"]="open"'
# the text evidence must say the same
cp "$good/android-production-apk.txt" "$tmp/ev2.txt"
edit "$tmp/ev2.txt" "artifact_sha256=$Z" "artifact_sha256=$Y"
rejected "manifest: text evidence with another artifact digest" "text evidence" BM verify "$M" --evidence "$tmp/ev2.txt"
cp "$good/android-production-apk.txt" "$tmp/ev3.txt"
edit "$tmp/ev3.txt" "(attempt 1)" "(attempt 2)"
rejected "manifest: text evidence from another attempt" "run line" BM verify "$M" --evidence "$tmp/ev3.txt"
# create refuses what it cannot represent
cp "$good/android-production-apk.txt" "$tmp/ev4.txt"
edit "$tmp/ev4.txt" "signing=debug" "signing=signed-by-other-key"
expect_rc "create: a signing kind of a release is refused" 2 "cannot be recorded" env GITHUB_EVENT_NAME=push GITHUB_RUN_ID=$RUN GITHUB_RUN_ATTEMPT=1 GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=CadenaBitcoin/signer_app GITHUB_SHA=$COMMIT python3 -I "$TOOLPY" create --evidence "$tmp/ev4.txt" --toolchain "$good/android-production-apk.toolchain" --out "$tmp/x.json"
expect_rc "create: no run identity is refused" 2 "GITHUB_RUN_ID" env -u GITHUB_RUN_ID -u GITHUB_RUN_ATTEMPT python3 -I "$TOOLPY" create --evidence "$good/android-production-apk.txt" --toolchain "$good/android-production-apk.toolchain" --out "$tmp/x.json"
expect_rc "create: a commit that differs from the evidence is refused" 2 "differs from the evidence" env GITHUB_EVENT_NAME=push GITHUB_RUN_ID=$RUN GITHUB_RUN_ATTEMPT=1 GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=CadenaBitcoin/signer_app GITHUB_SHA=0000000000000000000000000000000000000001 python3 -I "$TOOLPY" create --evidence "$good/android-production-apk.txt" --toolchain "$good/android-production-apk.toolchain" --out "$tmp/x.json"
cp "$good/android-production-apk.txt" "$tmp/ev5.txt"
printf 'signing=unsigned\n' >>"$tmp/ev5.txt"
expect_rc "create: ambiguous evidence (a repeated key) is refused" 2 "repeats the key" env GITHUB_EVENT_NAME=push GITHUB_RUN_ID=$RUN GITHUB_RUN_ATTEMPT=1 GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=CadenaBitcoin/signer_app GITHUB_SHA=$COMMIT python3 -I "$TOOLPY" create --evidence "$tmp/ev5.txt" --toolchain "$good/android-production-apk.toolchain" --out "$tmp/x.json"

# the manifests of one run
dirx="$tmp/dx"
PROD3="android-production-apk android-production-aab ios-production"
fresh_run() { rm -rf "$dirx" && cp -R "$pd" "$dirx"; }
fresh_run
mkman ios-production "$dirx" 1111111111111111111111111111111111111111 push production
rejected "run: manifests of different commits" "disagree on source.commit" BM verify-dir "$dirx" --variants "$PROD3" --repo "$fx"
fresh_run
rm "$dirx/ios-production.manifest.json"
rejected "run: a missing manifest" "missing" BM verify-dir "$dirx" --variants "$PROD3" --repo "$fx"
fresh_run
rm "$dirx/ios-production.txt"
rejected "run: missing text evidence" "missing" BM verify-dir "$dirx" --variants "$PROD3" --repo "$fx"
fresh_run
cp "$pd/android-production-apk.manifest.json" "$dirx/android-production-aab.manifest.json"
rejected "run: a manifest filed under another variant" "describes variant" BM verify-dir "$dirx" --variants "$PROD3" --repo "$fx"
fresh_run
EV_SIGNING=unsigned mkman android-production-aab "$dirx" "$COMMIT" push production
accepted "run: (control) an unsigned AAB is a valid manifest on its own" BM verify "$dirx/android-production-aab.manifest.json" --repo "$fx"
rejected "run: an APK and an AAB of one release must be signed alike" "differ in signing.status" BM verify-dir "$dirx" --variants "$PROD3" --repo "$fx"
fresh_run
apk_sha="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["artifact"]["sha256"])' "$pd/android-production-apk.manifest.json")"
mut "$pd/android-production-aab.manifest.json" "$dirx/android-production-aab.manifest.json" 'm["artifact"]["sha256"]="'"$apk_sha"'"'
edit "$dirx/android-production-aab.txt" "artifact_sha256=$(printf '%064d' 0 | tr 0 d)" "artifact_sha256=$apk_sha"
rejected "run: two variants with one artifact digest" "not unique" BM verify-dir "$dirx" --variants "$PROD3" --repo "$fx"
fresh_run
mut "$pd/android-production-aab.manifest.json" "$dirx/android-production-aab.manifest.json" 'm["ci"]["build_id"]=json.load(open("'"$pd"'/android-production-apk.manifest.json"))["ci"]["build_id"]'
rejected "run: a build identifier used twice is refused (also fails on its own variant)" "build_id" BM verify-dir "$dirx" --variants "$PROD3" --repo "$fx"
mixed="$tmp/mixed"; rm -rf "$mixed"; mkdir -p "$mixed"
mkman android-production-apk "$mixed" "$COMMIT" workflow_dispatch feature
mkman android-staging-apk "$mixed" 1111111111111111111111111111111111111111 workflow_dispatch feature
rejected "run: variants built from two commits" "disagree on source.commit" BM verify-dir "$mixed" --variants "android-production-apk android-staging-apk" --repo "$fx"
accepted "run: a manual run of one variant" BM verify-dir "$good" --variants "android-production-aab" --repo "$fx"
accepted "run: a manual run of all five variants from one branch" BM verify-dir "$allrun" --variants "$VARS" --repo "$fx"

# manual origin (MANUALLY GENERATED): decided by the event, recorded, and carried by every name
MS="$tmp/manual_staging"; rm -rf "$MS"; mkdir -p "$MS"
OTHER=2222222222222222222222222222222222222222
mkman android-staging-apk "$MS" "$COMMIT" workflow_dispatch development
mrejm() { # NAME FRAGMENT 'python using m' (mutates a real MANUAL staging manifest)
  mut "$MS/android-staging-apk.manifest.json" "$tmp/badm.json" "$3" || { bad "manifest: $1 (mutation failed)"; return; }
  rejected "manifest: $1" "$2" BM verify "$tmp/badm.json"
}
accepted "manifest: a manual staging build from a commit of development verifies" BM verify "$MS/android-staging-apk.manifest.json" --repo "$fx" --evidence "$MS/android-staging-apk.txt"
t "manifest: a manual build records origin MANUALLY GENERATED and on_development true" bash -c 'python3 -I -c "import json,sys; s=json.load(open(sys.argv[1]))[\"source\"]; assert s[\"origin\"]==\"MANUALLY GENERATED\" and s[\"on_development\"] is True and s[\"event\"]==\"workflow_dispatch\"" "$1"' _ "$MS/android-staging-apk.manifest.json"
t "manifest: a promotion records origin automatic and on_development null" bash -c 'python3 -I -c "import json,sys; s=json.load(open(sys.argv[1]))[\"source\"]; assert s[\"origin\"]==\"automatic\" and s[\"on_development\"] is None and s[\"event\"]==\"push\"" "$1"' _ "$good/android-staging-apk.manifest.json"
mrejm "a manual build claiming to be automatic" "source.origin is 'automatic'" 'm["source"]["origin"]="automatic"'
mrejm "a manual build with a different label" "source.origin" 'm["source"]["origin"]="manual"'
mrejm "a manual build without the on_development fact" "must be true or false" 'm["source"]["on_development"]=None'
mrejm "a manually generated STAGING build from a commit that is not on development" "must be built from a commit of development" 'm["source"]["on_development"]=False'
mrej "a promotion claiming MANUALLY GENERATED" "source.origin" 'm["source"]["origin"]="MANUALLY GENERATED"'
mrej "a promotion carrying an on_development value" "must be null for a promotion" 'm["source"]["on_development"]=True'
mrej "a manifest without the origin field" "missing key 'source.origin'" 'del m["source"]["origin"]'
mrej "a manifest without the on_development field" "missing key 'source.on_development'" 'del m["source"]["on_development"]'
mrejm "a manual manifest whose file name lacks the MANUALLY_GENERATED_ prefix" "not the canonical name" 'm["artifact"]["canonical_name"]=m["artifact"]["canonical_name"].replace("MANUALLY_GENERATED_","",1)'
mrej "a promotion manifest whose file name carries the manual prefix" "not the canonical name" 'm["artifact"]["canonical_name"]="MANUALLY_GENERATED_"+m["artifact"]["canonical_name"]'
mn="$(BM name "$MS/android-staging-apk.manifest.json")"
t "name: a manual build's name starts with MANUALLY_GENERATED_ and keeps the canonical name after it" eq "$mn" "MANUALLY_GENERATED_cadena-signer-staging-1.0.3+1000034-android-apk-${COMMIT:0:7}-run${RUN}.1.apk"
t "name: the marker is outermost, before the NON-DISTRIBUTABLE label" eq "$(BM name "$MS/android-staging-apk.manifest.json" --classification internal-evaluation)" "MANUALLY_GENERATED_NON-DISTRIBUTABLE_INTERNAL-EVALUATION_${mn#MANUALLY_GENERATED_}"
t "name: a promotion's name is unchanged by the marker (no prefix)" eq "$(BM name "$good/android-staging-apk.manifest.json")" "cadena-signer-staging-1.0.3+1000034-android-apk-${COMMIT:0:7}-run${RUN}.1.apk"
# a manual run records the commit of the run (GITHUB_SHA), the same as a promotion; there is no other source of the commit
MO="$tmp/manual_other"; rm -rf "$MO"; mkdir -p "$MO"
OTHER=2222222222222222222222222222222222222222
mkev android-staging-apk "$MO" "$OTHER"
CREATE_ENV="GITHUB_RUN_ID=$RUN GITHUB_RUN_ATTEMPT=1 GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=CadenaBitcoin/signer_app GITHUB_REF_NAME=development GITHUB_REF_TYPE=branch"
# shellcheck disable=SC2086
accepted "create: a manual run records the commit of the run" env $CREATE_ENV GITHUB_EVENT_NAME=workflow_dispatch GITHUB_SHA=$OTHER CADENA_COMMIT_ON_DEVELOPMENT=true python3 -I "$TOOLPY" create --evidence "$MO/android-staging-apk.txt" --toolchain "$MO/android-staging-apk.toolchain" --out "$MO/m.json"
t "create: the manual manifest holds that commit and the artifact name uses it" bash -c 'python3 -I -c "import json,sys; m=json.load(open(sys.argv[1])); assert m[\"source\"][\"commit\"]==sys.argv[2]; assert sys.argv[2][:7] in m[\"artifact\"][\"canonical_name\"] and m[\"artifact\"][\"canonical_name\"].startswith(\"MANUALLY_GENERATED_\")" "$1" "$2"' _ "$MO/m.json" "$OTHER"
# shellcheck disable=SC2086
expect_rc "create: a commit other than the evidence's is refused" 2 "differs from the evidence" env $CREATE_ENV GITHUB_EVENT_NAME=workflow_dispatch GITHUB_SHA=$COMMIT CADENA_COMMIT_ON_DEVELOPMENT=true python3 -I "$TOOLPY" create --evidence "$MO/android-staging-apk.txt" --toolchain "$MO/android-staging-apk.toolchain" --out "$MO/x.json"
# shellcheck disable=SC2086
expect_rc "create: a build commit cannot be redirected by an environment variable (CADENA_SOURCE_SHA is ignored)" 2 "differs from the evidence" env $CREATE_ENV GITHUB_EVENT_NAME=workflow_dispatch GITHUB_SHA=$COMMIT CADENA_SOURCE_SHA=$OTHER CADENA_COMMIT_ON_DEVELOPMENT=true python3 -I "$TOOLPY" create --evidence "$MO/android-staging-apk.txt" --toolchain "$MO/android-staging-apk.toolchain" --out "$MO/x.json"
# shellcheck disable=SC2086
expect_rc "create: a manual run without the on_development fact is refused" 2 "CADENA_COMMIT_ON_DEVELOPMENT must be true or false" env $CREATE_ENV GITHUB_EVENT_NAME=workflow_dispatch GITHUB_SHA=$OTHER python3 -I "$TOOLPY" create --evidence "$MO/android-staging-apk.txt" --toolchain "$MO/android-staging-apk.toolchain" --out "$MO/x.json"
# shellcheck disable=SC2086
expect_rc "create: an event that is neither push nor workflow_dispatch is refused" 2 "neither push nor workflow_dispatch" env $CREATE_ENV GITHUB_EVENT_NAME=pull_request GITHUB_SHA=$COMMIT python3 -I "$TOOLPY" create --evidence "$MO/android-staging-apk.txt" --toolchain "$MO/android-staging-apk.toolchain" --out "$MO/x.json"
# a manual and an automatic manifest of one run cannot mix (the manifests of one run agree on the origin)
mixo="$tmp/mixo"; rm -rf "$mixo"; mkdir -p "$mixo"
cp "$MS/android-staging-apk."* "$mixo/"
mut "$good/ios-staging.manifest.json" "$mixo/ios-staging.manifest.json" 'm["source"]["commit"]="'"$COMMIT"'"'
cp "$good/ios-staging.txt" "$mixo/"
rejected "run: manifests of one run that disagree on the origin are refused" "disagree on source.origin" BM verify-dir "$mixo" --variants "android-staging-apk ios-staging" --repo "$fx"

# historical manifests (schema 1, before source.origin / source.on_development): REAL files, written by the build_manifest.py
# of development at 7525c2b, the last commit before the origin fields (tool/fixtures/manifest-schema1/). They must stay verifiable.
H="$root/tool/fixtures/manifest-schema1"
HP="$H/promotion-android-staging-apk.manifest.json"     # a promotion (push to staging)
HM="$H/manual-android-production-apk.manifest.json"     # a manual run from a feature branch
t "legacy: the fixtures are schema 1 and carry no origin fields" bash -c 'python3 -I -c "
import json,sys
for p in sys.argv[1:]:
    m=json.load(open(p)); assert m[\"schema\"]==\"cadena-build-manifest/1\" and \"origin\" not in m[\"source\"] and \"on_development\" not in m[\"source\"], p" "$1" "$2"' _ "$HP" "$HM"
expect_rc "legacy: a historical promotion manifest verifies" 0 "RESULT: OK" BM verify "$HP"
expect_rc "legacy: a historical manual manifest verifies" 0 "RESULT: OK" BM verify "$HM"
expect_rc "legacy: ... against its own text evidence" 0 "RESULT: OK" BM verify "$HM" --evidence "$H/manual-android-production-apk.txt"
expect_rc "legacy: ... and the promotion one" 0 "RESULT: OK" BM verify "$HP" --evidence "$H/promotion-android-staging-apk.txt"
expect_rc "legacy: the verifier says the origin is not recorded in a schema-1 manifest" 0 "whether the build was started by hand is NOT recorded" BM verify "$HM"
expect_rc "legacy: the historical file name is unchanged (no prefix)" 0 "cadena-signer-production-1.0.3+1000034-android-apk-7b63c97-run39237471969.1.apk" BM name "$HM"
t "legacy: a historical manual manifest does not get the MANUALLY_GENERATED_ prefix" bash -c '! "$@" | grep -q MANUALLY_GENERATED' _ python3 -I "$tool" name "$HM"
# ... but only under schema-1 rules. The strict current rules cannot be dodged by choosing the old schema:
expect_rc "legacy: --require-current refuses a schema-1 manifest (the build jobs use it)" 1 "expected 'cadena-build-manifest/2'" BM verify "$HP" --require-current
mut "$HP" "$tmp/lg1.json" 'm["source"]["origin"]="MANUALLY GENERATED"; m["source"]["on_development"]=True'
rejected "legacy: a schema-1 manifest carrying the new fields is refused (strict key set)" "unknown key 'source.origin'" BM verify "$tmp/lg1.json"
mut "$HP" "$tmp/lg2.json" 'm["source"]["commit"]="7b63c97"'
rejected "legacy: a historical manifest is still checked (a short commit)" "40-character" BM verify "$tmp/lg2.json"
mut "$HP" "$tmp/lg3.json" 'm["artifact"]["canonical_name"]="MANUALLY_GENERATED_"+m["artifact"]["canonical_name"]'
rejected "legacy: a historical manifest whose name carries the manual prefix is refused" "not the canonical name" BM verify "$tmp/lg3.json"
mut "$HP" "$tmp/lg4.json" 'm["schema"]="cadena-build-manifest/2"'
rejected "legacy: a schema-1 manifest relabelled schema 2 is refused (the new fields are required)" "missing key 'source.origin'" BM verify "$tmp/lg4.json"
# a manual manifest cannot be downgraded to escape the marking: schema 1 has no prefix, so its file name no longer fits
mut "$MS/android-staging-apk.manifest.json" "$tmp/lg5.json" 'm["schema"]="cadena-build-manifest/1"; m["source"].pop("origin"); m["source"].pop("on_development")'
rejected "legacy: a new manual manifest downgraded to schema 1 is refused (its prefixed file name)" "not the canonical name" BM verify "$tmp/lg5.json"
rejected "legacy: ... and always by --require-current" "expected 'cadena-build-manifest/2'" BM verify "$tmp/lg5.json" --require-current
# a run is verified as a whole in the current schema: a directory of historical manifests is not a current run
lgd="$tmp/lgd"; rm -rf "$lgd"; mkdir -p "$lgd"
cp "$HP" "$lgd/android-staging-apk.manifest.json"; cp "$H/promotion-android-staging-apk.txt" "$lgd/android-staging-apk.txt"
rejected "legacy: verify-dir (the verdict of a run) refuses schema-1 manifests" "expected 'cadena-build-manifest/2'" BM verify-dir "$lgd" --variants android-staging-apk
mut "$HP" "$tmp/lg6.json" 'm["schema"]="cadena-build-manifest/9"'
rejected "legacy: an unknown schema is refused" "schema is 'cadena-build-manifest/9'" BM verify "$tmp/lg6.json"

# canonical names
n1="$(BM name "$M")"
expect_rc "name: the canonical name carries environment, version, platform, kind, commit and run" 0 "cadena-signer-production-1.0.3+1000034-android-apk-7b63c97-run39237471969.1.apk" BM name "$M"
expect_rc "name: an internal-evaluation copy is labelled NON-DISTRIBUTABLE" 0 "NON-DISTRIBUTABLE_INTERNAL-EVALUATION_$n1" BM name "$M" --classification internal-evaluation
expect_rc "name: no file name exists for a release classification" 2 "no file name is defined" BM name "$M" --classification release
t_aab="$(BM name "$good/android-production-aab.manifest.json")"; t_ios="$(BM name "$good/ios-production.manifest.json")"
case "$t_aab" in *.aab) ok "name: an AAB ends in .aab" ;; *) bad "name: an AAB ends in .aab" "$t_aab" ;; esac
case "$t_ios" in *-ios-app-*.app) ok "name: the iOS app is named as a directory" ;; *) bad "name: the iOS app is named as a directory" "$t_ios" ;; esac
all_names="$(for v in $VARS; do BM name "$good/$v.manifest.json"; done | sort | uniq -d)"
if [ -z "$all_names" ]; then ok "name: the five variants of one run have distinct names"; else bad "name: the five variants of one run have distinct names" "$all_names"; fi

# the production release gate has two independent rules, each tested alone and together on fixtures:
#   (1) the build number is above every published one   (2) the Android application ID is the published package
gate_repo() { mkfix "$tmp/g" "$@"; } # BUILD PACKAGE [FLOOR]
GATE() { BM gate --channel production --repo "$tmp/g"; }
# rule 1 alone: the ledger publishes the production application ID, so only the number can fail
gate_repo 1000033 "$PROD_ID"; rejected "gate: a lower build number is not releasable" "not above the published" GATE
gate_repo 1000034 "$PROD_ID"; rejected "gate: the published build number itself is not releasable" "not above the published" GATE
gate_repo 1000035 "$PROD_ID"; expect_rc "gate: the next build number is releasable" 0 "build 1000035 is above the published floor 1000034" GATE
gate_repo 1000099 "$PROD_ID"; expect_rc "gate: a future version far above the floor satisfies the build-number rule" 0 "is above the published floor 1000034" GATE
gate_repo 1000035 "$PROD_ID" 1000036; rejected "gate: a higher published number (ledger edited) blocks again" "not above the published" GATE
# the baseline after Android 1.0.4 (1000035) was published (#72): that number is spent, the next one is releasable
gate_repo 1000035 "$PROD_ID" 1000035; rejected "gate: with 1.0.4 (1000035) published, build 1000035 is not releasable" "not above the published build number 1000035" GATE
gate_repo 1000036 "$PROD_ID" 1000035; expect_rc "gate: with 1.0.4 (1000035) published, build 1000036 is releasable" 0 "build 1000036 is above the published floor 1000035" GATE
gate_repo 1000034 "$PROD_ID"; accepted "gate: staging is a separate application, no floor applies" BM gate --channel staging --repo "$tmp/g"
# rule 2 alone: the build number is far above the floor, the identity is not the published one (#72)
gate_repo 1000035 "$OTHER_ID"; rejected "gate: build 1000035 with a production application ID that is not the published package is blocked" "is not the published package $OTHER_ID" GATE
gate_repo 1000099 "$OTHER_ID"; rejected "gate: build 1000099 is blocked by the application ID too, whatever the number" "is not the published package $OTHER_ID" GATE
gate_repo 2000000000 "$OTHER_ID"; rejected "gate: even a huge build number does not hide the application-ID mismatch" "is not the published package" GATE
gate_repo 1000099 "$OTHER_ID"; expect_rc "gate: the build-number rule still reports its own pass beside the ID failure" 1 "build 1000099 is above the published floor" GATE
# both rules fail together: both are reported
gate_repo 1000034 "$OTHER_ID"; rejected "gate: both rules fail and both are reported" "FAILED (2)" GATE
# no record, unreadable record
gate_repo 1 "$PUBLISHED_ID"; printf '{"schema":"cadena-published-versions/1","entries":[]}' >"$tmp/g/config/release/published_versions.json"
accepted "gate: with no published record there is no floor and no identity to match" GATE
printf '{"schema":"other","entries":[]}' >"$tmp/g/config/release/published_versions.json"
expect_rc "gate: an unreadable ledger is an error, not a pass" 2 "unexpected schema" GATE
# live: the repository as it is today. Whatever its version, the gate agrees with the arithmetic and with the
# identity rule (the version moves with later releases; these assertions hold at every version).
ledger_floor="$(python3 -I -c 'import json,sys; print(max(e["version_code"] for e in json.load(open(sys.argv[1]))["entries"] if e["platform"]=="android"))' "$root/config/release/published_versions.json")"
ledger_pkgs="$(python3 -I -c 'import json,sys; print(" ".join(sorted({e["package"] for e in json.load(open(sys.argv[1]))["entries"] if e["platform"]=="android"})))' "$root/config/release/published_versions.json")"
pub_build="$(sed -n 's/^version: *[0-9.]*+//p' "$root/pubspec.yaml")"
live_id="$(cd "$root" && bash tool/verify_artifact.sh matrix | sed -n "s/^android[[:space:]]\{1,\}production[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p")"
live_out="$(BM gate --channel production 2>&1)"; live_rc=$?
if [ "$pub_build" -gt "$ledger_floor" ]; then want_frag="build $pub_build is above the published floor"; else want_frag="build $pub_build is not above the published build number"; fi
t "live gate: the build-number verdict agrees with the pubspec ($pub_build) and the ledger ($ledger_floor)" has "$live_out" "$want_frag"
if [ " $ledger_pkgs " = " $live_id " ] || [ -z "$ledger_pkgs" ]; then
  t "live gate: the production application ID ($live_id) matches the published package" has "$live_out" "PASS  android: the production application ID matches"
else
  t "live gate: the production application ID ($live_id) differs from the published package ($ledger_pkgs) and the gate says so" has "$live_out" "is not the published package"
  t "live gate: an unresolved application-ID mismatch fails the gate whatever the version (exit 1)" eq "$live_rc" 1
fi
# the identity matrix of the repository (#72): Android is the published Google Play package, iOS keeps its own bundle IDs
live_matrix="$(cd "$root" && bash tool/verify_artifact.sh matrix)"
matrix_id() { sed -n "s/^$1[[:space:]]\{1,\}$2[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p" <<<"$live_matrix"; }
t "identity: Android production is the published Google Play package ($PUBLISHED_ID)" eq "$(matrix_id android production)" "$PUBLISHED_ID"
t "identity: Android staging is the production package plus .staging" eq "$(matrix_id android staging)" "$PUBLISHED_ID.staging"
t "identity: iOS production keeps its bundle ID ($IOS_PROD_ID)" eq "$(matrix_id ios production)" "$IOS_PROD_ID"
t "identity: iOS staging keeps its bundle ID ($IOS_STAGING_ID)" eq "$(matrix_id ios staging)" "$IOS_STAGING_ID"
t "identity: the Android and iOS production identifiers are different" test "$(matrix_id android production)" != "$(matrix_id ios production)"
t "identity: the Android application ID in the ledger and in Gradle agree" has "$(grep -E '^[[:space:]]*applicationId[[:space:]]*=' "$root/android/app/build.gradle.kts")" "\"$ledger_pkgs\""
if [ "$pub_build" -ge "$ledger_floor" ]; then ok "ledger: the pubspec build is not below the published floor"; else bad "ledger: the pubspec build is below the published floor" "$pub_build < $ledger_floor"; fi
# Android 1.0.4+1000035 is published (confirmed 2026-11-04, #72): the floor never goes back below it, and the history is kept
t "ledger: Android 1.0.4 (1000035) is recorded as published, so the floor is at least 1000035" test "$ledger_floor" -ge 1000035
t "ledger: the 1.0.3 (1000034) and 1.0.4 (1000035) Google Play entries both exist for the published package" eq "$(python3 -I -c '
import json,sys
e=json.load(open(sys.argv[1]))["entries"]
have={(x["version_name"],x["version_code"]):x for x in e if x["platform"]=="android" and x["channel"]=="google-play" and x["package"]==sys.argv[2]}
print(("1.0.3",1000034) in have and ("1.0.4",1000035) in have and have[("1.0.4",1000035)]["status"]=="published")' "$root/config/release/published_versions.json" "$PUBLISHED_ID")" True
t "ledger: no iOS version is recorded as published" eq "$(python3 -I -c 'import json,sys; print(sum(1 for x in json.load(open(sys.argv[1]))["entries"] if x["platform"]=="ios"))' "$root/config/release/published_versions.json")" 0

# a release cannot be claimed while the published-version protections are open
RELCLAIM='m["classification"]="release"; m["signing"]["status"]="release"; m["signing"]["signer_dn"]="CN=Cadena Release"; m["source"]["release_id"]="v1.0.3"; m["distribution"]["distributable"]=True'
mrej "a release claimed with a build number that is not above the published floor" "not above the published floor" "$RELCLAIM" --repo "$fx"
mrej "a release claimed while the application ID differs from the published app" "known issues are open: application-id-differs-from-published-app" "$RELCLAIM; m['release_gate']={'status':'above-floor','published_floor':1000034}; m['known_issues']=['application-id-differs-from-published-app']"
mrej "a release candidate classification is claimed under the same rule" "not above the published floor" 'm["classification"]="release-candidate"'
# positive control: once the build number is above the floor AND the identity matches the published app
# (what #72 must achieve), the same claim is no longer blocked by these two rules
mkfix "$tmp/fut" 1000035 "$PROD_ID"
FIX="$tmp/fut" TOOLPY="$tmp/fut/tool/build_manifest.py" mkman android-production-apk "$tmp/futm" "$COMMIT" push production
mut "$tmp/futm/android-production-apk.manifest.json" "$tmp/futrel.json" "$RELCLAIM; m['signing']['signer_cert_sha256']=''"
rejected "future: a release claim is still refused without a fingerprint of a release key" "release-signed artifact must record" python3 -I "$tmp/fut/tool/build_manifest.py" verify "$tmp/futrel.json" --repo "$tmp/fut"
mut "$tmp/futm/android-production-apk.manifest.json" "$tmp/futrel.json" "$RELCLAIM; m['signing']['signer_cert_sha256']='$Y'"
accepted "future: with build 1000035 and the published identity a (hypothetical) release manifest passes" python3 -I "$tmp/fut/tool/build_manifest.py" verify "$tmp/futrel.json" --repo "$tmp/fut"
rejected "future: the same manifest is refused against the fixture at the published floor (another pubspec, ledger)" "the repository says" BM verify "$tmp/futrel.json" --repo "$fx"
t "future: its gate is above the floor and no known issue is open" eq "$(python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); print(m["release_gate"]["status"], m["known_issues"])' "$tmp/futm/android-production-apk.manifest.json")" "above-floor []"

# the complete gate regardless of the version number: a REAL manifest (written by the tool, not edited) of a build
# far above the floor, whose application ID is not the published one (#72), cannot claim a release
for hb in 1000035 1000099 2000000000; do
  mkfix "$tmp/hi" "$hb" "$OTHER_ID"
  rm -rf "$tmp/him"
  FIX="$tmp/hi" TOOLPY="$tmp/hi/tool/build_manifest.py" mkman android-production-apk "$tmp/him" "$COMMIT" push production
  HM="$tmp/him/android-production-apk.manifest.json"
  t "id-mismatch $hb: the tool records an open gate above the floor and the known issue" eq "$(python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); print(m["release_gate"]["status"], m["known_issues"])' "$HM")" "above-floor ['application-id-differs-from-published-app']"
  accepted "id-mismatch $hb: as compile validation the manifest is valid" python3 -I "$tmp/hi/tool/build_manifest.py" verify "$HM" --repo "$tmp/hi"
  mut "$HM" "$tmp/hirel.json" "$RELCLAIM; m['signing']['signer_cert_sha256']='$Y'"
  rejected "id-mismatch $hb: a release claim is refused although the number is above the floor" "known issues are open: application-id-differs-from-published-app" python3 -I "$tmp/hi/tool/build_manifest.py" verify "$tmp/hirel.json" --repo "$tmp/hi"
  mut "$HM" "$tmp/hidrop.json" "m['known_issues']=[]"
  rejected "id-mismatch $hb: the known issue cannot be dropped to pass" "cannot be dropped" python3 -I "$tmp/hi/tool/build_manifest.py" verify "$tmp/hidrop.json" --repo "$tmp/hi"
  mut "$HM" "$tmp/hidrop2.json" "$RELCLAIM; m['signing']['signer_cert_sha256']='$Y'; m['known_issues']=[]"
  rejected "id-mismatch $hb: a release claim with the issue dropped is refused" "cannot be dropped" python3 -I "$tmp/hi/tool/build_manifest.py" verify "$tmp/hidrop2.json" --repo "$tmp/hi"
  mkfix "$tmp/g" "$hb" "$OTHER_ID"
  rejected "id-mismatch $hb: the production gate fails" "is not the published package" GATE
done

# a retained binary and its manifest: what can be verified from the two files alone
bin="$tmp/retained/app.apk"; mkdir -p "$tmp/retained"
printf 'not really an apk' >"$bin"
bin_sha="$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$bin")"
mut "$M" "$tmp/retained/m.json" 'm["artifact"]["sha256"]="'"$bin_sha"'"; m["artifact"]["size"]="17"; m["artifact"]["file"]="app.apk"'
accepted "file: the binary matches its manifest" BM check-file "$tmp/retained/m.json" "$bin"
expect_rc "file: the output separates recorded claims from proof" 0 "recorded build provenance, not authenticated" BM check-file "$tmp/retained/m.json" "$bin"
expect_rc "file: the claimed commit is shown" 0 "source commit  $COMMIT" BM check-file "$tmp/retained/m.json" "$bin"
expect_rc "file: the claimed CI execution is shown" 0 "https://github.com/CadenaBitcoin/signer_app/actions/runs/$RUN" BM check-file "$tmp/retained/m.json" "$bin"
expect_rc "file: the claimed version, signing and classification are shown" 0 "classification compile-validation" BM check-file "$tmp/retained/m.json" "$bin"
printf 'tampered' >>"$bin"
rejected "file: a changed binary is refused (digest)" "SHA-256 mismatch" BM check-file "$tmp/retained/m.json" "$bin"
printf 'not really an apk' >"$bin"
cp "$bin" "$tmp/retained/renamed.bin"
expect_rc "file: a renamed copy still matches (the digest decides) and says so" 0 "none of the recorded names" BM check-file "$tmp/retained/m.json" "$tmp/retained/renamed.bin"
mut "$M" "$tmp/retained/m2.json" 'm["artifact"]["sha256"]="'"$bin_sha"'"; m["artifact"]["size"]="18"'
rejected "file: a wrong size is refused" "the manifest says 18" BM check-file "$tmp/retained/m2.json" "$bin"
rejected "file: a directory given for a file artifact is refused" "is not a file" BM check-file "$tmp/retained/m.json" "$tmp/retained"
# the iOS app is a directory: the digest is the one tool/verify_artifact.sh computes
app="$tmp/retained/Runner.app"; mkdir -p "$app/Frameworks/App.framework"
printf 'plist' >"$app/Info.plist"; printf 'snapshot' >"$app/Frameworks/App.framework/App"; ln -s Info.plist "$app/link"
printf 'z' >"$app/Zeta"; printf 'a' >"$app/alpha" # byte order (C locale): Zeta sorts before alpha
tree_sha="$(cd "$app" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s  %s\n' "$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$f")" "$f"; done | python3 -I -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
mut "$im" "$tmp/retained/im.json" 'm["artifact"]["sha256"]="'"$tree_sha"'"'
accepted "file: an iOS app directory matches the verify_artifact.sh directory digest" BM check-file "$tmp/retained/im.json" "$app"
printf 'x' >>"$app/Info.plist"
rejected "file: a changed file inside the app is refused" "SHA-256 mismatch" BM check-file "$tmp/retained/im.json" "$app"
rejected "file: a plain file given for a directory artifact is refused" "is not one" BM check-file "$tmp/retained/im.json" "$bin"

# the variant catalogue is stated once (the planner); the manifest tool must agree with it
plan_all="$(cd "$root" && tool/plan_build_variants.sh workflow_dispatch refs/heads/development all "" "" identical | sed -n 's/^variants=//p')"
tool_all="$(python3 -I -c '
import sys, runpy
g = runpy.run_path(sys.argv[1], run_name="not_main")
print(" ".join(sorted(g["VARIANTS"])))
' "$tool")"
sorted_plan="$(printf '%s' "$plan_all" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
if [ "$sorted_plan" = "$tool_all" ]; then ok "catalogue: the manifest tool knows exactly the planner's five variants"; else bad "catalogue: the manifest tool and the planner disagree" "planner: $sorted_plan | tool: $tool_all"; fi
cat_check="$(cd "$root" && python3 -I -c '
import sys, runpy, re, subprocess
g = runpy.run_path("tool/build_manifest.py", run_name="not_main")
cat = subprocess.run(["sed", "-n", "/^CATALOGUE=/,/\x27$/p", "tool/plan_build_variants.sh"], capture_output=True, text=True).stdout
bad = []
for line in cat.replace("CATALOGUE=\x27", "").replace("\x27", "").splitlines():
    f = line.split()
    if len(f) < 5: continue
    vid, plat, env, kind = f[0], f[1], f[2], f[3]
    want = (plat, "ios-app" if plat == "ios" else kind, env)
    if g["VARIANTS"].get(vid) != want: bad.append("%s %s != %s" % (vid, g["VARIANTS"].get(vid), want))
print(";".join(bad))
')"
if [ -z "$cat_check" ]; then ok "catalogue: platform, kind and environment of every variant agree with the planner"; else bad "catalogue: platform, kind and environment disagree" "$cat_check"; fi

# ---------------------------------------------------------------------------------------------
# 3. the workflow definition (read as text; comment lines removed first)
# ---------------------------------------------------------------------------------------------
wf="$tmp/workflow.yml"
grep -v '^[[:space:]]*#' "$workflow" >"$wf"
lacks() { ! has "$1" "$2"; }
lacksre() { ! grep -qE -- "$2" <<<"$1"; }
count() { grep -cF -- "$2" <<<"$1" || true; }
wft="$(cat "$wf")"
t "workflow: the manifest is created in both build jobs (Android and iOS)" eq "$(count "$wft" 'tool/build_manifest.py create --evidence')" 2
t "workflow: every manifest is verified against the repository and its text evidence" eq "$(count "$wft" 'tool/build_manifest.py verify "evidence/$BUILD_VARIANT.manifest.json" --repo . --evidence')" 2
t "workflow: a manifest that was just made must be in the current schema (--require-current, both build jobs)" eq "$(count "$wft" '--evidence "evidence/$BUILD_VARIANT.txt" --require-current')" 2
t "workflow: the plan job runs this test before any build" has "$wft" 'run: tool/test_release_versioning.sh'
t "workflow: the verdict verifies the manifests of the run together" has "$wft" 'tool/build_manifest.py verify-dir evidence --variants "$REQUIRED_VARIANTS" --repo .'
t "workflow: the verdict still checks the exact evidence set first" has "$wft" 'tool/check_verdict.sh evidence evidence'
t "workflow: five uploads: two evidence, one iOS diagnostics, two retained (encrypted, Stage 2)" eq "$(count "$wft" 'actions/upload-artifact@')" 5
t "workflow: two uploads are the evidence directory" eq "$(grep -cE '^          path: evidence/$' <<<"$wft")" 2
t "workflow: the third upload is the iOS diagnostics directory (text: build log, Podfile.lock diff)" eq "$(grep -cE '^          path: diagnostics/$' <<<"$wft")" 1
t "workflow: two uploads are the retained directory (ciphertext, checksums, manifests)" eq "$(grep -cE '^          path: retained/$' <<<"$wft")" 2
t "workflow: every retained upload is gated by the plan's retention decision" eq "$(count "$wft" "name: Upload the retained")" 2
t "workflow: the diagnostics artifact has its own name prefix, outside the verdict's evidence download" has "$wft" 'name: ios-diagnostics_${{ matrix.variant }}_a${{ github.run_attempt }}'
t "workflow: the retained artifacts have their own name prefix, outside the evidence download" has "$wft" 'name: ${{ needs.plan.outputs.name_prefix }}retained_${{ matrix.variant }}_a${{ github.run_attempt }}'
t "workflow: no upload names a build output" lacksre "$wft" 'path:.*(build/|\.apk|\.aab|\.ipa|Runner\.app|xcarchive)'
t "workflow: the retention of every text upload stays 14 days" eq "$(grep -cE '^          retention-days: 14$' <<<"$wft")" 3
t "workflow: the retained uploads use the workflow's RETENTION_DAYS (14)" eq "$(grep -cE '^          retention-days: \$\{\{ env\.RETENTION_DAYS \}\}$' <<<"$wft")" 2
t "workflow: RETENTION_DAYS is 14" has "$wft" 'RETENTION_DAYS: "14"'
t "workflow: no job writes pubspec.yaml" lacksre "$wft" '(sed -i|>>?|tee)[^|]*pubspec'
t "workflow: no workflow passes a version override" lacksre "$(cat "$root"/.github/workflows/*.yml | grep -v '^[[:space:]]*#')" '(--build-name|--build-number)'
t "workflow: the signing gate is not part of compile validation" lacks "$wft" 'build_manifest.py gate'
t "workflow: no tag, release or publication step" lacksre "$wft" 'gh release|git tag|create-release|upload-release|google-play|app-store|testflight|fastlane'

echo
echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
