#!/usr/bin/env bash

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/lib/palette.sh"

ssid=""
connected=0
for interface in en0 en1; do
  result="$(networksetup -getairportnetwork "$interface" 2>/dev/null)"
  if [[ "$result" == "Current Wi-Fi Network: "* ]]; then
    ssid="${result#*: }"
    connected=1
    break
  fi

  summary="$(ipconfig getsummary "$interface" 2>/dev/null)"
  if [[ "$summary" == *"InterfaceType : WiFi"* && "$summary" == *"Router : "* ]]; then
    connected=1
    break
  fi
done

if [[ -n "$ssid" ]]; then
  sketchybar --set "$NAME" icon="⌁" label="$ssid" icon.color="$OK"
elif [[ "$connected" == "1" ]]; then
  sketchybar --set "$NAME" icon="⌁" label="Online" icon.color="$OK"
else
  sketchybar --set "$NAME" icon="×" label="Offline" icon.color="$DANGER"
fi
