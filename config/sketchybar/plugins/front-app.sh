#!/usr/bin/env bash

app="${INFO:-}"
[[ -n "$app" ]] || app="$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)"
sketchybar --set "$NAME" label="${app:-Desktop}"
