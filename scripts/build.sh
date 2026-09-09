#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
app_dir="$PWD/build/Shade.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Frameworks" "$app_dir/Contents/Resources"
cp .build/release/Shade "$app_dir/Contents/MacOS/Shade"
cp Info.plist "$app_dir/Contents/Info.plist"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$app_dir/Contents/Resources/Sparkle-LICENSE"
ditto .build/release/Sparkle.framework "$app_dir/Contents/Frameworks/Sparkle.framework"
swift scripts/icon.swift "$PWD/build"
iconutil -c icns build/Shade.iconset -o "$app_dir/Contents/Resources/Shade.icns"
sign_identity="${SHADE_SIGN_IDENTITY:-}"
if [[ -z "$sign_identity" && -f .signing-identity ]]; then
  sign_identity="$(<.signing-identity)"
fi
sign_identity="${sign_identity:--}"
sign_args=(--force --sign "$sign_identity")
if [[ "${DISTRIBUTION:-0}" == 1 ]]; then
  [[ "$sign_identity" == "Developer ID Application:"* ]] || { print -u2 'Developer ID signing identity required'; exit 1; }
  sign_args+=(--options runtime --timestamp)
else
  sign_args+=(--timestamp=none)
fi
framework="$app_dir/Contents/Frameworks/Sparkle.framework"
for nested in "$framework/Versions/B/XPCServices/Downloader.xpc" "$framework/Versions/B/XPCServices/Installer.xpc" "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app" "$framework"; do
  codesign "${sign_args[@]}" "$nested" || codesign "${sign_args[@]}" "$nested"
done
codesign "${sign_args[@]}" "$app_dir"
codesign --verify --deep --strict "$app_dir"
print -r -- "$app_dir"
