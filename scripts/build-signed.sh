#!/bin/bash
# Builds Clipstack.app signed with the developer team in project.yml, which iCloud sync needs.
# Requires Xcode signed into that team's Apple Account (Xcode › Settings › Accounts) and XcodeGen
# (installed with Homebrew if missing). On the first run Xcode creates the signing certificate,
# app ID and iCloud container automatically.
#
#   scripts/build-signed.sh             # build into ./build/Clipstack.app
#   scripts/build-signed.sh --install   # also replace /Applications/Clipstack.app and launch it
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
    -project Clipstack.xcodeproj \
    -scheme Clipstack \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    build | (command -v xcpretty >/dev/null && xcpretty || cat)

rm -rf "$BUILD_DIR/Clipstack.app"
cp -R "$BUILD_DIR/DerivedData/Build/Products/Release/Clipstack.app" "$BUILD_DIR/Clipstack.app"
codesign --verify --strict "$BUILD_DIR/Clipstack.app"
echo "✓ Built $BUILD_DIR/Clipstack.app"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e 'quit app "Clipstack"' >/dev/null 2>&1 || true
    sleep 1
    rm -rf /Applications/Clipstack.app
    # Remove the build from before the app was renamed from "Clipboard".
    osascript -e 'quit app id "com.chiranjeebhub.clipboard"' >/dev/null 2>&1 || true
    rm -rf /Applications/Clipboard.app
    # The new signature doesn't match the old Accessibility entry, which would otherwise stay listed
    # as on while not applying. Clearing it lets the app ask again cleanly.
    tccutil reset Accessibility com.chiranjeebhub.clipstack >/dev/null 2>&1 || true
    cp -R "$BUILD_DIR/Clipstack.app" /Applications/
    open /Applications/Clipstack.app
    echo "✓ Installed /Applications/Clipstack.app"
fi
