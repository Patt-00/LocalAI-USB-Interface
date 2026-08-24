#!/usr/bin/env bash
set -u

case "$(uname -s 2>/dev/null || true)" in
    Darwin)
        if command -v open >/dev/null 2>&1; then
            open -a Terminal
            exit $?
        fi
        ;;
    Linux)
        case "${PREFIX:-}" in
            *com.termux*)
                printf 'LocalAI is already running inside the Termux terminal.\n'
                exit 0
                ;;
        esac

        if command -v gnome-terminal >/dev/null 2>&1; then
            nohup gnome-terminal -- bash -lc 'printf "Terminal opened by LocalAI.\n"; exec "${SHELL:-/bin/bash}" -l' >/dev/null 2>&1 &
            exit 0
        fi
        if command -v konsole >/dev/null 2>&1; then
            nohup konsole -e bash -lc 'printf "Terminal opened by LocalAI.\n"; exec "${SHELL:-/bin/bash}" -l' >/dev/null 2>&1 &
            exit 0
        fi
        if command -v xfce4-terminal >/dev/null 2>&1; then
            nohup xfce4-terminal >/dev/null 2>&1 &
            exit 0
        fi
        if command -v x-terminal-emulator >/dev/null 2>&1; then
            nohup x-terminal-emulator >/dev/null 2>&1 &
            exit 0
        fi
        if command -v xterm >/dev/null 2>&1; then
            nohup xterm -hold -e sh -c 'printf "Terminal opened by LocalAI.\n"; exec "${SHELL:-/bin/sh}" -l' >/dev/null 2>&1 &
            exit 0
        fi
        ;;
esac

printf 'No supported graphical terminal application was found.\n' >&2
exit 1
