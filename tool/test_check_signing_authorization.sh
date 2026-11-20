#!/usr/bin/env bash
# Tests of tool/check_signing_authorization.sh, the authorization tripwire of the hosted iOS signing workflow
# (docs/IOS_HOSTED_SIGNING.md, Issue #71). Credential-free and Linux/macOS portable; it reads files and runs nothing else.
#
#   tool/test_check_signing_authorization.sh
#
# The point that matters most is the first one: the record that is committed today does NOT authorize signing. A later
# record pull request that adds the G2S lines is the authorization; this test then still passes because it checks the
# committed record only for the absence of lines it does not carry itself, see "committed record" below.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$root/tool/check_signing_authorization.sh"
real_record="$root/docs/release-records/ios-1.0.4-1000035.md"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }

SHA=42d358a4e7bcbf85b92aa992ec6439214dbd4405
VER=1.0.4+1000035
BID=com.app.cadenabitcoin
TEAM=D65458CPDP
BLOBS="$(git hash-object "$root/tool/verify_ipa.py"),$(git hash-object "$root/tool/ipa_inspect.py")"
URL=https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-1234567890

run_gate() { # RECORD [overrides as extra args]
  local rec="$1"; shift
  bash "$gate" --record "$rec" --approved-sha "$SHA" --version "$VER" --bundle-id "$BID" --team-id "$TEAM" --tools-root "$root" "$@" 2>&1
}
expect_rc() { # NAME WANTED_RC RECORD [extra args]
  local name="$1" want="$2" rec="$3"; shift 3
  local out rc
  out="$(run_gate "$rec" "$@")"; rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$name"; else bad "$name" "exit $rc, wanted $want: $(printf '%s' "$out" | tail -n 3 | tr '\n' '|')"; fi
}

# A record that carries every line (made from the real record, never written back to the repository).
markers() {
  printf '%s\n' "G2S-STATUS: AUTHORIZED" "G2S-OPERATION: sign-and-verify-only" "G2S-APPROVED-SHA: $SHA" "G2S-VERSION: $VER" \
    "G2S-BUNDLE-ID: $BID" "G2S-TEAM-ID: $TEAM" "G2S-VERIFIER-BLOBS: $BLOBS" "G2S-AUTHORIZATION: $URL"
}
good="$tmp/good.md"
{ cat "$real_record"; echo; markers; } > "$good"
# the real record must not already carry any G2S line for the "adds the lines" fixtures to mean anything
if grep -q '^G2S-' "$real_record"; then G2S_PRESENT=1; else G2S_PRESENT=0; fi

# --- the committed record (what the workflow reads when nothing else has been merged) ---
if [ "$G2S_PRESENT" -eq 0 ]; then
  expect_rc "committed record: the record of this commit carries no G2S line, so signing is NOT authorized (exit 1)" 1 "$real_record"
  out="$(run_gate "$real_record")"
  printf '%s' "$out" | grep -q 'G2S-STATUS must appear exactly once' && ok "committed record: the refusal names the missing G2S-STATUS line" || bad "committed record: the refusal names the missing G2S-STATUS line" "$out"
else
  ok "committed record: G2S lines are present (a later authorization PR); the fixtures below are what is tested"
fi

# --- acceptance ---
expect_rc "a complete, matching record authorizes the sign-and-verify operation (exit 0)" 0 "$good"
{ sed 's/`G1 AUTHORIZED`/`G2 AUTHORIZED`/' "$real_record"; echo; markers; } > "$tmp/g2.md"
expect_rc "status G2 AUTHORIZED is also accepted for the signing stage" 0 "$tmp/g2.md"

# --- every single deviation is a refusal ---
mut() { # NAME SED-EXPRESSION   (applied to the good record)
  sed "$2" "$good" > "$tmp/m.md"; expect_rc "$1" 1 "$tmp/m.md"
}
mut "status NOT AUTHORIZED is refused" 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: NOT AUTHORIZED/'
mut "status in lower case is refused" 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: authorized/'
mut "status with a trailing space is refused" 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: AUTHORIZED /'
mut "status PENDING is refused" 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: PENDING/'
mut "an operation that includes upload is refused" 's/^G2S-OPERATION: sign-and-verify-only$/G2S-OPERATION: sign-and-upload/'
mut "a different approved SHA is refused" "s/^G2S-APPROVED-SHA: .*/G2S-APPROVED-SHA: 0000000000000000000000000000000000000001/"
mut "a different version is refused" 's/^G2S-VERSION: .*/G2S-VERSION: 1.0.5+1000036/'
mut "a different bundle ID is refused" 's/^G2S-BUNDLE-ID: .*/G2S-BUNDLE-ID: com.app.cadenabitcoin.staging/'
mut "a different team is refused" 's/^G2S-TEAM-ID: .*/G2S-TEAM-ID: ABCDE12345/'
mut "a verifier blob that is not the one the workflow runs is refused" 's/^G2S-VERIFIER-BLOBS: [0-9a-f]*/G2S-VERIFIER-BLOBS: 0000000000000000000000000000000000000000/'
mut "an authorization that is not an Issue #71 comment is refused" 's|^G2S-AUTHORIZATION: .*|G2S-AUTHORIZATION: https://example.com/approved|'
mut "an authorization on another issue is refused" 's|issues/71#|issues/72#|'
mut "a withdrawn record is refused even with the lines" 's/`G1 AUTHORIZED`/`WITHDRAWN`/'
mut "a draft record is refused even with the lines" 's/`G1 AUTHORIZED`/`DRAFT`/'
mut "a record whose APPROVED_SHA row names another commit is refused" "s/$SHA/1111111111111111111111111111111111111111/g"

for key in G2S-STATUS G2S-OPERATION G2S-APPROVED-SHA G2S-VERSION G2S-BUNDLE-ID G2S-TEAM-ID G2S-VERIFIER-BLOBS G2S-AUTHORIZATION; do
  grep -v "^$key: " "$good" > "$tmp/m.md"; expect_rc "a record without $key is refused" 1 "$tmp/m.md"
done
{ cat "$good"; echo "G2S-STATUS: AUTHORIZED"; } > "$tmp/m.md"; expect_rc "a duplicated G2S-STATUS line is refused (no first-match wins)" 1 "$tmp/m.md"
{ cat "$good"; echo "G2S-STATUS: NOT AUTHORIZED"; } > "$tmp/m.md"; expect_rc "a contradicting second G2S-STATUS line is refused" 1 "$tmp/m.md"
sed 's/$/\r/' "$good" > "$tmp/m.md"; expect_rc "CRLF line endings are refused (fail closed)" 1 "$tmp/m.md"
{ cat "$real_record"; echo; markers | sed 's/^/ /'; } > "$tmp/m.md"; expect_rc "indented marker lines (for example inside a quote or a list) are refused" 1 "$tmp/m.md"
{ cat "$real_record"; echo; markers | sed 's/^/> /'; } > "$tmp/m.md"; expect_rc "marker lines inside a block quote are refused" 1 "$tmp/m.md"
{ cat "$good"; echo '**Record Status: `WITHDRAWN`**'; } > "$tmp/m.md"; expect_rc "a second, contradicting Record Status line is refused" 1 "$tmp/m.md"

# --- the verifier the workflow would run is pinned: a changed verifier invalidates an old authorization ---
mkdir -p "$tmp/t1/tool"; cp "$root/tool/verify_ipa.py" "$root/tool/ipa_inspect.py" "$tmp/t1/tool/"
expect_rc "an unchanged verifier copy still matches the pinned blobs" 0 "$good" --tools-root "$tmp/t1"
printf '\n# changed\n' >> "$tmp/t1/tool/verify_ipa.py"
expect_rc "a changed verify_ipa.py no longer matches the authorized blobs (refused)" 1 "$good" --tools-root "$tmp/t1"
cp "$root/tool/verify_ipa.py" "$tmp/t1/tool/verify_ipa.py"; printf '\n# changed\n' >> "$tmp/t1/tool/ipa_inspect.py"
expect_rc "a changed ipa_inspect.py no longer matches the authorized blobs (refused)" 1 "$good" --tools-root "$tmp/t1"

# --- misuse is exit 2, never a silent pass ---
expect_rc "an unreadable record is a usage error (exit 2)" 2 "$tmp/does-not-exist.md"
expect_rc "a directory as the record is a usage error (exit 2)" 2 "$tmp"
expect_rc "a malformed SHA argument is a usage error (exit 2)" 2 "$good" --approved-sha XYZ
expect_rc "a malformed version argument is a usage error (exit 2)" 2 "$good" --version 1.0.4
expect_rc "a malformed team argument is a usage error (exit 2)" 2 "$good" --team-id d65458cpdp
expect_rc "a tools root without tool/ is a usage error (exit 2)" 2 "$good" --tools-root "$tmp"
out="$(bash "$gate" --bogus 2>&1)"; rc=$?; [ "$rc" -eq 2 ] && ok "an unknown argument is a usage error (exit 2)" || bad "an unknown argument is a usage error (exit 2)" "rc=$rc $out"

# --- the gate reads, it never writes ---
before="$(shasum -a 256 "$good" | awk '{print $1}')"; run_gate "$good" >/dev/null; after="$(shasum -a 256 "$good" | awk '{print $1}')"
[ "$before" = "$after" ] && ok "the gate does not modify the record" || bad "the gate does not modify the record"
if grep -vE '^[[:space:]]*#' "$gate" | grep -E '(^|[^[:alnum:]_])(curl|wget|gh)[[:space:]]|git (push|commit|fetch)|>>? *"?\$record' >/dev/null; then bad "the gate runs no network, git write or record write command"; else ok "the gate runs no network, git write or record write command"; fi
bash -n "$gate" && ok "the gate is syntactically valid" || bad "the gate is syntactically valid"

echo
echo "test_check_signing_authorization: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
