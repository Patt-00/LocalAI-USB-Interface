#!/usr/bin/env bash
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_ID="$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
MODEL_DIR="$ROOT/LocalAI/models"
WORK_BASE="${XDG_RUNTIME_DIR:-/tmp}/localai-usb-${UID}-${ROOT_ID}"
PIDFILE="$WORK_BASE/server.pid"

if [ ! -f "$PIDFILE" ]; then
    echo "No LOCAL AI server PID file was found. Nothing was stopped."
    exit 0
fi
server_pid="$(sed -n '1p' "$PIDFILE" 2>/dev/null || true)"
server_start="$(sed -n '2p' "$PIDFILE" 2>/dev/null || true)"
case "$server_pid" in ''|*[!0-9]*) echo "Invalid PID file; nothing was stopped." >&2; exit 1;; esac

if kill -0 "$server_pid" 2>/dev/null; then
    actual_start="$(awk '{print $22}' "/proc/$server_pid/stat" 2>/dev/null || true)"
    if [ -z "$server_start" ] || [ "$actual_start" != "$server_start" ]; then
        echo "PID $server_pid was reused by another process; nothing was stopped." >&2
        exit 1
    fi
    if ! tr '\0' ' ' < "/proc/$server_pid/cmdline" 2>/dev/null | grep -Fq -- "$MODEL_DIR"; then
        echo "PID $server_pid is not this USB's model router; nothing was stopped." >&2
        exit 1
    fi
    child_pids=""
    if command -v pgrep >/dev/null 2>&1; then
        for child_pid in $(pgrep -P "$server_pid" 2>/dev/null || true); do
            child_cmd="$(tr '\0' ' ' < "/proc/$child_pid/cmdline" 2>/dev/null || true)"
            case "$child_cmd" in *"$MODEL_DIR"*) child_pids="$child_pids $child_pid";; esac
        done
    fi
    kill "$server_pid" $child_pids 2>/dev/null || true
    for _ in $(seq 1 40); do kill -0 "$server_pid" 2>/dev/null || break; sleep 0.25; done
    kill -0 "$server_pid" 2>/dev/null && kill -KILL "$server_pid" 2>/dev/null || true
    for child_pid in $child_pids; do
        kill -0 "$child_pid" 2>/dev/null && kill -KILL "$child_pid" 2>/dev/null || true
    done
    for _ in $(seq 1 20); do kill -0 "$server_pid" 2>/dev/null || break; sleep 0.1; done
    kill -0 "$server_pid" 2>/dev/null && { echo "Server did not stop cleanly." >&2; exit 1; }
    for child_pid in $child_pids; do
        kill -0 "$child_pid" 2>/dev/null && { echo "A tracked model process did not stop cleanly." >&2; exit 1; }
    done
fi
rm -f -- "$PIDFILE"
case "$WORK_BASE" in /tmp/localai-usb-*|*/localai-usb-*) [ -d "$WORK_BASE" ] && rm -rf -- "$WORK_BASE";; esac
echo "LOCAL AI stopped. It is now safe to eject the USB."
