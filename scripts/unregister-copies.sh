#!/bin/bash
# unregister-copies.sh — Keep macOS from launching a build copy of Ombre.
#
# Each build outside Xcode's own DerivedData (worktrees, the pre-push hook,
# build.sh, the tests' app, the CI runner) leaves an Ombre.app with the same
# bundle id as the one in use, plus Sparkle's Updater.app. macOS registers
# them, and a notification click or a link can then launch one of them.
#
# Usage:
#   scripts/unregister-copies.sh <folder>...  unregister every app built under
#                                             these folders, and the ones
#                                             registered there but now gone
#   scripts/unregister-copies.sh --check      list the Ombre copies still
#                                             registered, and the apps built
#                                             in this repository outside a
#                                             .noindex folder; fails if there
#                                             is more than one copy, or any
#                                             such app
#
# Builds go to .noindex folders (build/DerivedData.noindex, build/TestData.noindex,
# build/Release.noindex): Spotlight skips them. An app elsewhere on the disk is
# registered again by Spotlight sooner or later, even after it was unregistered.
set -uo pipefail

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Every registered path, one per line ("path: /x/y.app (0x1234)" in the dump).
registered_paths() {
    "$LSREGISTER" -dump | awk '/^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); print }' | sort -u
}

if [[ "${1:-}" == "--check" ]]; then
    copies=$("$LSREGISTER" -dump | awk '
        /^path:/ { path = $0; sub(/^path: +/, "", path); sub(/ \(0x[0-9a-f]+\)$/, "", path) }
        /^identifier: +com\.barto95100\.ora/ { print path }' | sort -u)
    count=$(grep -c . <<<"$copies")
    echo "Registered Ombre copies: $count"
    [[ -n "$copies" ]] && sed 's/^/  /' <<<"$copies"
    # Xcode's Debug copy, plus an installed release in /Applications if any.
    others=$(grep -v '^/Applications/' <<<"$copies" | grep -c .)
    # Apps built in the repository and its worktrees, outside .noindex.
    common=$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir) || exit 2
    root=$(dirname "$common")
    exposed=$(find "$root" -path '*.noindex' -prune -o -type d -name '*.app' -print -prune 2>/dev/null)
    if [[ -n "$exposed" ]]; then
        echo "Apps Spotlight would register again (move them to a .noindex folder, or delete them):"
        sed 's/^/  /' <<<"$exposed"
    fi
    [[ "$others" -le 1 && -z "$exposed" ]]
    exit
fi

[[ $# -gt 0 ]] || { echo "usage: $0 <folder>... | --check" >&2; exit 2; }

registered=$(registered_paths)
for folder in "$@"; do
    [[ -n "$folder" ]] || continue
    folder="${folder%/}"
    [[ "$folder" == /* ]] || folder="$PWD/$folder"
    {
        # Apps there now (an app's own Updater.app included)...
        [[ -d "$folder" ]] && find "$folder" -type d -name '*.app'
        # ...and the ones registered from there, even if since deleted (the
        # path as given, and with its links resolved).
        resolved=$(cd "$folder" 2>/dev/null && pwd -P || echo "$folder")
        for prefix in "$folder/" "$resolved/"; do
            awk -v dir="$prefix" 'index($0, dir) == 1' <<<"$registered"
        done
    } | sort -u | while IFS= read -r app; do
        "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
    done
done
exit 0
