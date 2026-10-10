#!/bin/bash
# Regenerates Assets/AppIcon.icns from the icon drawn in Sources/NotchPet/AppInfo.swift.
# Only needed after changing the artwork; build.sh uses the committed .icns.
set -euo pipefail
cd "$(dirname "$0")"
swift build
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
.build/debug/NotchPet --export-icon "$TMP/icon.png"
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$TMP/icon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$TMP/icon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
mkdir -p Assets
iconutil -c icns "$SET" -o Assets/AppIcon.icns
cp "$TMP/icon.png" Assets/AppIcon.png
echo "Wrote Assets/AppIcon.icns"
