#!/bin/bash
# Builds build/NotchPet.app (ad-hoc signed). Pass --run to launch it afterwards.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/NotchPet.app
VERSION=$(tr -d '[:space:]' < VERSION)
# Build number: commits so far, so every release build counts up.
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchPet "$APP/Contents/MacOS/NotchPet"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Notch Pet</string>
  <key>CFBundleDisplayName</key><string>Notch Pet</string>
  <key>CFBundleIdentifier</key><string>dev.arpit.notchpet</string>
  <key>CFBundleExecutable</key><string>NotchPet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Pip switches to the Terminal or iTerm tab running the chat you click.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP (v$VERSION, build $BUILD)"
if [[ "${1:-}" == "--run" ]]; then
  pkill -x NotchPet 2>/dev/null || true
  open "$APP"
fi
