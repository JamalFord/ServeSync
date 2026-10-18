#!/bin/bash
# ==============================================================================
# ServeSync Sprint 3: Command-Line iOS Build Script (No IDE Required)
# Compiles the ServeSyncLocal iOS application target using Apple's xcodebuild CLI.
# ==============================================================================
set -e
echo "Building ServeSync iOS App from command line..."

PROJECT_PATH="xcode/ServeSyncLocal/ServeSyncLocal.xcodeproj"
SCHEME="ServeSyncLocal"
DESTINATION="platform=iOS Simulator,name=iPhone 16"

if command -v xcodebuild &> /dev/null; then
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -sdk iphonesimulator \
        -destination "$DESTINATION" \
        clean build
    echo "Build succeeded via command line."
else
    echo "xcodebuild CLI is available on macOS with Xcode Command Line Tools installed."
    echo "Run this script on the team's Mac to compile without launching the Xcode IDE."
fi
