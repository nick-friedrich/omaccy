#!/usr/bin/env bash

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/lib/palette.sh"
source "$CONFIG_DIR/lib/aerospace.sh"

aerospace_bin="$(find_aerospace)"
disabled_marker="$HOME/.omaccy/aerospace-disabled"

if [[ "${1:-}" == "toggle" && -n "$aerospace_bin" ]]; then
  if "$aerospace_bin" enable toggle >/dev/null 2>&1; then
    mkdir -p "$(dirname "$disabled_marker")"
    if [[ -f "$disabled_marker" ]]; then
      rm -f "$disabled_marker"
    else
      touch "$disabled_marker"
    fi
  fi
fi

if [[ -f "$disabled_marker" ]]; then
  sketchybar --set "$NAME" label="Tiling off" icon.color="$TEXT"
elif [[ -n "$aerospace_bin" ]] && "$aerospace_bin" list-workspaces --all >/dev/null 2>&1; then
  sketchybar --set "$NAME" label="Tiling" icon.color="$TEXT"
else
  sketchybar --set "$NAME" label="Tiling off" icon.color="$TEXT"
fi
