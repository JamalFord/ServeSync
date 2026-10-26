#!/bin/bash
# ==============================================================================
# ServeSync Sprint 3: Command-Line iOS Build Script (No IDE Required)
# Compiles the ServeSyncLocal iOS application target using Apple's xcodebuild CLI.
# ==============================================================================
set -e
echo "Building ServeSync iOS App from command line..."

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PROJECT_PATH="xcode/ServeSyncLocal/ServeSyncLocal.xcodeproj"
SCHEME="ServeSyncLocal"
DESTINATION="${1:-platform=iOS Simulator,name=iPhone 17}"

if command -v xcodebuild &> /dev/null; then
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        build
    echo "Build succeeded via command line."
else
    echo "xcodebuild CLI is available on macOS with Xcode installed."
fi
