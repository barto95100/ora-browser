#!/bin/bash
# Pre-push check: build without signing, in its own DerivedData so the unsigned
# products never mix with the signed ones of Xcode and `xcodebuild test`
# (which then failed with "code object is not signed at all").
set -eo pipefail
cd "$(dirname "$0")/.."

# This copy is only a build check: keep macOS from registering it as an app,
# or opening a link or a file could launch it instead of the one run by Xcode.
# Even when the build fails (a partly built app may be registered).
trap 'scripts/unregister-copies.sh build/DerivedData' EXIT

# Run from git's pre-push hook, GIT_DIR and the like point at this checkout:
# Swift Package Manager's own git commands then fail to fetch the packages
# ("Could not resolve package dependencies", in a checkout that never built).
unset $(git rev-parse --local-env-vars)

xcodebuild build \
  -scheme Ombre \
  -destination "platform=macOS" \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO | xcbeautify

