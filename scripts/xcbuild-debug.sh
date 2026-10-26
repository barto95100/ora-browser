#!/bin/bash
# Pre-push check: build without signing, in its own DerivedData so the unsigned
# products never mix with the signed ones of Xcode and `xcodebuild test`
# (which then failed with "code object is not signed at all").
set -o pipefail && xcodebuild build \
  -scheme ora \
  -destination "platform=macOS" \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO | xcbeautify
