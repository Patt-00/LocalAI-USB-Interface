#!/usr/bin/env bash
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec bash "$ROOT/START CLI.sh" "$@"
