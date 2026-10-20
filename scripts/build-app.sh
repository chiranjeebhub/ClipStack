#!/bin/bash
# Builds Clipboard.app into ./build. Requires macOS 14+ and Xcode 15+ (or the Swift toolchain).
#
#   scripts/build-app.sh            # release build
#   scripts/build-app.sh --debug    # debug build
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG=release
[[ "${1:-}" == "--debug" ]] && CONFIG=debug

BUILD_DIR=build
APP="$BUILD_DIR/Clipboard.app"

echo "▸ Building ($CONFIG)"
swift build -c "$CONFIG" --product Clipboard
swift build -c "$CONFIG" --product MakeIcon
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ Rendering app icon"
rm -rf "$BUILD_DIR/AppIcon.iconset"
"$BIN_DIR/MakeIcon" "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Clipboard" "$APP/Contents/MacOS/Clipboard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS remembers the Accessibility permission between launches of the same build.
codesign --force --sign - "$APP"

echo "✓ Built $APP"
echo "  Run it with: open $APP"
