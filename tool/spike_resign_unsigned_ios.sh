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
# STATUS: not yet run on macOS when written (developed on Linux); the first hosted run is the test.
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
cleanup() {
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
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null 2>&1 || true
identity="$(security find-identity -p codesigning "$keychain" | awk '/Spike Throwaway Signer/ {print $2; exit}')"
if [ -z "$identity" ]; then
  echo "spike: the throwaway identity was not created" >&2
  exit 1
fi
echo "   identity $identity (throwaway, exists only in $keychain)"

sign_one() { codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none "$@"; }

is_apple_signed() { # FILE: already signed by an Apple certificate (not ours, not ad hoc)?
  local info
  info="$(codesign -dvv "$1" 2>&1 || true)"
  [[ "$info" == *"Authority=Software Signing"* || "$info" == *"Authority=Apple"* ]]
}

run_variant() { # VARIANT
  local variant=$1 app="$work/$1/Payload/Runner.app" skipped="" item count=0 ipa="$out/test-$1-NOT-DISTRIBUTABLE.ipa"
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
    if sign_one "$item" >/dev/null 2>&1; then
      count=$((count + 1))
    else
      record "$variant" "codesign accepts $(basename "$item")" FAIL
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
  if sign_one --entitlements "$work/$variant/entitlements.plist" "$app" >/dev/null 2>&1; then
    record "$variant" "codesign signs the app (nested items signed: $count; left unsigned-by-us:${skipped:- none})" PASS
  else
    record "$variant" "codesign signs the app" FAIL
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
