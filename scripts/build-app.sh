#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
FOCUSDOCK_CONFIGURATION="${1:-release}"
xcrun swift build "${FOCUSDOCK_SWIFT_OPTIONS[@]}" -c "$FOCUSDOCK_CONFIGURATION" --product FocusDock
FOCUSDOCK_BIN_DIR="$(xcrun swift build "${FOCUSDOCK_SWIFT_OPTIONS[@]}" -c "$FOCUSDOCK_CONFIGURATION" --show-bin-path)"
FOCUSDOCK_APP="$FOCUSDOCK_ROOT/build/干了吗.app"
mkdir -p "$FOCUSDOCK_APP/Contents/MacOS" "$FOCUSDOCK_APP/Contents/Resources"
cp "$FOCUSDOCK_BIN_DIR/FocusDock" "$FOCUSDOCK_APP/Contents/MacOS/FocusDock"
cp "$FOCUSDOCK_ROOT/Resources/Info.plist" "$FOCUSDOCK_APP/Contents/Info.plist"
codesign --force --sign - "$FOCUSDOCK_APP"
codesign --verify --strict "$FOCUSDOCK_APP"
printf '\nBuilt: %s\n' "$FOCUSDOCK_APP"
