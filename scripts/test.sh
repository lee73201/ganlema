#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
xcrun swift test "${FOCUSDOCK_SWIFT_OPTIONS[@]}" --disable-xctest
