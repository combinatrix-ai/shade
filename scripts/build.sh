#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
app_dir="$PWD/build/Shade.app"
mkdir -p "$app_dir/Contents/MacOS"
cp .build/release/Shade "$app_dir/Contents/MacOS/Shade"
cp Info.plist "$app_dir/Contents/Info.plist"
# A certificate-based identity is recommended for stable permissions across rebuilds.
sign_identity="${SHADE_SIGN_IDENTITY:-}"
if [[ -z "$sign_identity" && -f .signing-identity ]]; then
  sign_identity="$(<.signing-identity)"
fi
codesign --force --sign "${sign_identity:--}" --identifier app.hmirin.shade "$app_dir"
print -r -- "$app_dir"
