#!/usr/bin/env bash
# Local, reproducible Android PRODUCTION release (Issue #72): build the production APK and AAB,
# sign both with an explicitly selected identity, verify them independently and write the release
# report. It publishes nothing and uploads nothing.
#
#   tool/release_android.sh --signing-properties FILE --expect-cert-sha256 FP \
#                           --identity-label "TEXT" --out DIR [--allow-dirty]
#
#   --signing-properties  Java properties file OUTSIDE the repository with storeFile, keyAlias and,
#                         unless CADENA_KEYSTORE_PASSWORD / CADENA_KEY_PASSWORD are set in the
#                         environment (preferred), storePassword and keyPassword. Never printed.
#   --expect-cert-sha256  the SHA-256 fingerprint of the upload certificate the artifacts must carry
#   --identity-label      free text for the audit trail, e.g. "CadenaBitcoin upload key 2026"
#   --out                 a directory that does not exist yet or is empty
#   --allow-dirty         only for tests: a dirty tracked tree is recorded and makes the report NOT READY
#
# Environment: JDK 17 (JAVA_HOME), ANDROID_HOME, Flutter 3.35.3 on PATH, and BUNDLETOOL_JAR pointing to
# bundletool-all-1.18.3.jar (SHA-256 is checked). No credential is ever read by this script itself:
# Gradle reads the keystore, and no value is echoed.
#
# Refuses (exit 2, before anything is built) when a precondition is missing: there is no fallback to
# the debug key. Exit 1: built, but not release-ready (a verification check, the clean-tree rule or the
# production gate failed). Exit 0: built, signed, verified and recorded - NOT published.
set -euo pipefail
set +x
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

BUNDLETOOL_SHA256=a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29
props="" fp="" label="" out="" allow_dirty=0
die() { echo "release_android: $1" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --signing-properties) props="${2:-}"; shift 2 ;;
    --expect-cert-sha256) fp="${2:-}"; shift 2 ;;
    --identity-label) label="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --allow-dirty) allow_dirty=1; shift ;;
    *) die "unknown option '$1' (see the header of this script)" ;;
  esac
done
[ -n "$props" ] && [ -n "$fp" ] && [ -n "$label" ] && [ -n "$out" ] || die "--signing-properties, --expect-cert-sha256, --identity-label and --out are all required"

# ---- preconditions: nothing is built until all of them hold -------------------------------
[ -f "$props" ] || die "the signing properties file does not exist"
props="$(cd "$(dirname "$props")" && pwd)/$(basename "$props")"
case "$props" in "$root"/*) die "the signing properties file must be outside the repository" ;; esac
fp_hex="$(printf '%s' "$fp" | tr -d ':' | tr 'A-F' 'a-f')"
printf '%s' "$fp_hex" | grep -Eq '^[0-9a-f]{64}$' || die "--expect-cert-sha256 is not a SHA-256 fingerprint"
if [ -e "$out" ] && [ -n "$(ls -A "$out" 2>/dev/null)" ]; then die "--out must not exist or must be empty (a release record is never overwritten)"; fi
command -v flutter >/dev/null || die "flutter not found on PATH"
command -v java >/dev/null && command -v keytool >/dev/null && command -v jarsigner >/dev/null || die "a JDK 17 (java, keytool, jarsigner) is needed"
java -version 2>&1 | head -n1 | grep -q '"17\.' || die "JDK 17 is required (Flutter is pointed at it with 'flutter config --jdk-dir'); got: $(java -version 2>&1 | head -n1)"
[ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ] || die "ANDROID_HOME must name the Android SDK"
[ -n "${BUNDLETOOL_JAR:-}" ] && [ -f "$BUNDLETOOL_JAR" ] || die "BUNDLETOOL_JAR must name bundletool-all-1.18.3.jar"
actual_sha="$( (sha256sum "$BUNDLETOOL_JAR" 2>/dev/null || shasum -a 256 "$BUNDLETOOL_JAR") | cut -d' ' -f1)"
[ "$actual_sha" = "$BUNDLETOOL_SHA256" ] || die "BUNDLETOOL_JAR is not the pinned bundletool 1.18.3 (SHA-256 differs)"
if [ "$allow_dirty" -eq 0 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  die "the tracked working tree is not clean: commit or stash first (a release is built from a committed state)"
fi
tool/verify_version.sh >/dev/null || die "tool/verify_version.sh fails: the version/flavor wiring is not intact"
# The gate: the build number must be above the published one and the application ID must be the published package.
if ! python3 -I tool/build_manifest.py gate --channel production >/tmp/release_android_gate.$$ 2>&1; then
  cat /tmp/release_android_gate.$$ >&2; rm -f /tmp/release_android_gate.$$
  die "the production release gate fails (see above); raise the version by a reviewed commit first. Nothing was built."
fi
rm -f /tmp/release_android_gate.$$
# The signing credentials are checked by Gradle before anything is signed (fingerprint, keystore location);
# fail early and cheaply here for the obvious omissions, without reading any value.
grep -Eq '^[[:space:]]*storeFile[[:space:]]*=' "$props" || die "the signing properties file has no storeFile"
grep -Eq '^[[:space:]]*keyAlias[[:space:]]*=' "$props" || die "the signing properties file has no keyAlias"
{ [ -n "${CADENA_KEYSTORE_PASSWORD:-}" ] || grep -Eq '^[[:space:]]*storePassword[[:space:]]*=' "$props"; } || die "no keystore password (CADENA_KEYSTORE_PASSWORD or storePassword)"
{ [ -n "${CADENA_KEY_PASSWORD:-}" ] || grep -Eq '^[[:space:]]*keyPassword[[:space:]]*=' "$props"; } || die "no key password (CADENA_KEY_PASSWORD or keyPassword)"

version="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n1 | tr -d '[:space:]')"
commit="$(git rev-parse HEAD)"
echo "release_android: production ${version}, commit ${commit}"
echo "release_android: identity label: ${label}; expected certificate: ${fp_hex}"

# ---- build ------------------------------------------------------------------------------------
flutter pub get --enforce-lockfile
(cd flutter_plugin/flutter_plugin && flutter pub get)
export CADENA_SIGNING=release CADENA_SIGNING_PROPERTIES="$props" CADENA_EXPECTED_CERT_SHA256="$fp_hex"
flutter build apk --release --flavor production --dart-define-from-file=config/build/production.json
flutter build appbundle --release --flavor production --dart-define-from-file=config/build/production.json
unset CADENA_SIGNING CADENA_SIGNING_PROPERTIES CADENA_EXPECTED_CERT_SHA256

apk_built=build/app/outputs/flutter-apk/app-production-release.apk
aab_built=build/app/outputs/bundle/productionRelease/app-production-release.aab
[ -f "$apk_built" ] && [ -f "$aab_built" ] || die "a build finished without its artifact"

mkdir -p "$out"
base="cadena-signer_production_${version}_${commit:0:7}"
cp "$apk_built" "$out/${base}_local-signed.apk"
cp "$aab_built" "$out/${base}_upload-signed.aab"

# ---- verify and record ------------------------------------------------------------------------
status=0
python3 -I tool/verify_android_release.py release production \
  --apk "$out/${base}_local-signed.apk" --aab "$out/${base}_upload-signed.aab" \
  --expect-cert-sha256 "$fp_hex" --identity-label "$label" --out "$out" \
  $( [ "$allow_dirty" -eq 1 ] && echo --allow-dirty ) || status=$?
echo
echo "release_android: artifacts and report are in $out"
echo "release_android: NOT published. The APK is signed with the UPLOAD identity: it cannot update installations from Google Play."
echo "release_android: the AAB is for Google Play (upload is a separate, authorized step); the APK is for the website (delivery is a separate, authorized step)."
exit "$status"
