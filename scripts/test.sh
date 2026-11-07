#!/bin/bash
# test.sh — Run the unit tests, then unregister the tests' app.
#
# Usage: scripts/test.sh [xcodebuild options...]
#   e.g. scripts/test.sh -only-testing:OmbreTests/TabTranslationTests
#
# Builds in build/TestData (each worktree has its own; the pre-push hook
# builds unsigned in build/DerivedData, kept apart). The tests' app
# declares itself a browser: left registered, macOS could launch it.
set -eo pipefail
cd "$(dirname "$0")/.."

trap 'scripts/unregister-copies.sh build/TestData' EXIT

xcodebuild test \
    -scheme Ombre \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath build/TestData \
    "$@" 2>&1 | xcbeautify
