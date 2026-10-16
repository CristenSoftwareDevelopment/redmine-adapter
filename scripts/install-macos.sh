#!/bin/bash
# Instala ou atualiza o Redmine Monitor com o DMG da última release do GitHub.
# Baixado pelo curl, o DMG não ganha quarentena, então o Gatekeeper não pede autorização.
set -euo pipefail

APP="Redmine Monitor"
URL=$(curl -fsSL https://api.github.com/repos/CristenSoftwareDevelopment/redmine-adapter/releases/latest |
  grep -o '"browser_download_url": *"[^"]*macos\.dmg"' | cut -d'"' -f4)
TMP=$(mktemp -d)
trap 'hdiutil detach -quiet "$TMP/mnt" 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "Baixando $URL"
curl -fL --progress-bar -o "$TMP/app.dmg" "$URL"
hdiutil attach -nobrowse -quiet -mountpoint "$TMP/mnt" "$TMP/app.dmg"

pkill -x "$APP" || true
rm -rf "/Applications/$APP.app"
ditto "$TMP/mnt/$APP.app" "/Applications/$APP.app"
open "/Applications/$APP.app"
echo "Instalado em /Applications/$APP.app"
