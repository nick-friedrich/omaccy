#!/usr/bin/env bash

find_aerospace() {
  command -v aerospace 2>/dev/null || {
    [[ -x /opt/homebrew/bin/aerospace ]] && printf '%s\n' /opt/homebrew/bin/aerospace && return
    [[ -x /usr/local/bin/aerospace ]] && printf '%s\n' /usr/local/bin/aerospace
  }
}

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
  sketchybar --set "$NAME" label="Tiling off" icon.color=0xffcdd6f4
elif [[ -n "$aerospace_bin" ]] && "$aerospace_bin" list-workspaces --all >/dev/null 2>&1; then
  sketchybar --set "$NAME" label="Tiling" icon.color=0xffcdd6f4
else
  sketchybar --set "$NAME" label="Tiling off" icon.color=0xffcdd6f4
fi
