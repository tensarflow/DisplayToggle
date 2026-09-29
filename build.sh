#!/bin/bash
# Builds build/DisplayToggle.app and build/DisplayToggle.zip.
# The app is a menu bar app; the same binary is the `displayctl` CLI.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.0.0
swift build -c release --product DisplayToggle
BIN="$(swift build -c release --show-bin-path)/DisplayToggle"
APP=build/DisplayToggle.app

rm -rf "$APP" build/DisplayToggle.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DisplayToggle"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DisplayToggle</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>io.github.tensarflow.DisplayToggle</string>
    <key>CFBundleName</key><string>DisplayToggle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License · github.com/tensarflow/DisplayToggle</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" build/DisplayToggle.zip
echo "Built $APP and build/DisplayToggle.zip"
