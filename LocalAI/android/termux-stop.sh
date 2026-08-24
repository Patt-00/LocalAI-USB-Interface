#!/data/data/com.termux/files/usr/bin/bash
set -u

BASE="$HOME/.localai-usb"
RUNTIME="$BASE/runtime"
BRIDGE="$BASE/bin/localai-agent"
STATE="$BASE/state"
PROCESS_FILE="$STATE/process.json"
TOKEN_FILE="$STATE/session.token"
URL="http://127.0.0.1:8080"

json_pid() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$PROCESS_FILE" 2>/dev/null | sed -n '1p'
}

process_matches() {
  candidate="$1"
  expected="$2"
  case "$candidate" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$candidate/cmdline" ] || return 1
  command_line="$(tr '\0' '\n' < "/proc/$candidate/cmdline" 2>/dev/null || true)"
  case "$command_line" in *"$expected"*) return 0 ;; *) return 1 ;; esac
}

bridge_pid="$(json_pid bridge_pid)"
llama_pid="$(json_pid llama_pid)"
token="$(sed -n '1p' "$TOKEN_FILE" 2>/dev/null || true)"

if [ -z "$bridge_pid" ] && [ -z "$llama_pid" ]; then
  echo "No LOCAL AI process is tracked."
  command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock >/dev/null 2>&1 || true
  exit 0
fi

if [ -n "$token" ] && command -v curl >/dev/null 2>&1; then
  curl --max-time 3 -sS -o /dev/null -X POST "$URL/api/shutdown" \
    -H "Authorization: Bearer $token" 2>/dev/null || true
fi

i=0
while [ "$i" -lt 120 ] && process_matches "$bridge_pid" "$BRIDGE"; do
  i=$((i + 1))
  sleep 0.1
done

if process_matches "$bridge_pid" "$BRIDGE"; then
  echo "Authenticated shutdown did not finish; sending TERM to the tracked bridge." >&2
  kill -TERM "$bridge_pid" 2>/dev/null || true
  i=0
  while [ "$i" -lt 80 ] && process_matches "$bridge_pid" "$BRIDGE"; do
    i=$((i + 1))
    sleep 0.1
  done
fi
if process_matches "$bridge_pid" "$BRIDGE"; then
  kill -KILL "$bridge_pid" 2>/dev/null || true
fi

i=0
while [ "$i" -lt 60 ] && process_matches "$llama_pid" "$RUNTIME/llama-server"; do
  i=$((i + 1))
  sleep 0.1
done
if process_matches "$llama_pid" "$RUNTIME/llama-server"; then
  echo "Stopping only the tracked llama-server owned by this bridge." >&2
  kill -TERM "$llama_pid" 2>/dev/null || true
  sleep 1
fi
if process_matches "$llama_pid" "$RUNTIME/llama-server"; then
  kill -KILL "$llama_pid" 2>/dev/null || true
fi

if process_matches "$bridge_pid" "$BRIDGE" || process_matches "$llama_pid" "$RUNTIME/llama-server"; then
  echo "LOCAL AI could not be fully stopped. Do not disconnect the USB yet." >&2
  exit 1
fi

[ -e "$PROCESS_FILE" ] && unlink "$PROCESS_FILE" 2>/dev/null || true
[ -e "$TOKEN_FILE" ] && unlink "$TOKEN_FILE" 2>/dev/null || true
command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock >/dev/null 2>&1 || true
echo "LOCAL AI stopped. It is safe to disconnect the USB."
