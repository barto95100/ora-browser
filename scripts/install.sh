#!/bin/bash
set -euo pipefail

# install.sh — Build the Release app and install it in /Applications.
#
# Usage: ./scripts/install.sh
#
# For using Ombre day to day: run it again after new changes are merged
# (from an up-to-date main). Quit the installed Ombre first: the script
# never replaces, nor quits, a running app. The Debug app (Xcode) is a
# separate app (com.barto95100.ora.dev): its data, passwords and settings
# are its own, and it is left alone.
#
# The installed version: defaults read /Applications/Ombre.app/Contents/Info.plist OmbreCommit

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
cd "$SCRIPT_DIR/.."

# Another folder only to try the script (a .noindex one, see build.sh).
INSTALL_DIR="${OMBRE_INSTALL_DIR:-/Applications}"
INSTALLED="${INSTALL_DIR}/Ombre.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

is_running() {
    pgrep -qf "^${INSTALLED}/Contents/MacOS/Ombre"
}

is_running && die "Ombre is open (${INSTALLED}): quit it, then run this again."

branch=$(git branch --show-current)
[[ "$branch" == "main" ]] || yellow "Not on main (${branch}): this branch's version will be installed."

"$SCRIPT_DIR/build.sh"

VERSION=$(grep "MARKETING_VERSION:" project.yml | sed 's/.*MARKETING_VERSION: //' | tr -d ' ')
DMG="build/Release.noindex/Ombre-${VERSION}.dmg"
[[ -f "$DMG" ]] || die "No DMG at ${DMG}."

step "Installing in ${INSTALL_DIR}"

MOUNT=$(mktemp -d)
# The DMG's copy is unregistered (same bundle id as the installed app).
detach() {
    "$LSREGISTER" -u "$MOUNT/Ombre.app" 2>/dev/null || true
    hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
    rmdir "$MOUNT" 2>/dev/null || true
}
trap detach EXIT
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" || die "Could not open ${DMG}."

# Opened while it was building?
is_running && die "Ombre was opened meanwhile: quit it, then run this again."

# Copied next to the old one first, then swapped: a failed copy leaves the
# installed app as it was.
NEW="${INSTALL_DIR}/.Ombre-new.app"
rm -rf "$NEW"
ditto "$MOUNT/Ombre.app" "$NEW" || die "Copy failed."
codesign --verify --deep --strict "$NEW" || { rm -rf "$NEW"; die "Signature check failed."; }
"$LSREGISTER" -u "$NEW" 2>/dev/null || true
rm -rf "$INSTALLED"
mv "$NEW" "$INSTALLED"
"$LSREGISTER" -f "$INSTALLED"

COMMIT=$(defaults read "$INSTALLED/Contents/Info.plist" OmbreCommit 2>/dev/null || echo "?")
green "Installed: ${INSTALLED} (${VERSION}, commit ${COMMIT})"
