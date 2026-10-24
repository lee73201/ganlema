#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
printf 'Developer override: %s\n' "${DEVELOPER_DIR:-system default}"
xcrun --find swiftc
xcrun swift --version
xcrun --show-sdk-path
if ! xcodebuild -version; then
    printf '\n完整 Xcode 尚未就绪。仍会继续检查 SwiftData 编译插件。\n'
fi
mkdir -p "$FOCUSDOCK_BUILD_ROOT/doctor"
cat > "$FOCUSDOCK_BUILD_ROOT/doctor/SwiftDataProbe.swift" <<'SWIFT'
import SwiftData
@Model final class FocusDockProbe {
    var title: String
    init(title: String) { self.title = title }
}
SWIFT
if xcrun swiftc -typecheck -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    "$FOCUSDOCK_BUILD_ROOT/doctor/SwiftDataProbe.swift" > "$FOCUSDOCK_BUILD_ROOT/doctor/swiftdata-probe.log" 2>&1; then
    printf '\nPASS: SwiftData @Model 编译插件可用。\n'
else
    printf '\nFAIL: SwiftData @Model 编译检查未通过。\n'
    cat "$FOCUSDOCK_BUILD_ROOT/doctor/swiftdata-probe.log"
    exit 1
fi
