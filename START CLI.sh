#!/usr/bin/env bash
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MODEL_DIR="$ROOT/LocalAI/models"
MODEL_SELECTOR="$ROOT/LocalAI/runtime/model-selection.sh"

usage() {
    cat <<'EOF'
Usage: LocalCLI [MODEL.gguf]

Starts a private terminal chat using the model on the LOCALAI USB.
With no argument, it automatically selects a primary GGUF from the USB.
Press Ctrl+C to exit the chat.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

[ -r "$MODEL_SELECTOR" ] || { echo "ERROR: Automatic model selector is missing." >&2; exit 1; }
. "$MODEL_SELECTOR" || { echo "ERROR: Could not load the automatic model selector." >&2; exit 1; }
MODEL="${1:-}"
if [ -z "$MODEL" ]; then
    MODEL="$(localai_select_default_model "$MODEL_DIR")" || {
        echo "ERROR: No readable primary GGUF was found in: $MODEL_DIR" >&2
        exit 1
    }
fi
if [ ! -r "$MODEL" ]; then
    printf 'ERROR: Model cannot be read: %s\n' "$MODEL" >&2
    exit 1
fi

case "$(uname -m)" in
    x86_64|amd64)
        CPU_RUNTIME="$ROOT/LocalAI/linux-x64"
        VULKAN_RUNTIME="$ROOT/LocalAI/linux-x64-vulkan"
        ;;
    aarch64|arm64)
        CPU_RUNTIME="$ROOT/LocalAI/linux-arm64"
        VULKAN_RUNTIME="$ROOT/LocalAI/linux-arm64-vulkan"
        ;;
    *)
        printf 'ERROR: Unsupported Linux architecture: %s\n' "$(uname -m)" >&2
        exit 1
        ;;
esac

RUNTIME="$CPU_RUNTIME"
GPU_ARGS=(--gpu-layers 0)
ACCELERATION="CPU"
SAVED_GPU_MODE="$(sed -n '1p' "$HOME/.localai-usb-gpu-mode" 2>/dev/null || printf 'on')"

if [ "${LOCALAI_FORCE_CPU:-0}" != "1" ] && [ "$SAVED_GPU_MODE" != "off" ] && \
   [ -f "$VULKAN_RUNTIME/llama-cli" ]; then
    vulkan_devices="$(env LD_LIBRARY_PATH="$VULKAN_RUNTIME" \
        "$VULKAN_RUNTIME/llama-cli" --list-devices 2>/dev/null || true)"
    case "$(uname -m)" in
        x86_64|amd64)
            gpu_device="$(printf '%s\n' "$vulkan_devices" | \
                sed -n '/Vulkan[0-9][0-9]*:.*\(NVIDIA\|Radeon RX\|Intel.*Arc\)/{s/^[[:space:]]*//;s/:.*//;p;q;}')"
            ;;
        *)
            gpu_device="$(printf '%s\n' "$vulkan_devices" | awk '
                /^[[:space:]]*Vulkan[0-9]+:/ && tolower($0) !~ /(llvmpipe|swiftshader|software)/ {
                    sub(/^[[:space:]]*/, ""); sub(/:.*/, ""); print; exit
                }')"
            ;;
    esac
    if [ -n "$gpu_device" ]; then
        RUNTIME="$VULKAN_RUNTIME"
        GPU_ARGS=(--device "$gpu_device" --gpu-layers auto --fit on --fit-target 512)
        ACCELERATION="Vulkan GPU offload ($gpu_device)"
    fi
fi

CLI="$RUNTIME/llama-cli"
[ -f "$CLI" ] || { printf 'ERROR: llama-cli was not found: %s\n' "$CLI" >&2; exit 1; }

CTX_SIZE="$(sed -n '1p' "$HOME/.localai-usb-context-size" 2>/dev/null || printf '4096')"
case "$CTX_SIZE" in ''|*[!0-9]*) CTX_SIZE=4096;; esac
if [ "$CTX_SIZE" -lt 512 ] || [ "$CTX_SIZE" -gt 131072 ]; then CTX_SIZE=4096; fi

# Switching to CLI mode should stop only this USB's safely tracked web server.
ROOT_ID="$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
WORK_BASE="${XDG_RUNTIME_DIR:-/tmp}/localai-usb-${UID}-${ROOT_ID}"
PIDFILE="$WORK_BASE/server.pid"
if [ -f "$PIDFILE" ]; then
    server_pid="$(sed -n '1p' "$PIDFILE" 2>/dev/null || true)"
    server_start="$(sed -n '2p' "$PIDFILE" 2>/dev/null || true)"
    actual_start="$(awk '{print $22}' "/proc/$server_pid/stat" 2>/dev/null || true)"
    if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null && \
       [ -n "$server_start" ] && [ "$actual_start" = "$server_start" ]; then
        printf 'Stopping this USB\047s website server before loading CLI mode...\n'
        bash "$ROOT/STOP AI.sh" || exit 1
    fi
fi

printf '\nLOCAL AI TERMINAL CHAT\n'
printf 'Model: %s\n' "$(basename -- "$MODEL")"
printf 'Context: %s tokens\n' "$CTX_SIZE"
printf 'Acceleration: %s\n' "$ACCELERATION"
printf 'Press Ctrl+C to exit.\n\n'

cd "$RUNTIME" || exit 1
exec env LD_LIBRARY_PATH="$RUNTIME${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$CLI" \
    --model "$MODEL" \
    --ctx-size "$CTX_SIZE" \
    --conversation \
    --jinja \
    --reasoning auto \
    "${GPU_ARGS[@]}"
