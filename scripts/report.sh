#!/bin/bash
set -euo pipefail

# report.sh — Gather what helps understand a problem with the installed Ombre.
#
# Usage: ./scripts/report.sh [hours] [folder]
#        (default: the last 2 hours, in a new folder on the Desktop)
#
# Writes a folder on the Desktop (Ombre-report-<date>) with:
#   - version.txt  the installed app's version and commit, macOS's version;
#   - ombre.log    the app's own messages (subsystem com.barto95100.ora);
#   - errors.log   the errors and faults of Ombre's own process (WebKit's
#                  included; its page processes are shared with every app,
#                  so left out);
#   - crashes/     the installed Ombre's crash reports, and those of WebKit's
#                  processes working for an Ombre.
# Nothing is sent anywhere. The logs may name sites you visited: read them
# before passing them on.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

HOURS="${1:-2}"
[[ "$HOURS" =~ ^[0-9]+$ ]] || die "Hours must be a whole number (got: ${HOURS})."
APP="/Applications/Ombre.app"
SUBSYSTEM="com.barto95100.ora"
OUT="${2:-$HOME/Desktop/Ombre-report-$(date +%Y-%m-%d_%H-%M-%S)}"
mkdir -p "$OUT/crashes"

step "Version"
# PlistBuddy reads the file itself (no cached value); empty or missing: "?".
plist_value() {
    local value
    value=$(/usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null || true)
    echo "${value:-?}"
}
{
    if [[ -d "$APP" ]]; then
        echo "Ombre: $(plist_value CFBundleShortVersionString) ($(plist_value CFBundleVersion), commit $(plist_value OmbreCommit))"
    else
        echo "Ombre: not installed in ${APP}"
    fi
    echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "Report: last ${HOURS} h, $(date)"
} | tee "$OUT/version.txt"

step "Logs (last ${HOURS} h)"
# The app's messages (the Debug app's are com.barto95100.ora.dev: not these).
log show --last "${HOURS}h" --info --debug --style compact \
    --predicate "subsystem == \"${SUBSYSTEM}\"" > "$OUT/ombre.log" 2>&1 || true
# Every error in the installed Ombre's process, WebKit's and macOS's included
# (not the Debug app's, nor the tests').
log show --last "${HOURS}h" --style compact \
    --predicate "processImagePath BEGINSWITH \"${APP}/\" AND messageType >= error" \
    > "$OUT/errors.log" 2>&1 || true
echo "$(wc -l < "$OUT/ombre.log" | tr -d ' ') lines (Ombre), $(wc -l < "$OUT/errors.log" | tr -d ' ') lines (errors)"

step "Crash reports (last 7 days)"
# Only the installed app's (not the Debug app's nor the tests', also named
# Ombre), and WebKit's processes working for an Ombre (Debug included: same
# process name), never another app's. Retired/ holds some recent ones too.
REPORTS="${OMBRE_REPORTS_DIR:-$HOME/Library/Logs/DiagnosticReports}"
while IFS= read -r -d '' report; do
    case "$(basename "$report")" in
    Ombre*) grep -qE "\"bundleID\" *: *\"${SUBSYSTEM//./\\.}\"" "$report" || continue ;;
    *) grep -qE '"responsibleProc" *: *"Ombre"' "$report" || continue ;;
    esac
    cp "$report" "$OUT/crashes/"
done < <(find "$REPORTS" "$REPORTS/Retired" -maxdepth 1 -type f -mtime -7 \
    \( -name "Ombre*" -o -name "com.apple.WebKit*" \) -print0 2>/dev/null)
count=$(find "$OUT/crashes" -type f | wc -l | tr -d ' ')
echo "${count} report(s)"

green "Report: ${OUT}"
