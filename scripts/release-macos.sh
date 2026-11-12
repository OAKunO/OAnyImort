#!/bin/zsh
set -eu
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
: "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool keychain profile}"
export UNIVERSAL=1
zsh scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
APP_PATH="$PROJECT_ROOT/dist/OAnyImort.app"
STAGING="$PROJECT_ROOT/.release-work/dmg"
mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/OAnyImort.app"
ln -sfn /Applications "$STAGING/Applications"
DMG="$PROJECT_ROOT/dist/OAnyImort-macOS-$VERSION-universal.dmg"
hdiutil create -volname OAnyImort -srcfolder "$STAGING" -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 10m
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "Notarized release ready: $DMG"
