#!/usr/bin/env bash
set -u

# The battery item, and the popup behind it: charge and time left, Low Power
# Mode, keep-awake, turning the display off, and Battery settings. Keep-awake
# used to hold a place in the bar at all times; it now appears only while it
# is on, and is started from here the rest of the time.

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/lib/palette.sh"
source "$CONFIG_DIR/lib/icons.sh"
source "$CONFIG_DIR/lib/caffeinate-state.sh"

SKETCHYBAR_BIN="${OMACCY_SKETCHYBAR_BIN:-sketchybar}"
PMSET_BIN="${OMACCY_PMSET_BIN:-pmset}"
OPEN_BIN="${OMACCY_OPEN_BIN:-/usr/bin/open}"
# Always the item's own name, never $NAME: the popup rows run this script too.
ITEM_NAME="battery"
BATTERY_SETTINGS="x-apple.systempreferences:com.apple.Battery-Settings.extension"

bar() {
  "$SKETCHYBAR_BIN" "$@" >/dev/null 2>&1 || true
}

status="$("$PMSET_BIN" -g batt 2>/dev/null)"
percentage="$(printf '%s\n' "$status" | sed -nE 's/.*[[:space:]]([0-9]+)%.*/\1/p' | head -n 1)"
[[ -n "$percentage" ]] || percentage="?"

update_item() {
  local icon="$ICON_BATTERY"
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
  bar --set "$ITEM_NAME" icon="$icon" icon.color="$TEXT" label="${percentage}%"
}

# pmset's own words, turned into the line a person would say: "8:17
# remaining" on battery, "Charging · 1:02 until full" on power.
battery_detail() {
  local state time
  state="$(printf '%s\n' "$status" | awk -F ';' '/InternalBattery/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }')"
  time="$(printf '%s\n' "$status" | sed -nE 's/.*[;[:space:]]([0-9]+:[0-9]+) remaining.*/\1/p' | head -n 1)"
  [[ "$time" == "0:00" ]] && time=""
  case "$state" in
    charged) printf 'Fully charged\n' ;;
    "finishing charge") printf 'Finishing charge\n' ;;
    charging)
      if [[ -n "$time" ]]; then printf 'Charging · %s until full\n' "$time"; else printf 'Charging\n'; fi
      ;;
    discharging)
      if [[ -n "$time" ]]; then printf '%s remaining\n' "$time"; else printf 'On battery\n'; fi
      ;;
    "") printf 'No battery\n' ;;
    *) printf 'On power, not charging\n' ;;
  esac
}

low_power_label() {
  if [[ "$("$PMSET_BIN" -g 2>/dev/null | awk '$1 == "lowpowermode" { print $2; exit }')" == 1 ]]; then
    printf 'Low Power Mode · On\n'
  else
    printf 'Low Power Mode · Off\n'
  fi
}

# Filled in each time the popup opens, in one call so it never shows a mix of
# old and new. The turn-off row only appears while keep-awake is on.
render_popup() {
  local off_drawing=off off_label="Turn off keep awake" remaining
  if remaining="$(caffeinate_remaining)"; then
    off_drawing=on
    (( remaining > 0 )) && off_label="Turn off keep awake · $(caffeinate_label "$remaining") left"
  fi
  bar --set "$ITEM_NAME.status" label="${percentage}% · $(battery_detail)" \
      --set "$ITEM_NAME.lowpower" label="$(low_power_label)" \
      --set caffeinate.off drawing="$off_drawing" label="$off_label"
}

case "${1:-update}" in
  click)
    render_popup
    bar --set "$ITEM_NAME" popup.drawing=toggle
    ;;
  settings)
    # Low Power Mode is changed in Battery settings rather than from the bar:
    # pmset needs an administrator password to set it, and a bar row asking
    # for one would be worse than a row that opens the pane.
    bar --set "$ITEM_NAME" popup.drawing=off
    "$OPEN_BIN" "$BATTERY_SETTINGS" >/dev/null 2>&1 || true
    ;;
  display-sleep)
    bar --set "$ITEM_NAME" popup.drawing=off
    "$PMSET_BIN" displaysleepnow >/dev/null 2>&1 || true
    ;;
  update) ;;
  *) exit 2 ;;
esac

update_item
