#!/bin/bash
# build-and-run.sh — Build the Redstone Setup app and launch it as a real macOS .app
# Run from the RedstoneSetup/ directory:  ./build-and-run.sh
#
# Why the .app bundle? A bare SwiftUI executable launched from the terminal has
# no bundle, so macOS runs it as a background process with no Dock icon and never
# brings its window to the front. Wrapping it in a minimal .app fixes that.

set -e

APP_NAME="RedstoneSetup"
BUILD_DIR=".build/release"
BINARY="$BUILD_DIR/$APP_NAME"
APP_BUNDLE=".build/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."
swift build -c release 2>&1

if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed: binary not found at $BINARY"
    exit 1
fi
echo "✅ Build succeeded"

echo "📦 Packaging $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

# Copy the executable and its SwiftPM resource bundle side by side so that
# Bundle.module can find setup_flows.json at runtime.
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [ -d "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$APP_BUNDLE/Contents/MacOS/"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Tablet Kit</string>
    <key>CFBundleIdentifier</key>
    <string>com.peloton.redstonesetup</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "🚀 Launching $APP_NAME..."
# Kill any running instance first — `open` only re-activates an already-running
# app and won't pick up the freshly built binary otherwise.
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5
open "$APP_BUNDLE"
