#!/bin/bash
# Prüft alle Bausteine auf dem Mac: Dokument-Werkzeug, Swift-Build, Modell-Antworten.
set -uo pipefail
cd "$(dirname "$0")/.."
SUPPORT="$HOME/Library/Application Support/Helferlein"
PY="$SUPPORT/venv/bin/python3"; [ -x "$PY" ] || PY=python3
MODEL="$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1])).get("model","qwen2.5:7b"))' "$SUPPORT/config.json" 2>/dev/null || echo qwen2.5:7b)"
FAIL=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✖\033[0m %s\n' "$1"; FAIL=1; }

echo "1) Dokument-Werkzeug"
(cd helper && "$PY" -m unittest -q test_craftdocs) && ok "Word/PDF/PowerPoint-Tests" || bad "Word/PDF/PowerPoint-Tests"

echo "2) Swift-Build"
if BUILD_LOG="$(swift build -c release 2>&1)"; then
  ok "kompiliert"
else
  bad "Build fehlgeschlagen – die ersten Fehler:"
  echo "$BUILD_LOG" | grep -E "error:" | head -15 | sed 's/^/     /'
fi

echo "3) Ollama + Modell ($MODEL)"
if ! curl -fs http://127.0.0.1:11434/api/tags >/dev/null; then
  bad "Ollama läuft nicht"
else
  ok "Ollama läuft"
  check() { # $1 = Eingabe, $2 = erwartete action
    local body out
    body="$("$PY" - "$MODEL" "$1" <<'PY'
import json, sys
schema = {"type": "object", "properties": {
  "reply": {"type": "string"},
  "action": {"type": "string", "enum": ["none", "create_document", "create_pdf", "create_presentation", "open_file", "open_website", "web_search", "close"]},
  "title": {"type": "string"}, "query": {"type": "string"}, "url": {"type": "string"},
  "sections": {"type": "array", "items": {"type": "object", "properties": {"heading": {"type": "string"}, "text": {"type": "string"}}, "required": ["heading", "text"]}},
  "slides": {"type": "array", "items": {"type": "object", "properties": {"title": {"type": "string"}, "bullets": {"type": "array", "items": {"type": "string"}}}, "required": ["title", "bullets"]}}},
  "required": ["reply", "action"]}
system = ("Du bist Helferlein. Aktionen: create_document (Brief/Liste in Word → sections), create_pdf (IMMER wenn das Wort PDF vorkommt), "
          "create_presentation (PowerPoint, slides), "
          "open_file (query), web_search (query, Brave), open_website (url), close (keine Hilfe nötig), none.")
print(json.dumps({"model": sys.argv[1], "stream": False, "format": schema, "options": {"temperature": 0.2},
                  "messages": [{"role": "system", "content": system}, {"role": "user", "content": sys.argv[2]}]}))
PY
)"
    out="$(curl -fs http://127.0.0.1:11434/api/chat -d "$body" | "$PY" -c 'import json,sys; print(json.loads(json.load(sys.stdin)["message"]["content"])["action"])' 2>/dev/null)"
    [ "$out" = "$2" ] && ok "„$1“ → $out" || bad "„$1“ → ${out:-keine gültige Antwort} (erwartet: $2)"
  }
  check "Schreib mir bitte eine Einkaufsliste für einen Apfelstrudel" create_document
  check "Mach mir eine kurze Präsentation über Vorarlberg" create_presentation
  check "Mach mir die Einladung zum Geburtstag bitte als PDF" create_pdf
  check "Such mir im Internet das Wetter für Dornbirn morgen" web_search
  check "Nein danke, heute brauche ich nichts" close
fi

echo "4) Stimme"
if say -v '?' 2>/dev/null | grep -qiE '^(Anna|Petra|Helena|Marlene).*\((Premium|Enhanced|Erweitert)\)'; then
  ok "hochwertige weibliche Stimme installiert"
  say -v '?' | grep -iE 'de_(DE|AT|CH)' | grep -iE '\((Premium|Enhanced|Erweitert)\)' | sed 's/^/     /'
else
  bad "keine Premium-Stimme – README › Stimme lesen"
fi

echo
[ $FAIL -eq 0 ] && echo "✅ Alles grün." || echo "⚠️  Siehe rote Punkte oben."
exit $FAIL
