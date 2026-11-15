#!/usr/bin/env bash
# check-pip-support.sh — Checks that a built Ombre.app can show Picture in
# Picture outside of Xcode.
#
# macOS's app sandbox lets an app reach the Picture in Picture service
# (PIPAgent) only if Picture in Picture's framework was loaded when the sandbox
# started. Ombre links AVKit for that (see PictureInPictureSupport.swift). The
# Debug build gets the framework from Xcode's preview support anyway, so only
# a Release build showed the problem: the video stayed "in Picture in Picture"
# with no window.
#
# Usage: scripts/check-pip-support.sh <path/to/Ombre.app>
set -euo pipefail

APP="${1:?Usage: $0 <path/to/Ombre.app>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENTITLEMENTS="$SCRIPT_DIR/../Ombre/Info/Ombre.entitlements"
BINARY="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist")"
failed=0

# 1. Linked at launch: the sandbox reads what is loaded when it starts. A
# Debug or Test build keeps its code, and its links, in <name>.debug.dylib.
linked() {
    local file
    for file in "$BINARY" "$BINARY.debug.dylib"; do
        [[ -f "$file" ]] && dyld_info -dependents "$file" 2>/dev/null | grep -q "/AVKit.framework/" && return 0
    done
    return 1
}
if linked; then
    echo "OK: $(basename "$BINARY") links AVKit (Picture in Picture's framework loads at launch)."
else
    echo "FAIL: $(basename "$BINARY") does not link AVKit: macOS's sandbox will refuse Picture in Picture." >&2
    failed=1
fi

# 2. The app was signed with the project's entitlements (the same keys). Xcode
# adds two to a Debug or Test build: get-task-allow (the debugger) and a read
# exception for the tests' files.
xcode_keys='{"com.apple.security.get-task-allow", "com.apple.security.temporary-exception.files.absolute-path.read-only"}'
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
