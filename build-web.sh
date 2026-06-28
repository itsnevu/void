#!/usr/bin/env bash
# Build the PRODUCTION web client (static files) into exports/web/ for Vercel.
# This builds ONLY the client — the master/gateway/world servers run elsewhere
# (see DEPLOY.md). After this, deploy with:  vercel deploy --prod
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$PROJECT_DIR/exports/web"

TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/4.7.stable"
if [ ! -f "$TEMPLATES_DIR/web_nothreads_release.zip" ] && [ ! -f "$TEMPLATES_DIR/web_release.zip" ]; then
  echo "✗ Godot 4.7 web export templates not installed (Editor > Manage Export Templates)."
  exit 1
fi

mkdir -p "$WEB_DIR"
echo "▸ Importing project…"
"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1 || true

echo "▸ Exporting RELEASE web build → $WEB_DIR/index.html"
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "Web" "$WEB_DIR/index.html" 2>&1 | tail -4

# Custom favicon (the blocky-knight mark) over the engine-generated icons.
cp "$PROJECT_DIR/assets/sprites/gui/branding/favicon_128.png" "$WEB_DIR/index.icon.png" 2>/dev/null || true
cp "$PROJECT_DIR/assets/sprites/gui/branding/favicon_180.png" "$WEB_DIR/index.apple-touch-icon.png" 2>/dev/null || true

echo
echo "✓ Web client built in exports/web/"
echo "  Deploy:  vercel deploy --prod        (serves exports/web via vercel.json)"
echo "  NOTE: the game servers must run separately — see DEPLOY.md."
