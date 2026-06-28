#!/usr/bin/env bash
# Launch Mythreach with TWO desktop clients for MULTIPLAYER / PARTY testing.
# Each client uses its own local dev-wallet (--id) and auto-joins the first world
# (--auto), so you instantly get 2 players in the same world — no clicking.
#
# Try across the two windows: /party invite <name>, /party accept, /p <msg>,
# /wave  /dance  /cheer, and press X to sit. Ctrl+C stops everything.
#
# (This is the DESKTOP test rig with simulated dev-wallets — for the REAL Phantom
#  flow use ./run-web.sh and open http://localhost:8000 in a browser.)
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$PROJECT_DIR/.run-logs"
mkdir -p "$LOG_DIR"

pids=()
cleanup() { echo; echo "Shutting down..."; for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

start_server() {
  "$GODOT" --headless --path "$PROJECT_DIR" "--mode=$1" > "$LOG_DIR/$1.log" 2>&1 &
  pids+=($!)
}

start_server master-server
sleep 2
start_server gateway-server
start_server world-server
sleep 2

echo "Launching 2 client windows (player 1 + player 2)..."
"$GODOT" --path "$PROJECT_DIR" --mode=client --auto --id=p1 > "$LOG_DIR/client-p1.log" 2>&1 &
pids+=($!)
sleep 1
"$GODOT" --path "$PROJECT_DIR" --mode=client --auto --id=p2 > "$LOG_DIR/client-p2.log" 2>&1 &
pids+=($!)

echo "──────────────────────────────────────────────────────────────"
echo "  2 players are in the same world. In a client's chat (Enter), try:"
echo "    /party invite <other player's name>   (then /party accept in the other)"
echo "    /p hello party!     /wave   /dance     (X = sit)"
echo "  Ctrl+C here stops everything."
echo "──────────────────────────────────────────────────────────────"
wait
