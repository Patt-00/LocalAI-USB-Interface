#!/data/data/com.termux/files/usr/bin/bash
set -u
umask 077

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) echo "ARM64 Android is required." >&2; exit 1 ;;
esac

BASE="$HOME/.localai-usb"
RUNTIME="$BASE/runtime"
BRIDGE="$BASE/bin/localai-agent"
MODEL_SELECTOR="$BASE/bin/model-selection.sh"
WEB="$BASE/web"
STATE="$BASE/state"
PROCESS_FILE="$STATE/process.json"
BRIDGE_LOG="$BASE/agent-bridge.log"
LLAMA_LOG="$BASE/llama-server.log"
URL="http://127.0.0.1:8080"

[ -x "$BRIDGE" ] || { echo "Run setup-termux.sh from the USB first." >&2; exit 1; }
[ -r "$MODEL_SELECTOR" ] || { echo "The model selector is missing; run setup-termux.sh again." >&2; exit 1; }
. "$MODEL_SELECTOR" || { echo "Could not load the automatic model selector." >&2; exit 1; }
[ -x "$RUNTIME/llama-server" ] || { echo "The private llama.cpp runtime is missing; run setup again." >&2; exit 1; }
[ -r "$WEB/index.html" ] || { echo "The official offline interface is missing; run setup again." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || {
  echo "Termux curl is required. While online once, run: pkg install curl" >&2
  exit 1
}

json_pid() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$PROCESS_FILE" 2>/dev/null | sed -n '1p'
}

bridge_matches() {
  candidate="$1"
  case "$candidate" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$candidate/cmdline" ] || return 1
  command_line="$(tr '\0' '\n' < "/proc/$candidate/cmdline" 2>/dev/null || true)"
  case "$command_line" in
    *"$BRIDGE"*"--listen"*"127.0.0.1:8080"*) return 0 ;;
    *) return 1 ;;
  esac
}

open_agent() {
  launch_url="$URL/?launch=$(date +%s)"
  /system/bin/am start -a android.intent.action.VIEW -d "$launch_url" >/dev/null 2>&1 || {
    echo "Open $launch_url in the Android browser." >&2
    return 1
  }
}

old_bridge="$(json_pid bridge_pid)"
if bridge_matches "$old_bridge"; then
  echo "LOCAL AI is already running (PID $old_bridge)."
  open_agent || true
  exit 0
fi

CTX_SIZE="$(sed -n '1p' "$HOME/.localai-usb-context-size" 2>/dev/null || printf '4096')"
case "$CTX_SIZE" in ''|*[!0-9]*) CTX_SIZE=4096;; esac
if [ "$CTX_SIZE" -lt 512 ] || [ "$CTX_SIZE" -gt 131072 ]; then CTX_SIZE=4096; fi

MODEL="${1:-}"
if [ -z "$MODEL" ]; then
  USB_HINT="$(sed -n '1p' "$BASE/usb-root" 2>/dev/null || true)"
  if [ -n "$USB_HINT" ]; then
    MODEL="$(localai_select_default_model "$USB_HINT/LocalAI/models")" || MODEL=""
  fi
fi
if [ -z "$MODEL" ]; then
  for volume in /mnt/media_rw/* /storage/*; do
    [ -d "$volume" ] || continue
    candidate="$(localai_select_default_model "$volume/LocalAI/models")" || candidate=""
    if [ -n "$candidate" ]; then
      MODEL="$candidate"
      break
    fi
  done
fi
if [ -z "$MODEL" ] || [ ! -r "$MODEL" ]; then
  echo "Termux cannot find a readable primary GGUF on the connected USB." >&2
  echo "No model was copied. Android may expose USB OTG under /mnt/media_rw/UUID or /storage/UUID." >&2
  echo "You may pass any readable GGUF explicitly:" >&2
  echo "  ~/localai-start /mnt/media_rw/UUID/LocalAI/models/model.gguf" >&2
  exit 1
fi

MMPROJ_ARGS=()
projector="$(localai_find_mmproj "$MODEL")" || projector=""
if [ -n "$projector" ]; then
  MMPROJ_ARGS=(--llama-arg=--mmproj --llama-arg="$projector")
fi

mkdir -p "$STATE"
: > "$BRIDGE_LOG"
: > "$LLAMA_LOG"
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock >/dev/null 2>&1 || true

env LD_LIBRARY_PATH="$RUNTIME:${PREFIX:-/data/data/com.termux/files/usr}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" nohup "$BRIDGE" \
  --listen 127.0.0.1:8080 \
  --llama-url http://127.0.0.1:8081 \
  --state-dir "$STATE" \
  --web "$WEB" \
  --llama-bin "$RUNTIME/llama-server" \
  --llama-log "$LLAMA_LOG" \
  --llama-arg=--model --llama-arg="$MODEL" \
  --llama-arg=--host --llama-arg=127.0.0.1 \
  --llama-arg=--port --llama-arg=8081 \
  --llama-arg=--ctx-size --llama-arg="$CTX_SIZE" \
  --llama-arg=--parallel --llama-arg=1 \
  --llama-arg=--cache-ram --llama-arg=256 \
  --llama-arg=--no-cache-idle-slots \
  --llama-arg=--gpu-layers --llama-arg=0 \
  --llama-arg=--flash-attn --llama-arg=auto \
  --llama-arg=--jinja \
  --llama-arg=--reasoning --llama-arg=off \
  --llama-arg=--reasoning-format --llama-arg=deepseek \
  "${MMPROJ_ARGS[@]}" \
  --llama-arg=--no-webui \
  >"$BRIDGE_LOG" 2>&1 &
started_bridge=$!

i=0
ready=no
while [ "$i" -lt 600 ]; do
  if ! kill -0 "$started_bridge" 2>/dev/null; then
    echo "The LocalAI agent bridge stopped during startup." >&2
    break
  fi
  status="$(curl --max-time 2 -fsS "$URL/api/status" 2>/dev/null || true)"
  case "$status" in
    *'"llama_ready":true'*) ready=yes; break ;;
  esac
  llama_pid="$(json_pid llama_pid)"
  if [ -n "$llama_pid" ] && ! kill -0 "$llama_pid" 2>/dev/null; then
    echo "llama-server stopped while loading the model." >&2
    break
  fi
  i=$((i + 1))
  sleep 1
done

if [ "$ready" != yes ]; then
  curl --max-time 3 -sS -o /dev/null -X POST "$URL/api/shutdown" \
    -H "Origin: $URL" 2>/dev/null || true
  echo "LOCAL AI did not become ready. Recent bridge log:" >&2
  tail -n 25 "$BRIDGE_LOG" 2>/dev/null || true
  echo "Recent llama-server log:" >&2
  tail -n 35 "$LLAMA_LOG" 2>/dev/null || true
  if [ -x "$HOME/localai-stop" ]; then
    "$HOME/localai-stop" || {
      echo "A tracked LocalAI process could not be stopped. Keep the USB connected and run ~/localai-stop again." >&2
      exit 1
    }
  else
    echo "The safe stop helper is missing. Keep the USB connected and rerun setup-termux.sh." >&2
    exit 1
  fi
  exit 1
fi

echo "LOCAL AI READY"
echo "DO NOT REMOVE USB WHILE AI IS RUNNING"
echo "Model: $MODEL"
echo "Context: $CTX_SIZE tokens"
echo "Agent tools use only Termux/Android permissions. Choose approval or Always allow in the Tools interface."
open_agent || true
