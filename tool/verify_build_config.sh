#!/usr/bin/env bash
# Build-configuration tooling. Requires `dart` and `python3` on PATH and a
# resolved package config (run `flutter pub get` first). Run from anywhere.
#
#   tool/verify_build_config.sh                  # = verify (everything below)
#   tool/verify_build_config.sh verify           # portability + analyzer + matrix + AOT
#   tool/verify_build_config.sh matrix           # valid / invalid configuration matrix (JIT)
#   tool/verify_build_config.sh aot              # release/AOT compile checks
#   tool/verify_build_config.sh analyzer         # analyzer is clean, one narrow suppression
#   tool/verify_build_config.sh portability      # static scan for bash > 3.2 constructs
#   tool/verify_build_config.sh resolve FILE     # print what the app resolves from FILE
#   tool/verify_build_config.sh defines FILE     # print the -D arguments for FILE
#   tool/verify_build_config.sh check-binary ENV FILE
#                                                # AOT binary contains ENV's backend URL
#                                                # and not the other environment's
#
# The rules live only in lib/config/build_config.dart (BuildConfig). The probe
# tool/build_config_probe.dart is compiled against it, so this script exercises
# the same constant assertions the app build enforces. Docs:
# docs/BUILD_CONFIGURATION.md.
#
# Portability: written for the bash 3.2 that macOS ships (CI runs it there as
# `/bin/bash tool/verify_build_config.sh`). No arrays (they are the main 3.2 /
# `set -u` hazard), no mapfile, no associative arrays, no case modification.
set -euo pipefail
cd "$(dirname "$0")/.."

PROBE=tool/build_config_probe.dart
BUILD_CONFIG_DART=lib/config/build_config.dart
STAGING_FILE=config/build/staging.json
PRODUCTION_FILE=config/build/production.json
STAGING_URL=https://staging.purabitcoin.com/app
PRODUCTION_URL=https://cadenabitcoin.com/app

failures=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; failures=$((failures + 1)); }

WORK_DIR=""
cleanup() { if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi; }
trap cleanup EXIT

# Print one -DKEY=VALUE per entry of a JSON config (bools as true/false, like
# `flutter build --dart-define-from-file`). Optional 2nd arg: python statements
# that mutate the dict `d` first (used to build invalid test configurations).
defines() {
  python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
if len(sys.argv) > 2:
    exec(sys.argv[2])
for k, v in d.items():
    if isinstance(v, bool):
        v = "true" if v else "false"
    print(f"-D{k}={v}")
' "$@"
}

# load_defines FILE [MUTATION]: put the -D arguments for FILE, one per line, in
# DEFINE_ARGS. FILE "" means "no configuration at all". A missing or unreadable
# FILE is an error of its own (never mistaken for "no configuration").
DEFINE_ARGS=""
load_defines() {
  local file=$1 mutation=${2-}
  DEFINE_ARGS=""
  if [ -n "$file" ]; then
    if [ ! -f "$file" ]; then
      echo "ERROR: build configuration file not found: $file" >&2
      exit 2
    fi
    DEFINE_ARGS=$(defines "$file" ${mutation:+"$mutation"}) || {
      echo "ERROR: could not read build configuration file: $file" >&2
      exit 2
    }
  fi
}

OUT=""
run_probe() { # FILE [MUTATION]; output in OUT, returns the dart exit code
  local file=$1 mutation=${2-} line rc=0
  load_defines "$file" "$mutation"
  set --
  while IFS= read -r line; do
    if [ -n "$line" ]; then set -- "$@" "$line"; fi
  done <<EOF
$DEFINE_ARGS
EOF
  OUT=$(dart run "$@" "$PROBE" 2>&1) || rc=$?
  return $rc
}

first_assertion() { # message of the first failed assertion in OUT, else its first line
  local m
  m=$(grep -m1 'assertion failed' <<<"$OUT" | sed 's/.*assertion failed with message: //' || true)
  if [ -n "$m" ]; then echo "$m"; else head -n1 <<<"$OUT"; fi
}

# expect_ok NAME FILE EXPECTED_LINE...
expect_ok() {
  local name=$1 file=$2 line
  shift 2
  if ! run_probe "$file" ""; then
    fail "$name (rejected: $(first_assertion))"
    return 0
  fi
  for line in "$@"; do
    if ! grep -qxF "$line" <<<"$OUT"; then
      fail "$name (missing expected resolved value: $line)"
      return 0
    fi
  done
  pass "$name"
}

# expect_rejected NAME FILE MUTATION MESSAGE_FRAGMENT
# The build configuration must be rejected BY BuildConfig, with a message that
# contains MESSAGE_FRAGMENT (so the right rule fired, not an unrelated error).
expect_rejected() {
  local name=$1 file=$2 mutation=$3 fragment=$4
  if run_probe "$file" "$mutation"; then
    fail "$name (ACCEPTED, must be rejected)"
    return 0
  fi
  if ! grep -q 'assertion failed' <<<"$OUT"; then
    fail "$name (failed, but not by a BuildConfig assertion: $(head -n1 <<<"$OUT"))"
    return 0
  fi
  if ! grep -qF -- "$fragment" <<<"$OUT"; then
    fail "$name (rejected by a different rule than expected '$fragment': $(first_assertion))"
    return 0
  fi
  pass "$name -> $(first_assertion)"
}

check_matrix() {
  local s=$STAGING_FILE p=$PRODUCTION_FILE

  echo "Valid configurations resolve to exactly the intended values:"
  expect_ok "staging.json" "$s" \
    "APP_ENV=staging" "NETWORK_ENVIRONMENT=signet" "USE_TESTNET=true" \
    "API_BASE_URL=$STAGING_URL"
  expect_ok "production.json" "$p" \
    "APP_ENV=production" "NETWORK_ENVIRONMENT=bitcoin" "USE_TESTNET=false" \
    "API_BASE_URL=$PRODUCTION_URL"

  echo "Missing configuration is rejected (there is no default environment):"
  expect_rejected "no configuration at all" "" "" "No build configuration was supplied"

  echo "Incomplete configuration is rejected:"
  expect_rejected "APP_ENV only (staging)" "$s" 'del d["NETWORK_ENVIRONMENT"], d["USE_TESTNET"], d["API_BASE_URL"]' 'Incomplete "staging"'
  expect_rejected "APP_ENV only (production)" "$p" 'del d["NETWORK_ENVIRONMENT"], d["USE_TESTNET"], d["API_BASE_URL"]' 'Incomplete "production"'
  expect_rejected "staging missing API_BASE_URL" "$s" 'del d["API_BASE_URL"]' 'Incomplete "staging"'
  expect_rejected "staging missing NETWORK_ENVIRONMENT" "$s" 'del d["NETWORK_ENVIRONMENT"]' 'Incomplete "staging"'
  expect_rejected "staging missing USE_TESTNET" "$s" 'del d["USE_TESTNET"]' 'Incomplete "staging"'
  expect_rejected "production missing API_BASE_URL" "$p" 'del d["API_BASE_URL"]' 'Incomplete "production"'
  expect_rejected "production missing NETWORK_ENVIRONMENT" "$p" 'del d["NETWORK_ENVIRONMENT"]' 'Incomplete "production"'
  expect_rejected "production missing USE_TESTNET" "$p" 'del d["USE_TESTNET"]' 'Incomplete "production"'
  expect_rejected "APP_ENV missing, rest present" "$s" 'del d["APP_ENV"]' 'Partial build configuration'
  expect_rejected "APP_ENV empty, rest present" "$s" 'd["APP_ENV"]=""' 'Partial build configuration'

  echo "Unknown environment or network value is rejected:"
  expect_rejected "unknown APP_ENV (typo)" "$s" 'd["APP_ENV"]="stagging"' 'APP_ENV must be'
  expect_rejected "APP_ENV wrong case" "$s" 'd["APP_ENV"]="Staging"' 'APP_ENV must be'
  expect_rejected "APP_ENV dev" "$p" 'd["APP_ENV"]="dev"' 'APP_ENV must be'
  expect_rejected "network not accepted by the native library (testnet)" "$s" 'd["NETWORK_ENVIRONMENT"]="testnet"' 'NETWORK_ENVIRONMENT must be'
  expect_rejected "network regtest" "$s" 'd["NETWORK_ENVIRONMENT"]="regtest"' 'NETWORK_ENVIRONMENT must be'
  expect_rejected "USE_TESTNET not a boolean" "$s" 'd["USE_TESTNET"]="yes"' 'USE_TESTNET must be true or false'

  echo "Contradictory configuration is rejected:"
  expect_rejected "staging with USE_TESTNET=false" "$s" 'd["USE_TESTNET"]=False' 'Contradictory network settings'
  expect_rejected "staging with NETWORK_ENVIRONMENT=bitcoin" "$s" 'd["NETWORK_ENVIRONMENT"]="bitcoin"' 'Contradictory network settings'
  expect_rejected "production with USE_TESTNET=true" "$p" 'd["USE_TESTNET"]=True' 'Contradictory network settings'

  echo "No fallback in either direction (backend / network / label mismatches):"
  expect_rejected "staging with the production API URL" "$s" 'd["API_BASE_URL"]="'"$PRODUCTION_URL"'"' 'A staging build must use API_BASE_URL'
  expect_rejected "staging with an unknown https URL" "$s" 'd["API_BASE_URL"]="https://example.invalid/app"' 'A staging build must use API_BASE_URL'
  expect_rejected "staging with a cleartext http URL" "$s" 'd["API_BASE_URL"]="http://staging.purabitcoin.com/app"' 'A staging build must use API_BASE_URL'
  expect_rejected "staging with a trailing-slash URL" "$s" 'd["API_BASE_URL"]="https://staging.purabitcoin.com/app/"' 'A staging build must use API_BASE_URL'
  expect_rejected "production with the staging API URL" "$p" 'd["API_BASE_URL"]="'"$STAGING_URL"'"' 'A production build must use API_BASE_URL'
  expect_rejected "production with an unknown https URL" "$p" 'd["API_BASE_URL"]="https://example.invalid/app"' 'A production build must use API_BASE_URL'
  expect_rejected "production with a cleartext http URL" "$p" 'd["API_BASE_URL"]="http://cadenabitcoin.com/app"' 'A production build must use API_BASE_URL'
  expect_rejected "production with signet" "$p" 'd["NETWORK_ENVIRONMENT"]="signet"; d["USE_TESTNET"]=True' 'A production build must use NETWORK_ENVIRONMENT'
  expect_rejected "staging values labelled production" "$s" 'd["APP_ENV"]="production"' 'A production build must use NETWORK_ENVIRONMENT'
  expect_rejected "production values labelled staging" "$p" 'd["APP_ENV"]="staging"' 'A staging build must use NETWORK_ENVIRONMENT'
}

# aot_compile NAME FILE [MUTATION]: dart compile exe with the given defines into
# $WORK_DIR/NAME. Returns the compiler exit code; OUT holds its output.
aot_compile() {
  local name=$1 file=$2 mutation=${3-} line rc=0
  load_defines "$file" "$mutation"
  set --
  while IFS= read -r line; do
    if [ -n "$line" ]; then set -- "$@" "$line"; fi
  done <<EOF
$DEFINE_ARGS
EOF
  rm -f "$WORK_DIR/$name"
  OUT=$(dart compile exe "$@" -o "$WORK_DIR/$name" "$PROBE" 2>&1) || rc=$?
  return $rc
}

# run_binary NAME EXPECTED_LINE: run $WORK_DIR/NAME and require EXPECTED_LINE in
# its output (captured first: `grep -q` in a pipeline can SIGPIPE under pipefail).
run_binary() {
  local printed
  printed=$("$WORK_DIR/$1" 2>&1) || return 1
  grep -qxF "$2" <<<"$printed"
}

# check_binary ENV FILE: the AOT binary must contain ENV's backend URL and must
# NOT contain the other environment's. Positive and negative; defense in depth
# only (see docs/BUILD_CONFIGURATION.md: not proof of complete isolation).
check_binary() {
  [ $# -eq 2 ] || { echo "usage: $0 check-binary staging|production FILE" >&2; return 2; }
  python3 -I - "$1" "$2" "$STAGING_URL" "$PRODUCTION_URL" <<'PYEOF'
import sys
env, path, staging, production = sys.argv[1:5]
if env not in ("staging", "production"):
    print("check-binary: ENV must be staging or production"); sys.exit(2)
want, other = (staging, production) if env == "staging" else (production, staging)
data = open(path, "rb").read()
n_want, n_other = data.count(want.encode()), data.count(other.encode())
ok = n_want >= 1 and n_other == 0
print(f"{path}: {len(data)} bytes")
print(f"  expected {env} URL {want}: {n_want} occurrence(s) -> {'ok' if n_want >= 1 else 'MISSING'}")
print(f"  other environment URL {other}: {n_other} occurrence(s) -> {'ok' if n_other == 0 else 'PRESENT'}")
sys.exit(0 if ok else 1)
PYEOF
}

check_aot() {
  WORK_DIR=${WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/cadena-build-config.XXXXXX")}

  echo "Release/AOT compilation (dart compile exe uses the same front end and AOT backend as a release app):"
  if aot_compile aot_staging "$STAGING_FILE" && run_binary aot_staging "API_BASE_URL=$STAGING_URL"; then
    pass "AOT: staging.json compiles and the binary resolves the staging backend"
  else
    fail "AOT: staging.json did not compile / resolve correctly: $(head -n2 <<<"$OUT" | tr '\n' ' ')"
  fi
  if aot_compile aot_production "$PRODUCTION_FILE" && run_binary aot_production "API_BASE_URL=$PRODUCTION_URL"; then
    pass "AOT: production.json compiles and the binary resolves the production backend"
  else
    fail "AOT: production.json did not compile / resolve correctly: $(head -n2 <<<"$OUT" | tr '\n' ' ')"
  fi

  if aot_compile aot_none ""; then
    fail "AOT: a build with NO configuration compiled (must be rejected)"
  elif [ -e "$WORK_DIR/aot_none" ]; then
    fail "AOT: a rejected build left a binary behind"
  elif grep -q 'No build configuration was supplied' <<<"$OUT"; then
    pass "AOT: no configuration -> rejected, no binary produced"
  else
    fail "AOT: no configuration failed for another reason: $(head -n1 <<<"$OUT")"
  fi
  if aot_compile aot_bad "$STAGING_FILE" 'd["API_BASE_URL"]="'"$PRODUCTION_URL"'"'; then
    fail "AOT: staging with the production URL compiled (must be rejected)"
  elif [ -e "$WORK_DIR/aot_bad" ]; then
    fail "AOT: a rejected build left a binary behind"
  elif grep -q 'A staging build must use API_BASE_URL' <<<"$OUT"; then
    pass "AOT: staging with the production URL -> rejected, no binary produced"
  else
    fail "AOT: contradictory configuration failed for another reason: $(head -n1 <<<"$OUT")"
  fi

  echo "Binary inspection (positive and negative; supporting evidence only):"
  if check_binary staging "$WORK_DIR/aot_staging" >/dev/null 2>&1; then
    pass "staging binary: has the staging URL, not the production URL"
  else
    fail "staging binary failed the URL check: $(check_binary staging "$WORK_DIR/aot_staging" 2>&1 | tr '\n' ' ')"
  fi
  if check_binary production "$WORK_DIR/aot_production" >/dev/null 2>&1; then
    pass "production binary: has the production URL, not the staging URL"
  else
    fail "production binary failed the URL check: $(check_binary production "$WORK_DIR/aot_production" 2>&1 | tr '\n' ' ')"
  fi
  if check_binary production "$WORK_DIR/aot_staging" >/dev/null 2>&1; then
    fail "the checker accepted a staging binary as production (negative check broken)"
  else
    pass "the checker rejects a staging binary presented as production"
  fi
  if check_binary staging "$WORK_DIR/aot_production" >/dev/null 2>&1; then
    fail "the checker accepted a production binary as staging (negative check broken)"
  else
    pass "the checker rejects a production binary presented as staging"
  fi
}

check_analyzer() {
  local out n_ignore ignore_lines
  echo "Analyzer (no build configuration is supplied to it):"
  out=$(dart analyze "$BUILD_CONFIG_DART" "$PROBE" 2>&1 || true)
  if grep -q 'No issues found' <<<"$out"; then
    pass "dart analyze: no issues in $BUILD_CONFIG_DART and $PROBE"
  else
    fail "dart analyze reports issues: $(tail -n 4 <<<"$out" | tr '\n' ' ')"
  fi
  ignore_lines=$(grep -nE '^[[:space:]]*//[[:space:]]*ignore' "$BUILD_CONFIG_DART" "$PROBE" || true)
  n_ignore=$(grep -c . <<<"$ignore_lines" || true)
  if [ -z "$ignore_lines" ]; then
    fail "the const_eval_throws_exception suppression is missing; flutter analyze would fail without a configuration"
  elif [ "$n_ignore" -eq 1 ] && grep -qE '// ignore: const_eval_throws_exception$' <<<"$ignore_lines"; then
    pass "exactly one analyzer suppression, narrowly scoped: const_eval_throws_exception"
  else
    fail "unexpected analyzer suppressions: $ignore_lines"
  fi
}

check_portability() {
  local hits
  echo "Portability scan (constructs unavailable in bash 3.2 / macOS):"
  # portability-pattern (this line is excluded from the scan)
  hits=$(grep -nE 'mapfile|readarray|declare -A|local -n|\$\{[A-Za-z_0-9]+(\^\^|,,)|\|&|&>>|coproc|;&|[A-Za-z_]+=\(' tool/verify_build_config.sh tool/verify_version.sh | grep -v 'portability-pattern' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
  if [ -z "$hits" ]; then
    pass "no bash 4+ construct and no array literal in tool/verify_build_config.sh and tool/verify_version.sh"
  else
    fail "constructs that are not portable to bash 3.2:"; echo "$hits" | sed 's/^/        /'
  fi
}

run_section() { # NAME FUNCTION: run FUNCTION, report only its own failures
  local before=$failures
  "$2"
  if [ "$failures" -eq "$before" ]; then echo "  -> $1: ok"; else echo "  -> $1: $((failures - before)) FAILED"; fi
}

verify_all() {
  run_section "portability" check_portability
  run_section "analyzer" check_analyzer
  run_section "configuration matrix" check_matrix
  run_section "release/AOT" check_aot
}

finish() {
  if [ "$failures" -ne 0 ]; then
    echo "$failures check(s) FAILED"
    exit 1
  fi
  echo "All build-configuration checks passed."
}

case "${1:-verify}" in
  verify)      verify_all; finish ;;
  matrix)      check_matrix; finish ;;
  aot)         check_aot; finish ;;
  analyzer)    check_analyzer; finish ;;
  portability) check_portability; finish ;;
  resolve)
    [ $# -eq 2 ] || { echo "usage: $0 resolve FILE" >&2; exit 2; }
    run_probe "$2" "" || { echo "$OUT" >&2; exit 1; }
    grep -E '^(APP_ENV|NETWORK_ENVIRONMENT|USE_TESTNET|API_BASE_URL)=' <<<"$OUT"
    ;;
  defines)
    [ $# -eq 2 ] || { echo "usage: $0 defines FILE" >&2; exit 2; }
    defines "$2"
    ;;
  check-binary)
    shift
    check_binary "$@"
    ;;
  *)
    echo "usage: $0 [verify | matrix | aot | analyzer | portability | resolve FILE | defines FILE | check-binary ENV FILE]" >&2
    exit 2
    ;;
esac
