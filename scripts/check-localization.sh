#!/bin/bash
# check-localization.sh — List the interface's texts without a French translation.
#
# Usage: scripts/check-localization.sh [--all]
#   --all: every file, not only the translated zones (ZONES in the .py).
#
# Builds in build/LocData.noindex to find the texts (and adds the new ones to
# Ombre/Resources/Localizable.xcstrings), then checks them (see the .py).
set -eo pipefail
cd "$(dirname "$0")/.."

trap 'scripts/unregister-copies.sh build/LocData.noindex >/dev/null' EXIT

xcodebuild -exportLocalizations \
    -project Ombre.xcodeproj \
    -scheme Ombre \
    -localizationPath build/Loc.noindex \
    -exportLanguage fr \
    -derivedDataPath build/LocData.noindex \
    -quiet
python3 -I scripts/check-localization.py build/LocData.noindex Ombre/Resources/Localizable.xcstrings "$@"
