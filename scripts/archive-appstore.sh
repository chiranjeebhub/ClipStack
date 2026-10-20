#!/bin/bash
# Archives Clipstack for the Mac App Store and exports a signed .pkg, using the team in project.yml.
# Needs the same setup as build-signed.sh, plus an app record for com.chiranjeebhub.clipstack in
# App Store Connect before uploading.
#
#   scripts/archive-appstore.sh            # archive and export build/AppStore/Clipstack.pkg
#   scripts/archive-appstore.sh --upload   # archive and upload the build to App Store Connect
#
# Every upload needs a new build number. It defaults to the current time; set BUILD_NUMBER to override.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR=build
ARCHIVE="$BUILD_DIR/Clipstack.xcarchive"
EXPORT_DIR="$BUILD_DIR/AppStore"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
TEAM_ID=$(sed -n 's/.*DEVELOPMENT_TEAM: \(.*\)/\1/p' project.yml)

DESTINATION=export
[[ "${1:-}" == "--upload" ]] && DESTINATION=upload

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

echo "▸ Archiving build $BUILD_NUMBER"
rm -rf "$ARCHIVE"
xcodebuild \
    -project Clipstack.xcodeproj \
    -scheme Clipstack \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    archive | (command -v xcpretty >/dev/null && xcpretty || cat)

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>$DESTINATION</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

echo "▸ Exporting ($DESTINATION)"
rm -rf "$EXPORT_DIR"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates

if [[ "$DESTINATION" == upload ]]; then
    echo "✓ Uploaded build $BUILD_NUMBER to App Store Connect. It appears there after processing."
else
    echo "✓ Exported $EXPORT_DIR (build $BUILD_NUMBER)"
fi
