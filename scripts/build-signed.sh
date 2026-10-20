#!/bin/bash
# Builds Clipboard.app signed with the developer team in project.yml, which iCloud sync needs.
# Requires Xcode signed into that team's Apple Account (Xcode › Settings › Accounts) and XcodeGen
# (installed with Homebrew if missing). On the first run Xcode creates the signing certificate,
# app ID and iCloud container automatically.
#
#   scripts/build-signed.sh             # build into ./build/Clipboard.app
#   scripts/build-signed.sh --install   # also replace /Applications/Clipboard.app and launch it
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR=build

if ! command -v xcodegen >/dev/null; then
    echo "▸ Installing XcodeGen"
    brew install xcodegen
fi

echo "▸ Rendering app icon"
swift build -c release --product MakeIcon
BIN_DIR="$(swift build -c release --show-bin-path)"
rm -rf "$BUILD_DIR/AppIcon.iconset"
"$BIN_DIR/MakeIcon" "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"

echo "▸ Generating Xcode project"
xcodegen generate --quiet

echo "▸ Building (signed)"
xcodebuild \
    -project Clipboard.xcodeproj \
    -scheme Clipboard \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -allowProvisioningUpdates \
    build | (command -v xcpretty >/dev/null && xcpretty || cat)

rm -rf "$BUILD_DIR/Clipboard.app"
cp -R "$BUILD_DIR/DerivedData/Build/Products/Release/Clipboard.app" "$BUILD_DIR/Clipboard.app"
codesign --verify --strict "$BUILD_DIR/Clipboard.app"
echo "✓ Built $BUILD_DIR/Clipboard.app"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e 'quit app "Clipboard"' >/dev/null 2>&1 || true
    sleep 1
    rm -rf /Applications/Clipboard.app
    cp -R "$BUILD_DIR/Clipboard.app" /Applications/
    open /Applications/Clipboard.app
    echo "✓ Installed /Applications/Clipboard.app"
fi
