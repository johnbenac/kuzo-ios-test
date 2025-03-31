#!/bin/bash
set -e

# Script to build and deploy the KuzuTestApp app to a connected iPhone
# IMPORTANT: This script ASSUMES you have:
# 1. Opened KuzuTestApp.xcodeproj in Xcode.
# 2. Copied the Kuzu.xcframework into the Xcode project navigator.
# 3. Set Kuzu.xcframework to "Embed & Sign" in Target -> General -> Frameworks.
# 4. Verified Xcode recognizes the KuzuTestApp-Bridging-Header.h (check Target -> Build Settings -> Swift Compiler - General).
# 5. Edited KuzuTestApp/ContentView.swift to replace the placeholder functions
#    `getActualDefaultSystemConfig()` and `freeKuzuString()` with the correct
#    function names found by inspecting Kuzu.xcframework/Headers/kuzu.h.
# 6. Configured code signing (Team, Bundle ID) in Xcode.
# FAILURE TO DO THESE STEPS WILL CAUSE THIS SCRIPT TO FAIL.

echo "Building KuzuTestApp app for iOS device..."

# Get the connected device ID
DEVICE_ID=$(xcrun xctrace list devices | grep "iPhone" | grep -v "Simulator" | head -1 | sed -E 's/.*\(([0-9A-Z-]+)\).*/\1/')

if [ -z "$DEVICE_ID" ]; then
  echo "No iPhone device connected. Please connect your iPhone and ensure it is trusted."
  exit 1
fi

echo "Found iPhone device with ID: $DEVICE_ID"

# Build the app using Xcode project settings
# Make sure you are in the KuzuTestApp directory containing the .xcodeproj
if [ ! -d "KuzuTestApp.xcodeproj" ]; then
    echo "Error: KuzuTestApp.xcodeproj not found in the current directory."
    echo "Please 'cd' into the KuzuTestApp directory before running this script."
    exit 1
fi

echo "Building app using Xcode signing configuration (this may take time)..."
xcodebuild clean build \
  -project KuzuTestApp.xcodeproj \
  -scheme KuzuTestApp \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  | cat # Pipe to cat to avoid pager issues

# Get path to the built app (adjust DerivedData path if necessary)
# This tries to read the build directory from build settings first
BUILD_DIR=$(xcodebuild -project KuzuTestApp.xcodeproj -scheme KuzuTestApp -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | sed 's/.* = //')
APP_PATH="$BUILD_DIR/KuzuTestApp.app"

# Fallback search if the build settings method fails (less reliable)
if [ -z "$BUILD_DIR" ] || [ ! -d "$APP_PATH" ]; then
  echo "Searching DerivedData for KuzuTestApp.app (Build settings method failed or path invalid)..."
  APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "KuzuTestApp.app" -type d | grep "Build/Products/Debug-iphoneos/KuzuTestApp.app" | head -1)
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "Failed to find built KuzuTestApp.app."
  echo "Check the xcodebuild output above for errors."
  echo "Ensure the scheme name ('KuzuTestApp') is correct and the build succeeded."
  exit 1
fi

echo "App built successfully at: $APP_PATH"

# Check if ios-deploy exists
if command -v ios-deploy >/dev/null 2>&1; then
  # Deploy to device
  echo "Deploying to iPhone..."
  echo "Installing app on device (this may take a moment)..."

  # First attempt: straightforward install
  ios-deploy --bundle "$APP_PATH" || {
    echo ""
    echo "Installation failed. Trying alternative method with device ID..."
    # Second attempt: with specific device ID
    ios-deploy --id $DEVICE_ID --bundle "$APP_PATH" || {
      echo ""
      echo "Both deployment methods failed. Please try running the app from Xcode directly."
      echo "App is built and ready at: $APP_PATH"
      # Don't exit script - the build succeeded, just deployment failed
    }
  }

  echo "App deployment attempted. Check your device."
else
  echo "------------------------------------------------------------------"
  echo "'ios-deploy' command not found. App cannot be deployed automatically."
  echo "Install it using Homebrew: 'brew install ios-deploy'"
  echo "Alternatively, use Xcode to run the app on your device."
  echo "App was built successfully and is located at:"
  echo "$APP_PATH"
  echo "------------------------------------------------------------------"
fi

echo ""
echo "Script finished." 