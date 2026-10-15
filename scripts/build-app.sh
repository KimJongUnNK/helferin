#!/bin/bash
# Baut build/Helferlein.app (braucht die Xcode Command Line Tools).
#
#   EMBED_PYTHON=/pfad/zu/python   eigenständiges Python (python-build-standalone) mit
#                                  python-docx, python-pptx, reportlab, openpyxl einbauen
#                                  → Download-Version, die ohne install.sh läuft
#   HELFERLEIN_VERSION=1.2.3       Versionsnummer in die App schreiben
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Helferlein"
APP="build/Helferlein.app"
RES="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"
cp "$BIN" "$APP/Contents/MacOS/Helferlein"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${HELFERLEIN_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${HELFERLEIN_VERSION#v}" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-1}" "$APP/Contents/Info.plist"
fi

# App-Icon aus dem Logo (orange, helfende Hände)
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/Logo/logo-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) Resources/Logo/logo-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"

# Dokument-Werkzeug und WordCraft-Deutsch-Paket mitliefern
cp helper/craftdocs.py "$RES/craftdocs.py"
mkdir -p "$RES/wordcraft-deutsch"
cp extras/wordcraft-deutsch/install.sh extras/wordcraft-deutsch/wordcraft-deutsch.patch extras/wordcraft-deutsch/BASE_COMMIT "$RES/wordcraft-deutsch/"

# Eigenständiges Python einbauen (Download-Version)
if [ -n "${EMBED_PYTHON:-}" ]; then
  [ -x "$EMBED_PYTHON/bin/python3" ] || { echo "EMBED_PYTHON: $EMBED_PYTHON/bin/python3 fehlt" >&2; exit 1; }
  ditto "$EMBED_PYTHON" "$RES/python"
  # Bytecode jetzt (vor dem Signieren) erzeugen; zur Laufzeit läuft Python mit -B und schreibt nichts ins Paket
  "$RES/python/bin/python3" -I -m compileall -q -j 0 "$RES/python/lib" >/dev/null || true
  # Jede ausführbare Datei / Bibliothek darin einzeln (ad hoc) signieren
  find "$RES/python" -type f \( -name "*.so" -o -name "*.dylib" -o -perm -u+x \) -print0 \
    | while IFS= read -r -d '' f; do
        if file "$f" | grep -q "Mach-O"; then codesign --force --sign - "$f" >/dev/null 2>&1 || true; fi
      done
  "$RES/python/bin/python3" -I -B -c "import docx, pptx, reportlab, openpyxl; print('Python ok')"
fi

find "$APP" -name ".DS_Store" -delete
codesign --force --sign - --identifier at.boenke.helferlein "$APP"
codesign --verify --deep --strict "$APP"
echo "✅ Gebaut: $APP"
