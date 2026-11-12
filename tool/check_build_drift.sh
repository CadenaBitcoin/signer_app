#!/usr/bin/env bash
# Fails if a build modified any tracked file. Read-only; works with the system bash 3.2 of macOS.
#
#   tool/check_build_drift.sh [REPO_ROOT]
#
# A build must not rewrite a tracked file. The one that CocoaPods does rewrite when the committed
# ios/Podfile.lock no longer matches what `pod install` produces ("Podfile.lock drift") is an
# ERROR here, not a warning: the lock is part of the reproducibility contract, a changed lock
# means the dependency resolution or the toolchain is not the reviewed one, and nobody reads a
# warning on a green run. The remedy is a reviewed change of the committed file, never an
# exception in the workflow.
#
# Exit 0: no tracked file was modified. Exit 1: one was (listed; the lock's diff is printed).
# When GITHUB_ENV is set, PODFILE_LOCK_DRIFT=no|yes is appended to it for the evidence record.
set -euo pipefail
ROOT=$(cd "${1:-$(dirname "$0")/..}" && pwd)
cd "$ROOT"

LOCK=ios/Podfile.lock
changed=$(git status --porcelain --untracked-files=no)

record() { if [ -n "${GITHUB_ENV:-}" ]; then echo "PODFILE_LOCK_DRIFT=$1" >> "$GITHUB_ENV"; fi; }

if [ -z "$changed" ]; then
  echo "No tracked file was modified by the build."
  record no
  exit 0
fi

echo "The build modified tracked files:"
echo "$changed"
git diff --stat

# porcelain lines are "XY path"; compare the path exactly
lock_changed=no
other=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  if [ "${line:3}" = "$LOCK" ]; then lock_changed=yes; else other="$other$line
"; fi
done <<<"$changed"

if [ "$lock_changed" = yes ]; then
  record yes
  echo
  echo "--- git diff -- $LOCK"
  git diff -- "$LOCK"
  echo "::error title=ios/Podfile.lock drift::CocoaPods rewrote $LOCK during the build. The committed lock does not match what the pinned toolchain produces. Review the diff above; a reviewed change of the committed file is the remedy. Note: the checksums of the plugin pods also depend on the Ruby json gem of the machine that writes the lock, so take the file from the pinned runner image, not from a developer machine (docs/IOS_CI.md)."
fi
if [ -n "$other" ]; then
  echo "::error title=tracked files modified by the build::The build modified tracked files other than $LOCK:"
  printf '%s' "$other"
fi
exit 1
