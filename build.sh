#!/bin/bash
# Builds build/NotchPet.app (ad-hoc signed). Pass --run to launch it afterwards.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/NotchPet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchPet "$APP/Contents/MacOS/NotchPet"
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
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
if [[ "${1:-}" == "--run" ]]; then
  pkill -x NotchPet 2>/dev/null || true
  open "$APP"
fi
