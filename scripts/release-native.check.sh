#!/bin/bash
# Self-check for release-native.sh, no Xcode needed: a fake app stands in for the build.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -o 'MARKETING_VERSION = [^;]*' CatNotch.xcodeproj/project.pbxproj | sort -u | sed 's/.*= //')

# A mismatched tag fails and builds nothing.
rm -rf build/release
if scripts/release-native.sh 0.0.0-mismatch 2>/dev/null; then echo "FAIL: mismatched tag passed"; exit 1; fi
[ ! -e build/release/latest-mac.yml ] || { echo "FAIL: mismatched tag staged files"; exit 1; }

# A matching tag stages the legacy-named zip, the dmg, and a feed with the zip's sha512.
FAKE=$(mktemp -d)/CatNotch.app
mkdir -p "$FAKE/Contents" && echo fake > "$FAKE/Contents/Info.plist"
APP="$FAKE" scripts/release-native.sh "$VERSION" >/dev/null
for f in "CatNotch-$VERSION-universal-mac.zip" CatNotch.dmg latest-mac.yml; do
  [ -s "build/release/$f" ] || { echo "FAIL: missing build/release/$f"; exit 1; }
done
[ "$(unzip -Z1 "build/release/CatNotch-$VERSION-universal-mac.zip" | grep -c "^CatNotch.app/Contents/")" -gt 0 ] || { echo "FAIL: CatNotch.app not at the zip root"; exit 1; }
SHA=$(openssl dgst -sha512 -binary "build/release/CatNotch-$VERSION-universal-mac.zip" | base64 | tr -d '\n')
[ "$(grep -c "sha512: $SHA" build/release/latest-mac.yml)" = 2 ] || { echo "FAIL: sha512 not in feed"; exit 1; }
grep -q "^version: $VERSION$" build/release/latest-mac.yml || { echo "FAIL: version not in feed"; exit 1; }
rm -rf build/release
echo "release-native checks passed"
