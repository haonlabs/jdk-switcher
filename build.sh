#!/bin/bash
# Builds build/JDK Switcher.app (universal) and build/JDKSwitcher-<version>.dmg.
# Optional: SIGN_ID="Developer ID Application: ..." to sign for distribution,
#           NOTARY_PROFILE=<notarytool keychain profile> to notarize the DMG.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/JDK Switcher.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
DMG="build/JDKSwitcher-$VERSION.dmg"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/dmg

swiftc Sources/JDKStore.swift Tests/main.swift -o build/selftest && build/selftest && rm build/selftest

for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13" Sources/*.swift -o "build/JDKSwitcher-$arch"
done
lipo -create build/JDKSwitcher-arm64 build/JDKSwitcher-x86_64 -output "$APP/Contents/MacOS/JDKSwitcher"
cp Info.plist "$APP/Contents/"

swiftc Sources/Logo.swift scripts/make-icon/main.swift -o build/make-icon && build/make-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --timestamp=none --sign "${SIGN_ID:--}" "$APP"
codesign --verify --strict "$APP"

cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "JDK Switcher" -srcfolder build/dmg -ov -format UDZO "$DMG" >/dev/null
rm -rf build/dmg build/AppIcon.iconset build/make-icon build/JDKSwitcher-arm64 build/JDKSwitcher-x86_64

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  codesign --sign "$SIGN_ID" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Built $DMG"
