#!/data/data/com.termux/files/usr/bin/bash
set -u
umask 077

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) echo "Unsupported architecture: $(uname -m). ARM64 Android is required." >&2; exit 1 ;;
esac

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
USB_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
RUNTIME_SOURCE="$USB_ROOT/LocalAI/android-arm64"
BRIDGE_SOURCE="$SCRIPT_DIR/localai-agent-android-arm64"
WEB_SOURCE="$USB_ROOT/LocalAI/web"
MODEL_DIR="$USB_ROOT/LocalAI/models"
SELECTOR_SOURCE="$USB_ROOT/LocalAI/runtime/model-selection.sh"

BASE="$HOME/.localai-usb"
RUNTIME_DEST="$BASE/runtime"
BIN_DEST="$BASE/bin"
WEB_DEST="$BASE/web"

[ -f "$RUNTIME_SOURCE/llama-server" ] || {
  echo "Official Android ARM64 llama.cpp runtime is missing from the USB." >&2
  exit 1
}
[ -f "$BRIDGE_SOURCE" ] || {
  echo "The LocalAI Android agent bridge is missing beside setup-termux.sh." >&2
  exit 1
}
[ -r "$WEB_SOURCE/index.html" ] || {
  echo "The official offline llama.cpp web interface is missing from the USB." >&2
  exit 1
}
[ -r "$SELECTOR_SOURCE" ] || {
  echo "The automatic GGUF model selector is missing from the USB." >&2
  exit 1
}
. "$SELECTOR_SOURCE" || {
  echo "Could not load the automatic GGUF model selector." >&2
  exit 1
}
MODEL="$(localai_select_default_model "$MODEL_DIR")" || MODEL=""

mkdir -p "$RUNTIME_DEST" "$BIN_DEST" "$WEB_DEST" "$BASE/state" || exit 1
[ -e "$BASE/state/session.token" ] && unlink "$BASE/state/session.token" 2>/dev/null || true
cp -RL "$RUNTIME_SOURCE/." "$RUNTIME_DEST/" || {
  echo "Could not copy the small runtime into Termux private storage." >&2
  exit 1
}
cp "$BRIDGE_SOURCE" "$BIN_DEST/localai-agent" || {
  echo "Could not copy the agent bridge into Termux private storage." >&2
  exit 1
}
cp "$SELECTOR_SOURCE" "$BIN_DEST/model-selection.sh" || {
  echo "Could not install the automatic model selector." >&2
  exit 1
}
cp -RL "$WEB_SOURCE/." "$WEB_DEST/" || {
  echo "Could not copy the official offline web interface." >&2
  exit 1
}

chmod 700 "$BIN_DEST/localai-agent" "$BIN_DEST/model-selection.sh" "$RUNTIME_DEST/llama-server"
chmod 700 "$RUNTIME_DEST"/llama* "$RUNTIME_DEST"/ggml-rpc-server 2>/dev/null || true
printf '%s\n' "$USB_ROOT" > "$BASE/usb-root"
cp "$SCRIPT_DIR/termux-start.sh" "$HOME/localai-start"
cp "$SCRIPT_DIR/termux-stop.sh" "$HOME/localai-stop"
chmod 700 "$HOME/localai-start" "$HOME/localai-stop"

echo "LocalAI Termux runtime and agent bridge installed."
echo "The GGUF model was NOT copied; it remains on the USB."
if ! command -v curl >/dev/null 2>&1; then
  echo "WARNING: Termux curl is missing. While online once, install it with: pkg install curl" >&2
fi
if [ ! -r "$MODEL" ]; then
  echo "WARNING: this USB path is not readable from Termux right now."
  echo "Reconnect the USB; ~/localai-start will scan for any readable primary GGUF."
fi
echo "Start with: ~/localai-start"
