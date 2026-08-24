#!/usr/bin/env bash
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_ID="$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
MODEL_DIR="$ROOT/LocalAI/models"
MODEL_SELECTOR="$ROOT/LocalAI/runtime/model-selection.sh"
WEB="$ROOT/LocalAI/web"
QWEN25_TEMPLATE="$ROOT/LocalAI/templates/Qwen-Qwen2.5-Instruct.jinja"
URL="http://127.0.0.1:8080"
WORK_BASE="${XDG_RUNTIME_DIR:-/tmp}/localai-usb-${UID}-${ROOT_ID}"
PIDFILE="$WORK_BASE/server.pid"
LOG="$WORK_BASE/server.log"
PRESETFILE="$WORK_BASE/device-models.ini"
CACHE_DIR="$WORK_BASE/cache"

fail() {
    printf '\nERROR: %s\n' "$1" >&2
    printf 'See: %s\n' "$LOG" >&2
    if [ -t 0 ]; then printf 'Press Enter to close...'; read -r _; fi
    exit 1
}

open_ui() {
    ui_url="$URL/?launch=$(date +%s)&bundle=$UI_BUNDLE"
    printf '\nBrowser link:\n%s\n' "$ui_url"
    printf 'Copy the link above if the browser does not open automatically.\n'
    command -v xdg-open >/dev/null 2>&1 && xdg-open "$ui_url" >/dev/null 2>&1 &
}

GPU_ARGS=(--gpu-layers 0)
GPU_BACKEND="CPU"
GPU_DEVICE=""
ACCELERATION="CPU compatibility mode"
SAVED_GPU_MODE="$(sed -n '1p' "$HOME/.localai-usb-gpu-mode" 2>/dev/null || printf 'on')"

case "$(uname -m)" in
    x86_64|amd64)
        RUNTIME="$ROOT/LocalAI/linux-x64"
        VULKAN_RUNTIME="$ROOT/LocalAI/linux-x64-vulkan"
        UI_BUNDLE="1UCgOgK4"
        if [ "${LOCALAI_FORCE_CPU:-0}" != "1" ] && [ "$SAVED_GPU_MODE" != "off" ] && [ -f "$VULKAN_RUNTIME/llama-server" ]; then
            vulkan_devices="$(env LD_LIBRARY_PATH="$VULKAN_RUNTIME" \
                "$VULKAN_RUNTIME/llama-server" --list-devices 2>/dev/null || true)"
            gpu_device="$(printf '%s\n' "$vulkan_devices" | \
                sed -n '/Vulkan[0-9][0-9]*:.*\(NVIDIA\|Radeon RX\|Intel.*Arc\)/{s/^[[:space:]]*//;s/:.*//;p;q;}')"
            if [ -n "$gpu_device" ]; then
                RUNTIME="$VULKAN_RUNTIME"
                GPU_ARGS=(--device "$gpu_device" --gpu-layers auto --fit on --fit-target 512)
                GPU_BACKEND="VULKAN"
                GPU_DEVICE="$gpu_device"
                ACCELERATION="Vulkan GPU offload ($gpu_device) with automatic CPU/RAM fallback"
            fi
        fi
        ;;
    aarch64|arm64)
        RUNTIME="$ROOT/LocalAI/linux-arm64"
        VULKAN_RUNTIME="$ROOT/LocalAI/linux-arm64-vulkan"
        UI_BUNDLE="NBtKIggZ"
        if [ "${LOCALAI_FORCE_CPU:-0}" != "1" ] && [ "$SAVED_GPU_MODE" != "off" ] && [ -f "$VULKAN_RUNTIME/llama-server" ]; then
            vulkan_devices="$(env LD_LIBRARY_PATH="$VULKAN_RUNTIME" \
                "$VULKAN_RUNTIME/llama-server" --list-devices 2>/dev/null || true)"
            gpu_device="$(printf '%s\n' "$vulkan_devices" | awk '
                /^[[:space:]]*Vulkan[0-9]+:/ && tolower($0) !~ /(llvmpipe|swiftshader|software)/ {
                    sub(/^[[:space:]]*/, ""); sub(/:.*/, ""); print; exit
                }')"
            if [ -n "$gpu_device" ]; then
                RUNTIME="$VULKAN_RUNTIME"
                GPU_ARGS=(--device "$gpu_device" --gpu-layers auto --fit on --fit-target 512)
                GPU_BACKEND="VULKAN"
                GPU_DEVICE="$gpu_device"
                ACCELERATION="Vulkan GPU offload ($gpu_device) with automatic CPU/RAM fallback"
            fi
        fi
        ;;
    *) fail "Unsupported Linux architecture: $(uname -m). This drive supports x86-64 and ARM64." ;;
esac
SERVER="$RUNTIME/llama-server"

[ -r "$MODEL_SELECTOR" ] || fail "Automatic model selector not found: $MODEL_SELECTOR"
. "$MODEL_SELECTOR" || fail "Could not load the automatic model selector."
DEFAULT_MODEL="$(localai_select_default_model "$MODEL_DIR")" || fail "No readable primary GGUF model was found in: $MODEL_DIR"
[ -r "$DEFAULT_MODEL" ] || fail "Automatically selected model is not readable: $DEFAULT_MODEL"
[ -r "$WEB/index.html" ] || fail "Offline chat interface not found: $WEB/index.html"
[ -r "$WEB/ui-config.json" ] || fail "Agent UI configuration not found: $WEB/ui-config.json"
[ -r "$QWEN25_TEMPLATE" ] || fail "Qwen2.5 tool template not found: $QWEN25_TEMPLATE"
[ -f "$SERVER" ] || fail "llama-server not found for this architecture."

CTX_SIZE="$(sed -n '1p' "$HOME/.localai-usb-context-size" 2>/dev/null || printf '4096')"
case "$CTX_SIZE" in ''|*[!0-9]*) CTX_SIZE=4096;; esac
if [ "$CTX_SIZE" -lt 512 ] || [ "$CTX_SIZE" -gt 131072 ]; then CTX_SIZE=4096; fi

if [ -f "$PIDFILE" ]; then
    oldpid="$(sed -n '1p' "$PIDFILE" 2>/dev/null || true)"
    oldstart="$(sed -n '2p' "$PIDFILE" 2>/dev/null || true)"
    actual_start="$(awk '{print $22}' "/proc/$oldpid/stat" 2>/dev/null || true)"
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null && \
       [ -n "$oldstart" ] && [ "$actual_start" = "$oldstart" ] && \
       tr '\0' ' ' < "/proc/$oldpid/cmdline" 2>/dev/null | grep -Fq -- "$MODEL_DIR"; then
        echo "LOCAL AI is already running (PID $oldpid)."
        open_ui
        exit 0
    fi
    rm -f -- "$PIDFILE"
fi

umask 077
mkdir -p -- "$WORK_BASE" "$CACHE_DIR" || fail "Could not create the private runtime directory."
chmod 700 -- "$WORK_BASE" || fail "Could not secure the private runtime directory."
printf 'version = 1\n\n[*]\n' > "$PRESETFILE" || fail "Could not create the device model list."
printf 'ctx-size = %s\n' "$CTX_SIZE" >> "$PRESETFILE"
if [ "$GPU_BACKEND" = "CPU" ]; then
    printf 'gpu-layers = 0\n' >> "$PRESETFILE"
else
    printf 'gpu-layers = auto\ndevice = %s\nfit = on\nfit-target = 512\n' \
        "$GPU_DEVICE" >> "$PRESETFILE"
fi

append_tool_template() {
    template_model_name="$(basename -- "$1" | tr '[:upper:]' '[:lower:]')"
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
        model_base="$(basename -- "$model_path")"
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
        primary=""
        projector=""
        for candidate in "$bundle_dir"/*.gguf "$bundle_dir"/*.GGUF; do
            [ -f "$candidate" ] || continue
            candidate_base="$(basename -- "$candidate")"
            case "$candidate_base" in
                mmproj*|MMPROJ*) [ -z "$projector" ] && projector="$candidate" ;;
                *-0000[2-9]-of-*.gguf|*-000[1-9][0-9]-of-*.gguf) ;;
                *) [ -z "$primary" ] && primary="$candidate" ;;
            esac
        done
        [ -n "$primary" ] || continue
        bundle_name="$(basename -- "$bundle_dir")"
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
if ! env LD_LIBRARY_PATH="$RUNTIME" "$SERVER" --version >/dev/null 2>&1; then
    mkdir -p -- "$WORK_BASE/runtime"
    cp -RL -- "$RUNTIME/." "$WORK_BASE/runtime/" || fail "Could not copy the small runtime to $WORK_BASE/runtime"
    chmod u+x "$WORK_BASE/runtime"/llama* "$WORK_BASE/runtime"/ggml-rpc-server 2>/dev/null || true
    RUN_RUNTIME="$WORK_BASE/runtime"
    SERVER="$RUN_RUNTIME/llama-server"
fi
LOCALAI_LIBRARY_PATH="$RUN_RUNTIME${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

: > "$LOG" || fail "Cannot write the server log."
(
    cd "$HOME" || exit 1
    exec nohup env LOCALAI_USB_ROOT="$ROOT" LOCALAI_PRESETFILE="$PRESETFILE" \
        LOCALAI_GPU_BACKEND="$GPU_BACKEND" LOCALAI_GPU_DEVICE="$GPU_DEVICE" \
        LLAMA_CACHE="$CACHE_DIR" LD_LIBRARY_PATH="$LOCALAI_LIBRARY_PATH" \
        "$SERVER" \
        --models-dir "$MODEL_DIR" --models-preset "$PRESETFILE" \
        --models-max 1 --models-autoload --parallel 1 \
        --cache-ram 256 --no-cache-idle-slots \
        --host 127.0.0.1 --port 8080 --context-shift \
        --jinja --reasoning off --reasoning-format deepseek \
        --tools all --path "$WEB" --ui-config-file "$WEB/ui-config.json"
) </dev/null >"$LOG" 2>&1 &
server_pid=$!
server_start="$(awk '{print $22}' "/proc/$server_pid/stat" 2>/dev/null || true)"
if [ -z "$server_start" ] || ! printf '%s\n%s\n' "$server_pid" "$server_start" > "$PIDFILE"; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    fail "Cannot create a safe PID record. The server was stopped."
fi

stop_failed_start() {
    kill "$server_pid" 2>/dev/null || true
    for _ in $(seq 1 40); do kill -0 "$server_pid" 2>/dev/null || break; sleep 0.25; done
    kill -0 "$server_pid" 2>/dev/null && kill -KILL "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    rm -f -- "$PIDFILE"
}

check_ready() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 1 "$URL/props" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 1 -O /dev/null "$URL/props" >/dev/null 2>&1
    else
        exec 3<>/dev/tcp/127.0.0.1/8080 2>/dev/null || return 1
        printf 'GET /props HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n' >&3
        IFS= read -r -t 1 status <&3 || true
        exec 3<&- 3>&-
        case "$status" in *' 200 '*) return 0;; *) return 1;; esac
    fi
}

ready=0
for _ in $(seq 1 300); do
    if ! kill -0 "$server_pid" 2>/dev/null; then
        tail -n 30 "$LOG" >&2
        rm -f -- "$PIDFILE"
        fail "llama-server exited before becoming ready. Port 8080 may already be in use."
    fi
    if check_ready; then
        ready=1; break
    fi
    sleep 1
done
[ "$ready" -eq 1 ] || { stop_failed_start; fail "Timed out waiting for llama-server readiness. The server was stopped."; }

actual_start="$(awk '{print $22}' "/proc/$server_pid/stat" 2>/dev/null || true)"
actual_command="$(tr '\0' ' ' < "/proc/$server_pid/cmdline" 2>/dev/null || true)"
if [ "$actual_start" != "$server_start" ] || \
   ! printf '%s' "$actual_command" | grep -Fq -- "$MODEL_DIR" || \
   ! printf '%s' "$actual_command" | grep -Fq -- "--host 127.0.0.1" || \
   ! printf '%s' "$actual_command" | grep -Fq -- "--port 8080"; then
    stop_failed_start
    fail "The healthy port did not belong to the server started by this USB. It was stopped."
fi

echo
echo "LOCAL AI READY"
echo "DO NOT REMOVE USB WHILE AI IS RUNNING"
echo "Choose a model in the website. Only one model is kept in RAM."
echo "Models: USB plus LocalAI-Models, Desktop, and Downloads on this device."
echo "The website asks before tools run unless you choose an Always allow option."
echo "Acceleration: $ACCELERATION"
echo "Context: $CTX_SIZE tokens with automatic local conversation compaction"
echo "$URL"
open_ui
