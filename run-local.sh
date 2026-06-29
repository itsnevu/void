#!/usr/bin/env bash
# Boot the full local stack (master -> gateway -> world) RELIABLY on macOS.
#
# Why this script exists: if more than one world-server is ever running, the
# master keeps BOTH in its world roster. `enter_world` then registers your
# auth-token on one world while the browser connects to whichever world owns
# :8087 -> token not found -> "Couldn't reach the world." So step 1 is ALWAYS
# to kill every stale godot process before starting a fresh, single stack.
#
# Usage:  ./run-local.sh          (boot the stack)
#         ./run-local.sh stop     (kill the stack)
#         ./run-local.sh status   (show what's running)
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="$ROOT/.run-logs"

godot_procs() { pgrep -fl "MacOS/Godot.*mode=" 2>/dev/null | sed 's#.*MacOS/Godot#Godot#' || true; }

kill_all() {
  echo ">> killing any existing godot mode processes..."
  pkill -9 -f "Godot.*mode=" 2>/dev/null || true
  # wait for the ports to actually free (max ~6s)
  for _ in 1 2 3 4 5 6; do
    pgrep -f "MacOS/Godot.*mode=" >/dev/null 2>&1 || break
    sleep 1
  done
}

start_one() {
  local mode="$1" wait="$2"
  echo ">> starting $mode"
  nohup "$GODOT" --headless --path "$ROOT" --mode="$mode" > "$LOGDIR/$mode.log" 2>&1 &
  sleep "$wait"
}

case "${1:-up}" in
  stop)
    kill_all
    echo "stopped."
    ;;
  status)
    echo "=== godot processes ==="; godot_procs || echo "  (none)"
    echo "=== listening ports ==="
    lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | grep -iE "8087|8088|8080|8062|8064" | awk '{print "  "$1, $9}' || echo "  (none)"
    ;;
  up|"")
    [ -x "$GODOT" ] || { echo "Godot not found at $GODOT (set GODOT=...)"; exit 1; }
    mkdir -p "$LOGDIR"
    kill_all
    start_one master-server 5
    start_one gateway-server 5
    start_one world-server 6
    echo
    echo "=== stack status ==="
    godot_procs
    echo "--- ports ---"
    lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | grep -iE "8087|8088|8080" | awk '{print "  "$1, $9}'
    echo
    # sanity: exactly one world must be registered with the master
    worlds=$(grep -ic "World:.*connected to WorldManager" "$LOGDIR/master-server.log" 2>/dev/null || echo 0)
    echo "worlds registered with master: $worlds (must be 1)"
    [ "$worlds" = "1" ] && echo "OK - clean single stack. Open the web client and enter the world." \
                        || echo "WARN - expected exactly 1 world; check $LOGDIR/*.log"
    ;;
  *)
    echo "usage: $0 [up|stop|status]"; exit 1
    ;;
esac
