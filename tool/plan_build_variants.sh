#!/usr/bin/env bash
# Decides WHICH of the five build variants a run of .github/workflows/build-variants.yml
# executes, and prints the plan as `key=value` lines (appended to $GITHUB_OUTPUT by the
# workflow). It selects; it builds nothing. The build jobs exist once, in the workflow, and
# receive their matrix from this plan, so there is no second copy of any build.
#
#   tool/plan_build_variants.sh EVENT REF [VARIANT [PARENTS [CREATED]]]
#
#   EVENT    GitHub event name: workflow_dispatch | push
#   REF      the full ref (github.ref), e.g. refs/heads/staging. Only a push is decided by it.
#   VARIANT  the selector of a manual run (workflow_dispatch input `variant`): `all` or one
#            variant identifier. It must be empty for a push.
#   PARENTS  number of parents of the pushed commit (tool/commit_parents.sh). A promotion is
#            a pull-request MERGE commit (the protected branches allow only merge commits),
#            so a push needs exactly 2.
#   CREATED  github.event.created of the push: `true` when the push created the branch.
#            Creating a branch is not a promotion, so a push needs `false`.
#
# Supported triggers, and nothing else (anything else exits 2 and runs nothing):
#   push to refs/heads/staging     -> the 2 staging builds
#   push to refs/heads/production  -> the 3 production builds
#   workflow_dispatch              -> `all` (5) or exactly one variant
# There is deliberately no mapping for development, issue branches, tags or pull requests.
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
parents="${4:-}"
created="${5:-}"
[ -n "$event" ] || die "usage: $0 EVENT REF [VARIANT [PARENTS [CREATED]]]"

is_variant_id() {
  local id
  while read -r id _; do
    [ "$id" = "$1" ] && return 0
  done <<EOF
$CATALOGUE
EOF
  return 1
}

# --- trigger -> selection ------------------------------------------------------------------
# This is the ONLY place that maps a trigger to the variants it must run.
expected_env=""   # a push: the one environment its branch may build
expected_count="" # a push: exactly how many variants that is (independent of the catalogue)
case "$event" in
  workflow_dispatch)
    # Manual run: all, or exactly the one variant that was chosen. The group names
    # `staging` and `production` belong to pushes and are not manual selections.
    selection="$input"
    [ -n "$selection" ] || die "a manual run needs a variant"
    [ "$selection" = all ] || is_variant_id "$selection" || die "'$selection' is not a variant (valid: all or a variant identifier)"
    ;;
  push)
    [ -z "$input" ] || die "a push cannot carry a variant selection ('$input')"
    case "$ref" in
      refs/heads/staging)
        selection="staging"
        expected_env="staging"
        expected_count=2
        ;;
      refs/heads/production)
        selection="production"
        expected_env="production"
        expected_count=3
        ;;
      *) die "no variants are defined for a push to '$ref' (only refs/heads/staging and refs/heads/production)" ;;
    esac
    # Creating the branch is not a promotion (the first promotion is the first merge after
    # it). Anything but an explicit `false` fails closed.
    [ "$created" = false ] || die "a push to '$ref' that creates the branch (or does not say) is not a promotion (created='${created:-unknown}')"
    # Defence in depth behind the branch protection: only a pull-request merge commit counts
    # as a promotion. A missing or different parent count fails closed.
    [ "$parents" = 2 ] || die "the pushed commit on '$ref' is not a merge commit (parents='${parents:-unknown}'); a promotion is a pull-request merge"
    ;;
  *) die "unsupported event '$event' (only push and workflow_dispatch)" ;;
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

[ -n "$variants" ] || die "'$selection' selects no variant"

count=0
for _ in $variants; do count=$((count + 1)); done

# A push must select exactly the variants of its own environment, and exactly the expected
# number of them, whatever the catalogue says.
if [ -n "$expected_env" ]; then
  [ "$count" = "$expected_count" ] || die "a push to '$ref' must select exactly $expected_count variants, not $count ($variants)"
  while read -r id _ env _; do
    case " $variants " in
      *" $id "*) [ "$env" = "$expected_env" ] || die "$id ($env) must not be built by a push to '$ref'" ;;
    esac
  done <<EOF
$CATALOGUE
EOF
fi

echo "selection=$selection"
echo "variants=$variants"
echo "count=$count"
echo "has_android=$([ -n "$android_items" ] && echo true || echo false)"
echo "has_ios=$([ -n "$ios_items" ] && echo true || echo false)"
echo "android_matrix={\"include\":[$android_items]}"
echo "ios_matrix={\"include\":[$ios_items]}"
