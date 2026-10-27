#!/bin/bash
# Pre-push check: build without signing, in its own DerivedData so the unsigned
# products never mix with the signed ones of Xcode and `xcodebuild test`
# (which then failed with "code object is not signed at all").
set -eo pipefail

xcodebuild build \
  -scheme ora \
  -destination "platform=macOS" \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO | xcbeautify

# This copy is only a build check: keep macOS from registering it as an app,
# or opening a link or a file could launch it instead of the one run by Xcode.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u build/DerivedData/Build/Products/Debug/Ora.app >/dev/null 2>&1 || true
