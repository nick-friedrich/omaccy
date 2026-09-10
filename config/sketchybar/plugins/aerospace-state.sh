#!/usr/bin/env bash

# The tiling item: it reports the focused workspace's layout mode and opens a
# popup to change it. Every decision about what a mode means lives in
# ~/.config/aerospace/layout.sh, which the AeroSpace callback drives too; this
# only renders what that script reports and hands clicks back to it.

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/lib/palette.sh"
source "$CONFIG_DIR/lib/aerospace.sh"

aerospace_bin="$(find_aerospace)"
disabled_marker="$HOME/.omaccy/aerospace-disabled"
layout_script="$HOME/.config/aerospace/layout.sh"
MODES="horizontal vertical grid recursive accordion"

# Always the item's own name, never $NAME: the popup rows run this script too,
# and there $NAME is the row that was clicked.
ITEM=aerospace

close_popup() {
  sketchybar --set "$ITEM" popup.drawing=off
}

tiling_is_off() {
  [[ -f "$disabled_marker" ]] && return 0
  [[ -z "$aerospace_bin" ]] && return 0
  ! "$aerospace_bin" list-workspaces --all >/dev/null 2>&1
}

toggle_tiling() {
  [[ -n "$aerospace_bin" ]] || return 0
  "$aerospace_bin" enable toggle >/dev/null 2>&1 || return 0
  mkdir -p "$(dirname "$disabled_marker")"
  if [[ -f "$disabled_marker" ]]; then
    rm -f "$disabled_marker"
  else
    touch "$disabled_marker"
  fi
}

render() {
  if tiling_is_off; then
    sketchybar --set "$ITEM" label="Tiling off" icon.color="$MUTED"
    sketchybar --set "$ITEM.toggle" icon="✓" icon.color="$OK" label="Turn tiling on"
    return
  fi

  local status mode label item
  status=""
  [[ -x "$layout_script" ]] && status="$("$layout_script" status 2>/dev/null)"
  mode=""
  label="Tiling"
  IFS=$'\t' read -r mode label <<< "$status"
  [[ -n "$label" ]] || label="Tiling"

  sketchybar --set "$ITEM" label="$label" icon.color="$TEXT"
  sketchybar --set "$ITEM.toggle" icon="×" icon.color="$DANGER" label="Turn tiling off"

  # The active mode is marked in the accent color rather than with a check, so
  # the rows keep their glyphs -- each one is a picture of the arrangement.
  for item in $MODES; do
    if [[ "$item" == "$mode" ]]; then
      sketchybar --set "$ITEM.$item" icon.color="$ACCENT" label.color="$ACCENT"
    else
      sketchybar --set "$ITEM.$item" icon.color="$TEXT" label.color="$TEXT"
    fi
  done
}

case "${1:-}" in
  click)
    sketchybar --set "$ITEM" popup.drawing=toggle
    exit 0
    ;;
  set)
    if [[ -n "${2:-}" && -x "$layout_script" ]]; then
      "$layout_script" set "$2" >/dev/null 2>&1
    fi
    close_popup
    render
    exit 0
    ;;
  toggle)
    toggle_tiling
    close_popup
    render
    exit 0
    ;;
esac

render
