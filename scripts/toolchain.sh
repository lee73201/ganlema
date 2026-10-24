#!/bin/bash
# Shared by build-app.sh and test.sh; all compiler caches stay inside this project.
FOCUSDOCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Prefer a newly installed full Xcode without changing the system-wide selection.
if [[ -z "${DEVELOPER_DIR:-}" && -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
FOCUSDOCK_BUILD_ROOT="${FOCUSDOCK_BUILD_ROOT:-$FOCUSDOCK_ROOT/.build}"
export CLANG_MODULE_CACHE_PATH="$FOCUSDOCK_BUILD_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$FOCUSDOCK_BUILD_ROOT/cache" "$FOCUSDOCK_BUILD_ROOT/config" "$FOCUSDOCK_BUILD_ROOT/security"
FOCUSDOCK_SWIFT_OPTIONS=(--package-path "$FOCUSDOCK_ROOT" --scratch-path "$FOCUSDOCK_BUILD_ROOT/swift"
    --cache-path "$FOCUSDOCK_BUILD_ROOT/cache" --config-path "$FOCUSDOCK_BUILD_ROOT/config"
    --security-path "$FOCUSDOCK_BUILD_ROOT/security")
# SwiftPM's child sandbox cannot start inside some automation sandboxes.
if [[ "${FOCUSDOCK_SWIFTPM_NO_SANDBOX:-0}" == "1" ]]; then
    FOCUSDOCK_SWIFT_OPTIONS+=(--disable-sandbox)
fi
