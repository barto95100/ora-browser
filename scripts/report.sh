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
#                  included);
#   - webkit.log   WebKit's messages in Ombre's process (pages made, loads,
#                  processes suspended, resumed or ended, its pages' own
#                  processes relayed there), and those of the network process
#                  working for the running Ombre;
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
# WebKit in Ombre's process (its pages' processes relay their messages there):
# loads, processes and visibility, not each resource of each page.
log show --last "${HOURS}h" --style compact \
    --predicate "processImagePath BEGINSWITH \"${APP}/\" AND subsystem == \"com.apple.WebKit\" \
AND category IN {\"Loading\", \"Process\", \"ProcessSuspension\", \"ProcessSwapping\", \"ViewState\"}" \
    > "$OUT/webkit.log" 2>&1 || true
# The network process loading the pages is shared by no other app, but it is
# found through its messages naming the running Ombre (parentPID=…), from
# Ombre's launch only (before it, the same numbers may have been another app's).
pids=$(pgrep -f "^${APP}/Contents/MacOS/Ombre" || true)
if [[ -n "$pids" ]]; then
    since=$(date -v-"${HOURS}"H "+%Y-%m-%d %H:%M:%S")
    for pid in $pids; do
        launched=$(date -j -f "%a %b %d %T %Y" "$(ps -o lstart= -p "$pid" | xargs)" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || true)
        [[ -n "$launched" && "$launched" > "$since" ]] && since="$launched"
    done
    match=$(sed 's/.*/composedMessage CONTAINS "parentPID=&,"/' <<<"$pids" | paste -sd'|' - | sed 's/|/ OR /g')
    network=$(log show --start "$since" --style compact \
        --predicate "process == \"com.apple.WebKit.Networking\" AND (${match})" 2>/dev/null \
        | sed -nE 's/.*com\.apple\.WebKit\.Networking\[([0-9]+):.*/\1/p' | sort -u || true)
    if [[ -n "$network" ]]; then
        ids=$(paste -sd, - <<<"$network")
        log show --start "$since" --style compact \
            --predicate "process == \"com.apple.WebKit.Networking\" AND processID IN {${ids}} \
AND (messageType >= error OR composedMessage CONTAINS \"isMainResource=1\")" \
            >> "$OUT/webkit.log" 2>&1 || true
    else
        echo "Network process: none found since ${since}."
    fi
else
    echo "Network process: Ombre is not running, left out (its PID is needed to find it)."
fi
echo "$(wc -l < "$OUT/ombre.log" | tr -d ' ') lines (Ombre), $(wc -l < "$OUT/errors.log" | tr -d ' ') lines (errors)," \
    "$(wc -l < "$OUT/webkit.log" | tr -d ' ') lines (WebKit)"

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
