#!/bin/bash
# Builds the native app and stages a Release in build/release/ for tag $1 (no v prefix):
#   CatNotch-VERSION-universal-mac.zip  the Bridge release name 1.0.x apps look for (arm64 content)
#   latest-mac.yml                      the feed 1.0.x apps read (electron-updater format)
#   CatNotch.dmg                        stable name for the README download link
# Publishing is the workflow's job, so this doubles as the dry run.
# CHECK_ONLY=1 stops after the tag check.
# APP=/path/CatNotch.app skips the xcodebuild step (used by the check script).
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: release-native.sh TAG}"
PROJECT=CatNotch.xcodeproj
VERSION=$(grep -o 'MARKETING_VERSION = [^;]*' "$PROJECT/project.pbxproj" | sort -u | sed 's/.*= //')
if [ "$(echo "$VERSION" | wc -l)" -ne 1 ] || [ "$VERSION" != "$TAG" ]; then
  echo "Tag $TAG does not match the project version $VERSION" >&2
  exit 1
fi
[ -z "${CHECK_ONLY:-}" ] || exit 0 # the workflow runs this first, before tests and the build

OUT=build/release
rm -rf "$OUT" && mkdir -p "$OUT"
if [ -z "${APP:-}" ]; then
  scripts/build-adapter.sh
  xcodebuild build -project "$PROJECT" -scheme CatNotch -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/native
  APP=build/native/Build/Products/Release/CatNotch.app
  # The Xcode phase only warns when the adapter is missing; a Release must not ship with now playing off.
  [ -d "$APP/Contents/Resources/mediaremote" ] || { echo "$APP has no mediaremote adapter" >&2; exit 1; }
fi

ZIP="CatNotch-$VERSION-universal-mac.zip"
ditto -c -k --keepParent "$APP" "$OUT/$ZIP"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/CatNotch.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname CatNotch -srcfolder "$STAGE" -ov -format UDZO "$OUT/CatNotch.dmg" >/dev/null
rm -rf "$STAGE"

SHA=$(openssl dgst -sha512 -binary "$OUT/$ZIP" | base64 | tr -d '\n')
SIZE=$(stat -f%z "$OUT/$ZIP")
cat > "$OUT/latest-mac.yml" <<YML
version: $VERSION
files:
  - url: $ZIP
    sha512: $SHA
    size: $SIZE
path: $ZIP
sha512: $SHA
releaseDate: '$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'
YML
echo "Staged $OUT: $ZIP, CatNotch.dmg, latest-mac.yml"
