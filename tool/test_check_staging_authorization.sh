#!/usr/bin/env bash
# Tests of the automatic iOS STAGING authorization gate: tool/check_staging_authorization.sh (docs/IOS_STAGING_DELIVERY.md).
#
#   tool/test_check_staging_authorization.sh
#
# Real git, no mocks: every case builds a throwaway bare "remote" with `development` and `staging`, a working clone, and a promotion merge,
# then runs the gate exactly as the workflow does (--remote). Nothing here contacts Apple or GitHub and nothing needs a credential.
# Exit 0 only if every check passes.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$root/tool/check_staging_authorization.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/staging-gate-test.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
pass=0; failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }
chk() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "${3:-}"; fi; }

TEAM="D65458CPDP"
BUNDLE="com.app.cadenabitcoin.staging"
VERSION="1.0.5+1000036"
SHA64a="$(printf 'a%.0s' $(seq 1 64))"
SHA64b="$(printf 'b%.0s' $(seq 1 64))"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

expected="$(bash "$gate" --print-expected --tools-root "$root")"
line_of() { printf '%s\n' "$expected" | grep "^$1: "; }

# A complete, valid record; the first argument is a space-separated list of KEY=VALUE overrides (KEY=- removes the line).
record() { # OVERRIDES... -> stdout
  local -A v=(
    [STATUS]=AUTHORIZED [OPERATION]=sign-verify-and-upload [VERSION]="$VERSION" [BUNDLE-ID]="$BUNDLE" [TEAM-ID]="$TEAM"
    [APP-APPLE-ID]=1234567890 [CERT-SHA256]="$SHA64a" [DLC-WALLET-SHA256]="$SHA64b"
    [AUTHORIZATION]="https://github.com/CadenaBitcoin/signer_app/issues/54#issuecomment-123456789"
    [DECISION-S1]="Decided by cto on 2026-11-26" [DECISION-S2]="Decided by cto on 2026-11-26"
    [DECISION-S3]="Decided by cto on 2026-11-26" [DECISION-S4]="Decided by cto on 2026-11-26"
  )
  local kv k
  for kv in "$@"; do k="${kv%%=*}"; v[$k]="${kv#*=}"; done
  echo "# Staging authorization (test)"
  echo
  for k in STATUS OPERATION VERSION BUNDLE-ID TEAM-ID APP-APPLE-ID CERT-SHA256 DLC-WALLET-SHA256 AUTHORIZATION DECISION-S1 DECISION-S2 DECISION-S3 DECISION-S4; do
    [ "${v[$k]}" = "-" ] || echo "G2S-STAGING-$k: ${v[$k]}"
  done
  line_of G2S-STAGING-WORKFLOW-BLOB; line_of G2S-STAGING-GATE-BLOB; line_of G2S-STAGING-TOOL-BLOBS
}

# One scenario: a remote with development and staging, and a promotion merge.
#   HEAD_REC  record that the promotion carries (default: a valid one)
#   DEV_REC   record on the CURRENT tip of development, committed after the merge (default: the same valid one)
#   SIDE      dev  (default): the merged side is part of development;  off: it is not
#   EVIL      1: the merge commit changes application content
#   FF        1: staging is fast-forwarded instead of merged
#   NEWER     1: another commit lands on staging after the merge
#   PUBVER    pubspec version of the promoted commit
#   NODEVREC  1: development has no record at all
scenario() { # DIR -> sets HEAD_SHA, REPO, REMOTE, RECFILE
  local d="$1" br
  rm -rf "$d"; mkdir -p "$d"
  REMOTE="$d/remote.git"; REPO="$d/w"
  git init -q --bare "$REMOTE"; git init -q "$REPO"
  ( cd "$REPO" || exit 1
    git checkout -q -b development
    git remote add origin "$REMOTE"
    mkdir -p lib config/build android ios flutter_plugin docs/release-records
    echo a > lib/a.dart; echo x > ios/x; echo x > android/x; echo x > flutter_plugin/x; echo '{}' > config/build/staging.json
    printf 'name: signer\nversion: 1.0.4+1000035\n' > pubspec.yaml; : > pubspec.lock
    git add -A; git commit -q -m base; git branch staging
    echo b > lib/b.dart; printf 'name: signer\nversion: %s\n' "${PUBVER:-$VERSION}" > pubspec.yaml
    printf '%s\n' "${HEAD_REC:-$(record)}" > docs/release-records/ios-staging-authorization.md
    git add -A; git commit -q -m feature
    if [ "${SIDE:-dev}" = off ]; then
      git checkout -q -b offside staging; echo c > lib/c.dart; git add -A; git commit -q -m offside; git checkout -q staging
      git merge -q --no-ff offside -m "Merge pull request #2 from CadenaBitcoin/offside"
    else
      git checkout -q staging
      if [ "${FF:-0}" = 1 ]; then git merge -q --ff-only development; else git merge -q --no-ff development -m "Merge pull request #1 from CadenaBitcoin/development"; fi
    fi
    if [ "${EVIL:-0}" = 1 ]; then echo evil >> lib/a.dart; git add -A; git commit -q --amend -m "Merge pull request #1 from CadenaBitcoin/development"; fi
    git rev-parse HEAD > "$d/head"
    [ "${NEWER:-0}" != 1 ] || { echo n > docs/n.md 2>/dev/null || { mkdir -p docs; echo n > docs/n.md; }; git add -A; git commit -q -m newer; }
    git checkout -q development
    if [ "${NODEVREC:-0}" = 1 ]; then git rm -q docs/release-records/ios-staging-authorization.md; git commit -q -m "no record"
    elif [ -n "${DEV_REC:-}" ]; then printf '%s\n' "$DEV_REC" > docs/release-records/ios-staging-authorization.md; git add -A; git commit -q -m "dev record"; fi
    if [ "${SIDE:-dev}" != off ]; then :; fi
    git push -q origin development staging
  ) >/dev/null 2>&1
  HEAD_SHA="$(cat "$d/head")"
  # The workflow's checkout of the commit being delivered: a full clone at that commit.
  rm -rf "$d/ck"; git clone -q "$REMOTE" "$d/ck" 2>/dev/null; git -C "$d/ck" checkout -q "$HEAD_SHA" 2>/dev/null
  git -C "$d/ck" show "$HEAD_SHA:docs/release-records/ios-staging-authorization.md" > "$d/record.md" 2>/dev/null
  REPO="$d/ck"; RECFILE="$d/record.md"
}

run_gate() { # [extra args...]; uses REPO REMOTE RECFILE HEAD_SHA
  bash "$gate" --record "$RECFILE" --head "$HEAD_SHA" --remote "$REMOTE" --bundle-id "$BUNDLE" --team-id "$TEAM" --tools-root "$root" --repo "$REPO" "$@"
}
authorized() { OUT="$(run_gate "$@" 2>&1)"; RC=$?; }
reset_env() { unset HEAD_REC DEV_REC SIDE EVIL FF NEWER PUBVER NODEVREC; }
expect_refused() { # DESCRIPTION [grep pattern of the reason]
  if [ "$RC" -eq 1 ] && { [ -z "${2:-}" ] || printf '%s\n' "$OUT" | grep -E -- "$2" >/dev/null; }; then ok "$1"; else bad "$1" "exit $RC; $(printf '%s\n' "$OUT" | grep -E 'NOT AUTHORIZED' | head -n 3 | tr '\n' ' ')"; fi
}

echo "== the happy path"
reset_env; scenario "$tmp/s1"; authorized
[ "$RC" -eq 0 ]; chk "a valid record on a reviewed merge from development, at the current tip, is AUTHORIZED" $? "$OUT"
printf '%s\n' "$OUT" | grep -F 'AUTHORIZED: automatic iOS staging delivery of 1.0.5+1000036' >/dev/null; chk "and says exactly what it authorizes" $?

echo "== the record"
for case in \
  "STATUS=WITHDRAWN|G2S-STAGING-STATUS is 'WITHDRAWN'" \
  "STATUS=authorized|G2S-STAGING-STATUS is 'authorized'" \
  "OPERATION=sign-and-verify-only|G2S-STAGING-OPERATION is" \
  "VERSION=1.0.5+1000037|G2S-STAGING-VERSION is '1.0.5\+1000037'" \
  "VERSION=1.0.4+1000035|G2S-STAGING-VERSION is" \
  "BUNDLE-ID=com.app.cadenabitcoin|G2S-STAGING-BUNDLE-ID is" \
  "TEAM-ID=ZZZZZZZZZZ|G2S-STAGING-TEAM-ID is" \
  "APP-APPLE-ID=6753348211|PRODUCTION application" \
  "APP-APPLE-ID=abc|numeric Apple ID" \
  "APP-APPLE-ID=-|G2S-STAGING-APP-APPLE-ID must appear exactly once" \
  "CERT-SHA256=1234|64 lower-case hex" \
  "CERT-SHA256=-|G2S-STAGING-CERT-SHA256 must appear exactly once" \
  "DLC-WALLET-SHA256=XYZ|64 lower-case hex" \
  "AUTHORIZATION=https://example.com/x|a comment on Issue #54 or #71" \
  "AUTHORIZATION=https://github.com/CadenaBitcoin/signer_app/issues/99#issuecomment-1|a comment on Issue #54 or #71" \
  "AUTHORIZATION=-|G2S-STAGING-AUTHORIZATION must appear exactly once" \
  "DECISION-S1=-|G2S-STAGING-DECISION-S1 must appear exactly once" \
  "DECISION-S2=Proposed|G2S-STAGING-DECISION-S2 must be" \
  "DECISION-S3=Decided by cto|G2S-STAGING-DECISION-S3 must be" \
  "DECISION-S4=Decided by cto on 26.11.2026|G2S-STAGING-DECISION-S4 must be" \
  ; do
  ov="${case%%|*}"; why="${case#*|}"
  reset_env; HEAD_REC="$(record "$ov")"; DEV_REC="$HEAD_REC"; scenario "$tmp/s2"; authorized
  expect_refused "refused: $ov" "$why"
done
reset_env; r="$(record)"; HEAD_REC="$(printf '%s\n' "$r" | sed 's/^G2S-STAGING-WORKFLOW-BLOB: .*/G2S-STAGING-WORKFLOW-BLOB: 0000000000000000000000000000000000000000/')"; DEV_REC="$HEAD_REC"; scenario "$tmp/s3"; authorized
expect_refused "refused: a stale workflow blob (the implementation changed after the authorization)" "G2S-STAGING-WORKFLOW-BLOB is"
reset_env; HEAD_REC="$(printf '%s\n' "$r" | sed 's/^G2S-STAGING-GATE-BLOB: .*/G2S-STAGING-GATE-BLOB: 0000000000000000000000000000000000000000/')"; DEV_REC="$HEAD_REC"; scenario "$tmp/s3"; authorized
expect_refused "refused: a stale gate blob" "G2S-STAGING-GATE-BLOB is"
reset_env; HEAD_REC="$(printf '%s\n' "$r" | sed 's/^G2S-STAGING-TOOL-BLOBS: .*/G2S-STAGING-TOOL-BLOBS: tool\/verify_ipa.py=0000000000000000000000000000000000000000/')"; DEV_REC="$HEAD_REC"; scenario "$tmp/s3"; authorized
expect_refused "refused: stale tool blobs" "G2S-STAGING-TOOL-BLOBS is"

echo "== what a reader of the record sees (the parser of the production gate)"
reset_env; HEAD_REC="$(printf '%s\n' "$r" | sed 's/^G2S-STAGING-STATUS: AUTHORIZED$/G2S-STAGING-STATUS: WITHDRAWN\n\n```\nG2S-STAGING-STATUS: AUTHORIZED\n```/')"; DEV_REC="$r"; scenario "$tmp/s4"; authorized
expect_refused "a line inside a fenced code block does not authorize" "G2S-STAGING-STATUS is 'WITHDRAWN'"
reset_env; HEAD_REC="$(printf '%s\n' "$r" | sed 's/^G2S-STAGING-STATUS: AUTHORIZED$/<!--\nG2S-STAGING-STATUS: AUTHORIZED\n-->\nG2S-STAGING-STATUS: WITHDRAWN/')"; DEV_REC="$r"; scenario "$tmp/s4"; authorized
expect_refused "a line inside an HTML comment does not authorize" "G2S-STAGING-STATUS is 'WITHDRAWN'"
reset_env; HEAD_REC="$(printf '%s\nG2S-STAGING-STATUS: AUTHORIZED\n' "$r")"; DEV_REC="$r"; scenario "$tmp/s4"; authorized
expect_refused "a repeated status line is refused" "G2S-STAGING-STATUS must appear exactly once"
reset_env; HEAD_REC="$(printf '%s\n' "$r" | sed 's/^G2S-STAGING-STATUS: AUTHORIZED$/ G2S-STAGING-STATUS: AUTHORIZED/')"; DEV_REC="$r"; scenario "$tmp/s4"; authorized
expect_refused "an indented line does not count" "G2S-STAGING-STATUS must appear exactly once"

echo "== the live record on development"
reset_env; DEV_REC="$(record STATUS=WITHDRAWN)"; scenario "$tmp/s5"; authorized
expect_refused "refused: the authorization was withdrawn on the current tip of development" "development says 'WITHDRAWN'"
reset_env; NODEVREC=1; scenario "$tmp/s5"; authorized
expect_refused "refused: development has no record" "development has no docs/release-records/ios-staging-authorization.md"
reset_env; DEV_REC="$(record VERSION=1.0.9+1000099)"; scenario "$tmp/s5"; authorized
[ "$RC" -eq 0 ]; chk "a LATER development record for a newer version does not block this earlier, still authorized promotion" $? "$OUT"

echo "== the source"
reset_env; NEWER=1; scenario "$tmp/s6"; authorized
expect_refused "refused: the commit is no longer the tip of staging (a re-run, or a newer promotion)" "not the current tip of staging"
reset_env; FF=1; scenario "$tmp/s6"; authorized
expect_refused "refused: a fast-forward is not a reviewed merge commit" "1 parent"
reset_env; SIDE=off; scenario "$tmp/s6"; authorized
expect_refused "refused: the merged side never was part of development" "not an ancestor of the current development"
reset_env; EVIL=1; scenario "$tmp/s6"; authorized
expect_refused "refused: the merge itself changed application content" "differs from the merged development side"
reset_env; PUBVER=1.0.6+1000040; scenario "$tmp/s6"; authorized
expect_refused "refused: the record names another version than pubspec.yaml carries" "G2S-STAGING-VERSION is '1.0.5\+1000036', expected '1.0.6\+1000040'"
reset_env; scenario "$tmp/s7"
rm -rf "$tmp/s7/remote.git"; authorized
expect_refused "refused (fail closed): the remote cannot be read" "could not be read from the remote"

echo "== the identity is a constant of the gate, not of the record or the caller"
reset_env; scenario "$tmp/s8"
OUT="$(bash "$gate" --record "$RECFILE" --head "$HEAD_SHA" --remote "$REMOTE" --bundle-id com.app.cadenabitcoin --team-id "$TEAM" --tools-root "$root" --repo "$REPO" 2>&1)"; RC=$?
expect_refused "refused: the workflow cannot hand the gate the production bundle ID" "only com.app.cadenabitcoin.staging"
reset_env; HEAD_REC="$(record BUNDLE-ID=com.app.cadenabitcoin APP-APPLE-ID=6753348211)"; DEV_REC="$HEAD_REC"; scenario "$tmp/s8"; authorized
expect_refused "refused: a record that names the production bundle and application cannot make a staging build go there" "PRODUCTION application"

echo "== usage and the helper modes"
reset_env; scenario "$tmp/s9"
bash "$gate" --record "$RECFILE" --head notasha --remote "$REMOTE" --bundle-id "$BUNDLE" --team-id "$TEAM" --tools-root "$root" --repo "$REPO" >/dev/null 2>&1; [ $? -eq 2 ]; chk "a malformed --head is a usage error (exit 2), not an authorization" $?
bash "$gate" --record "$RECFILE" --head "$HEAD_SHA" --bundle-id "$BUNDLE" --team-id "$TEAM" --tools-root "$root" --repo "$REPO" >/dev/null 2>&1; [ $? -eq 2 ]; chk "a missing --remote is a usage error" $?
bash "$gate" --bogus >/dev/null 2>&1; [ $? -eq 2 ]; chk "an unknown argument is a usage error" $?
[ "$(printf '%s\n' "$expected" | grep -c '^G2S-STAGING-\(WORKFLOW-BLOB\|GATE-BLOB\|TOOL-BLOBS\): ')" -eq 3 ]; chk "--print-expected prints the three blob lines" $?
v="$(bash "$gate" --print-field G2S-STAGING-VERSION --record "$RECFILE" --tools-root "$root")"; [ "$v" = "$VERSION" ]; chk "--print-field reads one effective line ($v)" $?
bash "$gate" --print-field G2S-VERSION --record "$RECFILE" --tools-root "$root" >/dev/null 2>&1; [ $? -eq 2 ]; chk "--print-field accepts only G2S-STAGING-... keys" $?

echo "== the committed record never authorizes by itself"
committed="$root/docs/release-records/ios-staging-authorization.md"
[ -f "$committed" ]; chk "the committed staging record exists" $?
st="$(bash "$gate" --print-field G2S-STAGING-STATUS --record "$committed" --tools-root "$root" 2>/dev/null)"
if [ "$st" = "AUTHORIZED" ]; then
  # An AUTHORIZED record must bind exactly the files of this checkout, or the first delivery would be refused (or, worse, unbound).
  for k in WORKFLOW-BLOB GATE-BLOB TOOL-BLOBS; do
    a="$(bash "$gate" --print-field "G2S-STAGING-$k" --record "$committed" --tools-root "$root" 2>/dev/null)"
    [ "$a" = "$(line_of "G2S-STAGING-$k" | sed "s/^G2S-STAGING-$k: //")" ]; chk "an AUTHORIZED committed record binds the current $k" $?
  done
else
  [ "$st" = "WITHDRAWN" ]; chk "the committed record is WITHDRAWN until the CTO's authorization is merged (status: ${st:-none})" $?
fi

echo
echo "check_staging_authorization: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
