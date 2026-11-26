#!/usr/bin/env bash
# Authorization gate of the AUTOMATIC iOS STAGING delivery (docs/IOS_STAGING_DELIVERY.md, Issues #54 and #71).
#
#   tool/check_staging_authorization.sh --record FILE --head SHA --remote URL \
#       --bundle-id ID --team-id TEAM --tools-root DIR [--repo DIR]
#   tool/check_staging_authorization.sh --print-expected --tools-root DIR
#   tool/check_staging_authorization.sh --print-field KEY --record FILE --tools-root DIR
#
# Prints every reason and exits
#   0  the staging release record authorizes THIS promotion: one automatic "sign, verify and upload the SAME verified IPA" of exactly the
#      version, bundle, team, App Store Connect application, certificate, native library and implementation the record names, for a
#      commit that is the current tip of `staging`, a reviewed merge commit, and whose application content is the content of `development`;
#   1  it does not (the default: a record whose status is not AUTHORIZED, or that lacks a line, authorizes nothing);
#   2  the call itself is wrong.
#
# WHY A SECOND GATE. The production gate (tool/check_signing_authorization.sh) authorizes ONE manual, consumed operation for a commit that
# already exists on `production`, and is read from `development`. A merge into `staging` has no such moment: the merge commit does not exist
# when the decision is taken, and no person starts anything afterwards (RELEASE_POLICY.md 2.3: the authorized merge is the authorization).
# So the authorization is given BEFORE the promotion, as part of the reviewed pull request that carries the version advance, and is bound to
# everything that can be known then. What it cannot name (the merge commit) is checked structurally instead (the source checks below).
# This gate is separate on purpose: the production gate, its record and its blobs are unchanged, and this gate can never authorize the
# production bundle: the bundle ID, the environment and the Apple App ID are constants of THIS file, not values of the record.
#
# The record names, each on a line of its own at column 0, exactly once, outside code blocks and HTML comments (the strict parser of the
# production gate reads them: `check_signing_authorization.sh --print-field`):
#   G2S-STAGING-STATUS: AUTHORIZED              WITHDRAWN (or anything else) refuses
#   G2S-STAGING-OPERATION: sign-verify-and-upload
#   G2S-STAGING-VERSION: X.Y.Z+N                equals pubspec.yaml of the commit that is being delivered
#   G2S-STAGING-BUNDLE-ID: com.app.cadenabitcoin.staging
#   G2S-STAGING-TEAM-ID: <10 characters>
#   G2S-STAGING-APP-APPLE-ID: <digits>          the STAGING App Store Connect application (never the production one)
#   G2S-STAGING-CERT-SHA256: <64 hex>           the RECORDED Apple Distribution certificate: the signed IPA must carry exactly this one
#   G2S-STAGING-DLC-WALLET-SHA256: <64 hex>     the native crypto library's framework that may be signed
#   G2S-STAGING-WORKFLOW-BLOB / -GATE-BLOB / -TOOL-BLOBS    the implementation this authorization was given for
#   G2S-STAGING-AUTHORIZATION: https://github.com/CadenaBitcoin/signer_app/issues/<54|71>#issuecomment-<digits>
#   G2S-STAGING-DECISION-S1..S4: Decided by <name> on YYYY-MM-DD
# A change to the workflow, this gate or a bound tool invalidates the authorization: the reviewed pull request names the new blobs.
#
# The gate itself reads, from --remote and at the moment it runs, the CURRENT tip of `staging` and the same record on the CURRENT tip of
# `development`. The commit being delivered must be that tip of `staging`, and the record on `development` must also say AUTHORIZED:
# withdrawing the authorization on `development` stops every later staging delivery at once, including a re-run of an old run.
set -uo pipefail

# --- constants: the staging identity and the things that must never be authorized here ---
STAGING_BUNDLE_ID="com.app.cadenabitcoin.staging"
PRODUCTION_BUNDLE_ID="com.app.cadenabitcoin"
PRODUCTION_APP_APPLE_ID="6753348211"
OPERATION="sign-verify-and-upload"
WORKFLOW_FILE=".github/workflows/ios-staging-delivery.yml"
# Every tool the signing job runs, directly or by import, and the record parser this gate delegates to.
TOOL_FILES="tool/build_manifest.py tool/check_signing_authorization.sh tool/ipa_inspect.py tool/validate_handover_archive.py tool/verify_artifact.sh tool/verify_build_config.sh tool/verify_ipa.py"
# What `staging` must have of `development` (the application: no documentation, no workflow). Same list as the production workflow's CONTENT_PATHS.
CONTENT_PATHS="lib ios flutter_plugin pubspec.yaml pubspec.lock config/build android"
REQUIRED_DECISIONS="S1 S2 S3 S4"

RE_SHA='^[0-9a-f]{40}$'
RE_VERSION='^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$'
RE_TEAM='^[A-Z0-9]{10}$'
RE_HEX64='^[0-9a-f]{64}$'
RE_DIGITS='^[0-9]{6,15}$'
RE_DATE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
RE_URL='^https://github\.com/CadenaBitcoin/signer_app/issues/(54|71)#issuecomment-[0-9]+$'
RECORD_PATH="docs/release-records/ios-staging-authorization.md"
DEV_REF="refs/staging-gate/development"
RE_DECISION='^Decided by [A-Za-z0-9._-]+ on [0-9]{4}-[0-9]{2}-[0-9]{2}$'

isexact() { # VALUE REGEX; whole-string match, a value with a line break never passes
  case "$1" in *$'\n'*|*$'\r'*) return 1 ;; esac
  [[ "$1" =~ $2 ]]
}

record=""; head=""; remote=""; bundle=""; team=""; tools=""; repo="."; print_expected=0; print_field=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --record) record="${2:-}"; shift 2 ;;
    --head) head="${2:-}"; shift 2 ;;
    --remote) remote="${2:-}"; shift 2 ;;
    --bundle-id) bundle="${2:-}"; shift 2 ;;
    --team-id) team="${2:-}"; shift 2 ;;
    --tools-root) tools="${2:-}"; shift 2 ;;
    --repo) repo="${2:-}"; shift 2 ;;
    --print-expected) print_expected=1; shift ;;
    --print-field) print_field="${2:-}"; shift 2 ;;
    *) echo "check_staging_authorization.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

usage_err() { echo "check_staging_authorization.sh: $1" >&2; exit 2; }
[ -n "$tools" ] && [ -d "$tools/tool" ] || usage_err "--tools-root must be a directory that holds tool/"
for f in $WORKFLOW_FILE $TOOL_FILES; do [ -r "$tools/$f" ] || usage_err "$tools/$f is not readable"; done
self="${BASH_SOURCE[0]}"
[ -r "$self" ] || usage_err "cannot read this script"
PARSER="$tools/tool/check_signing_authorization.sh"

blob() { git hash-object -- "$1"; }
want_tool_blobs() { local f out=""; for f in $TOOL_FILES; do out="${out:+$out,}$f=$(blob "$tools/$f")"; done; printf '%s' "$out"; }

if [ "$print_expected" -eq 1 ]; then
  echo "G2S-STAGING-WORKFLOW-BLOB: $(blob "$tools/$WORKFLOW_FILE")"
  echo "G2S-STAGING-GATE-BLOB: $(blob "$self")"
  echo "G2S-STAGING-TOOL-BLOBS: $(want_tool_blobs)"
  exit 0
fi

# One value of a record line, through the production gate's strict parser (code blocks and comments hidden, exactly one line, LF only).
# The parser needs a --tools-root that holds the PRODUCTION workflow and tools; any full checkout does.
field_of() { # FILE KEY -> value on stdout, exit 1 when refused
  bash "$PARSER" --print-field "$2" --record "$1" --tools-root "$tools" 2>/dev/null
}

if [ -n "$print_field" ]; then
  isexact "$print_field" '^G2S-STAGING-[A-Z0-9-]+$' || usage_err "--print-field needs a G2S-STAGING-... key"
  [ -n "$record" ] && [ -r "$record" ] && [ ! -d "$record" ] || usage_err "--record must name a readable file"
  field_of "$record" "$print_field"
  exit $?
fi

[ -n "$record" ] && [ -r "$record" ] && [ ! -d "$record" ] || usage_err "--record must name a readable file"
isexact "$head" "$RE_SHA" || usage_err "--head must be 40 lower-case hex characters (the commit being delivered)"
[ -n "$remote" ] || usage_err "--remote must name the repository that holds the current staging and development (a URL or a path)"
isexact "$bundle" '^[A-Za-z0-9.-]+$' || usage_err "--bundle-id is missing or malformed"
isexact "$team" "$RE_TEAM" || usage_err "--team-id must be 10 upper-case letters or digits"
git -C "$repo" cat-file -e "$head^{commit}" 2>/dev/null || usage_err "--head is not a commit of --repo"

fail=0
no() { echo "NOT AUTHORIZED: $1"; fail=1; }
yes() { echo "ok: $1"; }

FIELD=""
getfield() { # KEY ; returns 1 when refused; value in FIELD
  FIELD="$(field_of "$record" "$1")" || { FIELD=""; no "$1 must appear exactly once at the start of a line outside code blocks and comments"; return 1; }
  return 0
}
expect() { # KEY EXPECTED
  getfield "$1" || return 0
  if [ "$FIELD" = "$2" ]; then yes "$1 = $2"; else no "$1 is '$FIELD', expected '$2'"; fi
}
shape() { # KEY REGEX DESCRIPTION
  getfield "$1" || return 0
  if isexact "$FIELD" "$2"; then yes "$1 is $3"; else no "$1 must be $3"; fi
}

# ---------------------------------------------------------------- the staging identity: constants, never the record's say-so
[ "$bundle" = "$STAGING_BUNDLE_ID" ] && yes "the workflow's bundle ID is the staging bundle ID ($STAGING_BUNDLE_ID)" \
  || no "the bundle ID passed by the workflow is '$bundle'; this gate authorizes only $STAGING_BUNDLE_ID"
[ "$bundle" != "$PRODUCTION_BUNDLE_ID" ] || no "the production bundle ID can never be authorized by this gate"

# ---------------------------------------------------------------- the record on this commit
expect G2S-STAGING-STATUS "AUTHORIZED"
expect G2S-STAGING-OPERATION "$OPERATION"
expect G2S-STAGING-BUNDLE-ID "$STAGING_BUNDLE_ID"
expect G2S-STAGING-TEAM-ID "$team"
if getfield G2S-STAGING-APP-APPLE-ID; then
  if ! isexact "$FIELD" "$RE_DIGITS"; then no "G2S-STAGING-APP-APPLE-ID must be the numeric Apple ID of the staging App Store Connect application"
  elif [ "$FIELD" = "$PRODUCTION_APP_APPLE_ID" ]; then no "G2S-STAGING-APP-APPLE-ID is the PRODUCTION application ($PRODUCTION_APP_APPLE_ID); a staging build can never be uploaded to it"
  else yes "G2S-STAGING-APP-APPLE-ID is a staging application ID ($FIELD, not the production one)"; fi
fi
shape G2S-STAGING-CERT-SHA256 "$RE_HEX64" "the recorded SHA-256 of the Apple Distribution certificate (64 lower-case hex characters)"
shape G2S-STAGING-DLC-WALLET-SHA256 "$RE_HEX64" "a SHA-256 (64 lower-case hex characters)"
shape G2S-STAGING-AUTHORIZATION "$RE_URL" "a comment on Issue #54 or #71 (https://github.com/CadenaBitcoin/signer_app/issues/54#issuecomment-<digits>); existence and author are not checked here"
for id in $REQUIRED_DECISIONS; do
  shape "G2S-STAGING-DECISION-$id" "$RE_DECISION" "'Decided by <name> on YYYY-MM-DD'"
done

# The implementation the authorization was given for: a change to any of it needs a new, reviewed authorization.
expect G2S-STAGING-WORKFLOW-BLOB "$(blob "$tools/$WORKFLOW_FILE")"
expect G2S-STAGING-GATE-BLOB "$(blob "$self")"
expect G2S-STAGING-TOOL-BLOBS "$(want_tool_blobs)"

# ---------------------------------------------------------------- the version: the record names exactly what the commit carries
pub="$(git -C "$repo" show "$head:pubspec.yaml" 2>/dev/null | sed -n 's/^version:[[:space:]]*//p' | head -n1 | tr -d '[:space:]')"
if isexact "$pub" "$RE_VERSION"; then
  yes "pubspec.yaml of $head says $pub"
  expect G2S-STAGING-VERSION "$pub"
else
  no "pubspec.yaml of $head has no valid version ('$pub')"
fi

# ---------------------------------------------------------------- the live state, read now from the remote
tip="$(git -C "$repo" ls-remote "$remote" refs/heads/staging 2>/dev/null | awk '$2 == "refs/heads/staging" { print $1 }')"
if git -C "$repo" fetch --quiet --no-tags "$remote" "+refs/heads/development:$DEV_REF" 2>/dev/null; then
  live="$(mktemp "${TMPDIR:-/tmp}/staging-live-record.XXXXXX")"; trap 'rm -f "$live"' EXIT
  if git -C "$repo" show "$DEV_REF:$RECORD_PATH" > "$live" 2>/dev/null; then
    if live_status="$(field_of "$live" G2S-STAGING-STATUS)"; then
      if [ "$live_status" = "AUTHORIZED" ]; then yes "the record on the current tip of development still says AUTHORIZED"
      else no "the record on the current tip of development says '$live_status': the authorization was withdrawn there"; fi
    else
      no "the record on the current tip of development has no single G2S-STAGING-STATUS line: nothing is authorized"
    fi
  else
    no "development has no $RECORD_PATH: nothing is authorized"
  fi
else
  no "the current tip of development could not be read from the remote; signing stays refused"
fi

# ---------------------------------------------------------------- the source: a reviewed promotion, the current tip, development's content
if ! isexact "$tip" "$RE_SHA"; then no "the current tip of staging could not be read from the remote; signing stays refused"
elif [ "$head" = "$tip" ]; then yes "$head is the current tip of staging"
else no "$head is not the current tip of staging ($tip): a re-run of an old run, or a newer promotion, cannot deliver"; fi

parents="$(git -C "$repo" cat-file commit "$head" | awk '/^$/ { h = 1 } !h && /^parent / { n++ } END { print n + 0 }')"
if [ "$parents" -eq 2 ]; then
  yes "$head is a merge commit (two parents), the only thing the branch rules let into staging"
  p2="$(git -C "$repo" cat-file commit "$head" | awk '/^$/ { h = 1 } !h && /^parent / { n++; if (n == 2) print $2 }')"
  if git -C "$repo" rev-parse --verify --quiet "$DEV_REF^{commit}" >/dev/null; then
    if git -C "$repo" merge-base --is-ancestor "$p2" "$DEV_REF" 2>/dev/null; then yes "the merged side $p2 is part of the current development"
    else no "the merged side $p2 is not an ancestor of the current development: this promotion did not come from development"; fi
  else
    no "development could not be fetched: the origin of the merged side cannot be shown"
  fi
  # shellcheck disable=SC2086
  if git -C "$repo" diff --quiet "$p2" "$head" -- $CONTENT_PATHS 2>/dev/null; then yes "the application content of $head equals that of the merged development side $p2"
  else no "the application content of $head differs from the merged development side $p2 ($CONTENT_PATHS): the merge added or changed application content"; fi
else
  no "$head has $parents parent(s); a promotion into staging is a merge commit with exactly two"
fi

if [ "$fail" -eq 0 ]; then
  echo "AUTHORIZED: automatic iOS staging delivery of $pub: ONE signing, verification and upload of the SAME verified IPA to the staging application (no tester assignment, no App Review, no release)"
  exit 0
fi
echo "Signing stays refused. The CTO's written decision and a merged, reviewed record pull request set the lines above (docs/IOS_STAGING_DELIVERY.md section 4)."
exit 1
