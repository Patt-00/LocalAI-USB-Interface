#!/bin/bash
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MODEL_DIR="$ROOT/LocalAI/models"
MODEL_SELECTOR="$ROOT/LocalAI/runtime/model-selection.sh"

fail() {
  echo
  echo "ERROR: $1" >&2
  if [ -t 0 ]; then read -r -p "Press Return to close..." _; fi
  exit 1
}

case "${1:-}" in
  -h|--help)
    echo "Usage: LocalCLI.command [MODEL.gguf]"
    echo "Starts terminal chat with the shared model. Press Control-C to exit."
    exit 0
    ;;
esac

[ -r "$MODEL_SELECTOR" ] || fail "Automatic model selector is missing."
. "$MODEL_SELECTOR" || fail "Could not load the automatic model selector."
MODEL="${1:-}"
if [ -z "$MODEL" ]; then
  MODEL="$(localai_select_default_model "$MODEL_DIR")" || \
    fail "No readable primary GGUF was found in LocalAI/models."
fi
[ -r "$MODEL" ] || fail "Model cannot be read: $MODEL"

GPU_ARGS=(--gpu-layers 0)
ACCELERATION="CPU"
SAVED_GPU_MODE="$(sed -n '1p' "$HOME/.localai-usb-gpu-mode" 2>/dev/null || printf 'on')"
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
  RUNTIME="$ROOT/LocalAI/macos-arm64"
  if [ "${LOCALAI_FORCE_CPU:-0}" != "1" ] && [ "$SAVED_GPU_MODE" != "off" ] && \
     [ -f "$RUNTIME/libggml-metal.dylib" ]; then
    GPU_ARGS=(--gpu-layers auto --fit on --fit-target 512)
    ACCELERATION="Apple Metal GPU offload"
  fi
else
  case "$(uname -m)" in
    x86_64) RUNTIME="$ROOT/LocalAI/macos-x64" ;;
    *) fail "Unsupported Mac architecture: $(uname -m)" ;;
  esac
fi

CLI="$RUNTIME/llama-cli"
[ -f "$CLI" ] || fail "llama-cli was not found for this Mac."

CTX_SIZE="$(sed -n '1p' "$HOME/.localai-usb-context-size" 2>/dev/null || printf '4096')"
case "$CTX_SIZE" in ''|*[!0-9]*) CTX_SIZE=4096;; esac
if [ "$CTX_SIZE" -lt 512 ] || [ "$CTX_SIZE" -gt 131072 ]; then CTX_SIZE=4096; fi

# Stop only the web router whose PID, creation identity, and command line match
# this USB. Its direct children belong to that verified router.
ROOT_ID="$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
WEB_WORK_BASE="${TMPDIR:-/tmp}"
WEB_WORK_BASE="${WEB_WORK_BASE%/}/localai-usb-$UID-$ROOT_ID"
PIDFILE="$WEB_WORK_BASE/server.pid"
if [ -f "$PIDFILE" ]; then
  server_pid="$(sed -n '1p' "$PIDFILE" 2>/dev/null || true)"
  server_start="$(sed -n '2p' "$PIDFILE" 2>/dev/null || true)"
  case "$server_pid" in ''|*[!0-9]*) fail "The web server has an invalid PID record; nothing was stopped.";; esac
  if kill -0 "$server_pid" 2>/dev/null; then
    actual_start="$(ps -p "$server_pid" -o lstart= 2>/dev/null || true)"
    actual_command="$(ps -ww -p "$server_pid" -o command= 2>/dev/null || true)"
    [ -n "$server_start" ] && [ "$actual_start" = "$server_start" ] || \
      fail "The tracked web PID was reused; nothing was stopped."
    case "$actual_command" in
      *"$MODEL_DIR"*"--host 127.0.0.1"*"--port 8080"*) ;;
      *) fail "The tracked PID is not this USB's web server; nothing was stopped." ;;
    esac
    echo "Stopping this USB's website server before loading CLI mode..."
    child_pids="$(pgrep -P "$server_pid" 2>/dev/null || true)"
    kill "$server_pid" $child_pids 2>/dev/null || true
    i=0
    while kill -0 "$server_pid" 2>/dev/null && [ "$i" -lt 40 ]; do i=$((i + 1)); sleep 0.25; done
    kill -0 "$server_pid" 2>/dev/null && kill -KILL "$server_pid" 2>/dev/null || true
    for child_pid in $child_pids; do
      kill -0 "$child_pid" 2>/dev/null && kill -KILL "$child_pid" 2>/dev/null || true
    done
    kill -0 "$server_pid" 2>/dev/null && fail "The tracked web server did not stop cleanly."
  fi
  rm -f "$PIDFILE"
fi

RUN_RUNTIME="$RUNTIME"
CLI="$RUN_RUNTIME/llama-cli"
CLI_TMP=""
if ! env DYLD_LIBRARY_PATH="$RUN_RUNTIME" "$CLI" --version >/dev/null 2>&1; then
  CLI_TMP="${TMPDIR:-/tmp}"
  CLI_TMP="${CLI_TMP%/}/localai-cli-usb-$UID-$ROOT_ID"
  mkdir -p "$CLI_TMP" || fail "Cannot create a temporary runtime directory."
  cp -RL "$RUNTIME/." "$CLI_TMP/" || fail "Cannot copy the small runtime from exFAT."
  chmod u+x "$CLI_TMP"/llama* "$CLI_TMP"/ggml-rpc-server 2>/dev/null || true
  RUN_RUNTIME="$CLI_TMP"
  CLI="$RUN_RUNTIME/llama-cli"
fi

cleanup() {
  case "$CLI_TMP" in
    "${TMPDIR:-/tmp}"/localai-cli-usb-*|/tmp/localai-cli-usb-*)
      [ -d "$CLI_TMP" ] && rm -rf "$CLI_TMP"
      ;;
  esac
}
trap cleanup EXIT

echo
echo "LOCAL AI TERMINAL CHAT"
echo "Model: $(basename "$MODEL")"
echo "Context: $CTX_SIZE tokens"
echo "Acceleration: $ACCELERATION"
echo "Press Control-C to exit."
echo

cd "$RUN_RUNTIME" || fail "Cannot enter the runtime directory."
env DYLD_LIBRARY_PATH="$RUN_RUNTIME" "$CLI" \
  --model "$MODEL" \
  --ctx-size "$CTX_SIZE" \
  --conversation \
  --jinja \
  --reasoning auto \
  "${GPU_ARGS[@]}"
status=$?
echo
echo "LocalCLI finished."
if [ -t 0 ]; then read -r -p "Press Return to close..." _; fi
exit "$status"
