#!/usr/bin/env bash
# RuView sensing-server control script.
# Usage: ./ruview.sh {start|stop|restart|status|logs|ui}
#
# Modes (set MODE env):
#   frictionless (default) — HTTP/WS on 127.0.0.1, no token, full UI works, not LAN-exposed.
#   lan                    — HTTP/WS on 0.0.0.0 with bearer token (reachable from other machines).
# The UDP CSI receiver always binds 0.0.0.0:5005, so the ESP32 boards stream in either mode.

set -uo pipefail

# Resolve repo root from this script's location (no hardcoded paths).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$ROOT/repo/v2/target/release/sensing-server"
UI="$ROOT/repo/ui"
LOG="/tmp/sensing-server.log"
PIDFILE="/tmp/sensing-server.pid"

HTTP_PORT=3000
WS_PORT=3001
UDP_PORT=5005
# Match the server regardless of how it was launched (relative or absolute path).
PATTERN="target/release/sensing-server"
MODE="${MODE:-frictionless}"
# Provide your own token via RUVIEW_API_TOKEN; otherwise a random one is generated for lan mode.
TOKEN="${RUVIEW_API_TOKEN:-$(openssl rand -hex 32)}"
URL="http://localhost:$HTTP_PORT/ui/index.html"

is_running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

start() {
  if is_running; then echo "already running (pid $(cat "$PIDFILE"))."; status; return 0; fi
  # clear any stray instance / freed pidfile, then wait for ports to actually release
  pkill -f "$PATTERN" 2>/dev/null; rm -f "$PIDFILE"
  for _ in $(seq 1 20); do
    lsof -ti ":$WS_PORT" -ti ":$HTTP_PORT" >/dev/null 2>&1 || break
    sleep 0.5
  done
  [ -x "$BIN" ] || { echo "ERROR: server binary not found at $BIN"; exit 1; }
  [ -f "$UI/index.html" ] || echo "WARN: UI not found at $UI (UI pages will 404)."

  if [ "$MODE" = "lan" ]; then
    echo "starting (LAN mode, 0.0.0.0 + token)…"
    RUVIEW_API_TOKEN="$TOKEN" nohup "$BIN" --source esp32 --bind-addr 0.0.0.0 \
      --udp-port "$UDP_PORT" --http-port "$HTTP_PORT" --ws-port "$WS_PORT" \
      --ui-path "$UI" > "$LOG" 2>&1 &
  else
    echo "starting (frictionless mode, 127.0.0.1, no token)…"
    nohup "$BIN" --source esp32 --bind-addr 127.0.0.1 \
      --udp-port "$UDP_PORT" --http-port "$HTTP_PORT" --ws-port "$WS_PORT" \
      --ui-path "$UI" > "$LOG" 2>&1 &
  fi
  echo $! > "$PIDFILE"
  sleep 3
  if is_running; then
    echo "started (pid $(cat "$PIDFILE"))."
    [ "$MODE" = "lan" ] && echo "  API token: $TOKEN"
    status
  else
    echo "FAILED to start. Last log lines:"; tail -8 "$LOG" | sed -E 's/\x1b\[[0-9;]*m//g'
    rm -f "$PIDFILE"; exit 1
  fi
}

stop() {
  if is_running; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    for _ in 1 2 3 4 5; do is_running || break; sleep 0.5; done
    is_running && kill -9 "$(cat "$PIDFILE")" 2>/dev/null
  fi
  pkill -f "$PATTERN" 2>/dev/null
  rm -f "$PIDFILE"
  echo "stopped."
}

status() {
  if is_running; then
    local h; h=$(curl -s --max-time 3 "http://localhost:$HTTP_PORT/health")
    echo "● running (pid $(cat "$PIDFILE")) — mode=$MODE"
    echo "  health: ${h:-<no response>}"
    echo "  UI:     $URL"
  else
    echo "○ not running."
  fi
}

logs() { tail -n "${1:-40}" -f "$LOG"; }

ui() {
  is_running || { echo "server not running — start it first."; exit 1; }
  open "$URL" 2>/dev/null && echo "opened $URL" || echo "open this in your browser: $URL"
}

case "${1:-}" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; sleep 1; start ;;
  status)  status ;;
  logs)    logs "${2:-40}" ;;
  ui|open) ui ;;
  *) echo "Usage: $0 {start|stop|restart|status|logs|ui}"
     echo "  MODE=lan $0 start   # LAN-exposed + token instead of loopback frictionless"
     exit 1 ;;
esac
