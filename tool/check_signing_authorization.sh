#!/usr/bin/env bash
# Authorization gate of the hosted iOS signing workflow (docs/IOS_HOSTED_SIGNING.md, Issue #71).
#
#   tool/check_signing_authorization.sh --record FILE --approved-sha SHA --version X.Y.Z+N \
#       --bundle-id ID --team-id TEAM --tools-root DIR
#
# Prints every reason and exits
#   0  the release record carries a complete, matching "sign and verify only" authorization (G2S);
#   1  it does not (the default: a record without the G2S lines is NOT authorized);
#   2  the call itself is wrong (missing or malformed argument, unreadable file).
#
# It READS a record that is on `development` through a merged, reviewed pull request (the workflow checks out its own
# commit, which is that branch). It decides nothing and writes nothing: the authorization is the CTO's written decision
# and the merged pull request that adds the lines below (docs/IOS_RELEASE.md section 3). It is an automated tripwire so
# that the workflow cannot sign before that decision exists; it is not the authorization.
#
# The record must contain, each on a line of its own, at column 0, exactly once, with LF line endings:
#   G2S-STATUS: AUTHORIZED
#   G2S-OPERATION: sign-and-verify-only
#   G2S-APPROVED-SHA: <40 lower-case hex>            equals --approved-sha
#   G2S-VERSION: <X.Y.Z+N>                           equals --version
#   G2S-BUNDLE-ID: <bundle id>                       equals --bundle-id
#   G2S-TEAM-ID: <team id>                           equals --team-id
#   G2S-VERIFIER-BLOBS: <verify_ipa.py blob>,<ipa_inspect.py blob>     the git blobs of the verifier the workflow runs
#   G2S-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-<digits>
# and the record's own status must be `G1 AUTHORIZED` or `G2 AUTHORIZED` (not DRAFT, not WITHDRAWN), and its
# APPROVED_SHA row must name --approved-sha. Anything else, including a typo, a duplicate or a different case, is a stop.
# G2S is NOT the upload gate: G2 (signing plus the one upload) and G3 to G5 are separate and are not read here.
set -uo pipefail

record=""; sha=""; version=""; bundle=""; team=""; tools=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --record) record="${2:-}"; shift 2 ;;
    --approved-sha) sha="${2:-}"; shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    --bundle-id) bundle="${2:-}"; shift 2 ;;
    --team-id) team="${2:-}"; shift 2 ;;
    --tools-root) tools="${2:-}"; shift 2 ;;
    *) echo "check_signing_authorization.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

usage_err() { echo "check_signing_authorization.sh: $1" >&2; exit 2; }
[ -n "$record" ] && [ -r "$record" ] && [ ! -d "$record" ] || usage_err "--record must name a readable file"
printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$' || usage_err "--approved-sha must be 40 lower-case hex characters"
printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$' || usage_err "--version must look like 1.0.4+1000035"
printf '%s' "$bundle" | grep -Eq '^[A-Za-z0-9.-]+$' || usage_err "--bundle-id is missing or malformed"
printf '%s' "$team" | grep -Eq '^[A-Z0-9]{10}$' || usage_err "--team-id must be 10 upper-case letters or digits"
[ -n "$tools" ] && [ -d "$tools/tool" ] || usage_err "--tools-root must be a directory that holds tool/"
for f in verify_ipa.py ipa_inspect.py; do [ -r "$tools/tool/$f" ] || usage_err "$tools/tool/$f is not readable"; done

fail=0
no() { echo "NOT AUTHORIZED: $1"; fail=1; }
yes() { echo "ok: $1"; }

# One value of a marker line: exactly one line may start with "KEY: ", and it must be a clean LF line. Called without a
# subshell so that a refusal is recorded; the value is left in FIELD (empty when refused).
FIELD=""
getfield() { # KEY ; returns 1 when refused
  local key="$1" n line
  FIELD=""
  n="$(grep -c "^${key}: " "$record" || true)"
  if [ "$n" -ne 1 ]; then no "$key must appear exactly once at the start of a line (found $n)"; return 1; fi
  line="$(grep "^${key}: " "$record")"
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

want_blobs="$(git hash-object "$tools/tool/verify_ipa.py"),$(git hash-object "$tools/tool/ipa_inspect.py")"
expect G2S-VERIFIER-BLOBS "$want_blobs"

if getfield G2S-AUTHORIZATION; then
  if printf '%s' "$FIELD" | grep -Eq '^https://github\.com/CadenaBitcoin/signer_app/issues/71#issuecomment-[0-9]+$'; then yes "G2S-AUTHORIZATION names a comment on Issue #71"
  else no "G2S-AUTHORIZATION must be https://github.com/CadenaBitcoin/signer_app/issues/71#issuecomment-<digits>"; fi
fi

# The record's own status and approved source.
st_lines="$(grep -E '^\*\*Record Status: `[A-Z0-9 ]+`\*\*$' "$record" || true)"
st_count="$(printf '%s\n' "$st_lines" | grep -c . || true)"
if [ "$st_count" -ne 1 ]; then no "the record must carry exactly one '**Record Status: \`...\`**' line (found $st_count)"
else
  case "$st_lines" in
    '**Record Status: `G1 AUTHORIZED`**'|'**Record Status: `G2 AUTHORIZED`**') yes "record status allows this stage ($st_lines)" ;;
    *) no "record status is not G1 AUTHORIZED or G2 AUTHORIZED ($st_lines)" ;;
  esac
fi
if grep -E 'APPROVED_SHA' "$record" | grep -Fq "$sha"; then yes "the record's APPROVED_SHA row names $sha"
else no "no APPROVED_SHA row of the record names $sha"; fi

if [ "$fail" -eq 0 ]; then echo "AUTHORIZED: hosted signing and verification only (no upload, no G2 upload gate, no G3 to G5)"; exit 0; fi
echo "Signing stays refused. The CTO's written decision and a merged, reviewed record pull request add the G2S lines (docs/IOS_HOSTED_SIGNING.md section 5)."
exit 1
