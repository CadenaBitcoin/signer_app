#!/usr/bin/env bash
# Sourced by tool/test_retained_artifacts.sh and tool/test_resign_android_aab.sh: provides age for the tests.
# Needs $tmp (a scratch directory) and the callers' bad() / pass / failed. Sets AGE_BIN, AGE_KEYGEN and
# real_age. The real age is used when it is on PATH; otherwise a labelled STUB stands in (the age header
# plus a copy: it tests the logic, not the cryptography), unless CADENA_REQUIRE_AGE=1, which turns a
# missing age into a failure (CI sets it).
# ---- age: the real one if present, else a labelled stub ---------------------------------------
AGE_BIN="$(command -v age || true)"
AGE_KEYGEN="$(command -v age-keygen || true)"
real_age=false
if [ -n "$AGE_BIN" ] && [ -n "$AGE_KEYGEN" ]; then
  real_age=true
  echo "using the real age: $("$AGE_BIN" --version 2>&1 | head -n1)"
elif [ "${CADENA_REQUIRE_AGE:-}" = 1 ]; then
  bad "age and age-keygen are required (CADENA_REQUIRE_AGE=1) but are not on PATH"
  echo; echo "$pass passed, $failed failed"; exit 1
else
  echo "NOTE: age is not installed; a STUB stands in. This tests the logic, not the cryptography."
  mkdir -p "$tmp/stub"
  cat >"$tmp/stub/age-keygen" <<'EOF'
#!/usr/bin/env bash
# TEST STUB, not cryptography.
[ "$1" = -o ] || exit 2
pub="age1$(head -c 4000 /dev/urandom | LC_ALL=C tr -dc 'qpzry9x8gf2tvdw0s3jn54khce6mua7l' | head -c 58)"
printf '# created: stub\n# public key: %s\nAGE-SECRET-KEY-1STUBSTUBSTUBSTUB\n' "$pub" >"$2"
EOF
  cat >"$tmp/stub/age" <<'EOF'
#!/usr/bin/env bash
# TEST STUB, not cryptography: "encryption" is the age header plus a copy; it records its arguments.
mode=enc; out=""; ident=""; rf=""; r=""
while [ $# -gt 1 ]; do
  case "$1" in
    -d) mode=dec; shift ;;
    -o) out="$2"; shift 2 ;;
    -i) ident="$2"; shift 2 ;;
    -R) rf="$2"; shift 2 ;;
    -r) r="$r $2"; shift 2 ;;
    --version) echo "age stub"; exit 0 ;;
    *) shift ;;
  esac
done
in="$1"
[ -n "${AGE_STUB_LOG:-}" ] && echo "$mode R=$rf r=$r" >>"$AGE_STUB_LOG"
if [ "$mode" = enc ]; then
  { printf 'age-encryption.org/v1\n'; cat "$in"; } >"$out"
else
  [ -f "$ident" ] || exit 1
  head -c 22 "$in" | grep -q '^age-encryption.org/v1' || exit 1
  tail -c +23 "$in" >"$out"
fi
EOF
  chmod +x "$tmp/stub/age" "$tmp/stub/age-keygen"
  AGE_BIN="$tmp/stub/age"; AGE_KEYGEN="$tmp/stub/age-keygen"
  export AGE_STUB_LOG="$tmp/stub.log"
fi

