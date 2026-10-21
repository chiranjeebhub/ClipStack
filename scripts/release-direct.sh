#!/bin/bash
# Builds the direct download version of Clipstack: signed with Developer ID, notarized by Apple and
# packaged as a DMG. With --publish it also releases it: a GitHub release with the DMG and the Sparkle
# appcast (so installed copies update themselves), and an updated Homebrew cask.
# Run scripts/setup-direct.sh once first.
#
#   scripts/release-direct.sh             # build/Direct/Clipstack-<version>.dmg, notarized
#   scripts/release-direct.sh --publish   # also publish it
#
# The version comes from MARKETING_VERSION in project.yml and each release needs a new one.
# Set RELEASE_NOTES to describe the release on GitHub.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR=build
OUT_DIR="$BUILD_DIR/Direct"
ARCHIVE="$BUILD_DIR/ClipstackDirect.xcarchive"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
TEAM_ID=$(sed -n 's/.*DEVELOPMENT_TEAM: \(.*\)/\1/p' project.yml)
NOTARY_PROFILE="${NOTARY_PROFILE:-clipstack-notary}"
# Every release carries appcast.xml, so the feed URL in Info-Direct.plist
# (releases/latest/download/appcast.xml) always serves the newest one.
REPO=chiranjeebhub/ClipStack
TAP_REPO=chiranjeebhub/homebrew-tap
TAG="v$VERSION"
DMG="$OUT_DIR/Clipstack-$VERSION.dmg"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/Clipstack-$VERSION.dmg"

PUBLISH=false
[[ "${1:-}" == "--publish" ]] && PUBLISH=true

if grep -q SPARKLE_PUBLIC_KEY_NOT_SET Resources/Info-Direct.plist; then
    echo "error: the Sparkle public key isn't set. Run scripts/setup-direct.sh first."
    exit 1
fi
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | awk '{print $2}')
if [[ -z "$IDENTITY" ]]; then
    echo "error: no Developer ID Application certificate for team $TEAM_ID. Run scripts/setup-direct.sh."
    exit 1
fi
if $PUBLISH && gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    echo "error: $TAG is already released. Raise MARKETING_VERSION in project.yml first."
    exit 1
fi

# Submits a file to Apple's notary service and waits for the result.
notarize() {
    local file="$1" result="$BUILD_DIR/notary-result.json"
    echo "▸ Notarizing $(basename "$file") (usually a few minutes)"
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$result"
    local status id
    status=$(plutil -extract status raw -o - "$result")
    if [[ "$status" != "Accepted" ]]; then
        id=$(plutil -extract id raw -o - "$result")
        echo "error: notarization returned \"$status\". Apple's log:"
        xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE"
        exit 1
    fi
}

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

echo "▸ Archiving $VERSION ($BUILD_NUMBER)"
rm -rf "$ARCHIVE"
xcodebuild \
    -project Clipstack.xcodeproj \
    -scheme ClipstackDirect \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    archive | (command -v xcpretty >/dev/null && xcpretty || cat)

cat > "$BUILD_DIR/ExportOptions-Direct.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>iCloudContainerEnvironment</key>
    <string>Production</string>
</dict>
</plist>
PLIST

echo "▸ Exporting with Developer ID"
rm -rf "$OUT_DIR"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions-Direct.plist" \
    -exportPath "$OUT_DIR" \
    -allowProvisioningUpdates
APP="$OUT_DIR/Clipstack.app"
codesign --verify --deep --strict "$APP"

# The app is notarized and stapled on its own first, so it also opens offline once copied out of the DMG.
ditto -c -k --keepParent "$APP" "$OUT_DIR/Clipstack.zip"
notarize "$OUT_DIR/Clipstack.zip"
xcrun stapler staple "$APP"
rm "$OUT_DIR/Clipstack.zip"

echo "▸ Packaging $(basename "$DMG")"
STAGING="$OUT_DIR/dmg"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Clipstack" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

echo "▸ Checking Gatekeeper accepts it"
spctl --assess --type execute --verbose "$APP"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "✓ Built $DMG"

$PUBLISH || exit 0

echo "▸ Updating the Sparkle appcast"
GENERATE_APPCAST=$(find "$BUILD_DIR/DerivedData/SourcePackages/artifacts" -path '*/bin/generate_appcast' | head -1)
FEED_DIR="$BUILD_DIR/appcast"
rm -rf "$FEED_DIR"
mkdir -p "$FEED_DIR"
# Starts from the latest release's feed, so earlier versions stay listed.
gh release download -R "$REPO" --pattern appcast.xml --dir "$FEED_DIR" 2>/dev/null || true
cp "$DMG" "$FEED_DIR/"
# Signs the DMG with the key in the keychain.
"$GENERATE_APPCAST" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --link "https://github.com/$REPO" "$FEED_DIR"

echo "▸ Publishing GitHub release $TAG"
gh release create "$TAG" "$DMG" "$FEED_DIR/appcast.xml" -R "$REPO" --target main \
    --title "Clipstack $VERSION" --notes "${RELEASE_NOTES:-Clipstack $VERSION}"

echo "▸ Updating the Homebrew cask"
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
TAP="$BUILD_DIR/homebrew-tap"
rm -rf "$TAP"
gh repo clone "$TAP_REPO" "$TAP" -- --quiet
mkdir -p "$TAP/Casks"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" packaging/clipstack.rb > "$TAP/Casks/clipstack.rb"
git -C "$TAP" add -A
git -C "$TAP" commit --quiet -m "clipstack $VERSION"
git -C "$TAP" push --quiet

echo "✓ Released Clipstack $VERSION"
echo "  Download: $DOWNLOAD_URL"
echo "  Homebrew: brew install --cask chiranjeebhub/tap/clipstack"
