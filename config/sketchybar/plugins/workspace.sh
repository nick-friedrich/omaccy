#!/usr/bin/env bash

find_aerospace() {
  command -v aerospace 2>/dev/null || {
    [[ -x /opt/homebrew/bin/aerospace ]] && printf '%s\n' /opt/homebrew/bin/aerospace && return
    [[ -x /usr/local/bin/aerospace ]] && printf '%s\n' /usr/local/bin/aerospace
  }
}

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
      icon.color=0xff89b4fa \
      background.drawing=off
  else
    sketchybar --set "workspace.$workspace" \
      drawing=on \
      icon.color=0xff7f849c \
      background.drawing=off
  fi
done
