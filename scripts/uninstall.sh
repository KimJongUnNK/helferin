#!/bin/bash
# Entfernt Helferlein aus dem aktuellen Account. Erstellte Dokumente bleiben erhalten.
set -uo pipefail
AGENT_ID="at.boenke.helferlein"

launchctl bootout "gui/$(id -u)/$AGENT_ID" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$AGENT_ID.plist"
pkill -x Helferlein 2>/dev/null
rm -rf "$HOME/Applications/Helferlein.app" "$HOME/Library/Application Support/Helferlein"

echo "✅ Helferlein entfernt. Dokumente in ~/Documents/Helferlein bleiben."
echo "   Ollama und das Modell löschen (optional): ollama rm qwen2.5:7b, dann Ollama.app in den Papierkorb."
