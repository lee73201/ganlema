#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
xcrun swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    "$FOCUSDOCK_ROOT/Sources/FocusDockCore/PanelInteraction.swift" \
    "$FOCUSDOCK_ROOT/Sources/FocusDockCore/WindowPlacement.swift" \
    "$FOCUSDOCK_ROOT/Tests/LogicChecks/main.swift" \
    -o "$FOCUSDOCK_BUILD_ROOT/focusdock-logic-checks"
"$FOCUSDOCK_BUILD_ROOT/focusdock-logic-checks"
