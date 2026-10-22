#!/usr/bin/env bash
# SPIKE for Issue #71, stage D: does Apple's own `codesign` sign an UNSIGNED Runner.app (the output of
# `flutter build ios --release --no-codesign`) WITHOUT recompiling it, and can the result be packaged
# as an IPA whose code is still byte-identical to the build job's output?
#
#   tool/spike_resign_unsigned_ios.sh UNSIGNED_RUNNER_APP OUT_DIR
#
# macOS only (needs codesign, security, ditto). It uses a THROWAWAY self-signed identity created in a
# THROWAWAY keychain that is deleted on exit. It uses no Apple credential, certificate, provisioning
# profile or network, does not touch the login keychain or the keychain search list, and its output
# (OUT_DIR/spike-NOT-DISTRIBUTABLE.ipa) is not installable and must never be uploaded anywhere.
#
# STATUS: written for the authorized spike, NOT YET RUN ON macOS (it was developed on Linux, where
# `codesign` does not exist; docs/IOS_SIGNING.md records what was verified instead). Read it, run it
# on a Mac or in an authorized throwaway workflow, and report what it prints.
#
# What a pass shows: every Mach-O file accepted a signature, `codesign --verify --deep --strict`
# accepts the bundle, and tool/verify_ipa.py compare finds the signed bundle to be the unsigned one plus
# signatures only. What it does NOT show: that `xcodebuild -exportArchive`, a real Apple Distribution
# identity, a provisioning profile or App Store Connect accept the result (they need Apple assets).
set -euo pipefail

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

work="$(mktemp -d)"
keychain="$work/spike.keychain-db"
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

password="$(uuidgen)"          # protects only the throwaway keychain; not a secret
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$unsigned/Info.plist")"

echo "== 1. throwaway self-signed code-signing identity"
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
[ -n "$identity" ] || { echo "spike: the throwaway identity was not created" >&2; exit 1; }
echo "   identity $identity (throwaway)"

echo "== 2. copy the unsigned bundle and clear old signatures"
mkdir -p "$work/Payload"
ditto "$unsigned" "$work/Payload/Runner.app"
app="$work/Payload/Runner.app"
find "$app" -name _CodeSignature -type d -prune -exec rm -rf {} +

echo "== 3. sign nested code first, then the app (codesign --force replaces ad-hoc and foreign signatures)"
sign_one() { codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none "$@"; }
count=0
if [ -d "$app/Frameworks" ]; then
  while IFS= read -r item; do
    sign_one "$item"
    count=$((count + 1))
  done < <(find "$app/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) | sort)
fi
cat >"$work/entitlements.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>SPIKE00000.$bundle_id</string>
  <key>get-task-allow</key><false/>
</dict></plist>
EOF
sign_one --entitlements "$work/entitlements.plist" "$app"
echo "   signed $count nested item(s) and the app"

echo "== 4. Apple's own verification"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dvv "$app" 2>&1 | sed -n '1,12p'

echo "== 5. is it still the same code? (tool/verify_ipa.py compare)"
python3 -I "$root/tool/verify_ipa.py" compare "$unsigned" "$app"

echo "== 6. package"
ipa="$out/spike-NOT-DISTRIBUTABLE.ipa"
rm -f "$ipa"
( cd "$work" && zip -qry "$ipa" Payload )
python3 -I "$root/tool/verify_ipa.py" compare "$unsigned" "$ipa"
echo
echo "spike: done. $ipa is signed with a throwaway identity, has no provisioning profile and is NOT distributable."
echo "spike: it does not show that Xcode's archive export or App Store Connect accept an unsigned archive (needs Apple assets)."
