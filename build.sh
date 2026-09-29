#!/bin/bash
# Builds build/DisplayToggle.app (menu bar app; the same binary is the displayctl CLI).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product DisplayToggle
BIN="$(swift build -c release --show-bin-path)/DisplayToggle"
APP=build/DisplayToggle.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/DisplayToggle"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DisplayToggle</string>
    <key>CFBundleIdentifier</key><string>local.DisplayToggle</string>
    <key>CFBundleName</key><string>DisplayToggle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
