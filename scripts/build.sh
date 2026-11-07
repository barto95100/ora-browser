#!/bin/bash
set -euo pipefail

# build.sh — Build a Release Ombre.app and package it into a DMG.
#
# Usage: ./scripts/build.sh
#
# Signs with the team set in project.yml (Apple Development, like Debug).
# Such a build runs on the Macs of that team's account; distributing it to
# others needs a Developer ID certificate and notarization (paid Apple
# Developer Program), not set up yet. Updates (Sparkle) are disabled.
#
# Output: build/Ombre-<version>.dmg

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
cd "$SCRIPT_DIR/.."

VERSION=$(grep "MARKETING_VERSION:" project.yml | sed 's/.*MARKETING_VERSION: //' | tr -d ' ')
ARCHIVE_PATH="build/Ombre.xcarchive"
APP_PATH="build/Ombre.app"
DMG_PATH="build/Ombre-${VERSION}.dmg"

step "Building Ombre ${VERSION}"

rm -rf "$ARCHIVE_PATH" "$APP_PATH" "$DMG_PATH"
mkdir -p build

echo "Generating Xcode project..."
xcodegen

echo "Archiving (this may take a few minutes)..."
archive=(xcodebuild archive
    -scheme Ombre
    -configuration Release
    -destination "platform=macOS"
    -archivePath "$ARCHIVE_PATH"
    -allowProvisioningUpdates)
if command -v xcbeautify >/dev/null 2>&1; then
    "${archive[@]}" 2>&1 | xcbeautify
else
    "${archive[@]}"
fi

[[ -d "$ARCHIVE_PATH/Products/Applications/Ombre.app" ]] || die "Archive failed: no Ombre.app in ${ARCHIVE_PATH}."
ditto "$ARCHIVE_PATH/Products/Applications/Ombre.app" "$APP_PATH"

echo "Verifying the signature..."
codesign --verify --deep --strict "$APP_PATH" || die "Signature verification failed."
SIGNATURE=$(codesign -dvv "$APP_PATH" 2>&1)
grep -m1 "^Authority=" <<<"$SIGNATURE" || true
grep "^TeamIdentifier=" <<<"$SIGNATURE" || true

step "Packaging"

STAGING="build/dmg"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/Ombre.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Ombre" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null \
    || die "DMG creation failed."
rm -rf "$STAGING"

# These copies have the app's bundle id: keep macOS from launching one of
# them (a link, a notification click) instead of the app in use.
"$SCRIPT_DIR/unregister-copies.sh" "$APP_PATH" "$ARCHIVE_PATH" "$STAGING"

green "Build complete: ${DMG_PATH} ($(du -h "$DMG_PATH" | cut -f1))"

# GPL-3.0: the source of every distributed version must stay findable.
yellow "Distributing this DMG? Tag the commit it was built from: git tag v${VERSION} && git push origin v${VERSION}"
