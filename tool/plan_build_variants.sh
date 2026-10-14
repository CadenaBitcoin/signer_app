#!/usr/bin/env bash
# Decides WHICH of the five build variants a run of .github/workflows/build-variants.yml
# executes, and prints the plan as `key=value` lines (appended to $GITHUB_OUTPUT by the
# workflow). It selects; it builds nothing. The build jobs exist once, in the workflow, and
# receive their matrix from this plan, so there is no second copy of any build.
#
#   tool/plan_build_variants.sh EVENT REF [VARIANT]
#
#   EVENT    GitHub event name: workflow_dispatch | push
#   REF      branch name (github.ref_name)
#   VARIANT  the selector of a manual run (workflow_dispatch input `variant`)
#
# Output keys: selection, variants (space separated), count, has_android, has_ios,
# android_matrix, ios_matrix (JSON for `matrix: fromJSON(...)`).
#
# The variant identifiers are the single naming of a variant everywhere: the selector, the
# job name, the evidence file name (evidence/<variant>.txt).
set -euo pipefail

# id platform environment kind flutter-build-subcommand
CATALOGUE='android-staging-apk android staging apk apk
ios-staging ios staging app ios
android-production-apk android production apk apk
android-production-aab android production aab appbundle
ios-production ios production app ios'

die() { echo "plan_build_variants: $*" >&2; exit 2; }

event="${1:-}"
ref="${2:-}"
input="${3:-}"
[ -n "$event" ] || die "usage: $0 EVENT REF [VARIANT]"

# --- trigger -> selection ------------------------------------------------------------------
# This is the ONLY place that maps a trigger to the variants it must run.
case "$event" in
  workflow_dispatch)
    # Manual run: exactly the variant that was chosen, or all.
    selection="$input"
    [ -n "$selection" ] || die "a manual run needs a variant"
    ;;
  push)
    case "$ref" in
      # TEMPORARY testing triggers, to establish the five-build baseline: every variant.
      staging | issue/*) selection="all" ;;
      # Eventual architecture (not enabled yet; change the two lines above, and the
      # `on.push.branches` of the workflow, when the baseline is established):
      #   staging)    selection="staging"     # merge into staging    -> the 2 staging builds
      #   production) selection="production"  # merge into production -> the 3 production builds
      *) die "no variants are defined for a push to '$ref'" ;;
    esac
    ;;
  *) die "unsupported event '$event'" ;;
esac

# --- selection -> variants -----------------------------------------------------------------
variants=""
android_items=""
ios_items=""
while read -r id platform env kind sub; do
  case "$selection" in
    all | "$env" | "$id") ;;
    *) continue ;;
  esac
  variants="${variants:+$variants }$id"
  if [ "$platform" = android ]; then
    item="{\"variant\":\"$id\",\"env\":\"$env\",\"kind\":\"$kind\",\"flutter_command\":\"$sub\"}"
    android_items="${android_items:+$android_items,}$item"
  else
    if [ "$env" = staging ]; then other=production; else other=staging; fi
    item="{\"variant\":\"$id\",\"env\":\"$env\",\"other\":\"$other\"}"
    ios_items="${ios_items:+$ios_items,}$item"
  fi
done <<EOF
$CATALOGUE
EOF

[ -n "$variants" ] || die "'$selection' selects no variant (valid: all, staging, production, or one of: $(printf '%s\n' "$CATALOGUE" | while read -r id _; do printf '%s ' "$id"; done))"

count=0
for _ in $variants; do count=$((count + 1)); done

echo "selection=$selection"
echo "variants=$variants"
echo "count=$count"
echo "has_android=$([ -n "$android_items" ] && echo true || echo false)"
echo "has_ios=$([ -n "$ios_items" ] && echo true || echo false)"
echo "android_matrix={\"include\":[$android_items]}"
echo "ios_matrix={\"include\":[$ios_items]}"
