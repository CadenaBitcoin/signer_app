#!/usr/bin/env bash
# Required-reason API scan of `nm -u` output (docs/IOS_RELEASE.md section 9, Issue #71).
#
#   tool/scan_required_reason.sh nm-u-output.txt [more files ...]
#   nm -u "$MACHO_FILE" | tool/scan_required_reason.sh
#
# Prints, UNCHANGED, every line of the given `nm -u` output that names a symbol of the scan list. It never
# alters, reorders or drops the input and it is evidence only: finding nothing is exit 0, and no compliance
# statement follows from either result. Keep the complete `nm -u` output next to the matches; the list is
# only a pattern, and a covered API that is not in it is not found.
#
# The symbol name is the LAST whitespace-separated field of a line, so the scan reads each of the layouts that
# `nm -u` has produced instead of assuming one:
#   llvm-nm (Xcode 26.3 on the macos-15 runner, run 44619876867)  "_stat"
#   Apple cctools nm (the layout the first pattern was written for)  "                 U _stat"
#   BSD / GNU style and `nm -A`                                       "U _stat", "file.o: U _stat"
# The first pattern ` _(stat|...)$` needed a space before the name. llvm-nm prints none, so it matched
# nothing of the C symbols (the covered `_stat`, `_fstat` and `_lstat` of dlc_wallet.framework were missed).
# Lines such as "path (for architecture arm64):" (universal files) end in no symbol name and match nothing.
#
# C symbols (the 15 names below) must equal the whole name, so `_mystat`, `__stat` and `_stat64` do not match.
# Objective-C and Swift symbols are mangled around their names, so those five patterns match anywhere in the line.
# The list is the one of docs/IOS_RELEASE.md before this correction; widening it is a separate decision.
#
# Exit codes: 0 scan done (matches or not), 2 a named file cannot be read.
set -uo pipefail

for f in "$@"; do
  [ -r "$f" ] && [ ! -d "$f" ] || { echo "scan_required_reason.sh: cannot read '$f'" >&2; exit 2; }
done

awk '
BEGIN {
  n = split("stat fstat lstat fstatat statfs fstatfs statvfs getattrlist fgetattrlist getattrlistbulk mach_absolute_time clock_gettime clock_gettime_nsec_np sysctlbyname sysctl", names, " ")
  for (i = 1; i <= n; i++) covered["_" names[i]] = 1
}
{
  text = $0
  sub(/[ \t\r]+$/, "", text)          # trailing blanks and a CR never hide the name; the printed line is the original
  if (text ~ /NSUserDefaults|systemUptime|fileModificationDate|creationDate|NSURLVolume/) { print; next }
  m = split(text, field, /[ \t]+/)
  if (m > 0 && (field[m] in covered)) print
}
' "$@"
