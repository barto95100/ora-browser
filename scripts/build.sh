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
# Output: build/Release.noindex/Ombre-<version>.dmg, and nothing else: the
# archive and the app copies are deleted once the DMG is made. Everything is
# built in a .noindex folder, which Spotlight skips: it would otherwise
# register these copies with Launch Services (same bundle id as the app in
# use), and a link or a notification click could launch one of them.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
cd "$SCRIPT_DIR/.."

VERSION=$(grep "MARKETING_VERSION:" project.yml | sed 's/.*MARKETING_VERSION: //' | tr -d ' ')
# The commit, in the app's Info.plist (OmbreCommit), "+" if the tree had changes.
COMMIT=$(git rev-parse --short HEAD)
git diff --quiet HEAD -- || COMMIT="${COMMIT}+"
OUTPUT="build/Release.noindex"
WORK="$OUTPUT/work"
ARCHIVE_PATH="$WORK/Ombre.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Ombre.app"
STAGING="$WORK/dmg"
DMG_PATH="$OUTPUT/Ombre-${VERSION}.dmg"

# Even when a step fails: unregister the copies, then delete them.
cleanup() {
    "$SCRIPT_DIR/unregister-copies.sh" "$WORK"
    rm -rf "$WORK"
}
trap cleanup EXIT

step "Building Ombre ${VERSION} (${COMMIT})"

rm -rf "$WORK" "$DMG_PATH"
mkdir -p "$WORK"

echo "Generating Xcode project..."
xcodegen

echo "Archiving (this may take a few minutes)..."
archive=(xcodebuild archive
    -scheme Ombre
    -configuration Release
    -destination "platform=macOS"
    -archivePath "$ARCHIVE_PATH"
    -allowProvisioningUpdates
    OMBRE_GIT_COMMIT="$COMMIT")
if command -v xcbeautify >/dev/null 2>&1; then
    "${archive[@]}" 2>&1 | xcbeautify
else
    "${archive[@]}"
fi

[[ -d "$APP_PATH" ]] || die "Archive failed: no Ombre.app in ${ARCHIVE_PATH}."

echo "Verifying the signature..."
codesign --verify --deep --strict "$APP_PATH" || die "Signature verification failed."
SIGNATURE=$(codesign -dvv "$APP_PATH" 2>&1)
grep -m1 "^Authority=" <<<"$SIGNATURE" || true
grep "^TeamIdentifier=" <<<"$SIGNATURE" || true

step "Packaging"

mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/Ombre.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Ombre" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null \
    || die "DMG creation failed."
green "Build complete: ${DMG_PATH} ($(du -h "$DMG_PATH" | cut -f1))"

# GPL-3.0: the source of every distributed version must stay findable.
yellow "Distributing this DMG? Tag the commit it was built from: git tag v${VERSION} && git push origin v${VERSION}"
