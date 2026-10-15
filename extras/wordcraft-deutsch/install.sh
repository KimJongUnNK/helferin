#!/bin/bash
# WordCraft auf Deutsch – mit echter deutscher Rechtschreibprüfung.
#
#   ./install.sh            installieren / nach einem WordCraft-Update erneut ausführen
#   ./install.sh --restore  Original-WordCraft wiederherstellen
#
# Was passiert:
#   1. Deutsche Wörterbücher (Österreich, Deutschland, Schweiz) nach ~/Library/Spelling
#   2. WordCraft mit Deutsch-Erweiterung (Komposita, Vorschläge): fertig gebaut von GitHub,
#      sonst wird es hier aus dem Quellcode gebaut (Rust wird bei Bedarf installiert)
#   3. WordCraft startet auf Deutsch, neue Dokumente sind Deutsch
# Das Original wird gesichert und lässt sich mit --restore zurückholen.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="KimJongUnNK/helferin"
PREBUILT_URL="https://github.com/$REPO/releases/latest/download/WordCraft-Deutsch-macos-arm64.zip"
PATCH_URL="https://raw.githubusercontent.com/$REPO/main/extras/wordcraft-deutsch/wordcraft-deutsch.patch"
DICT_BASE="https://raw.githubusercontent.com/LibreOffice/dictionaries/master/de"
SPELLING="$HOME/Library/Spelling"
STATE="$HOME/Library/Application Support/Helferlein/wordcraft-deutsch"
AGENT_ID="at.boenke.helferlein.wordcraft-deutsch"
AGENT="$HOME/Library/LaunchAgents/$AGENT_ID.plist"
MARKER_NAME="helferlein-deutsch.txt"

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
die()  { printf '\n\033[31m✖ %s\033[0m\n' "$1"; exit 1; }

find_wordcraft() {
  find /Applications "$HOME/Applications" -maxdepth 3 -iname "WordCraft*.app" -prune 2>/dev/null | head -n 1
}

APP="$(find_wordcraft)"
[ -n "$APP" ] || die "WordCraft ist nicht installiert. Erst über den ArtCraft Launcher installieren: https://github.com/storytold/craft-launcher"
BIN="$APP/Contents/MacOS/WordCraft"
[ -f "$BIN" ] || BIN="$(find "$APP/Contents/MacOS" -maxdepth 1 -type f -perm -111 | head -n 1)"
[ -f "$BIN" ] || die "In $APP fehlt das Programm."
VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo unbekannt)"

# Schreibrechte: /Applications gehört oft dem Admin
SUDO=""
[ -w "$BIN" ] && [ -w "$APP/Contents" ] || SUDO="sudo"

quit_wordcraft() {
  if pgrep -x WordCraft >/dev/null; then
    osascript -e 'tell application "WordCraft" to quit' >/dev/null 2>&1 || true
    sleep 2
    pkill -x WordCraft 2>/dev/null || true
  fi
}

resign() {
  $SUDO xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
  $SUDO codesign --force --deep --sign - "$APP" >/dev/null
}

# --- Wiederherstellen ----------------------------------------------------------
if [ "${1:-}" = "--restore" ]; then
  [ -f "$STATE/WordCraft.original" ] || die "Keine Sicherung gefunden ($STATE)."
  quit_wordcraft
  $SUDO cp "$STATE/WordCraft.original" "$BIN"
  $SUDO rm -f "$APP/Contents/Resources/$MARKER_NAME"
  resign
  launchctl bootout "gui/$(id -u)/$AGENT_ID" 2>/dev/null || true
  rm -f "$AGENT"
  launchctl unsetenv WORDCRAFT_LANGUAGE 2>/dev/null || true
  ok "Original-WordCraft wiederhergestellt."
  exit 0
fi

echo "WordCraft $VERSION gefunden: $APP"

# --- 1. Wörterbücher ---------------------------------------------------------------
step "Lade deutsche Wörterbücher (igerman98, GPL) nach ~/Library/Spelling"
mkdir -p "$SPELLING"
for name in de_AT_frami de_DE_frami de_CH_frami; do
  for ext in aff dic; do
    if [ ! -s "$SPELLING/$name.$ext" ]; then
      curl -fsSL -o "$SPELLING/$name.$ext.tmp" "$DICT_BASE/$name.$ext" && mv "$SPELLING/$name.$ext.tmp" "$SPELLING/$name.$ext"
    fi
  done
  ok "$name"
done
curl -fsSL -o "$SPELLING/COPYING-igerman98.txt" "$DICT_BASE/COPYING_GPLv2" 2>/dev/null || true

# --- 2. WordCraft mit Deutsch ------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
NEW_BIN=""

step "Hole WordCraft mit Deutsch-Erweiterung"
if curl -fsSL -o "$WORK/prebuilt.zip" "$PREBUILT_URL" 2>/dev/null; then
  ditto -x -k "$WORK/prebuilt.zip" "$WORK/prebuilt"
  NEW_BIN="$(find "$WORK/prebuilt" -type f -name WordCraft | head -n 1)"
  [ -n "$NEW_BIN" ] && ok "fertig gebaute Version von GitHub ($(cat "$WORK/prebuilt/VERSION" 2>/dev/null || echo '?'))"
fi

if [ -z "$NEW_BIN" ]; then
  echo "  Keine fertige Version erreichbar – baue aus dem Quellcode (dauert ca. 10–20 Minuten)."
  if ! command -v cargo >/dev/null; then
    [ -x "$HOME/.cargo/bin/cargo" ] || {
      echo "  Installiere Rust (nur für diesen Benutzer) …"
      curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal >/dev/null
    }
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  command -v git >/dev/null || die "git fehlt (xcode-select --install)."
  SRC="$WORK/wordcraft"
  git clone -q --depth 1 --branch "v$VERSION" https://github.com/storytold/wordcraft "$SRC" 2>/dev/null \
    || git clone -q --depth 1 https://github.com/storytold/wordcraft "$SRC"
  PATCH="$HERE/wordcraft-deutsch.patch"
  [ -f "$PATCH" ] || { curl -fsSL -o "$WORK/de.patch" "$PATCH_URL"; PATCH="$WORK/de.patch"; }
  (cd "$SRC" && git apply --3way "$PATCH") || die "Die Deutsch-Erweiterung passt nicht auf diese WordCraft-Version. Bitte Helferlein aktualisieren."
  (cd "$SRC" && cargo build --release -p wordcraft)
  NEW_BIN="$SRC/target/release/wordcraft"
  ok "gebaut"
fi

# --- 3. Einbauen -----------------------------------------------------------------
step "Baue Deutsch in WordCraft ein"
quit_wordcraft
mkdir -p "$STATE"
if [ ! -f "$APP/Contents/Resources/$MARKER_NAME" ] || [ ! -f "$STATE/WordCraft.original" ]; then
  cp "$BIN" "$STATE/WordCraft.original"   # Sicherung des Originals (vor jedem neuen WordCraft-Update)
  echo "$VERSION" > "$STATE/original-version"
fi
$SUDO cp "$NEW_BIN" "$BIN"
$SUDO chmod +x "$BIN"
printf 'WordCraft Deutsch-Erweiterung von Helferlein\nWordCraft %s\n%s\n' "$VERSION" "$(date '+%Y-%m-%d')" \
  | $SUDO tee "$APP/Contents/Resources/$MARKER_NAME" >/dev/null
resign
ok "eingebaut (Original gesichert in $STATE)"

# --- 4. WordCraft auf Deutsch --------------------------------------------------------
step "Stelle WordCraft auf Deutsch"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$AGENT_ID</string>
  <key>ProgramArguments</key>
  <array><string>/bin/launchctl</string><string>setenv</string><string>WORDCRAFT_LANGUAGE</string><string>de</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)/$AGENT_ID" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT" 2>/dev/null || true
launchctl setenv WORDCRAFT_LANGUAGE de
ok "Oberfläche Deutsch, neue Dokumente Deutsch (gilt ab jetzt bei jedem Login)"

echo
echo "✅ Fertig. WordCraft prüft jetzt deutsche Rechtschreibung (rote Wellenlinie, Rechtsklick = Vorschläge)."
echo "   Bei Texten, die noch als Englisch markiert sind: Text markieren → Überprüfen › Sprache → Deutsch."
echo "   Nach einem WordCraft-Update einfach dieses Skript nochmal ausführen."
echo "   Zurück zum Original: $0 --restore"
