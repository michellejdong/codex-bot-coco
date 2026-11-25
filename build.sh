#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
stage=$(mktemp -d /tmp/coco-build.XXXXXXXX)
trap 'rm -rf -- "$stage"' EXIT
app="$stage/Coco.app"
destination="$root/dist/Coco.app"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/CocoSprite.png" "$root/Resources/Coco.icns" "$app/Contents/Resources/"

xcrun swiftc -O -target "$(uname -m)-apple-macos14.0" \
  "$root"/Sources/*.swift -o "$app/Contents/MacOS/Coco"
"$app/Contents/MacOS/Coco" --self-test
codesign --force --sign - "$app"
codesign --verify --strict "$app"

mkdir -p "$root/dist"
rm -rf -- "$destination"
ditto --norsrc --noextattr "$app" "$destination"
printf 'Built %s\n' "$destination"
