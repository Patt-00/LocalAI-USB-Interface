#!/usr/bin/env bash
set -eu

CONTEXT_SIZE="${1:-}"
case "$CONTEXT_SIZE" in
    ''|*[!0-9]*) printf 'ERROR: context size must be a whole number\n' >&2; exit 2 ;;
esac
[ "$CONTEXT_SIZE" -ge 512 ] && [ "$CONTEXT_SIZE" -le 131072 ] || {
    printf 'ERROR: context size must be between 512 and 131072 tokens\n' >&2
    exit 2
}

PRESETFILE="${LOCALAI_PRESETFILE:-}"
[ -n "$PRESETFILE" ] && [ -f "$PRESETFILE" ] || {
    printf 'ERROR: the active LocalAI preset file is unavailable\n' >&2
    exit 3
}

PREFERENCE_FILE="$HOME/.localai-usb-context-size"
printf '%s\n' "$CONTEXT_SIZE" > "$PREFERENCE_FILE"
chmod 600 "$PREFERENCE_FILE" 2>/dev/null || true

TEMPFILE="$(mktemp "${PRESETFILE}.context.XXXXXX")"
cleanup() { rm -f -- "$TEMPFILE"; }
trap cleanup EXIT HUP INT TERM

awk -v context_size="$CONTEXT_SIZE" '
    function insert_context_size() {
        if (inserted) return
        print "ctx-size = " context_size
        inserted = 1
    }
    /^\[\*\][[:space:]]*$/ {
        print
        insert_context_size()
        global_found = 1
        next
    }
    /^\[/ && !global_found {
        print "[*]"
        insert_context_size()
        print ""
        global_found = 1
    }
    !/^(ctx-size)[[:space:]]*=/ { print }
    END {
        if (!global_found) {
            print ""
            print "[*]"
            insert_context_size()
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
printf 'changed=%s context=%s restart=false\n' "$CHANGED" "$CONTEXT_SIZE"
