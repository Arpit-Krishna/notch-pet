#!/bin/bash
# Packages a release: dist/NotchPet-<version>.zip and dist/NotchPet-<version>.dmg.
# The version comes from the VERSION file.
#
# Unsigned by default (ad-hoc signature, like build.sh). For a build that opens without
# Gatekeeper warnings, set both of these first (needs a paid Apple Developer account):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE=notchpet     # from: xcrun notarytool store-credentials notchpet --apple-id … --team-id …
#
#   ./release.sh            build and package
#   ./release.sh --publish  also create the GitHub release v<version> and upload both files
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(tr -d '[:space:]' < VERSION)
APP=build/NotchPet.app
OUT=dist
NAME="NotchPet-$VERSION"
PUBLISH=false
[[ "${1:-}" == "--publish" ]] && PUBLISH=true

if $PUBLISH && gh release view "v$VERSION" >/dev/null 2>&1; then
  echo "Release v$VERSION already exists. Bump VERSION first." >&2
  exit 1
fi
if [[ -n "${NOTARY_PROFILE:-}" && -z "${SIGN_IDENTITY:-}" ]]; then
  echo "NOTARY_PROFILE needs SIGN_IDENTITY too: Apple only notarizes Developer ID signed apps." >&2
  exit 1
fi

./build.sh
rm -rf "$OUT"
mkdir -p "$OUT"

notarize() {   # notarize <file>: submit to Apple, wait for the verdict
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Signing with $SIGN_IDENTITY"
  codesign --force --options runtime --timestamp --entitlements NotchPet.entitlements \
           --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    notarize "$OUT/notarize.zip"
    rm "$OUT/notarize.zip"
    xcrun stapler staple "$APP"   # so the app opens offline too
  fi
fi

# Zip: what GitHub shows people first.
ditto -c -k --keepParent "$APP" "$OUT/$NAME.zip"

# Disk image with an Applications shortcut to drag onto.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Notch Pet $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT/$NAME.dmg" >/dev/null
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUT/$NAME.dmg"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notarize "$OUT/$NAME.dmg"
    xcrun stapler staple "$OUT/$NAME.dmg"
  fi
fi

(cd "$OUT" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS.txt)
echo "Packaged:"
ls -lh "$OUT"

if $PUBLISH; then
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    NOTES="Download the .dmg, open it and drag Notch Pet into Applications."
  else
    NOTES=$'Download the .dmg, open it and drag Notch Pet into Applications.\n\nThis build is not notarized by Apple, so macOS blocks it the first time. Open it once, then go to System Settings → Privacy & Security and click **Open Anyway**. Or run:\n\n```\nxattr -dr com.apple.quarantine "/Applications/NotchPet.app"\n```'
  fi
  gh release create "v$VERSION" "$OUT/$NAME.dmg" "$OUT/$NAME.zip" "$OUT/SHA256SUMS.txt" \
     --title "Notch Pet $VERSION" --notes "$NOTES"
fi
