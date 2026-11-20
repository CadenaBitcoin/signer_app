#!/usr/bin/env bash
# Tests of tool/check_signing_authorization.sh, the authorization tripwire of the hosted iOS signing workflow
# (docs/IOS_HOSTED_SIGNING.md, Issue #71). Credential-free and Linux/macOS portable; it reads files and runs nothing else.
#
#   tool/test_check_signing_authorization.sh
#
# The point that matters most is the first one: the record that is committed today does NOT authorize signing. A later
# record pull request that adds the G2S lines and decides the rows is the authorization; this test then still passes because
# it builds its own fixtures from the committed record and never writes them back.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$root/tool/check_signing_authorization.sh"
committed_record="$root/docs/release-records/ios-1.0.4-1000035.md"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# The record as it was BEFORE any G2S authorization: no G2S line, no D14 row, the nine G2S rows back to "Proposed". The tests build their
# fixtures from this, so they hold whether or not the committed record already carries the authorization (and stay valid after it is withdrawn).
neutral_record() { # IN OUT
  awk '/^G2S-/ { next } /^\| D14 \| / { next } { print }' "$1" | awk '
    BEGIN { n = split("D3 D6 D7 D8 D9 D10 D11 D12", a, " "); for (i = 1; i <= n; i++) want[i] = "| " a[i] " | " }
    { for (i = 1; i <= n; i++) if (index($0, want[i]) == 1) sub(/\| Decided \| [^|]*\| [0-9-]+ \|[ ]*$/, "| Proposed, not decided | TBD | TBD |"); print }' > "$2"
}
real_record="$tmp/neutral-record.md"; neutral_record "$committed_record" "$real_record"
pass=0; failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }

SHA=42d358a4e7bcbf85b92aa992ec6439214dbd4405
VER=1.0.4+1000035
BID=com.app.cadenabitcoin
TEAM=D65458CPDP
WFSHA=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
URL=https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-1234567890
DLC=9a2d1d98ee4cf7aa608a161cff3d57aa380fec227876ab9c4b2b93f3f381fc13   # the archive hash of both diagnostics runs (the proposed initial value)
DECISIONS="D3 D6 D7 D8 D9 D10 D11 D12"

# A tools root that holds exactly the files the gate binds (copied, so that a test can change one without touching the repository).
mktools() { # DIR
  rm -rf "$1"; mkdir -p "$1/tool" "$1/.github/workflows"
  cp "$root"/tool/{check_signing_authorization.sh,build_manifest.py,ipa_inspect.py,validate_handover_archive.py,verify_artifact.sh,verify_ipa.py} "$1/tool/"
  cp "$root/.github/workflows/ios-hosted-signing.yml" "$1/.github/workflows/"
}
tools="$tmp/tools"; mktools "$tools"
tgate="$tools/tool/check_signing_authorization.sh"
expected_lines() { bash "$tgate" --print-expected --tools-root "${1:-$tools}"; }

run_gate() { # RECORD [overrides as extra args]
  local rec="$1"; shift
  bash "$tgate" --record "$rec" --approved-sha "$SHA" --version "$VER" --bundle-id "$BID" --team-id "$TEAM" --tools-root "$tools" \
    --workflow-sha "$WFSHA" --development-tip "$WFSHA" "$@" 2>&1
}
expect_rc() { # NAME WANTED_RC RECORD [extra args]
  local name="$1" want="$2" rec="$3"; shift 3
  local out rc
  out="$(run_gate "$rec" "$@")"; rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$name"; else bad "$name" "exit $rc, wanted $want: $(printf '%s' "$out" | tail -n 3 | tr '\n' '|')"; fi
}

# A record that carries every line and decides the rows (made from the real record, never written back to the repository).
decide() { # RECORD ROW... : rows become Decided
  local rec="$1" id; shift
  for id in "$@"; do
    awk -v id="$id" 'index($0, "| " id " | ") == 1 { sub(/\| [^|]*\| TBD \| TBD \|[ ]*$/, "| Decided | CTO | 2026-11-21 |") } { print }' "$rec" > "$rec.n" && mv "$rec.n" "$rec"
  done
}
markers() {
  printf '%s\n' "G2S-STATUS: AUTHORIZED" "G2S-OPERATION: sign-and-verify-only" "G2S-APPROVED-SHA: $SHA" "G2S-VERSION: $VER" "G2S-BUNDLE-ID: $BID" "G2S-TEAM-ID: $TEAM"
  expected_lines
  printf '%s\n' "G2S-DLC-WALLET-SHA256: $DLC" "G2S-AUTHORIZATION: $URL"
}
d14() { awk '{ print } index($0, "| D13 | ") == 1 { print "| D14 | **Credential decision (test fixture)** | Decided | CTO | 2026-11-21 |" }' "$1" > "$1.n" && mv "$1.n" "$1"; }
good="$tmp/good.md"
cp "$real_record" "$good"; decide "$good" $DECISIONS; d14 "$good"; { echo; markers; } >> "$good"
# --- the actual release record of this checkout: REAL assertions on the gate's exit code, whatever state the record is in ---
committed_status="$(grep -E '^G2S-STATUS: ' "$committed_record" || true)"
case "$committed_status" in
  'G2S-STATUS: AUTHORIZED')
    expect_rc "the committed record carries a complete G2S authorization: the gate ACCEPTS it with this checkout's workflow, gate and tools (exit 0)" 0 "$committed_record"
    sed 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: WITHDRAWN/' "$committed_record" > "$tmp/committed-withdrawn.md"
    expect_rc "the committed record with G2S-STATUS: WITHDRAWN fails closed (exit 1)" 1 "$tmp/committed-withdrawn.md" ;;
  'G2S-STATUS: WITHDRAWN')
    expect_rc "the committed record's G2S authorization is withdrawn: the gate fails closed (exit 1)" 1 "$committed_record" ;;
  '')
    expect_rc "the committed record carries no G2S authorization: the gate fails closed (exit 1)" 1 "$committed_record" ;;
  *)
    bad "the committed record has an unrecognized G2S status line: $committed_status" ;;
esac
expect_rc "a record without any G2S authorization (the committed record before it, neutral copy) fails closed: G1 alone does NOT authorize signing (exit 1)" 1 "$real_record"
out="$(run_gate "$real_record")"
printf '%s' "$out" | grep -q 'G2S-STATUS must appear exactly once' && ok "that refusal names the missing G2S-STATUS line" || bad "that refusal names the missing G2S-STATUS line" "$out"
printf '%s' "$out" | grep -q 'decision D7 is not decided' && ok "that refusal names the undecided release rows" || bad "that refusal names the undecided release rows" "$out"
cp "$real_record" "$tmp/lines_only.md"; { echo; markers; } >> "$tmp/lines_only.md"
expect_rc "G2S lines WITHOUT the decided rows are refused (G1 plus lines is not enough)" 1 "$tmp/lines_only.md"
cp "$real_record" "$tmp/rows_only.md"; decide "$tmp/rows_only.md" $DECISIONS; d14 "$tmp/rows_only.md"
expect_rc "decided rows WITHOUT the G2S lines are refused" 1 "$tmp/rows_only.md"

# --- acceptance ---
expect_rc "a complete, matching, current, decided record authorizes the sign-and-verify operation (exit 0)" 0 "$good"
sed 's/`G1 AUTHORIZED`/`G2 AUTHORIZED`/' "$good" > "$tmp/g2.md"
expect_rc "status G2 AUTHORIZED is also accepted for the signing stage" 0 "$tmp/g2.md"
out="$(run_gate "$good")"; printf '%s' "$out" | grep -q 'no upload' && ok "the verdict states that nothing is uploaded" || bad "the verdict states that nothing is uploaded"

# --- every single deviation is a refusal ---
mut() { # NAME SED-EXPRESSION   (applied to the good record)
  sed -E "$2" "$good" > "$tmp/m.md"; expect_rc "$1" 1 "$tmp/m.md"
}
mut "status NOT AUTHORIZED is refused" 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: NOT AUTHORIZED/'
mut "status in lower case is refused" 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: authorized/'
mut "status with a trailing space is refused" 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: AUTHORIZED /'
mut "status PENDING is refused" 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: PENDING/'
mut "status WITHDRAWN is refused (fails closed)" 's/^G2S-STATUS: AUTHORIZED$/G2S-STATUS: WITHDRAWN/'
mut "an operation that includes upload is refused" 's/^G2S-OPERATION: sign-and-verify-only$/G2S-OPERATION: sign-and-upload/'
mut "a different approved SHA is refused" "s/^G2S-APPROVED-SHA: .*/G2S-APPROVED-SHA: 0000000000000000000000000000000000000001/"
mut "a different version is refused" 's/^G2S-VERSION: .*/G2S-VERSION: 1.0.5+1000036/'
mut "a different bundle ID is refused" 's/^G2S-BUNDLE-ID: .*/G2S-BUNDLE-ID: com.app.cadenabitcoin.staging/'
mut "a different team is refused" 's/^G2S-TEAM-ID: .*/G2S-TEAM-ID: ABCDE12345/'
mut "a workflow blob that is not this workflow is refused" 's/^G2S-WORKFLOW-BLOB: [0-9a-f]+/G2S-WORKFLOW-BLOB: 0000000000000000000000000000000000000000/'
mut "a gate blob that is not this gate is refused" 's/^G2S-GATE-BLOB: [0-9a-f]+/G2S-GATE-BLOB: 0000000000000000000000000000000000000000/'
mut "a tool blob that is not the one the workflow runs is refused" 's/(tool\/verify_ipa\.py=)[0-9a-f]+/\10000000000000000000000000000000000000000/'
mut "a tool list with a tool missing is refused" 's/(G2S-TOOL-BLOBS: )tool\/build_manifest\.py=[0-9a-f]+,/\1/'
mut "a dlc_wallet hash in upper case is refused" 's/^(G2S-DLC-WALLET-SHA256: ).*/\1'"${DLC^^}"'/'
mut "a dlc_wallet hash that is too short is refused" 's/^(G2S-DLC-WALLET-SHA256: ).*/\1abc123/'
mut "a dlc_wallet hash with trailing text is refused" 's/^(G2S-DLC-WALLET-SHA256: .*)$/\1 extra/'
mut "an empty dlc_wallet hash is refused" 's/^(G2S-DLC-WALLET-SHA256: ).*/\1/'
{ cat "$good"; echo "G2S-DLC-WALLET-SHA256: $DLC"; } > "$tmp/m.md"; expect_rc "a duplicated dlc_wallet hash line is refused" 1 "$tmp/m.md"
{ cat "$good"; echo "G2S-DLC-WALLET-SHA256: 0000000000000000000000000000000000000000000000000000000000000000"; } > "$tmp/m.md"; expect_rc "a second, different dlc_wallet hash line is refused (no first-match wins)" 1 "$tmp/m.md"
mut "an authorization that is not an Issue #71 comment is refused" 's|^G2S-AUTHORIZATION: .*|G2S-AUTHORIZATION: https://example.com/approved|'
mut "an authorization on another issue is refused" 's|issues/71#|issues/72#|'
mut "an authorization URL with a second line of junk after it is refused" 's|^(G2S-AUTHORIZATION: .*)$|\1 extra|'
mut "a withdrawn record is refused even with the lines" 's/`G1 AUTHORIZED`/`WITHDRAWN`/'
mut "a draft record is refused even with the lines" 's/`G1 AUTHORIZED`/`DRAFT`/'
mut "a record whose APPROVED_SHA row names another commit is refused" "s/\*\*\`$SHA\`\*\*/**\`$OLD\`**/"
mut "prose that mentions APPROVED_SHA and the SHA is not the table row" "s/^\| \`APPROVED_SHA\` /Prose APPROVED_SHA $SHA \| /"
for key in G2S-STATUS G2S-OPERATION G2S-APPROVED-SHA G2S-VERSION G2S-BUNDLE-ID G2S-TEAM-ID G2S-WORKFLOW-BLOB G2S-GATE-BLOB G2S-TOOL-BLOBS G2S-DLC-WALLET-SHA256 G2S-AUTHORIZATION; do
  grep -v "^$key: " "$good" > "$tmp/m.md"; expect_rc "a record without $key is refused" 1 "$tmp/m.md"
done
{ cat "$good"; echo "G2S-STATUS: AUTHORIZED"; } > "$tmp/m.md"; expect_rc "a duplicated G2S-STATUS line is refused (no first-match wins)" 1 "$tmp/m.md"
{ cat "$good"; echo "G2S-STATUS: NOT AUTHORIZED"; } > "$tmp/m.md"; expect_rc "a contradicting second G2S-STATUS line is refused" 1 "$tmp/m.md"
sed 's/$/\r/' "$good" > "$tmp/m.md"; expect_rc "CRLF line endings are refused (fail closed)" 1 "$tmp/m.md"
{ cat "$real_record"; echo; markers | sed 's/^/ /'; } > "$tmp/m.md"; expect_rc "indented marker lines (for example inside a quote or a list) are refused" 1 "$tmp/m.md"
{ cat "$real_record"; echo; markers | sed 's/^/> /'; } > "$tmp/m.md"; expect_rc "marker lines inside a block quote are refused" 1 "$tmp/m.md"
{ cat "$good"; echo '**Record Status: `WITHDRAWN`**'; } > "$tmp/m.md"; expect_rc "a second, contradicting Record Status line is refused" 1 "$tmp/m.md"
# what a reader of the record does not see never counts
sed -E 's/^(G2S-STATUS: AUTHORIZED)$/```\n\1/; $a ```' "$good" > "$tmp/m.md"; expect_rc "G2S lines inside a fenced code block are refused" 1 "$tmp/m.md"
sed -E 's/^(G2S-STATUS: AUTHORIZED)$/<!--\n\1/; $a -->' "$good" > "$tmp/m.md"; expect_rc "G2S lines inside an HTML comment are refused" 1 "$tmp/m.md"
{ cat "$good"; printf '%s\n' '```text' 'G2S-STATUS: WITHDRAWN' '```'; } > "$tmp/m.md"; expect_rc "an example in a code block after the real lines does not disturb them (exit 0)" 0 "$tmp/m.md"

# --- --print-field: the one place where the signing job reads the dlc_wallet hash ---
pf() { bash "$tgate" --print-field "$1" --record "$2" --tools-root "$tools" 2>/dev/null; }
[ "$(pf G2S-DLC-WALLET-SHA256 "$good")" = "$DLC" ] && ok "--print-field prints the dlc_wallet hash of the record" || bad "--print-field prints the dlc_wallet hash of the record"
pf G2S-DLC-WALLET-SHA256 "$real_record" >/dev/null; [ $? -eq 1 ] && ok "--print-field refuses (exit 1) when the line is absent (the committed record)" || bad "--print-field refuses when the line is absent"
{ cat "$good"; echo "G2S-DLC-WALLET-SHA256: $DLC"; } > "$tmp/m.md"; pf G2S-DLC-WALLET-SHA256 "$tmp/m.md" >/dev/null; [ $? -eq 1 ] && ok "--print-field refuses a repeated line" || bad "--print-field refuses a repeated line"
sed -E 's/^(G2S-DLC-WALLET-SHA256: .*)$/```\n\1\n```/' "$good" > "$tmp/m.md"; pf G2S-DLC-WALLET-SHA256 "$tmp/m.md" >/dev/null; [ $? -eq 1 ] && ok "--print-field ignores a line inside a code block (refuses, exit 1)" || bad "--print-field ignores a line inside a code block"
sed 's/$/\r/' "$good" > "$tmp/m.md"; pf G2S-DLC-WALLET-SHA256 "$tmp/m.md" >/dev/null; [ $? -eq 1 ] && ok "--print-field refuses a CRLF line" || bad "--print-field refuses a CRLF line"
bash "$tgate" --print-field "bogus; rm" --record "$good" --tools-root "$tools" >/dev/null 2>&1; [ $? -eq 2 ] && ok "--print-field refuses a key that is not G2S-..." || bad "--print-field refuses a key that is not G2S-..."
bash "$tgate" --print-field G2S-DLC-WALLET-SHA256 --record "$tmp/none.md" --tools-root "$tools" >/dev/null 2>&1; [ $? -eq 2 ] && ok "--print-field with an unreadable record is a usage error" || bad "--print-field with an unreadable record is a usage error"

# --- Markdown fences follow CommonMark: a fence is closed only by the same character, at least as long, with nothing after it ---
L="G2S-DLC-WALLET-SHA256: $DLC"
fence() { # NAME EXPECTED_RC LINES...   (the lines are a record; --print-field reads $L through the effective text)
  local name="$1" want="$2"; shift 2; printf '%s\n' "$@" > "$tmp/f.md"; pf G2S-DLC-WALLET-SHA256 "$tmp/f.md" >/dev/null; local rc=$?
  [ "$rc" -eq "$want" ] && ok "fence: $name" || bad "fence: $name" "rc=$rc, wanted $want"
}
fence "REVIEWER BYPASS 1: a ~~~ line inside a backtick block does not close it (the marker stays hidden)" 1 '```text' '~~~' "$L" '```'
fence "REVIEWER BYPASS 2: a shorter backtick fence inside a longer one does not close it" 1 '````text' '```' "$L" '````'
fence "a tilde block is not closed by backticks" 1 '~~~' '```' "$L" '~~~'
fence "a closing fence shorter than the opening one does not close it" 1 '~~~~~' '~~~' "$L" '~~~~~'
fence "a closing fence with text after it does not close it" 1 '```' '``` trailing' "$L" '```'
fence "a backtick fence is not closed by a tilde fence even of equal length" 1 '```' '~~~' "$L" '```'
fence "an unclosed fence hides everything after it (the record is refused)" 1 '```text' "$L"
fence "an unclosed tilde fence hides everything after it" 1 'text' '~~~' "$L"
fence "a block closed by a longer fence of the same character is closed; the next line is live" 0 '```text' 'example' '`````' "$L"
fence "a block closed by an equal fence is closed; the next line is live" 0 '~~~' 'example' '~~~' "$L"
fence "a closing fence may be followed by spaces" 0 '```' 'example' '```   ' "$L"
fence "a fence indented by three spaces is a fence" 1 '   ```' "$L" '   ```'
fence "four spaces make an indented code line, not a fence: the marker after it is live" 0 '    ```' "$L"
fence "a backtick opener with a backtick in its info string is not a fence: the marker is live" 0 '``` a`b' "$L"
fence "a tilde opener may have backticks in its info string: it is a fence, the marker stays hidden" 1 '~~~ a`b' "$L" '~~~'
fence "two fences in a row: the marker between them is live" 0 '```' 'a' '```' "$L" '~~~' 'b' '~~~'
fence "two fences in a row: the marker inside the second is hidden" 1 '```' 'a' '```' '~~~' "$L" '~~~'
fence "a live marker before an unclosed fence stays live" 0 "$L" '```text' 'example'
# the whole gate, not only --print-field: every G2S line inside a block that a reader sees as code never authorizes
awk '/^G2S-/ { next } { print }' "$good" > "$tmp/stripped.md"
{ cat "$tmp/stripped.md"; echo '```text'; echo '~~~'; markers; echo '```'; } > "$tmp/m.md"; expect_rc "the full authorization hidden behind a ~~~ line inside a backtick block does NOT authorize (exit 1)" 1 "$tmp/m.md"
{ cat "$tmp/stripped.md"; echo '````text'; echo '```'; markers; echo '````'; } > "$tmp/m.md"; expect_rc "the full authorization hidden behind a shorter fence inside a longer one does NOT authorize (exit 1)" 1 "$tmp/m.md"
{ cat "$tmp/stripped.md"; echo '```text'; echo 'example'; echo '```'; markers; } > "$tmp/m.md"; expect_rc "the same lines after a properly closed block authorize (exit 0)" 0 "$tmp/m.md"

# --- the decisions G2S needs (and the ones it does not) ---
for id in $DECISIONS; do
  awk -v id="$id" 'index($0, "| " id " | ") == 1 { sub(/\| Decided \| CTO \| 2026-11-21 \|[ ]*$/, "| Proposed, not decided | TBD | TBD |") } { print }' "$good" > "$tmp/m.md"
  expect_rc "decision $id still Proposed is refused" 1 "$tmp/m.md"
done
grep -v '^| D14 | ' "$good" > "$tmp/m.md"; expect_rc "a record without the D14 credential row is refused" 1 "$tmp/m.md"
sed -E 's/^(\| D14 \| .*)\| Decided \| CTO \| 2026-11-21 \|$/\1| Decided | TBD | 2026-11-21 |/' "$good" > "$tmp/m.md"; expect_rc "D14 Decided without a name (By TBD) is refused" 1 "$tmp/m.md"
sed -E 's/^(\| D14 \| .*)\| Decided \| CTO \| 2026-11-21 \|$/\1| Decided | CTO | yesterday |/' "$good" > "$tmp/m.md"; expect_rc "D14 Decided without a real date is refused" 1 "$tmp/m.md"
sed -E 's/^(\| D14 \| .*)\| Decided \| CTO \| 2026-11-21 \|$/\1| decided | CTO | 2026-11-21 |/' "$good" > "$tmp/m.md"; expect_rc "Status 'decided' in lower case is refused (exact vocabulary)" 1 "$tmp/m.md"
{ cat "$good"; echo '| D7 | duplicate row | Decided | CTO | 2026-11-21 |'; } > "$tmp/m.md"; expect_rc "a duplicated decision row is refused" 1 "$tmp/m.md"
# the upload-time decisions are NOT G2S prerequisites, and nothing here decides them
for id in D1 D2 D4 D5 X1 X2; do
  grep -q "^| $id | .*| \(Proposed, not decided\|Open\) |" "$good" && ok "$id stays undecided in the authorized fixture (G2S does not need it, and does not decide it)" || bad "$id stays undecided in the authorized fixture"
done
expect_rc "G2S is accepted although D1, D2, D4, D5, X1 and X2 are open (they gate the upload, G2)" 0 "$good"

# --- the revision must be the current tip of development (a re-run of an old run cannot use an old record) ---
expect_rc "a workflow revision that is not the tip of development is refused" 1 "$good" --development-tip "$OLD"
expect_rc "a malformed tip is a usage error (exit 2)" 2 "$good" --development-tip ""
expect_rc "a missing workflow revision is a usage error (exit 2)" 2 "$good" --workflow-sha XYZ

# --- the implementation is bound: any change invalidates an old authorization ---
for f in .github/workflows/ios-hosted-signing.yml tool/check_signing_authorization.sh tool/verify_ipa.py tool/ipa_inspect.py tool/build_manifest.py tool/verify_artifact.sh tool/validate_handover_archive.py; do
  t2="$tmp/t2"; mktools "$t2"; expect_rc "an unchanged copy of $f still matches (exit 0)" 0 "$good" --tools-root "$t2"
  printf '\n# changed after the authorization\n' >> "$t2/$f"
  if [ "$f" = tool/check_signing_authorization.sh ]; then
    out="$(bash "$t2/$f" --record "$good" --approved-sha "$SHA" --version "$VER" --bundle-id "$BID" --team-id "$TEAM" --tools-root "$t2" --workflow-sha "$WFSHA" --development-tip "$WFSHA" 2>&1)"; rc=$?
    [ "$rc" -eq 1 ] && ok "a changed $f (the running gate itself) no longer matches the authorized blob (refused)" || bad "a changed $f no longer matches" "rc=$rc"
  else
    expect_rc "a changed $f no longer matches the authorized blobs (refused)" 1 "$good" --tools-root "$t2"
  fi
done
out="$(expected_lines)"; [ "$(printf '%s\n' "$out" | grep -c '^G2S-')" = 3 ] && ok "--print-expected prints exactly the three blob lines" || bad "--print-expected prints exactly the three blob lines" "$out"
before="$(find "$tools" -type f | sort | xargs shasum -a 256 | shasum -a 256)"; bash "$tgate" --print-expected --tools-root "$tools" >/dev/null; after="$(find "$tools" -type f | sort | xargs shasum -a 256 | shasum -a 256)"
[ "$before" = "$after" ] && ok "--print-expected writes nothing" || bad "--print-expected writes nothing"

# --- input validation is whole-string: a value with a second line is a usage error, never a pass ---
nl=$'\n'
expect_rc "a SHA argument with a junk second line is a usage error (exit 2)" 2 "$good" --approved-sha "$SHA${nl}zz"
expect_rc "a SHA argument with a junk first line is a usage error (exit 2)" 2 "$good" --approved-sha "zz${nl}$SHA"
expect_rc "a version argument with a second line is a usage error (exit 2)" 2 "$good" --version "$VER${nl}x"
expect_rc "a team argument with a second line is a usage error (exit 2)" 2 "$good" --team-id "$TEAM${nl}x"
expect_rc "a tip argument with a second line is a usage error (exit 2)" 2 "$good" --development-tip "$WFSHA${nl}x"

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
if grep -vE '^[[:space:]]*#' "$gate" | grep -E '(^|[^[:alnum:]_])(curl|wget|gh)[[:space:]]|git (push|commit|fetch|ls-remote)|>>? *"?\$record' >/dev/null; then bad "the gate runs no network, git write or record write command"; else ok "the gate runs no network, git write or record write command"; fi
bash -n "$gate" && ok "the gate is syntactically valid" || bad "the gate is syntactically valid"

echo
echo "test_check_signing_authorization: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
