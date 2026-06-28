#!/usr/bin/env bash
# Launch Mythreach (godot-tiny-mmo) locally on macOS.
# Starts master-server -> gateway-server -> world-server (all headless),
# then opens one client window. Ctrl+C closes everything.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$PROJECT_DIR/.run-logs"
mkdir -p "$LOG_DIR"

pids=()
cleanup() {
  echo
  echo "Shutting down servers..."
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

start_server() {
  local mode="$1"
  echo "Starting $mode (log: $LOG_DIR/$mode.log)"
  "$GODOT" --headless --path "$PROJECT_DIR" "--mode=$mode" \
    > "$LOG_DIR/$mode.log" 2>&1 &
  pids+=($!)
}

# Order matters: master first, then gateway + world.
start_server master-server
sleep 2
start_server gateway-server
start_server world-server
sleep 2

echo "Master dashboard: http://localhost:8080"
echo "Launching client window... (Ctrl+C here to stop everything)"
"$GODOT" --path "$PROJECT_DIR" --mode=client
