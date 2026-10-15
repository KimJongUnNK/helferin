#!/bin/bash
# Installiert Helferlein für den aktuell angemeldeten Account – nur für diesen.
# Andere Accounts auf dem Mac sehen nichts davon. Beim ersten Start richtet man Name, Programme und Stil ein.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="${HELFERLEIN_MODEL:-qwen2.5:7b}"
SUPPORT="$HOME/Library/Application Support/Helferlein"
APPDIR="$HOME/Applications"
AGENT_ID="at.boenke.helferlein"
AGENT="$HOME/Library/LaunchAgents/$AGENT_ID.plist"

say_step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m✖ %s\033[0m\n' "$1"; exit 1; }

# --- 0. System ----------------------------------------------------------------
echo "Installiere Helferlein für den Account „$(id -F 2>/dev/null || whoami)“."
[ "$(uname -m)" = "arm64" ] || echo "⚠️  Kein Apple-Silicon-Mac – das Sprachmodell wird sehr langsam sein."

# --- 1. Xcode Command Line Tools --------------------------------------------
say_step "Prüfe Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null; then
  xcode-select --install || true
  die "Bitte die Command Line Tools fertig installieren (braucht Admin-Passwort) und install.sh danach nochmal starten."
fi

# --- 2. Ollama ---------------------------------------------------------------
say_step "Prüfe Ollama"
find_ollama_app() {
  for d in /Applications "$HOME/Applications"; do
    [ -d "$d/Ollama.app" ] && { echo "$d/Ollama.app"; return; }
  done
}
OLLAMA_APP="$(find_ollama_app || true)"
if [ -z "$OLLAMA_APP" ] && ! command -v ollama >/dev/null; then
  echo "Lade Ollama herunter …"
  TMP="$(mktemp -d)"
  curl -fL --progress-bar -o "$TMP/Ollama.zip" "https://ollama.com/download/Ollama-darwin.zip" \
    || die "Download fehlgeschlagen. Ollama bitte manuell von https://ollama.com/download installieren."
  TARGET=/Applications; [ -w "$TARGET" ] || TARGET="$APPDIR"
  mkdir -p "$TARGET"
  ditto -x -k "$TMP/Ollama.zip" "$TARGET"
  OLLAMA_APP="$TARGET/Ollama.app"
fi

if ! curl -fs http://127.0.0.1:11434/api/tags >/dev/null; then
  open -g -a "${OLLAMA_APP:-Ollama}" 2>/dev/null || (ollama serve >/dev/null 2>&1 &)
  printf "Warte auf Ollama "
  for _ in $(seq 1 60); do
    curl -fs http://127.0.0.1:11434/api/tags >/dev/null && break
    printf "."; sleep 1
  done
  echo
  curl -fs http://127.0.0.1:11434/api/tags >/dev/null || die "Ollama startet nicht. Einmal Ollama.app per Hand öffnen und nochmal versuchen."
fi

say_step "Lade Sprachmodell $MODEL (ca. 4–5 GB, dauert etwas)"
OLLAMA_BIN="$(command -v ollama || true)"
[ -z "$OLLAMA_BIN" ] && [ -n "$OLLAMA_APP" ] && OLLAMA_BIN="$OLLAMA_APP/Contents/Resources/ollama"
if [ -x "${OLLAMA_BIN:-}" ]; then
  "$OLLAMA_BIN" pull "$MODEL"
else
  curl -fsS http://127.0.0.1:11434/api/pull -d "{\"model\":\"$MODEL\",\"stream\":false}" >/dev/null \
    || die "Modell konnte nicht geladen werden."
fi

# --- 3. Dokument-Werkzeug (Python) ------------------------------------------
say_step "Richte Dokument-Werkzeug ein"
mkdir -p "$SUPPORT" "$HOME/Documents/Helferlein"
[ -x "$SUPPORT/venv/bin/python3" ] || /usr/bin/python3 -m venv "$SUPPORT/venv"
"$SUPPORT/venv/bin/python3" -m pip install --quiet --upgrade pip
"$SUPPORT/venv/bin/python3" -m pip install --quiet -r helper/requirements.txt
cp helper/craftdocs.py "$SUPPORT/craftdocs.py"

# --- 4. Programme finden (ArtCraft-Familie + Brave) ---------------------------
say_step "Suche die ArtCraft-Programme und Brave"
for pair in "WordCraft:Word" "GridCraft:Excel" "DeckCraft:PowerPoint" "PdfCraft:PDF Acrobat" "PhotoCraft:Photoshop" \
            "LightCraft:Lightroom" "VectorCraft:Illustrator" "DesignCraft:InDesign" "FilmCraft:Premiere" \
            "EffectCraft:After Effects" "SoundCraft:Pro Tools" "CADCraft:AutoCAD" "FigCraft:Figma" "Brave Browser:Internet"; do
  app="${pair%%:*}"; label="${pair#*:}"
  hit="$(find /Applications "$HOME/Applications" -maxdepth 3 -iname "${app// /*}*.app" -prune 2>/dev/null | head -n 1)"
  [ -z "$hit" ] && [ "$app" = "PdfCraft" ] && hit="$(find /Applications "$HOME/Applications" -maxdepth 3 -iname "PrintCraft*.app" -prune 2>/dev/null | head -n 1)"
  if [ -n "$hit" ]; then echo "  ✓ $label ($app)"; else echo "  · $label ($app) nicht installiert"; fi
done
echo "  Fehlende ArtCraft-Programme: https://github.com/storytold/craft-launcher"

# Technische Einstellungen (App-Namen findet Helferlein selbst)
if [ ! -f "$SUPPORT/config.json" ]; then
  cat > "$SUPPORT/config.json" <<JSON
{
  "model": "$MODEL",
  "speechRate": 0,
  "silenceSeconds": 1.6,
  "voiceName": "",
  "noSpeechSeconds": 7,
  "maxReprompts": 1
}
JSON
fi
echo "  Einstellungen: $SUPPORT/config.json"

# --- 4b. Schöne weibliche Stimme ---------------------------------------------
say_step "Prüfe deutsche Stimme"
VOICES="$(say -v '?' 2>/dev/null | grep -E 'de_(DE|AT|CH)' || true)"
if echo "$VOICES" | grep -qiE '^(Anna|Petra|Helena|Marlene).*\((Premium|Enhanced|Erweitert)\)'; then
  echo "  ✓ Hochwertige Stimme vorhanden:"
  echo "$VOICES" | grep -iE '\((Premium|Enhanced|Erweitert)\)' | sed 's/^/     /'
else
  echo "  ⚠️  Noch keine hochwertige weibliche Stimme installiert. So geht's (2 Minuten):"
  echo "     Systemeinstellungen → Bedienungshilfen → Gesprochene Inhalte → Systemstimme → Stimmen verwalten …"
  echo "     → Deutsch → „Anna (Premium)“ laden. Helferlein nimmt sie danach automatisch."
  open "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent" 2>/dev/null || true
fi

# --- 5. App bauen und nur für diesen Account installieren -----------------------
say_step "Baue Helferlein"
./scripts/build-app.sh
mkdir -p "$APPDIR"
pkill -x Helferlein 2>/dev/null || true
rm -rf "$APPDIR/Helferlein.app"
cp -R build/Helferlein.app "$APPDIR/"

# --- 6. Starten (Autostart richtet Helferlein selbst ein) ----------------------
say_step "Starte Helferlein"
# Alter LaunchAgent aus früheren Versionen: Helferlein übernimmt den Autostart jetzt selbst
launchctl bootout "gui/$(id -u)/$AGENT_ID" 2>/dev/null || true
rm -f "$AGENT"
open "$APPDIR/Helferlein.app"

echo
echo "✅ Fertig. Helferlein startet jetzt und ab sofort bei jedem Login in diesem Account."
echo "   Beim ersten Start: Vorname, wofür, Programme und Sprechstil einrichten."
echo "   Beim ersten Start fragt macOS nach Mikrofon und Spracherkennung → beides erlauben."
echo
echo "   Word (WordCraft) auf Deutsch mit Rechtschreibprüfung:"
echo "   ./extras/wordcraft-deutsch/install.sh   (oder in Helferlein: Zahnrad › Word auf Deutsch)"
