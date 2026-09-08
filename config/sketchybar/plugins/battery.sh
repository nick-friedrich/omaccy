#!/usr/bin/env bash

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/lib/palette.sh"
source "$CONFIG_DIR/lib/icons.sh"

status="$(pmset -g batt 2>/dev/null)"
percentage="$(printf '%s\n' "$status" | sed -nE 's/.*[[:space:]]([0-9]+)%.*/\1/p' | head -n 1)"
[[ -n "$percentage" ]] || percentage="?"

icon="$ICON_BATTERY"
if [[ "$status" == *"AC Power"* ]]; then
  icon="$ICON_BATTERY_CHARGING"
elif [[ "$percentage" != "?" ]]; then
  if (( percentage <= 10 )); then
    icon="$ICON_BATTERY_10"
  elif (( percentage <= 30 )); then
    icon="$ICON_BATTERY_30"
  elif (( percentage <= 60 )); then
    icon="$ICON_BATTERY_60"
  elif (( percentage <= 85 )); then
    icon="$ICON_BATTERY_85"
  fi
fi

sketchybar --set "$NAME" icon="$icon" icon.color="$TEXT" label="${percentage}%"
