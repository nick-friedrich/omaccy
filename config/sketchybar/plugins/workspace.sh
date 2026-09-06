#!/usr/bin/env bash

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/lib/palette.sh"
source "$CONFIG_DIR/lib/aerospace.sh"

aerospace_bin="$(find_aerospace)"
[[ -n "$aerospace_bin" ]] || exit 0

if [[ -n "${1:-}" ]]; then
  "$aerospace_bin" workspace "$1"
  exit
fi

focused="${FOCUSED_WORKSPACE:-}"
if [[ -z "$focused" ]]; then
  focused="$($aerospace_bin list-workspaces --focused 2>/dev/null | head -n 1)"
fi
occupied="$($aerospace_bin list-windows --all --format '%{workspace}' 2>/dev/null | sort -u)"

for workspace in {1..9}; do
  if [[ "$workspace" != "$focused" ]] && ! grep -Fxq "$workspace" <<< "$occupied"; then
    sketchybar --set "workspace.$workspace" drawing=off
  elif [[ "$workspace" == "$focused" ]]; then
    sketchybar --set "workspace.$workspace" \
      drawing=on \
      icon.color="$ACCENT" \
      background.drawing=off
  else
    sketchybar --set "workspace.$workspace" \
      drawing=on \
      icon.color="$MUTED" \
      background.drawing=off
  fi
done
