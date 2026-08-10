#!/bin/bash
# Regenerate, build, and (re)launch RoundPlay on the simulator in one step.
#
# `xcodebuild build` alone does NOT update the installed app — without the explicit
# install/terminate/launch below, the simulator keeps running the previous binary and every UI
# change looks like it silently did nothing.
set -euo pipefail

DEVICE_ID="${DEVICE_ID:-9CE293F3-8CD8-4232-9B5E-37E9B46EBE92}"
BUNDLE_ID="app.roundplay.RoundPlay"

cd "$(dirname "$0")/.."

xcodegen generate >/dev/null

if ! xcodebuild -project RoundPlay.xcodeproj -scheme RoundPlay \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" build 2>&1 \
    | grep -E "error:|BUILD" ; then
    echo "BUILD FAILED (no matching output)" >&2
    exit 1
fi

# Boot is idempotent; bootstatus blocks until the device is actually usable.
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null 2>&1 || true

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/RoundPlay-*/Build/Products/Debug-iphonesimulator \
    -name "RoundPlay.app" -print -quit)
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
