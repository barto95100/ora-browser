#!/bin/bash
# test.sh — Run the unit tests, then unregister the tests' app.
#
# Usage: scripts/test.sh [xcodebuild options...]
#   e.g. scripts/test.sh -only-testing:OmbreTests/TabTranslationTests
#
# Builds in build/TestData.noindex (each worktree has its own; the pre-push
# hook builds unsigned in build/DerivedData.noindex, kept apart). A warning
# fails the build, as in the CI (the project keeps 0). The tests'
# app declares itself a browser: left registered, macOS could launch it.
# Spotlight skips .noindex folders, so it never registers it there again.
set -eo pipefail
cd "$(dirname "$0")/.."

trap 'scripts/unregister-copies.sh build/TestData.noindex' EXIT

xcodebuild test \
    -scheme Ombre \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath build/TestData.noindex \
    OMBRE_WARNINGS_AS_ERRORS=YES \
    "$@" 2>&1 | xcbeautify
