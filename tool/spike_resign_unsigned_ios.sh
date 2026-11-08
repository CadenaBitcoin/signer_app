#!/usr/bin/env bash
# EXPERIMENT for Issue #71, stage D: does Apple's own `codesign` sign an UNSIGNED Runner.app (the output
# of `flutter build ios --release --no-codesign`) WITHOUT recompiling it, and does the independent
# verifier (tool/verify_ipa.py) agree with Apple about the result?
#
#   tool/spike_resign_unsigned_ios.sh UNSIGNED_RUNNER_APP OUT_DIR
#
# macOS only (needs codesign, security, ditto, zip). It uses a THROWAWAY self-signed identity in a
# THROWAWAY keychain that is deleted on exit. It uses no Apple credential, certificate, provisioning
# profile, App Store Connect key or network (`--timestamp=none`: no timestamp server is contacted), does
# not touch the login keychain or the keychain search list, and produces test IPAs that are not
# installable and must never be uploaded or published. The workflow that runs it uploads nothing.
#
# It runs two variants on fresh copies of the same input and reports both:
#   all                 every Mach-O file is signed with the throwaway identity (`codesign --force`)
#   keep-apple-signed   Mach-O files that already carry an Apple signature (the embedded Swift runtime
#                       back-deployment library) are left exactly as they are
# Whether a device accepts the second variant cannot be learned here: `codesign --verify` does not
# judge team-identity consistency; the kernel does, at load time. See docs/IOS_SIGNING.md 3.2.
#
# Per variant it records (RESULT lines): Apple's `codesign --verify --deep --strict`; our `structure`
# check of what Apple wrote (CodeDirectory, special slots, CMS, DER entitlements, CodeResources); our
# `compare` (the executables are byte-identical to the input apart from the signature, nothing added).
#
# SUCCESS HERE DOES NOT PROVE APPLE DISTRIBUTION COMPATIBILITY: the identity is self-signed, there is no
# provisioning profile, and neither `xcodebuild -exportArchive`, App Store Connect nor a device was
# involved. It shows only that the signing mechanics work on this application's real build output.
#
# STATUS: developed on Linux. The first hosted run (39820242689, 2026-10-22) failed on every codesign call
# and the script discarded codesign's error text. Re-run with the error text visible (42231261892,
# 2026-11-08), it showed the cause: `codesign: The specified item could not be found in the keychain.` for
# every file, even a harmless canary, because the self-signed certificate is not TRUSTED for code signing
# (`security find-identity`: CSSMERR_TP_NOT_TRUSTED, 0 valid identities) and codesign only uses valid
# identities. This version therefore gives the throwaway certificate a code-signing trust setting, see below.
#
# THE TRUST SETTING (the only thing here that lives outside the throwaway keychain; Issue #71):
#   scope     the USER trust-settings domain of the account that runs the job: never the admin or system
#             domain (no `-d`, no sudo), never the login keychain (`-k` names the throwaway keychain).
#             It names this one certificate (by hash), only for the code-signing policy (`-p codeSign`).
#   when      only on a GitHub-hosted runner (RUNNER_ENVIRONMENT=github-hosted: a fresh VM that is destroyed
#             after the job) and only if the untrusted identity was actually unusable. On any other machine
#             the script refuses to change trust settings and stops, so it cannot alter a developer's Mac.
#   cleanup   `security remove-trusted-cert` for that certificate in the EXIT trap, then the keychain and
#             all files are deleted. The workflow checks afterwards that no trust setting remains.
#   risk      while it exists, code signed with the throwaway key counts as validly signed to that user on
#             that runner. The key never leaves the runner (it exists only in $work and the throwaway
#             keychain), the certificate expires after one day, and the job runs only reviewed repository code.
#   limit     each trust command is cut off after 30 seconds: a headless authorization prompt must not hang the job.
set -uo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "spike_resign_unsigned_ios: macOS only (needs codesign and security)." >&2
  exit 2
fi
if [ $# -ne 2 ]; then
  echo "usage: $0 UNSIGNED_RUNNER_APP OUT_DIR" >&2
  exit 2
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unsigned="$1"
out="$2"
[ -f "$unsigned/Info.plist" ] || { echo "spike: $unsigned is not a Runner.app directory" >&2; exit 2; }
mkdir -p "$out"
evidence="$out/evidence.txt"
: >"$evidence"

work="$(mktemp -d)"
keychain="$work/spike.keychain-db"
trust_added=0

run_limited() { # SECONDS OUTFILE COMMAND...: run, and stop it after SECONDS (returns 124 then)
  local secs=$1 outfile=$2 pid i=0
  shift 2
  "$@" >"$outfile" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$secs" ]; do sleep 1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 124
  fi
  wait "$pid"
}

cleanup() {
  if [ "$trust_added" = 1 ]; then
    if run_limited 30 "$work/untrust.txt" security remove-trusted-cert "$work/cert.pem"; then
      echo "spike: removed the code-signing trust setting of the throwaway certificate" >&2
    else
      echo "spike: WARNING the trust setting of the throwaway certificate could not be removed: $(head -2 "$work/untrust.txt" | tr '\n' ' ')" >&2
    fi
  fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

failures=0
record() { # VARIANT CHECK PASS|FAIL [DETAIL]
  echo "RESULT $1 | $2 | $3${4:+ | $4}" | tee -a "$evidence"
  [ "$3" = "PASS" ] || failures=$((failures + 1))
}
verify_py="$root/tool/verify_ipa.py"

password="$(uuidgen)"          # protects only the throwaway keychain; not a secret
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$unsigned/Info.plist")"

echo "== input: what has to be signed (tool/verify_ipa.py analyze-unsigned)"
python3 -I "$verify_py" analyze-unsigned "$unsigned" | tee -a "$evidence"

echo "== 1. throwaway self-signed code-signing identity in a throwaway keychain"
cat >"$work/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Spike Throwaway Signer
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 -config "$work/openssl.cnf" \
  -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/id.p12" -passout "pass:$password" >/dev/null 2>&1
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$work/id.p12" -k "$keychain" -P "$password" -A -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >"$work/partition.txt" 2>&1
partition_rc=$?
identity="$(security find-identity -p codesigning "$keychain" | awk '/Spike Throwaway Signer/ {print $2; exit}')"
if [ -z "$identity" ]; then
  echo "spike: the throwaway identity was not created" >&2
  exit 1
fi
echo "   identity $identity (throwaway, exists only in $keychain)"

sign_one() { codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none "$@"; }

# Diagnostics (Issue #71). The first hosted run (39820242689) failed on every codesign call and discarded
# the error text, so the cause was never seen. Everything printed here is non-sensitive: the identity and
# the keychain are throwaway and the password is never printed. DIAG lines are part of the evidence.
echo "== 1b. diagnostics: can codesign use the throwaway identity at all?"
{
  echo "DIAG set-key-partition-list exit code: $partition_rc"
  head -5 "$work/partition.txt" | sed 's/^/DIAG   /'
  echo "DIAG identities in the throwaway keychain, all (find-identity -p codesigning):"
  security find-identity -p codesigning "$keychain" 2>&1 | sed 's/^/DIAG   /'
  echo "DIAG identities in the throwaway keychain, valid only (find-identity -v -p codesigning):"
  security find-identity -v -p codesigning "$keychain" 2>&1 | sed 's/^/DIAG   /'
  echo "DIAG throwaway keychain settings (show-keychain-info):"
  security show-keychain-info "$keychain" 2>&1 | sed 's/^/DIAG   /'
} | tee -a "$evidence"
# Canary: the same signing call on a harmless file. If it fails like the real files did, the cause is the
# identity or the keychain, not this application's contents.
try_canary() { # LABEL: sets canary_rc and canary_out
  cp /bin/ls "$work/canary"
  canary_out="$(sign_one "$work/canary" 2>&1)"
  canary_rc=$?
  echo "DIAG canary ($1): codesign --force on a copy of /bin/ls: exit code $canary_rc" | tee -a "$evidence"
  printf '%s\n' "$canary_out" | head -5 | sed 's/^/DIAG   /' | tee -a "$evidence"
}
# Control: ad-hoc signing needs no identity. If this fails too, codesign itself is unusable on the runner.
cp /bin/ls "$work/canary-adhoc"
adhoc_out="$(codesign --force --sign - --timestamp=none "$work/canary-adhoc" 2>&1)"
adhoc_rc=$?
echo "DIAG control: ad-hoc codesign (no identity) of a copy of /bin/ls: exit code $adhoc_rc" | tee -a "$evidence"
printf '%s\n' "$adhoc_out" | head -3 | sed 's/^/DIAG   /' | tee -a "$evidence"
[ "$adhoc_rc" -eq 0 ] || record preflight "control: ad-hoc codesign works on the runner" FAIL "$(printf '%s' "$adhoc_out" | tr '\n' ' ' | cut -c1-200)"

try_canary "identity as created, before any trust setting"
if [ "$canary_rc" -ne 0 ]; then
  if [ "${RUNNER_ENVIRONMENT:-}" = "github-hosted" ]; then
    echo "== 1c. give the throwaway certificate a code-signing-only trust setting (user domain, removed on exit)" | tee -a "$evidence"
    echo "DIAG trust settings of the user domain before the change:" | tee -a "$evidence"
    { security dump-trust-settings 2>&1 | head -8; } | sed 's/^/DIAG   /' | tee -a "$evidence"
    run_limited 30 "$work/trust.txt" security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$work/cert.pem"
    trust_rc=$?
    [ "$trust_rc" -ne 0 ] || trust_added=1   # only a trust setting that was really written has to be removed
    echo "DIAG add-trusted-cert (user domain, codeSign policy, throwaway keychain) exit code: $trust_rc" | tee -a "$evidence"
    head -5 "$work/trust.txt" | sed 's/^/DIAG   /' | tee -a "$evidence"
    echo "DIAG trust settings of the user domain after the change:" | tee -a "$evidence"
    { security dump-trust-settings 2>&1 | head -12; } | sed 's/^/DIAG   /' | tee -a "$evidence"
    echo "DIAG valid identities now (find-identity -v -p codesigning):" | tee -a "$evidence"
    security find-identity -v -p codesigning "$keychain" 2>&1 | sed 's/^/DIAG   /' | tee -a "$evidence"
    try_canary "after the trust setting"
  else
    echo "DIAG not changing trust settings: RUNNER_ENVIRONMENT is '${RUNNER_ENVIRONMENT:-unset}', not 'github-hosted'" | tee -a "$evidence"
  fi
fi
if [ "$canary_rc" -eq 0 ]; then
  record preflight "codesign signs a harmless canary with the throwaway identity" PASS
else
  record preflight "codesign signs a harmless canary with the throwaway identity" FAIL "$(printf '%s' "$canary_out" | tr '\n' ' ' | cut -c1-300)"
  echo "spike: codesign cannot use the throwaway identity; the variants were not run." | tee -a "$evidence"
  echo "failures: $failures"
  exit 1
fi

is_apple_signed() { # FILE: already signed by an Apple certificate (not ours, not ad hoc)?
  local info
  info="$(codesign -dvv "$1" 2>&1 || true)"
  [[ "$info" == *"Authority=Software Signing"* || "$info" == *"Authority=Apple"* ]]
}

run_variant() { # VARIANT
  local variant=$1 app="$work/$1/Payload/Runner.app" skipped="" item count=0 ipa="$out/test-$1-NOT-DISTRIBUTABLE.ipa" sign_out
  echo
  echo "== variant: $variant"
  mkdir -p "$work/$variant/Payload"
  ditto "$unsigned" "$app"
  find "$app" -name _CodeSignature -type d -prune -exec rm -rf {} +

  # nested code first (frameworks and dylibs), then the app; no --deep
  while IFS= read -r item; do
    if [ "$variant" = "keep-apple-signed" ] && [ -f "$item" ] && is_apple_signed "$item"; then
      skipped="$skipped $(basename "$item")"
      continue
    fi
    if sign_out="$(sign_one "$item" 2>&1)"; then
      count=$((count + 1))
    else
      record "$variant" "codesign accepts $(basename "$item")" FAIL "$(printf '%s' "$sign_out" | tr '\n' ' ' | cut -c1-300)"
    fi
  done < <(find "$app/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) 2>/dev/null | sort)
  cat >"$work/$variant/entitlements.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>SPIKE00000.$bundle_id</string>
  <key>get-task-allow</key><false/>
  <key>keychain-access-groups</key><array><string>SPIKE00000.$bundle_id</string></array>
</dict></plist>
EOF
  if sign_out="$(sign_one --entitlements "$work/$variant/entitlements.plist" "$app" 2>&1)"; then
    record "$variant" "codesign signs the app (nested items signed: $count; left unsigned-by-us:${skipped:- none})" PASS
  else
    record "$variant" "codesign signs the app" FAIL "$(printf '%s' "$sign_out" | tr '\n' ' ' | cut -c1-300)"
    return
  fi

  # Apple's own verification
  if codesign --verify --deep --strict --verbose=2 "$app" >"$work/$variant/verify.txt" 2>&1; then
    record "$variant" "Apple: codesign --verify --deep --strict" PASS
  else
    record "$variant" "Apple: codesign --verify --deep --strict" FAIL "$(tr '\n' ' ' <"$work/$variant/verify.txt" | cut -c1-200)"
  fi
  codesign -dvv "$app" 2>&1 | sed -n '1,14p' | sed "s/^/    [$variant] /" | tee -a "$evidence"
  codesign -d --entitlements :- "$app" 2>/dev/null | head -20 | sed "s/^/    [$variant] ent: /" | tee -a "$evidence"
  # team identifiers across all Mach-O files: a mixture is reported, not judged
  echo "    [$variant] team identifiers of the signed code:" | tee -a "$evidence"
  find "$app" -type f \( -perm -u+x -o -name '*.dylib' \) 2>/dev/null | sort | while IFS= read -r f; do
    t="$(codesign -dvv "$f" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
    echo "      ${t:-none}  ${f#"$app"/}"
  done | sort | uniq -c | sort -rn | head -20 | tee -a "$evidence"

  # our independent reading of what Apple wrote
  if python3 -I "$verify_py" structure "$app" >"$work/$variant/structure.txt" 2>&1; then
    record "$variant" "verify_ipa structure agrees with Apple (CodeDirectory, slots, CMS, DER entitlements, CodeResources)" PASS
  else
    record "$variant" "verify_ipa structure agrees with Apple" FAIL "$(grep -m3 'FAIL' "$work/$variant/structure.txt" | tr '\n' '|' | cut -c1-300)"
  fi
  sed 's/^/    /' "$work/$variant/structure.txt" | grep -E 'INFO|FAIL|WARN' | head -20 | tee -a "$evidence"

  # the code is the code that was built
  if python3 -I "$verify_py" compare "$unsigned" "$app" >"$work/$variant/compare.txt" 2>&1; then
    record "$variant" "verify_ipa compare: executables identical to the build apart from signatures, nothing added" PASS
  else
    record "$variant" "verify_ipa compare" FAIL "$(grep -m3 'FAIL' "$work/$variant/compare.txt" | tr '\n' '|' | cut -c1-300)"
  fi
  sed 's/^/    /' "$work/$variant/compare.txt" | grep -E 'PASS|FAIL' | tee -a "$evidence"

  # package as a test IPA and read it back
  rm -f "$ipa"
  ( cd "$work/$variant" && zip -qry "$ipa" Payload )
  if python3 -I "$verify_py" structure "$ipa" >/dev/null 2>&1 && python3 -I "$verify_py" compare "$unsigned" "$ipa" >/dev/null 2>&1; then
    record "$variant" "the packaged test IPA passes structure and compare" PASS
  else
    record "$variant" "the packaged test IPA passes structure and compare" FAIL
  fi
}

run_variant all
run_variant keep-apple-signed

echo
echo "== summary"
{
  echo "failures: $failures"
  echo "NOT PROVEN by this experiment: acceptance by Xcode's archive export, by the App Store or by a device;"
  echo "the self-signed identity has no profile and no Apple certificate chain."
} | tee -a "$evidence"
echo "spike: the test IPAs in $out are signed with a throwaway identity and are NOT distributable."
[ "$failures" -eq 0 ]
