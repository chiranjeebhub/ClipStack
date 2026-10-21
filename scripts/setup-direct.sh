#!/bin/bash
# One-time setup on the Mac that builds the direct download version (scripts/release-direct.sh).
# Safe to run again: it only does the steps that are still missing.
#
#   1. Checks for a "Developer ID Application" signing certificate.
#   2. Creates the Sparkle update signing key (kept in your login keychain) and writes its public
#      half into Resources/Info-Direct.plist.
#   3. Saves your notarization login in the keychain as the "clipstack-notary" profile.
#   4. Checks that the GitHub CLI is signed in, for publishing.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR=build
TEAM_ID=$(sed -n 's/.*DEVELOPMENT_TEAM: \(.*\)/\1/p' project.yml)
NOTARY_PROFILE="${NOTARY_PROFILE:-clipstack-notary}"
MISSING=0

echo "▸ Developer ID certificate"
if security find-identity -v -p codesigning | grep "Developer ID Application" | grep -q "($TEAM_ID)"; then
    echo "  ✓ Found"
else
    MISSING=1
    cat <<MSG
  ✗ Not found. In Xcode open Settings › Accounts, select team $TEAM_ID, click Manage Certificates…,
    then + › Developer ID Application. Only the team's Account Holder can create it.
MSG
fi

if ! command -v xcodegen >/dev/null; then
    echo "▸ Installing XcodeGen"
    brew install xcodegen
fi
echo "▸ Fetching Sparkle"
xcodegen generate --quiet
xcodebuild -resolvePackageDependencies -project Clipstack.xcodeproj -scheme ClipstackDirect \
    -derivedDataPath "$BUILD_DIR/DerivedData" >/dev/null
GENERATE_KEYS=$(find "$BUILD_DIR/DerivedData/SourcePackages/artifacts" -path '*/bin/generate_keys' | head -1)
[[ -x "$GENERATE_KEYS" ]] || { echo "error: Sparkle's generate_keys tool wasn't found"; exit 1; }

echo "▸ Sparkle update key"
# Creates the key the first time and reuses the one in the keychain after that.
"$GENERATE_KEYS" >/dev/null
PUBLIC_KEY=$("$GENERATE_KEYS" -p)
CURRENT=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Resources/Info-Direct.plist)
if [[ "$CURRENT" == "$PUBLIC_KEY" ]]; then
    echo "  ✓ Info-Direct.plist has the public key"
else
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" Resources/Info-Direct.plist
    cat <<MSG
  ✓ Wrote the public key into Resources/Info-Direct.plist. Commit that change.
    Back up the private key now; without it, existing copies can't be updated:
      $GENERATE_KEYS -x ~/Desktop/clipstack-sparkle-private-key
    and keep that file in your password manager, not in the repo.
MSG
fi

echo "▸ Notarization login"
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "  ✓ Keychain profile \"$NOTARY_PROFILE\" works"
else
    cat <<MSG
  Create an app-specific password at https://account.apple.com (Sign-In and Security ›
  App-Specific Passwords), then enter your Apple Account email and that password below.
MSG
    xcrun notarytool store-credentials "$NOTARY_PROFILE" --team-id "$TEAM_ID"
fi

echo "▸ GitHub CLI"
if gh auth status >/dev/null 2>&1; then
    echo "  ✓ Signed in"
else
    MISSING=1
    echo "  ✗ Run: gh auth login"
fi

if [[ $MISSING == 1 ]]; then
    echo "Some steps still need you (see ✗ above). Run this script again afterwards."
    exit 1
fi
echo "✓ Ready. Build a release with scripts/release-direct.sh"
