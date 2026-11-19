#!/usr/bin/env bash
# Tests tool/scan_required_reason.sh (the required-reason scan of docs/IOS_RELEASE.md section 9, Issue #71)
# against BOTH layouts of `nm -u` output, without Xcode or macOS. It runs on the `plan` job of build-variants.yml
# and locally:
#
#   tool/test_required_reason_scan.sh
#   REAL_NM_DIR=<evidence>/preflight/nm-u tool/test_required_reason_scan.sh     # also every real file of a run
#
#   current layout     Xcode 26.3 llvm-nm, one bare name per line ("_stat"). The fixtures are the real output of
#                      run 44619876867 (tool/fixtures/nm-u-xcode26.3-llvm-nm, byte-for-byte, SHA-256 checked).
#   historical layout  Apple cctools nm ("                 U _stat"), the layout the first pattern was written for.
#                      No real capture of it is kept in this repository: it is DERIVED from the real files by adding
#                      the "U" column, which is the documented shape of that output, and it is not a recording.
#
# What it proves: the scan reads both layouts, returns the same symbols for the same input, finds the confirmed
# `_stat`, `_fstat` and `_lstat` of dlc_wallet.framework, matches exactly as the first pattern did on the historical
# layout (no regression), and keeps its anchoring (`_mystat`, `__stat`, `_stat64` are not matches). It also pins
# that the workflow and the documentation use the script and no longer carry the old inline pattern.
# What it does not prove: that a future Xcode keeps one of these layouts. The complete `nm -u` output is kept next
# to the matches (the workflow writes nm-u/ for every Mach-O file), so a new layout can be read by hand.
#
# (No `grep -q` at the end of a pipeline: under pipefail an early-closed pipe is a SIGPIPE failure.)
# Needs bash, awk, grep, sed, sort, cmp, sha256sum or shasum. Exit 0 only if every check passes.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scan="$root/tool/scan_required_reason.sh"
fx="$root/tool/fixtures/nm-u-xcode26.3-llvm-nm"
workflow="$root/.github/workflows/ios-release-diagnostics.yml"
doc="$root/docs/IOS_RELEASE.md"

pass=0
failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
check() { # check "<name>" <expected> <actual>   (text compared as is)
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $(printf '%s' "$2" | tr '\n' ' ') | got: $(printf '%s' "$3" | tr '\n' ' ')"; fi
}
sum() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The first pattern, verbatim (the one removed from the workflow and the documentation). It is the oracle of the
# historical layout and the demonstration of the defect on the current one.
OLD_RE=' _(stat|fstat|lstat|fstatat|statfs|fstatfs|statvfs|getattrlist|fgetattrlist|getattrlistbulk|mach_absolute_time|clock_gettime|clock_gettime_nsec_np|sysctlbyname|sysctl)$|NSUserDefaults|systemUptime|fileModificationDate|creationDate|NSURLVolume'
# An independent oracle for the bare layout (a different expression, not the awk of the scan).
BARE_RE='^_(stat|fstat|lstat|fstatat|statfs|fstatfs|statvfs|getattrlist|fgetattrlist|getattrlistbulk|mach_absolute_time|clock_gettime|clock_gettime_nsec_np|sysctlbyname|sysctl)$|NSUserDefaults|systemUptime|fileModificationDate|creationDate|NSURLVolume'

historical() { sed 's/^/                 U /' "$1"; }    # cctools column: 17 spaces, "U", one space

[ -x "$scan" ] || { echo "FAIL $scan is missing or not executable"; exit 1; }

# --- 1. the fixtures are the recorded evidence, byte for byte -----------------------------------------
declare -A want=(
  [dlc_wallet.framework__dlc_wallet]=a405e33da6cec828e7f02a5ec566da4bb0db80126a785319bda1f91bf9e22643
  [flutter_local_notifications.framework__flutter_local_notifications]=f5b8c316b9b07948309cb81b346be3b9e5c138d37e3edc018f9cdc8d1fb5efa7
  [flutter_secure_storage.framework__flutter_secure_storage]=e0b35571e06e7ca0da5ee78f3a36a21a58855b443b5c3cf24016d6c0c0c440a2
  [path_provider_foundation.framework__path_provider_foundation]=3b69fc52a259e1ac6602a94908aa60d2ae8037add28ffd9b3baec063521bc009
  [shared_preferences_foundation.framework__shared_preferences_foundation]=bd89e0e932e395068e3ec3f2c76ec74a61d179d904cad0c0fda2083ec079db51
)
for n in "${!want[@]}"; do
  [ -f "$fx/$n.txt" ] && [ "$(sum "$fx/$n.txt")" = "${want[$n]}" ] && ok "fixture $n is the recorded run 44619876867 output" || bad "fixture $n differs from the recorded evidence (or is missing)"
done

# --- 2. the confirmed imports of dlc_wallet.framework --------------------------------------------------
dw="$fx/dlc_wallet.framework__dlc_wallet.txt"
got="$("$scan" "$dw")"
check "current layout: dlc_wallet matches are exactly the five confirmed symbols" "$(printf '_clock_gettime\n_fstat\n_lstat\n_stat\n_sysctlbyname')" "$got"
for s in _stat _fstat _lstat; do
  case $'\n'"$got"$'\n' in *$'\n'"$s"$'\n'*) ok "current layout: $s is detected in dlc_wallet.framework" ;; *) bad "current layout: $s is NOT detected in dlc_wallet.framework" ;; esac
done
# The defect, reproduced: the first pattern finds none of them on the same file.
old_got="$(grep -E "$OLD_RE" "$dw" || true)"
check "defect reproduced: the first pattern finds nothing in the Xcode 26.3 dlc_wallet output" "" "$old_got"

# --- 3. the historical layout --------------------------------------------------------------------------
historical "$dw" > "$tmp/dw.hist"
got_h="$("$scan" "$tmp/dw.hist")"
check "historical layout: the same five symbols, lines returned unchanged (with the U column)" "$(printf '                 U _clock_gettime\n                 U _fstat\n                 U _lstat\n                 U _stat\n                 U _sysctlbyname')" "$got_h"
check "historical layout: identical to what the first pattern returned (no regression)" "$(grep -E "$OLD_RE" "$tmp/dw.hist")" "$got_h"
check "both layouts name the same symbols" "$got" "$(printf '%s\n' "$got_h" | sed 's/^ *U //')"

# --- 4. every fixture, both layouts, against the independent oracles ------------------------------------
for f in "$fx"/*.txt; do
  b="$(basename "$f" .txt)"
  check "current layout, independent oracle: $b" "$(grep -E "$BARE_RE" "$f" || true)" "$("$scan" "$f")"
  historical "$f" > "$tmp/h.txt"
  check "historical layout, first pattern as oracle: $b" "$(grep -E "$OLD_RE" "$tmp/h.txt" || true)" "$("$scan" "$tmp/h.txt")"
done
# The other frameworks keep their results (NSUserDefaults is a class symbol, matched in either layout).
check "flutter_local_notifications: NSUserDefaults still found" "_OBJC_CLASS_\$_NSUserDefaults" "$("$scan" "$fx/flutter_local_notifications.framework__flutter_local_notifications.txt")"
check "flutter_secure_storage: no match (unchanged)" "" "$("$scan" "$fx/flutter_secure_storage.framework__flutter_secure_storage.txt")"
check "path_provider_foundation: no match (unchanged)" "" "$("$scan" "$fx/path_provider_foundation.framework__path_provider_foundation.txt")"

# --- 5. other layouts and edge cases ---------------------------------------------------------------------
printf 'U _stat\nU _mystat\n' > "$tmp/bsd.txt"
check "BSD/GNU style 'U _stat'" "U _stat" "$("$scan" "$tmp/bsd.txt")"
printf '/x/App.o: U _lstat\n/x/App.o: U _status\n' > "$tmp/a.txt"
check "nm -A style with a file prefix" "/x/App.o: U _lstat" "$("$scan" "$tmp/a.txt")"
printf '/b/App.framework/App (for architecture arm64):\n_fstat\n/b/App.framework/App (for architecture x86_64):\n                 U _fstat\n' > "$tmp/fat.txt"
check "universal file: header lines never match, symbols of every slice do" "$(printf '_fstat\n                 U _fstat')" "$("$scan" "$tmp/fat.txt")"
printf '_stat\r\n_fstat \n\t_lstat\n' > "$tmp/ws.txt"
"$scan" "$tmp/ws.txt" > "$tmp/ws.out"
cmp -s "$tmp/ws.txt" "$tmp/ws.out" && ok "CRLF, trailing blank and tab layouts are read, lines returned byte for byte" || bad "CRLF, trailing blank and tab layouts" "got: $(od -c "$tmp/ws.out" | head -3 | tr '\n' ' ')"
printf '_mystat\n__stat\n_stat64\n_stat_helper\n_restat\n_statx\n_fstatat64\n_sysctlnametomib\n_mach_absolute_time_extra\nstat\n' > "$tmp/neg.txt"
check "anchoring: near misses are not matches" "" "$("$scan" "$tmp/neg.txt")"
printf '_fstatat\n_statfs\n_fstatfs\n_statvfs\n_getattrlist\n_fgetattrlist\n_getattrlistbulk\n_mach_absolute_time\n_clock_gettime\n_clock_gettime_nsec_np\n_sysctlbyname\n_sysctl\n' > "$tmp/all.txt"
check "all fifteen C names of the list match as bare names" "$(printf '_stat\n_fstat\n_lstat\n'; cat "$tmp/all.txt")" "$("$scan" <(printf '_stat\n_fstat\n_lstat\n'; cat "$tmp/all.txt"))"
printf '_OBJC_CLASS_$_NSUserDefaults\n_$s10Foundation17URLResourceValuesV12creationDateAA0E0VSgvg\n_OBJC_CLASS_$_NSURLVolumeTotalCapacityKey\n_$sSo6NSDateC10systemUptime\n_fileModificationDate\n' > "$tmp/sub.txt"
check "Objective-C and Swift name patterns match as before (bare)" "$(cat "$tmp/sub.txt")" "$("$scan" "$tmp/sub.txt")"
check "...and in the historical layout" "$(historical "$tmp/sub.txt")" "$("$scan" <(historical "$tmp/sub.txt"))"
check "stdin is read when no file is given" "_stat" "$(printf '_stat\n_other\n' | "$scan")"
check "empty input: no match, exit 0" "" "$("$scan" /dev/null)"
"$scan" /dev/null; check "empty input exits 0" 0 "$?"
printf '_other\n' > "$tmp/none.txt"; "$scan" "$tmp/none.txt" >/dev/null; check "no match exits 0 (evidence, not a verdict)" 0 "$?"
"$scan" "$tmp/does-not-exist" >/dev/null 2>&1; check "unreadable file exits 2" 2 "$?"
# The scan returns the input lines and does not alter them (the evidence stays the evidence).
cp "$dw" "$tmp/dw.before"; "$scan" "$dw" >/dev/null; cmp -s "$dw" "$tmp/dw.before" && ok "the input file is not modified" || bad "the input file was modified"

# --- 6. the workflow and the documentation use the script, not the old inline pattern --------------------
for pair in "workflow:$workflow" "documentation:$doc"; do
  label="${pair%%:*}"; file="${pair#*:}"
  if grep -Fq 'scan_required_reason.sh' "$file"; then ok "$label uses tool/scan_required_reason.sh"; else bad "$label does not use tool/scan_required_reason.sh"; fi
  if grep -Fq ' _(stat|fstat|lstat' "$file"; then bad "$label still contains the first inline pattern"; else ok "$label has no inline copy of the first pattern"; fi
done
if grep -Fq 'REASON_RE' "$workflow"; then bad "workflow still defines REASON_RE"; else ok "workflow has no REASON_RE"; fi
# The scan must keep the complete output: the workflow writes nm -u to nm-u/ BEFORE it scans.
if grep -nE 'nm -u "\$f" > "\$out/nm-u/\$flat.txt"' "$workflow" >/dev/null; then ok "workflow still keeps the complete nm -u output of every Mach-O file"; else bad "workflow no longer keeps the complete nm -u output"; fi

# --- 7. optional: every real file of a diagnostics run ---------------------------------------------------
if [ -n "${REAL_NM_DIR:-}" ]; then
  n=0
  for f in "$REAL_NM_DIR"/*.txt; do
    n=$((n + 1))
    check "REAL_NM_DIR bare, independent oracle: $(basename "$f")" "$(grep -E "$BARE_RE" "$f" || true)" "$("$scan" "$f")"
    historical "$f" > "$tmp/r.txt"
    check "REAL_NM_DIR historical, first pattern: $(basename "$f")" "$(grep -E "$OLD_RE" "$tmp/r.txt" || true)" "$("$scan" "$tmp/r.txt")"
  done
  [ "$n" -gt 0 ] && ok "REAL_NM_DIR: $n real files checked" || bad "REAL_NM_DIR holds no *.txt file"
fi

echo
echo "passed: $pass  failed: $failed"
[ "$failed" -eq 0 ]
