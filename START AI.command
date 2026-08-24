#!/bin/bash
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_ID="$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
MODEL_DIR="$ROOT/LocalAI/models"
MODEL_SELECTOR="$ROOT/LocalAI/runtime/model-selection.sh"
WEB="$ROOT/LocalAI/web"
QWEN25_TEMPLATE="$ROOT/LocalAI/templates/Qwen-Qwen2.5-Instruct.jinja"
URL="http://127.0.0.1:8080"
WORK_BASE="${TMPDIR:-/tmp}"
WORK_BASE="${WORK_BASE%/}/localai-usb-$UID-$ROOT_ID"
PIDFILE="$WORK_BASE/server.pid"
STATEFILE="$WORK_BASE/runtime-path.txt"
LOG="$WORK_BASE/server.log"
PRESETFILE="$WORK_BASE/device-models.ini"
CACHE_DIR="$WORK_BASE/cache"
TOKENFILE="$WORK_BASE/api-key"

fail() { echo; echo "ERROR: $1" >&2; echo "See: $LOG" >&2; read -r -p "Press Return to close..." _; exit 1; }
open_ui() {
  ui_key="$(sed -n '1p' "$TOKENFILE" 2>/dev/null || true)"
  case "$ui_key" in *[!0-9A-Fa-f]*|'') open "$URL/?launch=$(date +%s)&bundle=$UI_BUNDLE";; *) open "$URL/?launch=$(date +%s)&bundle=$UI_BUNDLE#apiKey=$ui_key";; esac
}
GPU_BACKEND="CPU"
GPU_DEVICE=""
SAVED_GPU_MODE="$(sed -n '1p' "$HOME/.localai-usb-gpu-mode" 2>/dev/null || printf 'on')"
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
  RUNTIME="$ROOT/LocalAI/macos-arm64"
  UI_BUNDLE="BD6jg1Qf"
  GPU_ARGS=(--gpu-layers 0)
  ACCELERATION="CPU compatibility mode"
  if [ "${LOCALAI_FORCE_CPU:-0}" != "1" ] && [ "$SAVED_GPU_MODE" != "off" ] && [ -f "$RUNTIME/libggml-metal.dylib" ]; then
    GPU_ARGS=(--gpu-layers auto --fit on --fit-target 512)
    GPU_BACKEND="METAL"
    ACCELERATION="Apple Metal GPU offload with automatic CPU/RAM fallback"
  fi
else
  case "$(uname -m)" in
    x86_64) RUNTIME="$ROOT/LocalAI/macos-x64"; UI_BUNDLE="CEV3XtFH"; GPU_ARGS=(--gpu-layers 0); ACCELERATION="CPU compatibility mode" ;;
    *) fail "Unsupported Mac architecture: $(uname -m)" ;;
  esac
fi
SERVER="$RUNTIME/llama-server"
[ -r "$MODEL_SELECTOR" ] || fail "Automatic model selector not found."
. "$MODEL_SELECTOR" || fail "Could not load the automatic model selector."
DEFAULT_MODEL="$(localai_select_default_model "$MODEL_DIR")" || fail "No readable primary GGUF model was found in LocalAI/models."
[ -r "$DEFAULT_MODEL" ] || fail "The automatically selected model is not readable."
[ -r "$WEB/index.html" ] || fail "Offline chat interface not found."
[ -r "$WEB/ui-config.json" ] || fail "Agent UI configuration not found."
[ -r "$QWEN25_TEMPLATE" ] || fail "Qwen2.5 tool template not found."
[ -f "$SERVER" ] || fail "llama-server not found for this Mac."

CTX_SIZE="$(sed -n '1p' "$HOME/.localai-usb-context-size" 2>/dev/null || printf '4096')"
case "$CTX_SIZE" in ''|*[!0-9]*) CTX_SIZE=4096;; esac
if [ "$CTX_SIZE" -lt 512 ] || [ "$CTX_SIZE" -gt 131072 ]; then CTX_SIZE=4096; fi

if [ -f "$PIDFILE" ]; then
  oldpid="$(sed -n '1p' "$PIDFILE" 2>/dev/null || true)"
  oldstart="$(sed -n '2p' "$PIDFILE" 2>/dev/null || true)"
  actual_start="$(ps -p "$oldpid" -o lstart= 2>/dev/null || true)"
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null && [ -n "$oldstart" ] && \
     [ "$actual_start" = "$oldstart" ] && ps -ww -p "$oldpid" -o command= | grep -Fq -- "$MODEL_DIR"; then
    oldkey="$(sed -n '1p' "$TOKENFILE" 2>/dev/null || true)"
    case "$oldkey" in
      *[!0-9A-Fa-f]*|'') fail "LOCAL AI is running but its private API key is missing or invalid. Run STOP AI.command, then start again." ;;
      *)
        [ "${#oldkey}" -eq 64 ] || fail "LOCAL AI is running but its private API key is invalid. Run STOP AI.command, then start again."
        echo "LOCAL AI is already running (PID $oldpid)."; open_ui; exit 0 ;;
    esac
  fi
  rm -f -- "$PIDFILE"
fi

umask 077
mkdir -p "$WORK_BASE" "$CACHE_DIR" || fail "Cannot create a private runtime directory."
chmod 700 "$WORK_BASE" || fail "Cannot secure the private runtime directory."
API_KEY="$(LC_ALL=C od -An -N32 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
[ "${#API_KEY}" -eq 64 ] || fail "Could not generate the private local API key."
printf '%s\n' "$API_KEY" > "$TOKENFILE" || fail "Could not store the private local API key."
chmod 600 "$TOKENFILE" || fail "Could not secure the private local API key."
printf 'version = 1\n\n[*]\n' > "$PRESETFILE" || fail "Cannot create the device model list."
printf 'ctx-size = %s\n' "$CTX_SIZE" >> "$PRESETFILE"
if [ "$GPU_BACKEND" = "CPU" ]; then
  printf 'gpu-layers = 0\n' >> "$PRESETFILE"
else
  printf 'gpu-layers = auto\nfit = on\nfit-target = 512\n' >> "$PRESETFILE"
fi

append_tool_template() {
  template_model_name="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$template_model_name" in
    *qwen2.5*vl*|*qwen2-5*vl*|*qwen2_5*vl*) ;;
    *qwen2.5*instruct*|*qwen2-5*instruct*|*qwen2_5*instruct*)
      printf 'chat-template-file = %s\n' "$QWEN25_TEMPLATE" >> "$PRESETFILE"
      ;;
  esac
}

scan_models() {
  scan_label="$1"
  scan_dir="$2"
  [ -d "$scan_dir" ] || return 0
  for model_path in "$scan_dir"/*.gguf "$scan_dir"/*.GGUF; do
    [ -f "$model_path" ] || continue
    model_base="$(basename "$model_path")"
    case "$model_base" in
      mmproj*|MMPROJ*) continue ;;
      *-0000[2-9]-of-*.gguf|*-000[1-9][0-9]-of-*.gguf) continue ;;
    esac
    model_name="${model_base%.*}"
    safe_name="$(printf '%s' "$model_name" | sed 's/[^A-Za-z0-9._-]/-/g')"
    printf '\n[Device-%s-%s]\nmodel = %s\n' "$scan_label" "$safe_name" "$model_path" >> "$PRESETFILE"
    append_tool_template "$model_path"
  done
}

scan_bundles() {
  bundle_root="$1"
  [ -d "$bundle_root" ] || return 0
  for bundle_dir in "$bundle_root"/*; do
    [ -d "$bundle_dir" ] || continue
    primary=""; projector=""
    for candidate in "$bundle_dir"/*.gguf "$bundle_dir"/*.GGUF; do
      [ -f "$candidate" ] || continue
      candidate_base="$(basename "$candidate")"
      case "$candidate_base" in
        mmproj*|MMPROJ*) [ -z "$projector" ] && projector="$candidate" ;;
        *-0000[2-9]-of-*.gguf|*-000[1-9][0-9]-of-*.gguf) ;;
        *) [ -z "$primary" ] && primary="$candidate" ;;
      esac
    done
    [ -n "$primary" ] || continue
    bundle_name="$(basename "$bundle_dir")"
    safe_name="$(printf '%s' "$bundle_name" | sed 's/[^A-Za-z0-9._-]/-/g')"
    printf '\n[Device-Bundle-%s]\nmodel = %s\n' "$safe_name" "$primary" >> "$PRESETFILE"
    append_tool_template "$primary"
    [ -n "$projector" ] && printf 'mmproj = %s\n' "$projector" >> "$PRESETFILE"
  done
}

scan_models "Library" "$HOME/LocalAI-Models"
scan_models "Desktop" "$HOME/Desktop"
scan_models "Downloads" "$HOME/Downloads"
scan_bundles "$HOME/LocalAI-Models"

RUN_RUNTIME="$RUNTIME"
if ! env DYLD_LIBRARY_PATH="$RUNTIME" "$SERVER" --version >/dev/null 2>&1; then
  RUN_RUNTIME="$WORK_BASE/runtime"
  mkdir -p "$RUN_RUNTIME" || fail "Cannot create a temporary runtime directory."
  cp -RL "$RUNTIME/." "$RUN_RUNTIME/" || fail "Cannot copy the small runtime from exFAT."
  chmod u+x "$RUN_RUNTIME"/llama* "$RUN_RUNTIME"/ggml-rpc-server 2>/dev/null || true
  SERVER="$RUN_RUNTIME/llama-server"
fi
printf '%s\n' "$RUN_RUNTIME" > "$STATEFILE"
: > "$LOG" || fail "Cannot write the server log."
(
  cd "$HOME" || exit 1
  exec nohup env LOCALAI_USB_ROOT="$ROOT" LOCALAI_PRESETFILE="$PRESETFILE" \
    LOCALAI_GPU_BACKEND="$GPU_BACKEND" LOCALAI_GPU_DEVICE="$GPU_DEVICE" \
    LLAMA_CACHE="$CACHE_DIR" \
    "$SERVER" \
    --models-dir "$MODEL_DIR" --models-preset "$PRESETFILE" \
    --models-max 1 --models-autoload --parallel 1 \
    --cache-ram 256 --no-cache-idle-slots \
    --host 127.0.0.1 --port 8080 --api-key-file "$TOKENFILE" --context-shift \
    --jinja --reasoning off --reasoning-format deepseek \
    --tools all --path "$WEB" --ui-config-file "$WEB/ui-config.json"
) </dev/null >"$LOG" 2>&1 &
server_pid=$!
server_start="$(ps -p "$server_pid" -o lstart= 2>/dev/null || true)"
if [ -z "$server_start" ] || ! printf '%s\n%s\n' "$server_pid" "$server_start" > "$PIDFILE"; then
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  fail "Cannot create a safe PID record. The server was stopped."
fi

stop_failed_start() {
  kill "$server_pid" 2>/dev/null || true
  i=0; while kill -0 "$server_pid" 2>/dev/null && [ "$i" -lt 40 ]; do i=$((i + 1)); sleep 0.25; done
  kill -0 "$server_pid" 2>/dev/null && kill -KILL "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  rm -f "$PIDFILE"
  rm -f "$TOKENFILE"
}

ready=0
i=0
while [ "$i" -lt 300 ]; do
  kill -0 "$server_pid" 2>/dev/null || { tail -n 30 "$LOG"; rm -f "$PIDFILE" "$TOKENFILE"; fail "llama-server exited before becoming ready."; }
  if curl -fsS --max-time 1 -H "Authorization: Bearer $API_KEY" "$URL/props" >/dev/null 2>&1; then ready=1; break; fi
  i=$((i + 1)); sleep 1
done
[ "$ready" -eq 1 ] || { stop_failed_start; fail "Timed out waiting for llama-server readiness. The server was stopped."; }
actual_start="$(ps -p "$server_pid" -o lstart= 2>/dev/null || true)"
actual_command="$(ps -ww -p "$server_pid" -o command= 2>/dev/null || true)"
case "$actual_command" in
  *"$MODEL_DIR"*"--host 127.0.0.1"*"--port 8080"*) ;;
  *) stop_failed_start; fail "The healthy port did not belong to the server started by this USB. It was stopped." ;;
esac
[ "$actual_start" = "$server_start" ] || { stop_failed_start; fail "The tracked server identity changed during startup. It was stopped."; }
echo
echo "LOCAL AI READY"
echo "DO NOT REMOVE USB WHILE AI IS RUNNING"
echo "Choose a model in the website. Only one model is kept in RAM."
echo "Models: USB plus LocalAI-Models, Desktop, and Downloads on this Mac."
echo "The website asks before tools run unless you choose an Always allow option."
echo "Acceleration: $ACCELERATION"
echo "Context: $CTX_SIZE tokens with automatic local conversation compaction"
echo "$URL"
open_ui
read -r -p "You may close this window. Run STOP AI.command before ejecting. Press Return..." _
