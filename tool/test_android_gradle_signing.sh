#!/usr/bin/env bash
# Regression tests of the Android release-signing rules in android/app/build.gradle.kts, run by REAL
# Gradle (Issue #72). Nothing is compiled, signed or written: every case is a Gradle --dry-run, which
# configures the project (so the signing code runs) and builds the task graph (so the production-only
# rule runs), then stops. Each case takes seconds.
#
#   tool/test_android_gradle_signing.sh
#
# Needs JDK 17 (JAVA_HOME or java on PATH), the Android SDK (ANDROID_HOME or android/local.properties)
# and a resolved Flutter project (flutter pub get, which writes android/local.properties). Without them
# the script exits 2 and says why: it never reports success for tests it could not run.
#
# What it pins:
#   - validation mode (CADENA_SIGNING unset or "validation") holds no signing identity and builds
#     every flavor's variants: the credential-free CI builds are unaffected;
#   - "release" mode signs the PRODUCTION application only: any task of the release variant of another
#     flavor (staging, or one added later), also through the flavor-less aggregate tasks, fails the build;
#   - "release" mode still refuses a typo, missing credentials and a certificate that is not the expected one.
# The only key is a DISPOSABLE keystore generated here in a temporary directory that is deleted at the end.
# No real key, keystore or password is read or needed. Set GRADLE_TEST_FLAGS (e.g. --offline) to pass
# extra flags to Gradle.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

command -v keytool >/dev/null || { echo "test_android_gradle_signing: keytool (JDK 17) not found" >&2; exit 2; }
java -version 2>&1 | head -n1 | grep -q '"17\.' || { echo "test_android_gradle_signing: JDK 17 is required (got: $(java -version 2>&1 | head -n1))" >&2; exit 2; }
[ -x android/gradlew ] || { echo "test_android_gradle_signing: android/gradlew not found" >&2; exit 2; }
[ -f android/local.properties ] || { echo "test_android_gradle_signing: android/local.properties is missing; run 'flutter pub get' first" >&2; exit 2; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/cadena-gradle-signing-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0
failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }

# A disposable keystore; its passwords are test constants that protect nothing.
pw="disposable-test-only"
keytool -genkeypair -keystore "$tmp/test.p12" -storetype PKCS12 -alias test -keyalg RSA -keysize 2048 \
  -validity 400 -dname "CN=Disposable Gradle signing test" -storepass "$pw" -keypass "$pw" >/dev/null 2>&1 \
  || { echo "test_android_gradle_signing: could not create the disposable keystore" >&2; exit 2; }
fp="$(keytool -list -v -keystore "$tmp/test.p12" -storepass "$pw" -alias test 2>/dev/null | sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' | head -n1)"
[ -n "$fp" ] || { echo "test_android_gradle_signing: could not read the disposable certificate fingerprint" >&2; exit 2; }
wrong_fp="00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"

# gradle_case LABEL EXPECT(ok|fail) FRAGMENT TASKS... : environment variables are taken from $CASE_ENV (lines NAME=VALUE).
CASE_ENV=()
gradle_case() {
  local label="$1" expect="$2" fragment="$3" log="$tmp/case.log" status; shift 3
  (cd android && env -u CADENA_SIGNING -u CADENA_SIGNING_PROPERTIES -u CADENA_KEYSTORE_FILE -u CADENA_KEY_ALIAS \
      -u CADENA_KEYSTORE_PASSWORD -u CADENA_KEY_PASSWORD -u CADENA_EXPECTED_CERT_SHA256 \
      "${CASE_ENV[@]}" ./gradlew --console=plain ${GRADLE_TEST_FLAGS:-} -q --dry-run "$@" >"$log" 2>&1)
  status=$?
  if [ "$expect" = ok ]; then
    if [ "$status" -eq 0 ]; then ok "$label"; else bad "$label" "exit $status, expected success: $(tail -n 6 "$log" | cut -c1-240 | tr '\n' '|')"; fi
  else
    if [ "$status" -ne 0 ] && grep -qF -- "$fragment" "$log"; then ok "$label"; else bad "$label" "exit $status; wanted failure containing '$fragment': $(tail -n 6 "$log" | cut -c1-240 | tr '\n' '|')"; fi
  fi
}
release_env=(CADENA_SIGNING=release "CADENA_KEYSTORE_FILE=$tmp/test.p12" CADENA_KEY_ALIAS=test
  "CADENA_KEYSTORE_PASSWORD=$pw" "CADENA_KEY_PASSWORD=$pw" "CADENA_EXPECTED_CERT_SHA256=$fp")
ONLY='signs the production application only'

# ---- validation mode: credential-free, every flavor ---------------------------------------------
CASE_ENV=()
gradle_case "validation (CADENA_SIGNING unset): the staging release variant configures and plans" ok "" :app:assembleStagingRelease
gradle_case "validation: the production release APK plans" ok "" :app:assembleProductionRelease
gradle_case "validation: the production release bundle plans" ok "" :app:bundleProductionRelease
gradle_case "validation: the flavor-less aggregate (every flavor) plans" ok "" :app:assembleRelease
CASE_ENV=(CADENA_SIGNING=validation)
gradle_case "CADENA_SIGNING=validation: the staging release variant plans" ok "" :app:assembleStagingRelease

# ---- release mode: the production application only ----------------------------------------------
CASE_ENV=("${release_env[@]}")
gradle_case "release: the production release APK plans" ok "" :app:assembleProductionRelease
gradle_case "release: the production release bundle plans" ok "" :app:bundleProductionRelease
gradle_case "release: the staging release APK is refused" fail "$ONLY" :app:assembleStagingRelease
gradle_case "release: the staging release bundle is refused" fail "$ONLY" :app:bundleStagingRelease
gradle_case "release: packaging the staging release variant is refused" fail "$ONLY" :app:packageStagingRelease
gradle_case "release: the flavor-less assembleRelease (every flavor) is refused" fail "$ONLY" :app:assembleRelease
gradle_case "release: the flavor-less bundleRelease (every flavor) is refused" fail "$ONLY" :app:bundleRelease
gradle_case "release: the all-variants assemble is refused" fail "$ONLY" :app:assemble
gradle_case "release: production and staging requested together is refused" fail "$ONLY" :app:assembleProductionRelease :app:assembleStagingRelease
gradle_case "release: the refusal names the cause and that nothing was signed" fail "Nothing was signed" :app:assembleStagingRelease
gradle_case "release: a staging DEBUG variant holds no release identity and is not affected" ok "" :app:assembleStagingDebug

# ---- release mode: the rest of the fail-closed rules (unchanged by the production-only rule) ----
CASE_ENV=(CADENA_SIGNING=relase)
gradle_case "a mistyped CADENA_SIGNING fails" fail "refusing to guess a signing mode" :app:assembleProductionRelease
CASE_ENV=(CADENA_SIGNING=release)
gradle_case "release without credentials fails and does not fall back to the debug key" fail "does not fall back to the debug key" :app:assembleProductionRelease
CASE_ENV=("${release_env[@]/CADENA_EXPECTED_CERT_SHA256=*/CADENA_EXPECTED_CERT_SHA256=$wrong_fp}")
gradle_case "release with a certificate that is not the expected one fails" fail "does not match the expected one" :app:assembleProductionRelease
CASE_ENV=("${release_env[@]/CADENA_KEYSTORE_PASSWORD=*/CADENA_KEYSTORE_PASSWORD=wrong-password}")
gradle_case "release with a wrong keystore password fails" fail "keystore cannot be opened" :app:assembleProductionRelease

# ---- no secret in any output --------------------------------------------------------------------
CASE_ENV=("${release_env[@]}")
gradle_case "release: (output check) the staging refusal" fail "$ONLY" :app:assembleStagingRelease
if grep -qF -- "$pw" "$tmp/case.log"; then bad "the output of a refused build contains a password"; else ok "the output of a refused build contains no password"; fi

echo
echo "test_android_gradle_signing: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
