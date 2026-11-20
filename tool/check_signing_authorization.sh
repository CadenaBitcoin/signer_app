#!/usr/bin/env bash
# Authorization gate of the hosted iOS signing workflow (docs/IOS_HOSTED_SIGNING.md, Issue #71).
#
#   tool/check_signing_authorization.sh --record FILE --approved-sha SHA --version X.Y.Z+N \
#       --bundle-id ID --team-id TEAM --tools-root DIR --workflow-sha SHA --development-tip SHA
#   tool/check_signing_authorization.sh --print-expected --tools-root DIR
#   tool/check_signing_authorization.sh --print-field KEY --record FILE --tools-root DIR
#
# Prints every reason and exits
#   0  the release record carries a complete, matching "sign and verify only" authorization (G2S);
#   1  it does not (the default: a record without the G2S lines is NOT authorized);
#   2  the call itself is wrong (missing or malformed argument, unreadable file).
#
# It READS a record that is on `development` through a merged, reviewed pull request (the workflow checks out its own
# commit, which is that branch). It decides nothing and writes nothing: the authorization is the CTO's written decision
# and the merged pull request that adds the lines below (docs/IOS_HOSTED_SIGNING.md section 5). It is an automated
# tripwire so that the workflow cannot sign before that decision exists; it is not the authorization.
#
# G2S is exactly: sign and verify ONE approved iOS release artifact. No upload, no tester distribution. G2 (signing plus
# the one upload) and G3 to G5 are separate and are not read here.
#
# The record must contain, each on a line of its own, at column 0, exactly once, with LF line endings, and NOT inside a
# fenced code block or an HTML comment (those are not what a reader of the record sees, so they never count):
#   G2S-STATUS: AUTHORIZED
#   G2S-OPERATION: sign-and-verify-only
#   G2S-APPROVED-SHA: <40 lower-case hex>            equals --approved-sha
#   G2S-VERSION: <X.Y.Z+N>                           equals --version
#   G2S-BUNDLE-ID: <bundle id>                       equals --bundle-id
#   G2S-TEAM-ID: <team id>                           equals --team-id
#   G2S-WORKFLOW-BLOB: <git blob>                    of .github/workflows/ios-hosted-signing.yml (the implementation)
#   G2S-GATE-BLOB: <git blob>                        of THIS script (the file that is running)
#   G2S-TOOL-BLOBS: <path>=<blob>,...                of the tools the signing job runs (TOOL_FILES below, sorted)
#   G2S-DLC-WALLET-SHA256: <64 lower-case hex>       SHA-256 of Frameworks/dlc_wallet.framework/dlc_wallet in the UNSIGNED archive
#                                                    that the CTO authorizes to be signed (the native crypto library's framework);
#                                                    the signing job compares the archive's real binary with it before any secret
#   G2S-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-<digits>
# a change to the workflow, this gate or any bound tool therefore invalidates an earlier authorization: the CTO's pull
# request must name the new blobs. `--print-expected` prints the three blob lines for a checkout (it authorizes nothing).
# `--print-field KEY` prints the value of one effective, single, LF-terminated G2S line (exit 1 when it is absent, repeated, hidden
# in a code block or comment, or has a carriage return); the signing job reads the dlc_wallet hash that way, so that the record is
# parsed in exactly one place.
# Also required: the record's own status is `G1 AUTHORIZED` or `G2 AUTHORIZED` (not DRAFT, not WITHDRAWN); its
# APPROVED_SHA row names --approved-sha; and every decision row of REQUIRED_DECISIONS below is DECIDED (Status exactly
# `Decided`, By not TBD, Date YYYY-MM-DD). The workflow revision (--workflow-sha, GITHUB_SHA) must be the current tip of
# `development` (--development-tip): a re-run of a historical run therefore cannot use an authorization that a later
# commit withdrew. Anything else, including a typo, a duplicate or a different case, is a stop.
set -uo pipefail

# --- what the authorization is bound to (paths relative to --tools-root) ---
WORKFLOW_FILE=".github/workflows/ios-hosted-signing.yml"
# Every tool the SIGNING job runs, directly or by import: verify_ipa.py imports ipa_inspect.py and build_manifest.py;
# build_manifest.py asks verify_artifact.sh for the identity matrix; validate_handover_archive.py checks the hand-over.
TOOL_FILES="tool/build_manifest.py tool/ipa_inspect.py tool/validate_handover_archive.py tool/verify_artifact.sh tool/verify_ipa.py"

# --- release decisions that must be DECIDED before G2S (signing and verification only) ---
# D3 route, D6 no push entitlement (enforced by the signing job), D7 cloud-managed certificate and its account side effects,
# D8 certificate verification and recording, D9 export, verify, no second compile, D10 verification tooling, D11 and D12
# the gate reading and policy basis, D14 the credential decision (a dedicated Developer-role Apple Team API key,
# whose scope cannot be limited to one application; rotation and revocation stay available; a temporary Admin key needs its own decision).
# NOT required for G2S, required before G2 (upload, TestFlight): D1 (Issue #22 residual risk), D2 (zero-value wallets),
# D4 (production App Store Connect record), D5 (production gate), X1 (export compliance, App Privacy), X2 (privacy
# manifest) and the prerequisites of record section 4.1. The signed IPA never leaves the runner under G2S.
REQUIRED_DECISIONS="D3 D6 D7 D8 D9 D10 D11 D12 D14"

RE_SHA='^[0-9a-f]{40}$'
RE_VERSION='^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$'
RE_BUNDLE='^[A-Za-z0-9.-]+$'
RE_TEAM='^[A-Z0-9]{10}$'
RE_HEX64='^[0-9a-f]{64}$'
RE_DATE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
RE_URL='^https://github\.com/CadenaBitcoin/signer_app/issues/71#issuecomment-[0-9]+$'

# Whole-string match: a value with a line break never passes, however its other lines look (grep -E matches per line).
isexact() { # VALUE REGEX
  case "$1" in *$'\n'*|*$'\r'*) return 1 ;; esac
  [[ "$1" =~ $2 ]]
}

record=""; sha=""; version=""; bundle=""; team=""; tools=""; wfsha=""; tip=""; print_expected=0; print_field=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --record) record="${2:-}"; shift 2 ;;
    --approved-sha) sha="${2:-}"; shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    --bundle-id) bundle="${2:-}"; shift 2 ;;
    --team-id) team="${2:-}"; shift 2 ;;
    --tools-root) tools="${2:-}"; shift 2 ;;
    --workflow-sha) wfsha="${2:-}"; shift 2 ;;
    --development-tip) tip="${2:-}"; shift 2 ;;
    --print-expected) print_expected=1; shift ;;
    --print-field) print_field="${2:-}"; shift 2 ;;
    *) echo "check_signing_authorization.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

usage_err() { echo "check_signing_authorization.sh: $1" >&2; exit 2; }
[ -n "$tools" ] && [ -d "$tools/tool" ] || usage_err "--tools-root must be a directory that holds tool/"
for f in $WORKFLOW_FILE $TOOL_FILES; do [ -r "$tools/$f" ] || usage_err "$tools/$f is not readable"; done
self="${BASH_SOURCE[0]}"
[ -r "$self" ] || usage_err "cannot read this script"

blob() { git hash-object -- "$1"; }
want_tool_blobs() { local f out=""; for f in $TOOL_FILES; do out="${out:+$out,}$f=$(blob "$tools/$f")"; done; printf '%s' "$out"; }
want_workflow_blob() { blob "$tools/$WORKFLOW_FILE"; }
want_gate_blob() { blob "$self"; }

# What a reader of the record sees: without fenced code blocks and HTML comments (a line that opens or closes one is
# dropped too). Nothing in those regions can authorize, withdraw or decide anything. Fences follow CommonMark: an opening
# fence is three or more backticks or tildes after at most three spaces (a backtick fence's info string has no backtick); it
# is closed ONLY by a fence of the same character, at least as long as the opening one, with nothing but spaces after it;
# an unclosed fence runs to the end of the record (so everything after it is hidden and the gate refuses).
eff=""
make_eff() {
  eff="$(mktemp "${TMPDIR:-/tmp}/g2s-record.XXXXXX")"; trap 'rm -f "$eff"' EXIT
  awk '
    # sets PCH (the fence character), PLEN (its run length) and PREST (the rest of the line); returns 1 for a fence line
    function fenceline(l,    sp, c, n) {
      sp = 0
      while (sp < 4 && substr(l, sp + 1, 1) == " ") sp++
      if (sp > 3) return 0
      c = substr(l, sp + 1, 1)
      if (c != "`" && c != "~") return 0
      n = 0
      while (substr(l, sp + 1 + n, 1) == c) n++
      if (n < 3) return 0
      PCH = c; PLEN = n; PREST = substr(l, sp + 1 + n)
      return 1
    }
    BEGIN { fence = 0; cmt = 0; fch = ""; flen = 0 }
    {
      line = $0
      if (fence) {
        if (fenceline(line) && PCH == fch && PLEN >= flen && PREST ~ /^[ \t]*$/) fence = 0
        next
      }
      if (cmt) { if (index(line, "-->") > 0) cmt = 0; next }
      if (fenceline(line) && !(PCH == "`" && index(PREST, "`") > 0)) { fence = 1; fch = PCH; flen = PLEN; next }
      if (index(line, "<!--") > 0) { if (index(line, "-->") == 0) cmt = 1; next }
      print line
    }' "$record" > "$eff"
}

if [ "$print_expected" -eq 1 ]; then
  echo "G2S-WORKFLOW-BLOB: $(want_workflow_blob)"
  echo "G2S-GATE-BLOB: $(want_gate_blob)"
  echo "G2S-TOOL-BLOBS: $(want_tool_blobs)"
  exit 0
fi

if [ -n "$print_field" ]; then
  isexact "$print_field" '^G2S-[A-Z0-9-]+$' || usage_err "--print-field needs a G2S-... key"
  [ -n "$record" ] && [ -r "$record" ] && [ ! -d "$record" ] || usage_err "--record must name a readable file"
  make_eff
  n="$(grep -c "^${print_field}: " "$eff" || true)"
  [ "$n" -eq 1 ] || { echo "check_signing_authorization.sh: $print_field must appear exactly once outside code blocks and comments (found $n)" >&2; exit 1; }
  line="$(grep "^${print_field}: " "$eff")"
  case "$line" in *$'\r'*) echo "check_signing_authorization.sh: $print_field line has a carriage return" >&2; exit 1 ;; esac
  printf '%s\n' "${line#"${print_field}: "}"
  exit 0
fi

[ -n "$record" ] && [ -r "$record" ] && [ ! -d "$record" ] || usage_err "--record must name a readable file"
isexact "$sha" "$RE_SHA" || usage_err "--approved-sha must be 40 lower-case hex characters"
isexact "$version" "$RE_VERSION" || usage_err "--version must look like 1.0.4+1000035"
isexact "$bundle" "$RE_BUNDLE" || usage_err "--bundle-id is missing or malformed"
isexact "$team" "$RE_TEAM" || usage_err "--team-id must be 10 upper-case letters or digits"
isexact "$wfsha" "$RE_SHA" || usage_err "--workflow-sha must be 40 lower-case hex characters"
isexact "$tip" "$RE_SHA" || usage_err "--development-tip must be 40 lower-case hex characters (the current tip of development)"

fail=0
no() { echo "NOT AUTHORIZED: $1"; fail=1; }
yes() { echo "ok: $1"; }
make_eff

# One value of a marker line: exactly one line may start with "KEY: ", and it must be a clean LF line. Called without a
# subshell so that a refusal is recorded; the value is left in FIELD (empty when refused).
FIELD=""
getfield() { # KEY ; returns 1 when refused
  local key="$1" n line
  FIELD=""
  n="$(grep -c "^${key}: " "$eff" || true)"
  if [ "$n" -ne 1 ]; then no "$key must appear exactly once at the start of a line outside code blocks and comments (found $n)"; return 1; fi
  line="$(grep "^${key}: " "$eff")"
  case "$line" in *$'\r'*) no "$key line has a carriage return"; return 1 ;; esac
  FIELD="${line#"${key}: "}"
  return 0
}
expect() { # KEY EXPECTED
  getfield "$1" || return 0
  if [ "$FIELD" = "$2" ]; then yes "$1 = $2"; else no "$1 is '$FIELD', expected '$2'"; fi
}

expect G2S-STATUS "AUTHORIZED"
expect G2S-OPERATION "sign-and-verify-only"
expect G2S-APPROVED-SHA "$sha"
expect G2S-VERSION "$version"
expect G2S-BUNDLE-ID "$bundle"
expect G2S-TEAM-ID "$team"
# The implementation the authorization was given for: any change to it needs a new, reviewed authorization.
expect G2S-WORKFLOW-BLOB "$(want_workflow_blob)"
expect G2S-GATE-BLOB "$(want_gate_blob)"
expect G2S-TOOL-BLOBS "$(want_tool_blobs)"

# The native crypto library's framework in the archive that may be signed (the signing job compares the real binary).
if getfield G2S-DLC-WALLET-SHA256; then
  if isexact "$FIELD" "$RE_HEX64"; then yes "G2S-DLC-WALLET-SHA256 is a SHA-256 ($FIELD)"
  else no "G2S-DLC-WALLET-SHA256 must be 64 lower-case hex characters"; fi
fi

if getfield G2S-AUTHORIZATION; then
  if isexact "$FIELD" "$RE_URL"; then yes "G2S-AUTHORIZATION names a comment on Issue #71 (existence and author are not checked here)"
  else no "G2S-AUTHORIZATION must be https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-<digits>"; fi
fi

# The record's own status and approved source.
st_lines="$(grep -E '^\*\*Record Status: `[A-Z0-9 ]+`\*\*$' "$eff" || true)"
st_count="$(printf '%s\n' "$st_lines" | grep -c . || true)"
if [ "$st_count" -ne 1 ]; then no "the record must carry exactly one '**Record Status: \`...\`**' line (found $st_count)"
else
  case "$st_lines" in
    '**Record Status: `G1 AUTHORIZED`**'|'**Record Status: `G2 AUTHORIZED`**') yes "record status allows this stage ($st_lines)" ;;
    *) no "record status is not G1 AUTHORIZED or G2 AUTHORIZED ($st_lines)" ;;
  esac
fi
row_count="$(grep -c '^| `APPROVED_SHA` ' "$eff" || true)"
if [ "$row_count" -ne 1 ]; then no "the record must carry exactly one '| \`APPROVED_SHA\` ...' table row (found $row_count)"
elif grep '^| `APPROVED_SHA` ' "$eff" | grep -Fq "**\`$sha\`**"; then yes "the record's APPROVED_SHA row names $sha"
else no "the record's APPROVED_SHA row does not name $sha"; fi

# Decision rows: | ID | text | Status | By | Date |   (the three cells on the right; the text may contain anything).
cell() { # ID N_FROM_RIGHT (1 = Date, 2 = By, 3 = Status)
  grep "^| $1 | " "$eff" | awk -F'|' -v k="$2" '{ n = NF; if ($n ~ /^[ \t]*$/) n--; v = $(n - k + 1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v }'
}
for id in $REQUIRED_DECISIONS; do
  n="$(grep -c "^| $id | " "$eff" || true)"
  if [ "$n" -ne 1 ]; then no "decision row $id must appear exactly once in the decision table (found $n); G2S needs: $REQUIRED_DECISIONS"; continue; fi
  st="$(cell "$id" 3)"; by="$(cell "$id" 2)"; dt="$(cell "$id" 1)"
  if [ "$st" = "Decided" ] && [ -n "$by" ] && [ "$by" != "TBD" ] && isexact "$dt" "$RE_DATE"; then yes "decision $id is Decided (by $by, $dt)"
  else no "decision $id is not decided (Status '$st', By '$by', Date '$dt'); G2S needs Status 'Decided', a name and a date"; fi
done

# The workflow revision must be the tip of development: a re-run of an old run cannot outlive a withdrawal.
if [ "$wfsha" = "$tip" ]; then yes "this workflow revision ($wfsha) is the current tip of development"
else no "this workflow revision ($wfsha) is not the current tip of development ($tip): a historical or re-run workflow cannot sign; start a new run from the tip"; fi

if [ "$fail" -eq 0 ]; then echo "AUTHORIZED: hosted signing and verification only (no upload, no G2 upload gate, no G3 to G5)"; exit 0; fi
echo "Signing stays refused. The CTO's written decision and a merged, reviewed record pull request add the G2S lines and decide the rows above (docs/IOS_HOSTED_SIGNING.md section 5)."
exit 1
