#!/bin/bash
# Baut build/Helferlein.app (braucht die Xcode Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Helferlein"
APP="build/Helferlein.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Helferlein"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App-Icon aus dem Logo (orange, helfende Hände)
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/Logo/logo-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) Resources/Logo/logo-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier at.boenke.helferlein "$APP"

echo "✅ Gebaut: $APP"
