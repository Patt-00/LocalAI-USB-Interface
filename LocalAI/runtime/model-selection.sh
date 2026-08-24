#!/usr/bin/env bash

# Shared by Linux, macOS, and Android/Termux launchers. A primary GGUF is a
# model file, not an mmproj projector or a secondary split-model shard.
localai_is_primary_gguf() {
  local candidate base lower
  candidate="$1"
  [ -f "$candidate" ] && [ -r "$candidate" ] || return 1
  base="$(basename -- "$candidate")"
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.gguf) ;;
    *) return 1 ;;
  esac
  case "$lower" in
    mmproj*) return 1 ;;
    *-0000[2-9]-of-*.gguf|*-000[1-9][0-9]-of-*.gguf) return 1 ;;
  esac
  return 0
}

localai_select_default_model() {
  local model_dir selector entry candidate bundle_dir
  model_dir="$1"
  [ -d "$model_dir" ] || return 1
  selector="$model_dir/default-model.txt"

  if [ -r "$selector" ]; then
    entry="$(sed -n 's/\r$//; /^[[:space:]]*#/d; /^[[:space:]]*$/d; p; q' "$selector")"
    if [ -n "$entry" ]; then
      case "$entry" in
        /*) candidate="$entry" ;;
        *) candidate="$model_dir/$entry" ;;
      esac
      if localai_is_primary_gguf "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
      printf 'WARNING: default-model.txt points to a missing or non-primary GGUF; selecting another model automatically.\n' >&2
    fi
  fi

  # Prefer models directly inside LocalAI/models, then one-level bundle folders.
  for candidate in "$model_dir"/*.gguf "$model_dir"/*.GGUF; do
    if localai_is_primary_gguf "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  for bundle_dir in "$model_dir"/*; do
    [ -d "$bundle_dir" ] || continue
    for candidate in "$bundle_dir"/*.gguf "$bundle_dir"/*.GGUF; do
      if localai_is_primary_gguf "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  done
  return 1
}

localai_find_mmproj() {
  local model parent candidate
  model="$1"
  parent="$(CDPATH= cd -- "$(dirname -- "$model")" 2>/dev/null && pwd)" || return 1
  for candidate in "$parent"/mmproj*.gguf "$parent"/MMPROJ*.GGUF; do
    [ -f "$candidate" ] && [ -r "$candidate" ] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}
