#!/usr/bin/env bash
# Build + serve Mythreach as a WEB build so you can connect the REAL Phantom wallet.
# Phantom is a browser extension, so wallet sign-in only works in a browser tab —
# NOT in the desktop client (run.sh), which uses a local dev-wallet instead.
#
# This starts the 3 servers locally, exports the web client, and serves it at
# http://localhost:8000 . Open that in a browser that has the Phantom extension,
# click "Connect Wallet", approve in Phantom — done. Ctrl+C stops everything.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$PROJECT_DIR/.run-logs"
WEB_DIR="$PROJECT_DIR/exports/web"
PORT="${PORT:-8000}"
mkdir -p "$LOG_DIR" "$WEB_DIR"

# --- Preflight: web export templates must be installed -----------------------
TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/4.7.stable"
if [ ! -f "$TEMPLATES_DIR/web_nothreads_debug.zip" ] && [ ! -f "$TEMPLATES_DIR/web_debug.zip" ]; then
  echo "✗ Web export templates for Godot 4.7 are not installed."
  echo "  Install them ONE of these ways, then re-run ./run-web.sh :"
  echo "    A) In the Godot editor: Editor menu > Manage Export Templates > Download and Install"
  echo "    B) CLI: $GODOT --headless --export-templates-download   (if your build supports it)"
  exit 1
fi

pids=()
cleanup() {
  echo; echo "Shutting down..."
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT INT TERM

start_server() {
  local mode="$1"
  echo "Starting $mode (log: $LOG_DIR/$mode.log)"
  "$GODOT" --headless --path "$PROJECT_DIR" "--mode=$mode" > "$LOG_DIR/$mode.log" 2>&1 &
  pids+=($!)
}

# Order matters: master first, then gateway + world.
start_server master-server
sleep 2
start_server gateway-server
start_server world-server
sleep 2

# --- Export the web client ---------------------------------------------------
echo "Exporting web build → $WEB_DIR/index.html"
"$GODOT" --headless --path "$PROJECT_DIR" --export-debug "Web" "$WEB_DIR/index.html" 2>&1 \
  | tail -5

# Custom favicon (the blocky-knight character) — overwrite the engine-generated icons
# the export just produced so the browser tab shows our mark, not the Godot default.
cp "$PROJECT_DIR/assets/sprites/gui/branding/favicon_128.png" "$WEB_DIR/index.icon.png" 2>/dev/null || true
cp "$PROJECT_DIR/assets/sprites/gui/branding/favicon_180.png" "$WEB_DIR/index.apple-touch-icon.png" 2>/dev/null || true

# --- Serve it ----------------------------------------------------------------
echo
echo "──────────────────────────────────────────────────────────────"
echo "  Open in a browser with the Phantom extension:"
echo "    http://localhost:$PORT"
echo "  Click 'Connect Wallet' → approve in Phantom."
echo "  (Ctrl+C here stops the servers + web host.)"
echo "──────────────────────────────────────────────────────────────"
cd "$WEB_DIR"
# Serve with no-store headers so the browser NEVER shows a stale .wasm/.pck after a
# re-export (Godot web filenames aren't hashed, so default caching is sticky).
python3 -c "
import http.server, socketserver
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('', $PORT), H) as httpd:
    httpd.serve_forever()
"
