#!/usr/bin/env bash
set -eu

MODE="${1:-}"
case "$MODE" in
    on|off) ;;
    *) printf 'ERROR: mode must be on or off\n' >&2; exit 2 ;;
esac

PRESETFILE="${LOCALAI_PRESETFILE:-}"
[ -n "$PRESETFILE" ] && [ -f "$PRESETFILE" ] || {
    printf 'ERROR: the active LocalAI preset file is unavailable\n' >&2
    exit 3
}

PREFERENCE_FILE="$HOME/.localai-usb-gpu-mode"
printf '%s\n' "$MODE" > "$PREFERENCE_FILE"
chmod 600 "$PREFERENCE_FILE" 2>/dev/null || true

BACKEND="${LOCALAI_GPU_BACKEND:-CPU}"
DEVICE="${LOCALAI_GPU_DEVICE:-}"
ACTIVE=off
if [ "$MODE" = on ] && [ "$BACKEND" != CPU ]; then
    ACTIVE=on
fi

TEMPFILE="$(mktemp "${PRESETFILE}.gpu.XXXXXX")"
cleanup() { rm -f -- "$TEMPFILE"; }
trap cleanup EXIT HUP INT TERM

awk -v active="$ACTIVE" -v device="$DEVICE" '
    function insert_gpu_settings() {
        if (inserted) return
        if (active == "on") {
            print "gpu-layers = auto"
            if (device != "") print "device = " device
            print "fit = on"
            print "fit-target = 512"
        } else {
            print "gpu-layers = 0"
        }
        inserted = 1
    }
    /^\[\*\][[:space:]]*$/ {
        print
        insert_gpu_settings()
        global_found = 1
        next
    }
    /^\[/ && !global_found {
        print "[*]"
        insert_gpu_settings()
        print ""
        global_found = 1
    }
    !/^((gpu-layers|device|fit|fit-target)[[:space:]]*=)/ { print }
    END {
        if (!global_found) {
            print ""
            print "[*]"
            insert_gpu_settings()
        }
    }
' "$PRESETFILE" > "$TEMPFILE"

if cmp -s -- "$TEMPFILE" "$PRESETFILE"; then
    CHANGED=false
else
    mv -f -- "$TEMPFILE" "$PRESETFILE"
    CHANGED=true
fi

trap - EXIT HUP INT TERM
printf 'changed=%s mode=%s active=%s backend=%s device=%s\n' \
    "$CHANGED" "$MODE" "$ACTIVE" "$BACKEND" "$DEVICE"
