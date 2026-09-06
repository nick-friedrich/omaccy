#!/usr/bin/env bash

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/lib/palette.sh"

status="$(pmset -g batt 2>/dev/null)"
percentage="$(printf '%s\n' "$status" | sed -nE 's/.*[[:space:]]([0-9]+)%.*/\1/p' | head -n 1)"
[[ -n "$percentage" ]] || percentage="?"

icon="􀛨"
if [[ "$status" == *"AC Power"* ]]; then
  icon="􀢋"
elif [[ "$percentage" != "?" ]]; then
  if (( percentage <= 10 )); then
    icon="􀛪"
  elif (( percentage <= 30 )); then
    icon="􀛩"
  elif (( percentage <= 60 )); then
    icon="􀺶"
  elif (( percentage <= 85 )); then
    icon="􀺸"
  fi
fi

sketchybar --set "$NAME" icon="$icon" icon.color="$TEXT" label="${percentage}%"
