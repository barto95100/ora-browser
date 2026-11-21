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
# It also installs the ombre command (scripts/ombre: agents and scripts
# drive Ombre) in ~/.local/bin, and says how to add that folder to the PATH
# when it isn't there.
# Then it offers to install, or update, the Claude Code skill for ombre
# (tools/claude-skill/ombre) in ~/.claude/skills/ombre: asked yes or no,
# never done without asking (nor without a terminal to ask in).
#
# The installed version:
#   /usr/libexec/PlistBuddy -c "Print :OmbreCommit" /Applications/Ombre.app/Contents/Info.plist

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
NEW="${INSTALL_DIR}/.Ombre-new.app"
# The DMG's copy is unregistered (same bundle id as the installed app).
detach() {
    "$LSREGISTER" -u "$MOUNT/Ombre.app" 2>/dev/null || true
    # Stopped before the swap: no second copy left beside the installed one.
    if [[ -e "$NEW" ]]; then
        "$LSREGISTER" -u "$NEW" 2>/dev/null || true
        rm -rf "$NEW"
    fi
    hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
    rmdir "$MOUNT" 2>/dev/null || true
}
trap detach EXIT
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" || die "Could not open ${DMG}."

# Copied next to the old one first, then swapped: a failed copy leaves the
# installed app as it was.
rm -rf "$NEW"
ditto "$MOUNT/Ombre.app" "$NEW" || die "Copy failed."
codesign --verify --deep --strict "$NEW" || { rm -rf "$NEW"; die "Signature check failed."; }
# Opened while it was building or copying? Checked right before the swap.
is_running && die "Ombre was opened meanwhile: quit it, then run this again."
"$LSREGISTER" -u "$NEW" 2>/dev/null || true
rm -rf "$INSTALLED"
mv "$NEW" "$INSTALLED"
"$LSREGISTER" -f "$INSTALLED"

COMMIT=$(/usr/libexec/PlistBuddy -c "Print :OmbreCommit" "$INSTALLED/Contents/Info.plist" 2>/dev/null || echo "?")
green "Installed: ${INSTALLED} (${VERSION}, commit ${COMMIT})"

# The ombre command (agents, scripts: see scripts/ombre), in ~/.local/bin.
BIN_DIR="${OMBRE_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN_DIR"
install -m 755 "$SCRIPT_DIR/ombre" "$BIN_DIR/ombre"
green "Installed: ${BIN_DIR}/ombre"
case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *)
        yellow "${BIN_DIR} isn't in your PATH: add this line to ~/.zshrc, then open a new terminal:"
        # The folder written as the user's shell will read it.
        echo "  export PATH=\"${BIN_DIR/#$HOME/\$HOME}:\$PATH\""
        ;;
esac

# The Claude Code skill for ombre: only when the user says yes.
SKILL_SOURCE="tools/claude-skill/ombre/SKILL.md"
SKILL_DIR="${OMBRE_SKILL_DIR:-$HOME/.claude/skills/ombre}"
if [[ -f "$SKILL_DIR/SKILL.md" ]] && cmp -s "$SKILL_SOURCE" "$SKILL_DIR/SKILL.md"; then
    green "Claude Code skill up to date: ${SKILL_DIR}"
elif [[ ! -t 0 ]]; then
    yellow "Claude Code skill not installed (no terminal to ask): run this script from a terminal to be asked."
else
    if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
        question="Update the Claude Code skill for ombre in ${SKILL_DIR}? [y/N] "
    else
        question="Install the Claude Code skill for ombre in ${SKILL_DIR}? [y/N] "
    fi
    read -r -p "$question" answer || answer=""
    case "$answer" in
        [yY] | [yY][eE][sS] | [oO] | [oO][uU][iI])
            mkdir -p "$SKILL_DIR"
            install -m 644 "$SKILL_SOURCE" "$SKILL_DIR/SKILL.md"
            green "Installed: ${SKILL_DIR}/SKILL.md"
            ;;
        *) echo "Claude Code skill left as it was." ;;
    esac
fi
