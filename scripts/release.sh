#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SHADE_SIGN_IDENTITY:?Developer ID identity required}"
: "${NOTARY_PROFILE:?Notary keychain profile required}"
: "${SPARKLE_ACCOUNT:=ai.combinatrix.shade}"
: "${RELEASE_REPO:?GitHub owner/repo required}"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Info.plist)
[[ "${RELEASE_TAG:-v$version}" == "v$version" ]] || { echo 'Tag/version mismatch' >&2; exit 1; }
[[ $(uname -m) == arm64 ]] || { echo 'Release requires an Apple Silicon host' >&2; exit 1; }
/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Info.plist >/dev/null
swift test
DISTRIBUTION=1 ./scripts/build.sh
app="$PWD/build/Shade.app"
[[ $(lipo -archs "$app/Contents/MacOS/Shade") == arm64 ]] || exit 1
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p dist
zip="$PWD/dist/Shade.zip"
dmg="$PWD/dist/Shade.dmg"
ditto -c -k --keepParent "$app" "$stage/submit.zip"
xcrun notarytool submit "$stage/submit.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute "$app"
ditto "$app" "$stage/dmg/Shade.app"
ln -s /Applications "$stage/dmg/Applications"
hdiutil create -volname Shade -srcfolder "$stage/dmg" -ov -format UDZO "$dmg"
codesign --sign "$SHADE_SIGN_IDENTITY" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
ditto -c -k --keepParent "$app" "$zip"
ditto -x -k "$zip" "$stage/unpacked"
codesign --verify --deep --strict "$stage/unpacked/Shade.app"
xcrun stapler validate "$stage/unpacked/Shade.app"
hdiutil attach "$dmg" -mountpoint "$stage/mount" -nobrowse
codesign --verify --deep --strict "$stage/mount/Shade.app"
xcrun stapler validate "$stage/mount/Shade.app"
hdiutil detach "$stage/mount"
if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
  .build/artifacts/sparkle/Sparkle/bin/sign_update "$zip" --ed-key-file "$SPARKLE_KEY_FILE" > "$stage/signature"
else
  .build/artifacts/sparkle/Sparkle/bin/sign_update "$zip" --account "$SPARKLE_ACCOUNT" > "$stage/signature"
fi
swift scripts/verify-update.swift "$zip" "$app/Contents/Info.plist" "$stage/signature"
python3 scripts/appcast.py "$version" "$build" "$RELEASE_REPO" "$stage/signature"
(cd dist && shasum -a 256 Shade.zip Shade.dmg appcast.xml > SHA256SUMS)
echo 'Signed, notarized release assets ready in dist/'
