#!/bin/bash
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_ID="$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
MODEL_DIR="$ROOT/LocalAI/models"
WORK_BASE="${TMPDIR:-/tmp}"
WORK_BASE="${WORK_BASE%/}/localai-usb-$UID-$ROOT_ID"
PIDFILE="$WORK_BASE/server.pid"
STATEFILE="$WORK_BASE/runtime-path.txt"
if [ ! -f "$PIDFILE" ]; then echo "No LOCAL AI PID file found. Nothing was stopped."; read -r -p "Press Return..." _; exit 0; fi
server_pid="$(sed -n '1p' "$PIDFILE" 2>/dev/null || true)"
server_start="$(sed -n '2p' "$PIDFILE" 2>/dev/null || true)"
case "$server_pid" in ''|*[!0-9]*) echo "Invalid PID file; nothing stopped." >&2; read -r -p "Press Return..." _; exit 1;; esac
if kill -0 "$server_pid" 2>/dev/null; then
  actual_start="$(ps -p "$server_pid" -o lstart= 2>/dev/null || true)"
  [ -n "$server_start" ] && [ "$actual_start" = "$server_start" ] || { echo "PID was reused by another process; nothing stopped." >&2; read -r -p "Press Return..." _; exit 1; }
  ps -ww -p "$server_pid" -o command= | grep -Fq -- "$MODEL_DIR" || { echo "PID is not this USB's model router; nothing stopped." >&2; read -r -p "Press Return..." _; exit 1; }
  child_pids=""
  if command -v pgrep >/dev/null 2>&1; then
    for child_pid in $(pgrep -P "$server_pid" 2>/dev/null || true); do
      child_cmd="$(ps -ww -p "$child_pid" -o command= 2>/dev/null || true)"
      case "$child_cmd" in *"$MODEL_DIR"*) child_pids="$child_pids $child_pid";; esac
    done
  fi
  kill "$server_pid" $child_pids 2>/dev/null || true
  i=0; while kill -0 "$server_pid" 2>/dev/null && [ "$i" -lt 40 ]; do i=$((i + 1)); sleep 0.25; done
  kill -0 "$server_pid" 2>/dev/null && kill -KILL "$server_pid" 2>/dev/null || true
  for child_pid in $child_pids; do kill -0 "$child_pid" 2>/dev/null && kill -KILL "$child_pid" 2>/dev/null || true; done
  i=0; while kill -0 "$server_pid" 2>/dev/null && [ "$i" -lt 20 ]; do i=$((i + 1)); sleep 0.1; done
  kill -0 "$server_pid" 2>/dev/null && { echo "Server did not stop cleanly." >&2; exit 1; }
  for child_pid in $child_pids; do kill -0 "$child_pid" 2>/dev/null && { echo "A tracked model process did not stop cleanly." >&2; exit 1; }; done
fi
run_runtime="$(sed -n '1p' "$STATEFILE" 2>/dev/null || true)"
case "$run_runtime" in "$WORK_BASE"/runtime) [ -d "$run_runtime" ] && rm -rf "$run_runtime";; esac
case "$WORK_BASE" in /tmp/localai-usb-*|*/localai-usb-*) [ -d "$WORK_BASE" ] && rm -rf "$WORK_BASE";; esac
rm -f "$PIDFILE" "$STATEFILE"
echo "LOCAL AI stopped. It is now safe to eject the USB."
read -r -p "Press Return to close..." _
