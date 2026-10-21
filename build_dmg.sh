#!/usr/bin/env bash
# Build dist/MacEditor-<version>.dmg (macOS only).
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || echo 1.0.0)

# Universal build needs a toolchain that can target both archs; fall back to native.
if command -v lipo >/dev/null && UNIVERSAL=1 ./build_app.sh; then
  echo "Built universal app"
else
  echo "Universal build unavailable, building native arch"
  UNIVERSAL=0 ./build_app.sh
fi

STAGE=build/dmg-stage
DMG=dist/MacEditor-$VERSION.dmg
rm -rf "$STAGE" && mkdir -p "$STAGE" dist
cp -R build/MacEditor.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "MacEditor $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Created $DMG"
