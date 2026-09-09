#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
app_dir="$PWD/build/Shade.app"
mkdir -p "$app_dir/Contents/MacOS"
cp .build/release/Shade "$app_dir/Contents/MacOS/Shade"
cp Info.plist "$app_dir/Contents/Info.plist"
# Stable bundle identity and requirement preserve local permissions across rebuilds.
codesign --force --sign "${SHADE_SIGN_IDENTITY:--}" --identifier app.hmirin.shade "$app_dir"
print -r -- "$app_dir"
