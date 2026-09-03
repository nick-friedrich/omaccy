#!/usr/bin/env bash

status="$(pmset -g batt 2>/dev/null)"
percentage="$(printf '%s\n' "$status" | sed -nE 's/.*[[:space:]]([0-9]+)%.*/\1/p' | head -n 1)"
[[ -n "$percentage" ]] || percentage="?"

icon="▰"
color=0xffcdd6f4
[[ "$status" == *"AC Power"* ]] && icon="↯"
if [[ "$percentage" != "?" && "$percentage" -le 20 ]]; then
  color=0xfff38ba8
fi

sketchybar --set "$NAME" icon="$icon" icon.color="$color" label="${percentage}%"
