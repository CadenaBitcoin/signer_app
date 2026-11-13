#!/usr/bin/env bash
# Installs the pinned `age` and `age-keygen` (https://github.com/FiloSottile/age) for the
# retained-artifact steps (docs/RETAINED_ARTIFACTS.md), the same way the workflow installs the
# pinned bundletool: a fixed release URL, a fixed SHA-256 of the release asset, no other source.
#
#   tool/install_age.sh [DIR]      installs into DIR (default: $RUNNER_TEMP/age, else a temp dir)
#                                  and, on GitHub Actions, adds DIR/bin to $GITHUB_PATH.
#
# age is used only to ENCRYPT to public keys (and to decrypt with a one-time key inside the same
# job to prove the round trip). The runner never holds a key that can read the retained artifact.
# To change the version: download the new asset yourself, update AGE_VERSION and the two digests
# below in a reviewed pull request, and run tool/test_retained_artifacts.sh.
set -euo pipefail

AGE_VERSION="1.3.2"
AGE_RELEASE_URL="https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}"
# SHA-256 of the release assets (age-v1.3.2-<os>-<arch>.tar.gz), computed from the assets.
AGE_SHA256_LINUX_AMD64="cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10"
AGE_SHA256_DARWIN_ARM64="e2020b073c44f692685a24d6abc378817eb81ffaaf49fd0531ef8565f767f2f5"

if [ "${1:-}" = "--print-pins" ]; then
  # Read by tool/test_retained_artifacts.sh, so that the pins are checked and not only written.
  echo "AGE_VERSION=$AGE_VERSION"
  echo "AGE_SHA256_LINUX_AMD64=$AGE_SHA256_LINUX_AMD64"
  echo "AGE_SHA256_DARWIN_ARM64=$AGE_SHA256_DARWIN_ARM64"
  exit 0
fi

dest="${1:-${RUNNER_TEMP:-$(mktemp -d)}/age}"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) asset="age-v${AGE_VERSION}-linux-amd64.tar.gz"; want="$AGE_SHA256_LINUX_AMD64" ;;
  Darwin-arm64) asset="age-v${AGE_VERSION}-darwin-arm64.tar.gz"; want="$AGE_SHA256_DARWIN_ARM64" ;;
  *) echo "install_age: no pinned age for $(uname -s)-$(uname -m)" >&2; exit 2 ;;
esac

sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 3 -o "$work/$asset" "$AGE_RELEASE_URL/$asset"
got="$(sha256_of "$work/$asset")"
if [ "$got" != "$want" ]; then
  echo "install_age: $asset has SHA-256 $got, pinned $want. Refusing to use it." >&2
  exit 1
fi
mkdir -p "$dest/bin"
tar -xzf "$work/$asset" -C "$work"
cp "$work/age/age" "$work/age/age-keygen" "$dest/bin/"
chmod 755 "$dest/bin/age" "$dest/bin/age-keygen"
"$dest/bin/age" --version
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$dest/bin" >> "$GITHUB_PATH"
fi
echo "age $AGE_VERSION installed in $dest/bin"
