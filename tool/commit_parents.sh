#!/usr/bin/env bash
# Prints the number of parents of a commit (default HEAD): 0 for an initial commit, 1 for an
# ordinary commit, 2 for a merge commit, more for an octopus merge.
#
#   tool/commit_parents.sh [REV]
#
# It reads the `parent` lines from the header of the commit OBJECT. `git rev-list --parents`
# and `git log --parents` cannot be used: the default GitHub Actions checkout is shallow
# (depth 1), and in a shallow clone those commands graft the boundary commit and report no
# parents for a genuine merge commit. Only the header is read (up to the first empty line),
# so a message line that happens to start with "parent " is not counted.
# Fails (non-zero, prints nothing) if REV is not a commit.
set -euo pipefail

rev="${1:-HEAD}"
object="$(git cat-file commit "$rev")"
printf '%s\n' "$object" | awk '/^$/ { h = 1 } !h && /^parent / { n++ } END { print n + 0 }'
