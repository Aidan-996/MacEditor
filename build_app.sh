#!/usr/bin/env bash
# Build MacEditor.app on macOS 13+ (requires Xcode or Command Line Tools with Swift 5.9+).
# Usage: ./build_app.sh            (native arch, release)
#        UNIVERSAL=1 ./build_app.sh (arm64 + x86_64, needs full Xcode)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MacEditor.app
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacEditor
else
  swift build -c release
  BIN=$(swift build -c release --show-bin-path)/MacEditor
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacEditor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# App icon: Resources/AppIcon.png -> AppIcon.icns (best effort; never fails the build)
make_icon() {
  local src=Resources/AppIcon.png set=build/AppIcon.iconset
  [[ -f "$src" ]] && command -v sips >/dev/null && command -v iconutil >/dev/null || return 1
  rm -rf "$set" && mkdir -p "$set"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$src" --out "$set/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$src" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$set" -o "$APP/Contents/Resources/AppIcon.icns"
}
make_icon || echo "warning: icon generation skipped"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "warning: ad-hoc codesign failed (app still runs locally)"

echo "Built $APP"
echo "Run: open $APP"
