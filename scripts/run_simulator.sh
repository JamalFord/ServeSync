#!/bin/bash
# ==============================================================================
# ServeSync Sprint 3: Launch / Restart App on iOS Simulator
# ==============================================================================
set -e

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo "Booting iOS Simulator..."
DEVICE_ID="5E31B438-57FB-4EAC-850E-932674ED6555"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator

echo "Building latest iOS code..."
"$(dirname "$0")/build_ios.sh" "platform=iOS Simulator,name=iPhone 17"

APP_PATH="/Users/jamal/Library/Developer/Xcode/DerivedData/ServeSyncLocal-fdwypkjveindlvcenamhznrblebe/Build/Products/Debug-iphonesimulator/ServeSyncLocal.app"

echo "Installing and launching ServeSync..."
xcrun simctl install booted "$APP_PATH"
xcrun simctl terminate booted com.salem.ServeSyncLocal 2>/dev/null || true
xcrun simctl launch booted com.salem.ServeSyncLocal

echo "ServeSync launched successfully on the iOS Simulator!"
