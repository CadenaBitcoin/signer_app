#!/usr/bin/env bash
# The two pass/fail decisions of the `verdict` job of .github/workflows/build-variants.yml,
# kept in a script so that they are tested (tool/test_release_triggers.sh) and not only read.
#
#   tool/check_verdict.sh results
#       Every REQUIRED job must have the result `success`; every job that was not selected
#       must be `skipped`. Anything else (failure, cancelled, an unexpected skip, a job that
#       ran although it was not selected) fails.
#       Environment: SELECTION, REQUIRED_VARIANTS (space separated), HAS_ANDROID, HAS_IOS,
#                    RESULT_PLAN, RESULT_STATIC, RESULT_REJECT, RESULT_ANDROID, RESULT_IOS
#
#   tool/check_verdict.sh evidence DIR
#       DIR must hold a non-empty <variant>.txt and <variant>.manifest.json for every required
#       variant and no evidence file for any other variant ("exactly the selected builds").
#       (What the manifests say is checked by tool/build_manifest.py verify-dir.)
#       Environment: REQUIRED_VARIANTS
#
#   tool/check_verdict.sh retained DIR
#       Only when the run retains artifacts (Stage 2, docs/RETAINED_ARTIFACTS.md): DIR must hold
#       one non-empty directory retained_<variant>_a<attempt> for every required variant and no
#       other entry.
#       Environment: REQUIRED_VARIANTS, RUN_ATTEMPT
set -euo pipefail

mode="${1:-}"

case "$mode" in
  results)
    echo "selection=${SELECTION:-} required=[${REQUIRED_VARIANTS:-}]"
    echo "plan=${RESULT_PLAN:-} static=${RESULT_STATIC:-} reject=${RESULT_REJECT:-} android=${RESULT_ANDROID:-} ios=${RESULT_IOS:-}"
    fail=0
    need() { # NAME RESULT REQUIRED(true|false)
      if [ "$3" = true ]; then
        [ "$2" = success ] || { echo "::error::$1 is required but its result is '$2'"; fail=1; }
      else
        [ "$2" = skipped ] || { echo "::error::$1 was not selected but its result is '$2'"; fail=1; }
      fi
    }
    need plan "${RESULT_PLAN:-}" true
    need static "${RESULT_STATIC:-}" true
    need reject "${RESULT_REJECT:-}" "${HAS_ANDROID:-false}"
    need android "${RESULT_ANDROID:-}" "${HAS_ANDROID:-false}"
    need ios "${RESULT_IOS:-}" "${HAS_IOS:-false}"
    if [ "$fail" -ne 0 ]; then
      echo "::error::A required job failed, was cancelled or did not run; the selected variants are NOT proven."
      exit 1
    fi
    if [ -z "${REQUIRED_VARIANTS:-}" ]; then
      echo "::error::The plan selected no variant."
      exit 1
    fi
    ;;
  evidence)
    dir="${2:-}"
    [ -d "$dir" ] || { echo "::error::No evidence directory '$dir'"; exit 1; }
    for v in ${REQUIRED_VARIANTS:-}; do
      for f in "$v.txt" "$v.manifest.json"; do
        if [ ! -s "$dir/$f" ]; then
          echo "::error::Missing verification evidence $f"
          exit 1
        fi
      done
    done
    for f in "$dir"/*; do
      [ -e "$f" ] || continue
      name="$(basename "$f")"
      case "$name" in
        *.manifest.json) base="${name%.manifest.json}" ;;
        *.txt) base="${name%.txt}" ;;
        *) echo "::error::Unexpected evidence file $name"; exit 1 ;;
      esac
      case " ${REQUIRED_VARIANTS:-} " in
        *" $base "*) ;;
        *) echo "::error::Evidence for a variant that was not selected: $name"; exit 1 ;;
      esac
    done
    ;;
  retained)
    # Retained bundles (Stage 2): DIR holds one directory retained_<variant>_a<attempt> for every
    # required variant and nothing else. What a bundle says is checked by
    # tool/retain_artifact.py verify.
    # Environment: REQUIRED_VARIANTS, RUN_ATTEMPT
    dir="${2:-}"
    [ -d "$dir" ] || { echo "::error::No retained directory '$dir'"; exit 1; }
    [ -n "${RUN_ATTEMPT:-}" ] || { echo "::error::RUN_ATTEMPT is not set"; exit 1; }
    for v in ${REQUIRED_VARIANTS:-}; do
      d="$dir/retained_${v}_a${RUN_ATTEMPT}"
      if [ ! -d "$d" ] || [ -z "$(ls -A "$d" 2>/dev/null)" ]; then
        echo "::error::Missing retained artifact for $v ($d)"
        exit 1
      fi
    done
    for d in "$dir"/*; do
      [ -e "$d" ] || continue
      name="$(basename "$d")"
      ok=false
      for v in ${REQUIRED_VARIANTS:-}; do
        [ "$name" = "retained_${v}_a${RUN_ATTEMPT}" ] && ok=true
      done
      if [ "$ok" != true ] || [ ! -d "$d" ]; then
        echo "::error::Unexpected retained entry $name (not a required variant of this attempt)"
        exit 1
      fi
    done
    ;;
  *)
    echo "usage: $0 results | evidence DIR | retained DIR" >&2
    exit 2
    ;;
esac
