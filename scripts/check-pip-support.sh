#!/usr/bin/env bash
# check-pip-support.sh — Checks that a built Ombre.app can show Picture in
# Picture outside of Xcode, and still opens on macOS 15.
#
# macOS's app sandbox lets an app reach the Picture in Picture service
# (PIPAgent) only if Picture in Picture's framework was loaded when the sandbox
# started. Ombre links AVKit for that (see PictureInPictureSupport.swift). The
# Debug build gets the framework from Xcode's preview support anyway, so only
# a Release build showed the problem: the video stayed "in Picture in Picture"
# with no window.
#
# Usage: scripts/check-pip-support.sh <path/to/Ombre.app> [entitlements file]
# (default: Ombre/Info/Ombre.entitlements, the Release one)
set -euo pipefail

APP="${1:?Usage: $0 <path/to/Ombre.app>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENTITLEMENTS="${2:-$SCRIPT_DIR/../Ombre/Info/Ombre.entitlements}"
BINARY="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist")"
failed=0

# 1. Linked at launch: the sandbox reads what is loaded when it starts. A
# Debug or Test build keeps its code, and its links, in <name>.debug.dylib.
linked() {
    local file
    for file in "$BINARY" "$BINARY.debug.dylib"; do
        [[ -f "$file" ]] || continue
        # Read whole (grep -q would cut dyld_info's output short).
        local dependents
        dependents=$(dyld_info -dependents "$file" 2>/dev/null || true)
        [[ "$dependents" == *"/AVKit.framework/"* ]] && return 0
    done
    return 1
}
if linked; then
    echo "OK: $(basename "$BINARY") links AVKit (Picture in Picture's framework loads at launch)."
else
    echo "FAIL: $(basename "$BINARY") does not link AVKit: macOS's sandbox will refuse Picture in Picture." >&2
    failed=1
fi

# 2. Frameworks of macOS 26 and later (Apple's on-device model) linked weakly:
# a strong link and the app no longer opens on macOS 15.
strong=0
for framework in FoundationModels; do
    for file in "$BINARY" "$BINARY.debug.dylib"; do
        [[ -f "$file" ]] || continue
        dependents=$(dyld_info -dependents "$file" 2>/dev/null || true)
        line=$(grep "/$framework.framework/" <<<"$dependents" || true)
        if [[ -n "$line" && "$line" != *weak-link* ]]; then
            echo "FAIL: $(basename "$file") links $framework strongly: Ombre would no longer open on macOS 15." >&2
            strong=1
            failed=1
        fi
    done
done
[[ "$strong" == 0 ]] && echo "OK: macOS 26 frameworks are linked weakly (Ombre opens on macOS 15)."

# 3. The app was signed with the project's entitlements (the same keys). Xcode
# adds two to a Debug or Test build: get-task-allow (the debugger) and a read
# exception for the tests' files.
xcode_keys='{"com.apple.security.get-task-allow", "com.apple.security.temporary-exception.files.absolute-path.read-only"}'
if ! codesign -d --entitlements :- "$APP" >/dev/null 2>&1; then
    echo "FAIL: can't read $(basename "$APP")'s signature." >&2
    exit 1
fi
signed=$(codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -convert json -o - - \
    | python3 -c "import json,sys; print('\n'.join(sorted(set(json.load(sys.stdin)) - ${xcode_keys})))")
expected=$(plutil -convert json -o - "$ENTITLEMENTS" | python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin))))')
if [[ "$signed" == "$expected" ]]; then
    echo "OK: signed with the project's entitlements."
else
    echo "FAIL: the signed entitlements differ from $(basename "$ENTITLEMENTS"):" >&2
    diff <(echo "$expected") <(echo "$signed") >&2 || true
    failed=1
fi

exit "$failed"
