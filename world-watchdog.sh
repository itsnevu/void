#!/usr/bin/env bash
# Keep the world-server ALIVE on macOS.
#
# Why: on Apple-Silicon macOS the headless world-server intermittently SIGSEGVs
# in MoltenVK while loading the map scene (a GPU/Metal driver bug, NOT game code -
# see the run-locally notes). It's transient: relaunching on a clean slate boots
# fine most tries. This watchdog relaunches it whenever it's not up + listening on
# :8087, with a cooldown so we don't thrash the GPU (rapid restarts make the crash
# MORE likely). master + gateway stay owned by run-local.sh - this only guards the world.
#
# Usage:
#   ./run-local.sh            # start master + gateway (+ a first world try)
#   ./world-watchdog.sh       # then run this; leave it running. Ctrl+C to stop.
#
# It survives crashes: the web client's "No worlds online" clears within ~10s of a
# crash because the world is right back up. Don't also let run-local.sh manage the
# world while this runs (they'd fight) - this is the world's owner once started.
set -uo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="$ROOT/.run-logs"
COOLDOWN="${COOLDOWN:-5}"   # seconds to wait before a relaunch (GPU settle)
BOOT_WAIT="${BOOT_WAIT:-9}" # seconds to let a fresh world boot + bind :8087
mkdir -p "$LOGDIR"

[ -x "$GODOT" ] || { echo "[watchdog] Godot not found at $GODOT - install it (brew reinstall --cask godot)"; exit 1; }

world_up() {
  pgrep -f "MacOS/Godot.*mode=world-server" >/dev/null 2>&1 \
    && lsof -nP -iTCP:8087 -sTCP:LISTEN >/dev/null 2>&1
}

launches=0
echo "[watchdog] guarding world-server (cooldown ${COOLDOWN}s, boot-wait ${BOOT_WAIT}s). Ctrl+C to stop."
trap 'echo "[watchdog] stopped."; exit 0' INT TERM

while true; do
  if ! world_up; then
    pkill -9 -f "mode=world-server" 2>/dev/null || true
    sleep "$COOLDOWN"
    launches=$((launches + 1))
    echo "[watchdog] $(date '+%H:%M:%S') world down -> relaunch #$launches"
    nohup "$GODOT" --headless --path "$ROOT" --mode=world-server > "$LOGDIR/world-server.log" 2>&1 &
    sleep "$BOOT_WAIT"
    if world_up; then
      echo "[watchdog] $(date '+%H:%M:%S') world UP (:8087 listening)"
    else
      echo "[watchdog] $(date '+%H:%M:%S') boot failed (likely the transient crash) - will retry"
    fi
  fi
  sleep 3
done
